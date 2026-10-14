//! Volume par application (melangeur de volume de Windows) : sortie (son de
//! Spotify, Discord...) et entree (micro utilise par Discord...).
//! Une appli est designee par un bout du nom de son executable ("spotify").

use serde::Serialize;
use windows::core::{Interface, PWSTR};
use windows::Win32::Foundation::CloseHandle;
use windows::Win32::Media::Audio::{
    eCapture, eRender, EDataFlow, IAudioSessionControl2, IAudioSessionManager2, IMMDeviceEnumerator,
    ISimpleAudioVolume, MMDeviceEnumerator, DEVICE_STATE_ACTIVE,
};
use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_ALL};
use windows::Win32::System::Threading::{
    OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION,
};

/// Nom de l'executable d'un processus, en minuscules et sans « .exe ».
fn exe_name(pid: u32) -> Option<String> {
    unsafe {
        let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok()?;
        let mut buf = [0u16; 520];
        let mut len = buf.len() as u32;
        let r = QueryFullProcessImageNameW(h, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &mut len);
        let _ = CloseHandle(h);
        r.ok()?;
        let path = String::from_utf16_lossy(&buf[..len as usize]);
        let file = path.rsplit('\\').next()?.to_lowercase();
        Some(file.trim_end_matches(".exe").to_string())
    }
}

/// Sessions audio de l'appli `app`, sur tous les peripheriques actifs.
fn sessions(app: &str, flow: EDataFlow) -> Vec<ISimpleAudioVolume> {
    crate::com_init_mta();
    let key = app.to_lowercase().trim_end_matches(".exe").to_string();
    let mut out = Vec::new();
    if key.is_empty() {
        return out;
    }
    let mut f = || -> windows::core::Result<()> {
        unsafe {
            let en: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
            let devs = en.EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE)?;
            for d in 0..devs.GetCount()? {
                let Ok(mgr) = devs.Item(d)?.Activate::<IAudioSessionManager2>(CLSCTX_ALL, None) else {
                    continue;
                };
                let list = mgr.GetSessionEnumerator()?;
                for i in 0..list.GetCount()? {
                    let Ok(ctl) = list.GetSession(i) else { continue };
                    let Ok(ctl2) = ctl.cast::<IAudioSessionControl2>() else { continue };
                    let Ok(pid) = ctl2.GetProcessId() else { continue };
                    if pid == 0 || !exe_name(pid).is_some_and(|n| n.contains(&key)) {
                        continue;
                    }
                    if let Ok(v) = ctl.cast::<ISimpleAudioVolume>() {
                        out.push(v);
                    }
                }
            }
            Ok(())
        }
    };
    let _ = f();
    out
}

#[derive(Serialize)]
pub struct AppVolume {
    level: f32,
    muted: bool,
}

/// Volume d'une appli (None si elle n'a pas de session audio).
#[tauri::command(async)]
pub fn app_volume_get(app: String, mic: Option<bool>) -> Option<AppVolume> {
    let flow = if mic.unwrap_or(false) { eCapture } else { eRender };
    let s = sessions(&app, flow);
    let first = s.first()?;
    unsafe {
        Some(AppVolume {
            level: first.GetMasterVolume().ok()?,
            muted: s.iter().any(|v| v.GetMute().is_ok_and(|m| m.as_bool())),
        })
    }
}

#[tauri::command(async)]
pub fn app_volume_set(app: String, mic: Option<bool>, level: Option<f32>, muted: Option<bool>) -> bool {
    let flow = if mic.unwrap_or(false) { eCapture } else { eRender };
    let s = sessions(&app, flow);
    unsafe {
        for v in &s {
            if let Some(l) = level {
                let _ = v.SetMasterVolume(l.clamp(0.0, 1.0), std::ptr::null());
            }
            if let Some(m) = muted {
                let _ = v.SetMute(m, std::ptr::null());
            }
        }
    }
    !s.is_empty()
}
