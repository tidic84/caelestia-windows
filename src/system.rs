//! Volume, ressources, batterie, presse-papiers et actions de session.

use std::collections::VecDeque;
use std::os::windows::process::CommandExt;
use std::process::Command;
use std::sync::Mutex;

use serde::Serialize;
use sysinfo::{Disks, System};
use tauri::{AppHandle, Emitter, Manager, State};
use windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolume;
use windows::Win32::Media::Audio::{eConsole, eRender, IMMDeviceEnumerator, MMDeviceEnumerator};
use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_ALL};
use windows::Win32::System::DataExchange::GetClipboardSequenceNumber;
use windows::Win32::System::Power::{GetSystemPowerStatus, SetSuspendState, SYSTEM_POWER_STATUS};
use windows::Win32::System::Shutdown::LockWorkStation;

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

// ------------------------------------------------------------------ volume

fn endpoint() -> windows::core::Result<IAudioEndpointVolume> {
    crate::com_init_mta();
    unsafe {
        let en: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
        let dev = en.GetDefaultAudioEndpoint(eRender, eConsole)?;
        dev.Activate::<IAudioEndpointVolume>(CLSCTX_ALL, None)
    }
}

#[derive(Serialize)]
pub struct Volume {
    level: f32,
    muted: bool,
}

#[tauri::command(async)]
pub fn volume_get() -> Volume {
    endpoint()
        .and_then(|ep| unsafe {
            Ok(Volume {
                level: ep.GetMasterVolumeLevelScalar()?,
                muted: ep.GetMute()?.as_bool(),
            })
        })
        .unwrap_or(Volume { level: 0.0, muted: false })
}

#[tauri::command(async)]
pub fn volume_set(level: Option<f32>, muted: Option<bool>) {
    if let Ok(ep) = endpoint() {
        unsafe {
            if let Some(l) = level {
                let _ = ep.SetMasterVolumeLevelScalar(l.clamp(0.0, 1.0), std::ptr::null());
            }
            if let Some(m) = muted {
                let _ = ep.SetMute(m, std::ptr::null());
            }
        }
    }
}

// --------------------------------------------------------------- ressources

#[derive(Serialize, Clone)]
pub struct Resources {
    cpu: f32,
    mem_used: u64,
    mem_total: u64,
    disk_used: u64,
    disk_total: u64,
    /// -1 = pas de batterie
    battery: i32,
    charging: bool,
    uptime: u64,
}

/// Emet `sys` toutes les deux secondes.
pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        let mut sys = System::new();
        let mut disks = Disks::new_with_refreshed_list();
        loop {
            sys.refresh_cpu_usage();
            sys.refresh_memory();
            disks.refresh(true);
            let (mut du, mut dt) = (0, 0);
            for d in disks.list() {
                if d.mount_point().to_string_lossy().starts_with("C:") {
                    dt = d.total_space();
                    du = dt - d.available_space();
                }
            }
            let mut ps = SYSTEM_POWER_STATUS::default();
            let ok = unsafe { GetSystemPowerStatus(&mut ps) }.is_ok();
            let no_batt = !ok || ps.BatteryFlag & 128 != 0 || ps.BatteryLifePercent == 255;
            let r = Resources {
                cpu: sys.global_cpu_usage(),
                mem_used: sys.used_memory(),
                mem_total: sys.total_memory(),
                disk_used: du,
                disk_total: dt,
                battery: if no_batt { -1 } else { ps.BatteryLifePercent as i32 },
                charging: ps.ACLineStatus == 1,
                uptime: System::uptime(),
            };
            let _ = app.emit("sys", r);
            std::thread::sleep(std::time::Duration::from_secs(2));
        }
    });
}

// ----------------------------------------------------------- presse-papiers

pub struct Clips(pub Mutex<VecDeque<String>>);

const CLIP_MAX: usize = 40;

/// Surveille le presse-papiers (texte uniquement) et emet `clips`.
pub fn watch_clipboard(app: AppHandle) {
    std::thread::spawn(move || {
        let mut seq = 0u32;
        loop {
            let s = unsafe { GetClipboardSequenceNumber() };
            if s != seq {
                seq = s;
                let text = arboard::Clipboard::new().and_then(|mut c| c.get_text());
                if let Ok(t) = text {
                    if !t.trim().is_empty() {
                        let st = app.state::<Clips>();
                        let mut q = st.0.lock().unwrap();
                        q.retain(|x| x != &t);
                        q.push_front(t);
                        q.truncate(CLIP_MAX);
                        let _ = app.emit("clips", Vec::from(q.clone()));
                    }
                }
            }
            std::thread::sleep(std::time::Duration::from_millis(400));
        }
    });
}

#[tauri::command]
pub fn clips_get(st: State<Clips>) -> Vec<String> {
    Vec::from(st.0.lock().unwrap().clone())
}

#[tauri::command(async)]
pub fn clip_copy(text: String) -> bool {
    arboard::Clipboard::new()
        .and_then(|mut c| c.set_text(text))
        .is_ok()
}

#[tauri::command]
pub fn clips_clear(app: AppHandle, st: State<Clips>) {
    st.0.lock().unwrap().clear();
    let _ = app.emit("clips", Vec::<String>::new());
}

// ------------------------------------------------------------------ session

#[tauri::command(async)]
pub fn session_action(action: String) {
    let shutdown = |args: &[&str]| {
        let _ = Command::new("shutdown")
            .args(args)
            .creation_flags(CREATE_NO_WINDOW)
            .spawn();
    };
    match action.as_str() {
        "lock" => unsafe {
            let _ = LockWorkStation();
        },
        "sleep" => unsafe {
            let _ = SetSuspendState(false, false, false);
        },
        "logout" => shutdown(&["/l"]),
        "restart" => shutdown(&["/r", "/t", "0"]),
        "shutdown" => shutdown(&["/s", "/t", "0"]),
        _ => {}
    }
}
