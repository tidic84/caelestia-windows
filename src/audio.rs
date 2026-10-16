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

/// Chemin complet de l'executable d'un processus.
fn exe_path(pid: u32) -> Option<String> {
    unsafe {
        let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok()?;
        let mut buf = [0u16; 520];
        let mut len = buf.len() as u32;
        let r = QueryFullProcessImageNameW(h, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &mut len);
        let _ = CloseHandle(h);
        r.ok()?;
        Some(String::from_utf16_lossy(&buf[..len as usize]))
    }
}

/// Nom de l'executable d'un processus, en minuscules et sans « .exe ».
fn exe_name(pid: u32) -> Option<String> {
    let path = exe_path(pid)?;
    let file = path.rsplit('\\').next()?.to_lowercase();
    Some(file.trim_end_matches(".exe").to_string())
}

/// Une session audio : appli (nom d'exe, « @system » pour les sons Windows), etat, volume.
struct Sess {
    exe: String,
    pid: u32,
    active: bool,
    vol: ISimpleAudioVolume,
}

/// Toutes les sessions audio, sur tous les peripheriques actifs.
fn all_sessions(flow: EDataFlow) -> Vec<Sess> {
    crate::com_init_mta();
    let mut out = Vec::new();
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
                    let exe = if pid == 0 { "@system".to_string() } else {
                        let Some(n) = exe_name(pid) else { continue };
                        n
                    };
                    let active = ctl.GetState().is_ok_and(|s| s.0 == 1);
                    if let Ok(vol) = ctl.cast::<ISimpleAudioVolume>() {
                        out.push(Sess { exe, pid, active, vol });
                    }
                }
            }
            Ok(())
        }
    };
    let _ = f();
    out
}

/// Sessions audio de l'appli `app` (bout du nom de l'executable).
fn sessions(app: &str, flow: EDataFlow) -> Vec<ISimpleAudioVolume> {
    let key = app.to_lowercase().trim_end_matches(".exe").to_string();
    if key.is_empty() {
        return Vec::new();
    }
    all_sessions(flow).into_iter().filter(|s| s.pid != 0 && s.exe.contains(&key)).map(|s| s.vol).collect()
}

// ------------------------------------------------- melangeur (onglet PC)

#[derive(Serialize)]
pub struct MixerApp {
    /// nom de l'executable (cle pour `mixer_set`), « @system » = sons Windows
    exe: String,
    level: f32,
    muted: bool,
    /// joue du son en ce moment
    active: bool,
    icon: String,
}

static MIXER_ICONS: std::sync::OnceLock<std::sync::Mutex<std::collections::HashMap<String, String>>> =
    std::sync::OnceLock::new();

/// Applis qui ont une session audio de sortie, regroupees par executable.
#[tauri::command(async)]
pub fn mixer_get() -> Vec<MixerApp> {
    let mut out: Vec<MixerApp> = Vec::new();
    let mut paths: Vec<(String, std::path::PathBuf)> = Vec::new();
    for s in all_sessions(eRender) {
        let (level, muted) = unsafe { (s.vol.GetMasterVolume().unwrap_or(1.0), s.vol.GetMute().is_ok_and(|m| m.as_bool())) };
        match out.iter_mut().find(|a| a.exe == s.exe) {
            Some(a) => {
                a.active |= s.active;
                a.muted |= muted;
            }
            None => {
                if s.pid != 0 {
                    if let Some(p) = exe_path(s.pid) {
                        paths.push((s.exe.clone(), p.into()));
                    }
                }
                out.push(MixerApp { exe: s.exe, level, muted, active: s.active, icon: String::new() });
            }
        }
    }
    // icones des executables (cache)
    let mut cache = MIXER_ICONS.get_or_init(Default::default).lock().unwrap();
    let missing: Vec<_> = paths.iter().filter(|(e, _)| !cache.contains_key(e)).cloned().collect();
    if !missing.is_empty() {
        let (keys, files): (Vec<String>, Vec<std::path::PathBuf>) = missing.into_iter().unzip();
        for (k, (_, icon)) in keys.into_iter().zip(crate::tasks::icons_for(files)) {
            cache.insert(k, icon);
        }
    }
    for a in &mut out {
        a.icon = cache.get(&a.exe).cloned().unwrap_or_default();
    }
    out
}

/// Volume / sourdine d'une appli du melangeur (nom d'executable exact).
#[tauri::command(async)]
pub fn mixer_set(exe: String, level: Option<f32>, muted: Option<bool>) -> bool {
    let s: Vec<_> = all_sessions(eRender).into_iter().filter(|s| s.exe == exe).collect();
    unsafe {
        for x in &s {
            if let Some(l) = level {
                let _ = x.vol.SetMasterVolume(l.clamp(0.0, 1.0), std::ptr::null());
            }
            if let Some(m) = muted {
                let _ = x.vol.SetMute(m, std::ptr::null());
            }
        }
    }
    !s.is_empty()
}

/// Diagnostic (`--check-audio`) : toutes les sessions audio, sortie et micro.
pub fn report() -> String {
    crate::com_init_mta();
    let mut out = String::new();
    for (label, flow) in [("sortie", eRender), ("micro", eCapture)] {
        let r = (|| -> windows::core::Result<()> {
            unsafe {
                let en: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
                let devs = en.EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE)?;
                for d in 0..devs.GetCount()? {
                    let Ok(mgr) = devs.Item(d)?.Activate::<IAudioSessionManager2>(CLSCTX_ALL, None) else { continue };
                    let list = mgr.GetSessionEnumerator()?;
                    for i in 0..list.GetCount()? {
                        let Ok(ctl) = list.GetSession(i) else { continue };
                        let Ok(ctl2) = ctl.cast::<IAudioSessionControl2>() else { continue };
                        let pid = ctl2.GetProcessId().unwrap_or(0);
                        let st = ctl.GetState().map(|s| s.0).unwrap_or(-1);
                        let (vol, mute) = ctl
                            .cast::<ISimpleAudioVolume>()
                            .map(|v| (v.GetMasterVolume().unwrap_or(-1.0), v.GetMute().is_ok_and(|m| m.as_bool())))
                            .unwrap_or((-1.0, false));
                        out += &format!(
                            "{label} dev{d} pid={pid} exe={} etat={st} volume={vol:.2} muet={mute}\n",
                            exe_name(pid).unwrap_or_else(|| "?".into())
                        );
                    }
                }
                Ok(())
            }
        })();
        if let Err(e) = r {
            out += &format!("{label}: erreur {e}\n");
        }
    }
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

#[derive(Serialize)]
pub struct FgVolume {
    exe: String,
    level: f32,
}

/// Molette + Maj sur la pilule : volume de l'appli au premier plan, par pas de `step`.
#[tauri::command(async)]
pub fn fg_volume(step: f32) -> Option<FgVolume> {
    use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId};
    let mut pid = 0u32;
    unsafe { GetWindowThreadProcessId(GetForegroundWindow(), Some(&mut pid)) };
    let exe = exe_name(pid)?;
    let s: Vec<_> = all_sessions(eRender).into_iter().filter(|s| s.exe == exe).collect();
    let first = s.first()?;
    let level = unsafe { first.vol.GetMasterVolume().ok()? };
    let level = ((level + step) * 50.0).round() / 50.0;
    let level = level.clamp(0.0, 1.0);
    unsafe {
        for x in &s {
            let _ = x.vol.SetMasterVolume(level, std::ptr::null());
            if level > 0.0 {
                let _ = x.vol.SetMute(false, std::ptr::null());
            }
        }
    }
    Some(FgVolume { exe, level })
}
