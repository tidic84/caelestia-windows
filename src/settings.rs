//! Reglages : lancement au demarrage de Windows et ecran de l'ilot.

use std::path::PathBuf;
use std::sync::Mutex;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Manager, State, WebviewWindow};
use windows::core::{w, PCWSTR};
use windows::Win32::System::Registry::{
    RegDeleteKeyValueW, RegGetValueW, RegSetKeyValueW, HKEY_CURRENT_USER, REG_SZ, RRF_RT_REG_SZ,
};

const RUN: PCWSTR = w!(r"Software\Microsoft\Windows\CurrentVersion\Run");
const RUN_NAME: PCWSTR = w!("Ilot");

/// Ce qui est enregistre dans `%APPDATA%\io.github.tidic84.ilot\settings.json`.
/// Le lancement au demarrage n'y figure pas : le registre fait foi.
#[derive(Default, Clone, Serialize, Deserialize)]
pub struct Config {
    /// Nom Windows de l'ecran (`\\.\DISPLAY2`) ; `None` = ecran principal.
    #[serde(default)]
    pub monitor: Option<String>,
}

pub struct Settings(pub Mutex<Config>);

fn file(app: &AppHandle) -> Option<PathBuf> {
    Some(app.path().app_config_dir().ok()?.join("settings.json"))
}

pub fn load(app: &AppHandle) -> Config {
    file(app)
        .and_then(|f| std::fs::read_to_string(f).ok())
        .and_then(|s| serde_json::from_str(&s).ok())
        .unwrap_or_default()
}

fn save(app: &AppHandle, cfg: &Config) {
    let Some(f) = file(app) else { return };
    if let Some(dir) = f.parent() {
        let _ = std::fs::create_dir_all(dir);
    }
    let _ = std::fs::write(f, serde_json::to_string_pretty(cfg).unwrap_or_default());
}

// --------------------------------------------------------------- demarrage

fn autostart_on() -> bool {
    unsafe { RegGetValueW(HKEY_CURRENT_USER, RUN, RUN_NAME, RRF_RT_REG_SZ, None, None, None) }
        .is_ok()
}

fn set_autostart(on: bool) -> bool {
    unsafe {
        if !on {
            let r = RegDeleteKeyValueW(HKEY_CURRENT_USER, RUN, RUN_NAME);
            return r.is_ok() || !autostart_on();
        }
        let Ok(exe) = std::env::current_exe() else { return false };
        let cmd: Vec<u16> = format!("\"{}\"", exe.display()).encode_utf16().chain([0]).collect();
        RegSetKeyValueW(
            HKEY_CURRENT_USER,
            RUN,
            RUN_NAME,
            REG_SZ.0,
            Some(cmd.as_ptr() as _),
            (cmd.len() * 2) as u32,
        )
        .is_ok()
    }
}

// ------------------------------------------------------------------ ecrans

#[derive(Serialize)]
pub struct Monitor {
    id: String,
    label: String,
    width: u32,
    height: u32,
    primary: bool,
}

/// `\\.\DISPLAY2` -> « Écran 2 »
fn label(name: &str, i: usize) -> String {
    let n: String = name.chars().rev().take_while(char::is_ascii_digit).collect();
    let n: String = n.chars().rev().collect();
    format!("Écran {}", if n.is_empty() { (i + 1).to_string() } else { n })
}

/// Ecran choisi s'il est branche, sinon l'ecran principal.
pub fn target_monitor(win: &WebviewWindow) -> Option<tauri::Monitor> {
    let wanted = win.state::<Settings>().0.lock().unwrap().monitor.clone();
    if let Some(name) = wanted {
        let found = win
            .available_monitors()
            .ok()?
            .into_iter()
            .find(|m| m.name().is_some_and(|n| *n == name));
        if found.is_some() {
            return found;
        }
    }
    win.primary_monitor().ok().flatten()
}

// -------------------------------------------------------------- commandes

#[derive(Serialize)]
pub struct SettingsView {
    autostart: bool,
    monitor: Option<String>,
    monitors: Vec<Monitor>,
}

#[tauri::command]
pub fn settings_get(win: WebviewWindow, st: State<Settings>) -> SettingsView {
    let primary = win.primary_monitor().ok().flatten().and_then(|m| m.name().cloned());
    let mut monitors: Vec<Monitor> = win
        .available_monitors()
        .unwrap_or_default()
        .iter()
        .enumerate()
        .map(|(i, m)| {
            let id = m.name().cloned().unwrap_or_default();
            Monitor {
                label: label(&id, i),
                width: m.size().width,
                height: m.size().height,
                primary: primary.as_ref() == Some(&id),
                id,
            }
        })
        .collect();
    monitors.sort_by(|a, b| a.label.cmp(&b.label));
    SettingsView {
        autostart: autostart_on(),
        monitor: st.0.lock().unwrap().monitor.clone(),
        monitors,
    }
}

#[tauri::command]
pub fn settings_autostart(on: bool) -> bool {
    set_autostart(on);
    autostart_on()
}

#[tauri::command]
pub fn settings_monitor(win: WebviewWindow, st: State<Settings>, id: Option<String>) {
    let cfg = {
        let mut cfg = st.0.lock().unwrap();
        cfg.monitor = id;
        cfg.clone()
    };
    save(win.app_handle(), &cfg);
    crate::place(&win);
}

pub fn init(app: &AppHandle) {
    app.manage(Settings(Mutex::new(load(app))));
}
