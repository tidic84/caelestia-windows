//! Reglages : lancement au demarrage, ecran de l'ilot, apparence, meteo,
//! calendriers, fonds, notifications, barre.

use std::path::PathBuf;
use std::sync::Mutex;

use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, State, WebviewWindow};
use windows::core::{w, PCWSTR};
use windows::Win32::System::Registry::{
    RegDeleteKeyValueW, RegGetValueW, RegSetKeyValueW, HKEY_CURRENT_USER, REG_SZ, RRF_RT_REG_SZ,
};

const RUN: PCWSTR = w!(r"Software\Microsoft\Windows\CurrentVersion\Run");
const RUN_NAME: PCWSTR = w!("Ilot");

/// Ce qui est enregistre dans `%APPDATA%\io.github.tidic84.ilot\settings.json`.
/// Le lancement au demarrage n'y figure pas : le registre fait foi.
#[derive(Clone, Serialize, Deserialize)]
#[serde(default)]
pub struct Config {
    /// Nom Windows de l'ecran (`\\.\DISPLAY2`) ; `None` = ecran principal.
    pub monitor: Option<String>,
    /// Variante Material You : tonalspot, vibrant, expressive...
    pub variant: String,
    /// auto (suit Windows), dark, light
    pub mode: String,
    /// Applique la couleur d'accent a Windows
    pub win_accent: bool,
    /// Applique le mode clair / sombre a Windows
    pub win_mode: bool,
    /// Fond de l'ilot : solid, glass, clear, wall (fond d'ecran floute)
    pub island_bg: String,
    pub city: Option<City>,
    /// Adresses iCal (Google Agenda, Outlook...)
    pub icals: Vec<String>,
    /// Rotation des fonds, en minutes (0 = jamais)
    pub rotate_min: u32,
    /// Affiche les notifications dans l'ilot
    pub notif_popups: bool,
    /// Ne pas deranger : plus de notifications dans l'ilot
    pub dnd: bool,
    /// OSD du volume et de la luminosite
    pub osd: bool,
    /// Notifications masquees (« tout effacer » : tout ce qui est <= cet id)
    pub notif_cleared: i64,
    pub notif_hidden: Vec<i64>,
    /// Barre facon Waybar en haut de l'ecran
    pub bar: bool,
    /// Masque la barre des taches Windows (avec la barre)
    pub hide_taskbar: bool,
    /// Barre sans fond : chaque groupe devient un ilot detache
    pub bar_islands: bool,
    /// Fenetres ouvertes dans la barre
    pub bar_tasks: bool,
    /// Barre masquee, affichee quand la souris touche le haut de l'ecran
    pub bar_autohide: bool,
    /// Masquage automatique de la barre des taches avant que l'ilot ne le
    /// force, pour le remettre ensuite (`None` : rien n'a ete change)
    pub taskbar_autohide: Option<bool>,
    /// La touche Windows seule ouvre le lanceur au lieu du menu Demarrer
    pub win_key: bool,
    /// Remappage de la touche Windows modifie depuis le demarrage de Windows
    /// (un redemarrage est alors necessaire)
    pub win_key_boot: Option<crate::winkey::BootRemap>,
}

#[derive(Clone, Serialize, Deserialize)]
pub struct City {
    pub name: String,
    pub lat: f64,
    pub lon: f64,
}

impl Default for Config {
    fn default() -> Self {
        Config {
            monitor: None,
            variant: "tonalspot".into(),
            mode: "dark".into(),
            win_accent: false,
            win_mode: false,
            island_bg: "solid".into(),
            city: None,
            icals: Vec::new(),
            rotate_min: 0,
            notif_popups: true,
            dnd: false,
            osd: true,
            notif_cleared: 0,
            notif_hidden: Vec::new(),
            bar: false,
            hide_taskbar: true,
            bar_islands: true,
            bar_tasks: false,
            bar_autohide: true,
            taskbar_autohide: None,
            win_key: false,
            win_key_boot: None,
        }
    }
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
    monitors: Vec<Monitor>,
    #[serde(flatten)]
    cfg: Config,
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
        monitors,
        cfg: st.0.lock().unwrap().clone(),
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
    crate::bar::sync(win.app_handle());
}

/// Modifie la config, l'enregistre et previent l'interface (`settings`).
pub fn update(app: &AppHandle, f: impl FnOnce(&mut Config)) -> Config {
    let cfg = {
        let st = app.state::<Settings>();
        let mut cfg = st.0.lock().unwrap();
        f(&mut cfg);
        let cleared = cfg.notif_cleared;
        cfg.notif_hidden.retain(|&id| id > cleared);
        cfg.clone()
    };
    save(app, &cfg);
    let _ = app.emit("settings", &cfg);
    cfg
}

/// Fusionne `patch` (un objet JSON partiel) dans la config.
#[tauri::command]
pub fn settings_set(app: AppHandle, patch: serde_json::Value) -> Config {
    let cfg = update(&app, |cfg| {
        let mut v = serde_json::to_value(&*cfg).unwrap_or_default();
        if let (Some(obj), Some(p)) = (v.as_object_mut(), patch.as_object()) {
            for (k, val) in p {
                if !matches!(k.as_str(), "monitor" | "taskbar_autohide" | "win_key_boot") {
                    obj.insert(k.clone(), val.clone());
                }
            }
        }
        if let Ok(new) = serde_json::from_value(v) {
            *cfg = new;
        }
    });
    if ["bar", "hide_taskbar", "bar_autohide"].iter().any(|k| patch.get(k).is_some()) {
        if let Some(win) = app.get_webview_window("island") {
            crate::place(&win);
        }
        crate::bar::sync(&app);
    }
    if patch.get("win_key").is_some() {
        crate::winkey::set(&app, cfg.win_key);
    }
    cfg
}

pub fn init(app: &AppHandle) {
    app.manage(Settings(Mutex::new(load(app))));
}
