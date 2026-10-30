//! Reglages : lancement au demarrage, ecran de l'ilot, apparence, meteo,
//! calendriers, fonds, notifications, barre, addons, mises a jour.

use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Command, Stdio};
use std::sync::Mutex;

use serde::{Deserialize, Serialize};
use crate::host::{AppHandle, State};
use windows::core::{w, PCWSTR};
use windows::Win32::System::Registry::{
    RegDeleteKeyValueW, RegGetValueW, RegSetKeyValueW, HKEY_CURRENT_USER, REG_SZ, RRF_RT_REG_SZ,
};

const RUN: PCWSTR = w!(r"Software\Microsoft\Windows\CurrentVersion\Run");
const RUN_NAME: PCWSTR = w!("Ilot");
/// Tache planifiee du lancement au demarrage (racine du Planificateur).
const TASK: &str = "Ilot";
const CREATE_NO_WINDOW: u32 = 0x0800_0000;

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
    /// Addons actives (onglets facultatifs : mail, pc, sounds...) ; les
    /// onglets essentiels (accueil, media, controles, apps, reglages) sont
    /// toujours la
    pub addons: Vec<String>,
    /// Mises a jour : auto (telechargees et installees), notify (prevenir
    /// seulement), off
    pub update_mode: String,
    /// Reglages de l'interface seule (apparence de la pilule, compagnon,
    /// accessibilite, mode jeu...) : gardes tels quels, l'interface les lit
    #[serde(flatten)]
    pub extra: serde_json::Map<String, serde_json::Value>,
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
            addons: Vec::new(),
            update_mode: "notify".into(),
            extra: serde_json::Map::new(),
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
//
// Lancement par une tache planifiee « a l'ouverture de session » : la cle
// `Run` passe par la file de l'Explorateur, qui lance ses entrees une a une
// (l'ilot arrivait 2 a 3 min apres l'ouverture de session). La cle `Run`
// reste le repli si le Planificateur refuse la tache.

fn schtasks(args: &[&str]) -> bool {
    Command::new("schtasks.exe")
        .args(args)
        .creation_flags(CREATE_NO_WINDOW)
        .stdin(Stdio::null())
        .stdout(Stdio::null())
        .stderr(Stdio::null())
        .status()
        .is_ok_and(|s| s.success())
}

fn task_on() -> bool {
    schtasks(&["/Query", "/TN", TASK])
}

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

/// Tache de l'utilisateur courant, sans droits admin. `--autostart` : l'ilot
/// attend la barre de l'Explorateur (main.cpp). Priorite normale (7 par
/// defaut, sous la normale) et pas de limite de duree (72 h par defaut).
fn task_create(exe: &Path) -> bool {
    let user = match (std::env::var("USERDOMAIN"), std::env::var("USERNAME")) {
        (Ok(d), Ok(u)) => format!("{d}\\{u}"),
        (_, Ok(u)) => u,
        _ => return false,
    };
    let dir = exe.parent().map(|d| d.display().to_string()).unwrap_or_default();
    let xml = format!(
        r#"<?xml version="1.0" encoding="UTF-16"?>
<Task version="1.2" xmlns="http://schemas.microsoft.com/windows/2004/02/mit/task">
  <RegistrationInfo><Description>Lance l'ilot a l'ouverture de session.</Description></RegistrationInfo>
  <Triggers>
    <LogonTrigger><Enabled>true</Enabled><UserId>{user}</UserId></LogonTrigger>
  </Triggers>
  <Principals>
    <Principal id="Author"><UserId>{user}</UserId><LogonType>InteractiveToken</LogonType><RunLevel>LeastPrivilege</RunLevel></Principal>
  </Principals>
  <Settings>
    <MultipleInstancesPolicy>IgnoreNew</MultipleInstancesPolicy>
    <DisallowStartIfOnBatteries>false</DisallowStartIfOnBatteries>
    <StopIfGoingOnBatteries>false</StopIfGoingOnBatteries>
    <AllowHardTerminate>true</AllowHardTerminate>
    <StartWhenAvailable>false</StartWhenAvailable>
    <IdleSettings><StopOnIdleEnd>false</StopOnIdleEnd><RestartOnIdle>false</RestartOnIdle></IdleSettings>
    <AllowStartOnDemand>true</AllowStartOnDemand>
    <Enabled>true</Enabled>
    <Hidden>false</Hidden>
    <ExecutionTimeLimit>PT0S</ExecutionTimeLimit>
    <Priority>4</Priority>
  </Settings>
  <Actions Context="Author">
    <Exec><Command>{exe}</Command><Arguments>--autostart</Arguments><WorkingDirectory>{dir}</WorkingDirectory></Exec>
  </Actions>
</Task>
"#,
        user = xml_escape(&user),
        exe = xml_escape(&exe.display().to_string()),
        dir = xml_escape(&dir),
    );
    // schtasks lit l'XML en UTF-16 (avec BOM)
    let bytes: Vec<u8> = std::iter::once(0xFEFF)
        .chain(xml.encode_utf16())
        .flat_map(u16::to_le_bytes)
        .collect();
    let f = std::env::temp_dir().join(format!("ilot-task-{}.xml", std::process::id()));
    if std::fs::write(&f, bytes).is_err() {
        return false;
    }
    let Some(fs) = f.to_str() else { return false };
    let ok = schtasks(&["/Create", "/TN", TASK, "/XML", fs, "/F"]);
    let _ = std::fs::remove_file(&f);
    ok
}

fn run_on() -> bool {
    unsafe { RegGetValueW(HKEY_CURRENT_USER, RUN, RUN_NAME, RRF_RT_REG_SZ, None, None, None) }
        .is_ok()
}

/// Chemin enregistre dans la cle `Run` (sans les guillemets).
fn run_exe() -> Option<PathBuf> {
    let mut buf = [0u16; 1024];
    let mut len = (buf.len() * 2) as u32;
    unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            RUN,
            RUN_NAME,
            RRF_RT_REG_SZ,
            None,
            Some(buf.as_mut_ptr() as _),
            Some(&mut len),
        )
    }
    .ok()
    .ok()?;
    let n = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
    let s = String::from_utf16_lossy(&buf[..n]);
    let s = s.trim().trim_matches('"');
    (!s.is_empty()).then(|| PathBuf::from(s))
}

fn run_set(exe: &Path) -> bool {
    let cmd: Vec<u16> = format!("\"{}\"", exe.display()).encode_utf16().chain([0]).collect();
    unsafe {
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

fn run_delete() {
    let _ = unsafe { RegDeleteKeyValueW(HKEY_CURRENT_USER, RUN, RUN_NAME) };
}

fn autostart_on() -> bool {
    task_on() || run_on()
}

fn set_autostart(on: bool) -> bool {
    if !on {
        run_delete();
        if task_on() {
            schtasks(&["/Delete", "/TN", TASK, "/F"]);
        }
        return !autostart_on();
    }
    let Ok(exe) = std::env::current_exe() else { return false };
    if task_create(&exe) {
        run_delete();
        return true;
    }
    run_set(&exe)
}

/// Ancien lancement par la cle `Run` : remplace par la tache, vers le meme
/// executable. La cle reste si la tache n'a pas pu etre creee.
fn migrate_autostart() {
    let Some(exe) = run_exe() else { return };
    if exe.is_file() && task_create(&exe) {
        run_delete();
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
pub fn target_screen(app: &AppHandle) -> Option<crate::Screen> {
    let wanted = app.state::<Settings>().0.lock().unwrap().monitor.clone();
    let list = crate::screens();
    if let Some(name) = wanted {
        if let Some(s) = list.iter().find(|s| s.name == name) {
            return Some(s.clone());
        }
    }
    list.into_iter().find(|s| s.primary)
}

// -------------------------------------------------------------- commandes

#[derive(Serialize)]
pub struct SettingsView {
    autostart: bool,
    monitors: Vec<Monitor>,
    #[serde(flatten)]
    cfg: Config,
}

pub fn settings_get(st: State<Settings>) -> SettingsView {
    let mut monitors: Vec<Monitor> = crate::screens()
        .into_iter()
        .enumerate()
        .map(|(i, m)| Monitor {
            label: label(&m.name, i),
            width: m.width as u32,
            height: m.height as u32,
            primary: m.primary,
            id: m.name,
        })
        .collect();
    monitors.sort_by(|a, b| a.label.cmp(&b.label));
    SettingsView {
        autostart: autostart_on(),
        monitors,
        cfg: st.0.lock().unwrap().clone(),
    }
}

pub fn settings_autostart(on: bool) -> bool {
    set_autostart(on);
    autostart_on()
}

pub fn settings_monitor(app: AppHandle, st: State<Settings>, id: Option<String>) {
    let cfg = {
        let mut cfg = st.0.lock().unwrap();
        cfg.monitor = id;
        cfg.clone()
    };
    save(&app, &cfg);
    // l'interface replace ses fenetres
    let _ = app.emit("@place", ());
    crate::bar::sync(&app);
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
pub fn settings_set(app: AppHandle, patch: serde_json::Value) -> Config {
    let cfg = update(&app, |cfg| {
        let mut v = serde_json::to_value(&*cfg).unwrap_or_default();
        if let (Some(obj), Some(p)) = (v.as_object_mut(), patch.as_object()) {
            for (k, val) in p {
                if !matches!(k.as_str(), "monitor" | "taskbar_autohide" | "win_key_boot" | "autostart" | "monitors") {
                    obj.insert(k.clone(), val.clone());
                }
            }
        }
        if let Ok(new) = serde_json::from_value(v) {
            *cfg = new;
        }
    });
    if ["bar", "hide_taskbar", "bar_autohide"].iter().any(|k| patch.get(k).is_some()) {
        let _ = app.emit("@place", ());
        crate::bar::sync(&app);
    }
    if patch.get("win_key").is_some() {
        crate::winkey::set(&app, cfg.win_key);
    }
    cfg
}

/// Addon (onglet facultatif) active dans Reglages > Addons : ses releves en
/// arriere-plan (mail, etat des services...) ne tournent que dans ce cas.
pub fn addon_on(app: &AppHandle, id: &str) -> bool {
    app.state::<Settings>().0.lock().unwrap().addons.iter().any(|a| a == id)
}

pub fn init(app: &AppHandle) {
    app.manage(Settings(Mutex::new(load(app))));
    std::thread::spawn(migrate_autostart);
}
