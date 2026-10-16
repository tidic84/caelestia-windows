//! Reglages « systeme » de l'ilot : position de la pilule (haut / bas, ecran),
//! raccourcis clavier globaux configurables et sauvegarde / restauration de
//! tous les reglages dans un seul fichier.

use std::collections::HashMap;
use std::sync::Mutex;

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, Monitor, WebviewWindow};
use tauri_plugin_global_shortcut::{GlobalShortcutExt, Shortcut};

// ------------------------------------------------------------ position

/// (en bas de l'ecran, ecran choisi : None = principal)
static PLACE: Mutex<(bool, Option<usize>)> = Mutex::new((false, None));

fn monitor_of(win: &WebviewWindow) -> Option<Monitor> {
    let (_, idx) = *PLACE.lock().unwrap();
    if let Some(i) = idx {
        if let Some(m) = win.available_monitors().ok().and_then(|v| v.into_iter().nth(i)) {
            return Some(m);
        }
    }
    win.primary_monitor().ok().flatten()
}

/// Place la fenetre en haut (ou en bas, au-dessus de la barre des taches),
/// au centre de l'ecran choisi.
pub fn place(win: &WebviewWindow) {
    let Some(mon) = monitor_of(win) else { return };
    let Ok(size) = win.outer_size() else { return };
    let bottom = PLACE.lock().unwrap().0;
    let mpos = mon.position();
    let msize = mon.size();
    let x = mpos.x + (msize.width as i32 - size.width as i32) / 2;
    let y = if bottom {
        let wa = mon.work_area();
        wa.position.y + wa.size.height as i32 - size.height as i32
    } else {
        mpos.y
    };
    let _ = win.set_position(tauri::PhysicalPosition::new(x, y));
}

#[tauri::command]
pub fn set_placement(win: WebviewWindow, bottom: bool, monitor: Option<usize>) {
    *PLACE.lock().unwrap() = (bottom, monitor);
    place(&win);
}

#[derive(Serialize)]
pub struct MonitorInfo {
    name: String,
    primary: bool,
}

#[tauri::command]
pub fn monitors_list(win: WebviewWindow) -> Vec<MonitorInfo> {
    let primary = win.primary_monitor().ok().flatten().map(|m| *m.position());
    win.available_monitors()
        .unwrap_or_default()
        .iter()
        .enumerate()
        .map(|(i, m)| MonitorInfo {
            name: format!("Écran {} ({}×{})", i + 1, m.size().width, m.size().height),
            primary: Some(*m.position()) == primary,
        })
        .collect()
}

// ---------------------------------------------------------- raccourcis

/// Raccourcis configures : (raccourci, action). L'action est un onglet
/// (« media », « pc »...) ou « toggle » / « play » / « next ».
static KEYS: Mutex<Vec<(Shortcut, String)>> = Mutex::new(Vec::new());

/// Appele par le gestionnaire du plugin : vrai si le raccourci est configure.
pub fn on_shortcut(app: &AppHandle, sc: &Shortcut) -> bool {
    let action = KEYS.lock().unwrap().iter().find(|(s, _)| s.id() == sc.id()).map(|(_, a)| a.clone());
    let Some(action) = action else { return false };
    if let Some(win) = app.get_webview_window("island") {
        // la lecture se commande sans prendre le focus du jeu ou de l'appli en cours
        if !matches!(action.as_str(), "play" | "next" | "captions") {
            let _ = win.set_ignore_cursor_events(false);
            let _ = win.set_focus();
        }
        let _ = win.emit("shortcut", action);
    }
    true
}

/// Remplace les raccourcis configures ; renvoie ceux qui n'ont pas pu etre pris
/// (format inconnu, ou deja utilises par une autre appli).
#[tauri::command]
pub fn shortcuts_set(app: AppHandle, map: HashMap<String, String>) -> Vec<String> {
    let gs = app.global_shortcut();
    let mut keys = KEYS.lock().unwrap();
    for (s, _) in keys.drain(..) {
        let _ = gs.unregister(s);
    }
    let mut failed = Vec::new();
    for (action, combo) in &map {
        if combo.is_empty() {
            continue;
        }
        match combo.parse::<Shortcut>() {
            Ok(s) if gs.register(s).is_ok() => keys.push((s, action.clone())),
            _ => failed.push(action.clone()),
        }
    }
    crate::store::write("shortcuts", &map);
    failed
}

#[tauri::command]
pub fn shortcuts_get() -> HashMap<String, String> {
    crate::store::read("shortcuts").unwrap_or_default()
}

/// Au demarrage : raccourcis enregistres.
pub fn load_shortcuts(app: &AppHandle) {
    let map = shortcuts_get();
    if !map.is_empty() {
        shortcuts_set(app.clone(), map);
    }
}

// ----------------------------------------------------------- sauvegarde

/// Fichiers jamais exportes : mots de passe des mails, jetons Discord.
const SECRET: &[&str] = &["mail", "discord"];

/// Ecrit tous les reglages (+ `local` : ce que la page garde de son cote) dans
/// Telechargements\Ilot-reglages-<date>.json et l'affiche dans l'Explorateur.
#[tauri::command(async)]
pub fn settings_export(local: serde_json::Value) -> Option<String> {
    let mut files = serde_json::Map::new();
    for e in std::fs::read_dir(crate::store::data_dir()).ok()?.flatten() {
        let name = e.file_name().to_string_lossy().to_string();
        let Some(key) = name.strip_suffix(".json") else { continue };
        if SECRET.contains(&key) {
            continue;
        }
        if let Some(v) = crate::store::read::<serde_json::Value>(key) {
            files.insert(key.to_string(), v);
        }
    }
    let out = serde_json::json!({ "ilot": 1, "files": files, "local": local });
    let day = {
        let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).ok()?.as_secs() as i64;
        // date civile depuis le nombre de jours (algorithme de H. Hinnant)
        let z = secs / 86400 + 719468;
        let era = z.div_euclid(146097);
        let doe = z - era * 146097;
        let yoe = (doe - doe / 1460 + doe / 36524 - doe / 146096) / 365;
        let doy = doe - (365 * yoe + yoe / 4 - yoe / 100);
        let mp = (5 * doy + 2) / 153;
        let d = doy - (153 * mp + 2) / 5 + 1;
        let m = if mp < 10 { mp + 3 } else { mp - 9 };
        let y = yoe + era * 400 + i64::from(m <= 2);
        format!("{y}-{m:02}-{d:02}")
    };
    let dir = std::path::Path::new(&std::env::var("USERPROFILE").ok()?).join("Downloads");
    let path = dir.join(format!("Ilot-reglages-{day}.json"));
    std::fs::write(&path, serde_json::to_string_pretty(&out).ok()?).ok()?;
    let _ = std::process::Command::new("explorer.exe").arg(format!("/select,{}", path.display())).spawn();
    Some(path.to_string_lossy().to_string())
}

/// Restaure un fichier de sauvegarde ; renvoie sa partie `local` (ou une erreur).
#[tauri::command(async)]
pub fn settings_import(content: String) -> Result<serde_json::Value, String> {
    let v: serde_json::Value = serde_json::from_str(&content).map_err(|_| "fichier illisible".to_string())?;
    let files = v["files"].as_object().filter(|_| v["ilot"].is_number()).ok_or("ce n'est pas une sauvegarde d'Ilot")?;
    for (key, val) in files {
        if !SECRET.contains(&key.as_str()) {
            crate::store::write(key, val);
        }
    }
    Ok(v["local"].clone())
}

// ---------------------------------------------------- compagnon baladeur

/// Fenetre transparente, sans clic, juste au-dessus de la barre des taches :
/// le compagnon de la pilule s'y promene quand le PC est inactif (pet.html).
#[tauri::command]
pub fn pet_walk(app: AppHandle, on: bool) -> bool {
    let Some(island) = app.get_webview_window("island") else { return false };
    let pet = match app.get_webview_window("pet") {
        Some(w) => w,
        None if on => {
            let Ok(w) = tauri::WebviewWindowBuilder::new(&app, "pet", tauri::WebviewUrl::App("pet.html".into()))
                .title("Ilot compagnon")
                .transparent(true)
                .decorations(false)
                .shadow(false)
                .always_on_top(true)
                .skip_taskbar(true)
                .resizable(false)
                .focused(false)
                .visible(false)
                .disable_drag_drop_handler()
                .build()
            else {
                return false;
            };
            w
        }
        None => return true,
    };
    if !on {
        let _ = pet.hide();
        return true;
    }
    let Some(mon) = monitor_of(&island) else { return false };
    let wa = mon.work_area();
    let h = (90.0 * mon.scale_factor()) as u32;
    let _ = pet.set_size(tauri::PhysicalSize::new(wa.size.width, h));
    let _ = pet.set_position(tauri::PhysicalPosition::new(wa.position.x, wa.position.y + wa.size.height as i32 - h as i32));
    let _ = pet.set_ignore_cursor_events(true);
    let _ = pet.show();
    true
}
