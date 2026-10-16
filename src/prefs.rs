//! Raccourcis clavier globaux configurables (Apparence > Raccourcis) et
//! sauvegarde / restauration de tous les reglages dans un seul fichier.

use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, Ordering};
use std::sync::Mutex;

use crate::host::AppHandle;
use windows::Win32::Foundation::{LPARAM, WPARAM};
use windows::Win32::System::Threading::GetCurrentThreadId;
use windows::Win32::UI::Input::KeyboardAndMouse::{
    RegisterHotKey, UnregisterHotKey, HOT_KEY_MODIFIERS, MOD_ALT, MOD_CONTROL, MOD_NOREPEAT, MOD_SHIFT, MOD_WIN,
};
use windows::Win32::UI::WindowsAndMessaging::{
    GetMessageW, PeekMessageW, PostThreadMessageW, MSG, PM_NOREMOVE, WM_APP, WM_HOTKEY, WM_USER,
};

// ---------------------------------------------------------- raccourcis

/// Combinaison au format de l'interface : « Ctrl+Alt+KeyM », « Shift+F5 »,
/// « Ctrl+Digit1 », « Alt+Numpad3 » ou « Ctrl+VK188 » (code de touche Windows).
fn parse(combo: &str) -> Option<(HOT_KEY_MODIFIERS, u32)> {
    let mut mods = HOT_KEY_MODIFIERS(0);
    let mut vk = None;
    for part in combo.split('+') {
        match part {
            "Ctrl" => mods |= MOD_CONTROL,
            "Alt" => mods |= MOD_ALT,
            "Shift" => mods |= MOD_SHIFT,
            "Super" | "Win" => mods |= MOD_WIN,
            k => vk = Some(key_code(k)?),
        }
    }
    let vk = vk?;
    // une touche seule bloquerait la frappe partout (sauf F1-F24)
    if mods.0 == 0 && !(0x70..=0x87).contains(&vk) {
        return None;
    }
    Some((mods, vk))
}

fn key_code(k: &str) -> Option<u32> {
    let one = |s: &str| (s.len() == 1).then(|| s.as_bytes()[0]);
    if let Some(c) = k.strip_prefix("Key").and_then(one).filter(u8::is_ascii_uppercase) {
        return Some(c as u32);
    }
    if let Some(c) = k.strip_prefix("Digit").and_then(one).filter(u8::is_ascii_digit) {
        return Some(c as u32);
    }
    if let Some(c) = k.strip_prefix("Numpad").and_then(one).filter(u8::is_ascii_digit) {
        return Some(0x60 + (c - b'0') as u32);
    }
    if let Some(n) = k.strip_prefix('F').and_then(|n| n.parse::<u32>().ok()).filter(|n| (1..=24).contains(n)) {
        return Some(0x70 + n - 1);
    }
    if let Some(n) = k.strip_prefix("VK").and_then(|n| n.parse::<u32>().ok()).filter(|n| (1..255).contains(n)) {
        return Some(n);
    }
    Some(match k {
        "Space" => 0x20,
        "Enter" => 0x0D,
        "Tab" => 0x09,
        "ArrowLeft" => 0x25,
        "ArrowUp" => 0x26,
        "ArrowRight" => 0x27,
        "ArrowDown" => 0x28,
        "Insert" => 0x2D,
        "Home" => 0x24,
        "End" => 0x23,
        "PageUp" => 0x21,
        "PageDown" => 0x22,
        _ => return None,
    })
}

/// Raccourcis configures (action -> combinaison) et thread qui les recoit
static KEYS: Mutex<Vec<String>> = Mutex::new(Vec::new());
static THREAD: AtomicU32 = AtomicU32::new(0);
/// Reponse du thread : actions refusees (deja prises par une autre appli...)
static FAILED: Mutex<Option<std::sync::mpsc::Sender<Vec<String>>>> = Mutex::new(None);
const WM_RELOAD: u32 = WM_APP + 7;

/// Thread des raccourcis : `RegisterHotKey` sans fenetre poste WM_HOTKEY au
/// thread qui l'a appele.
fn start(app: AppHandle) {
    let (tx, rx) = std::sync::mpsc::channel();
    std::thread::spawn(move || unsafe {
        // la file de messages du thread n'existe qu'apres un premier appel :
        // sans elle, PostThreadMessageW (reload) echouerait
        let mut msg = MSG::default();
        let _ = PeekMessageW(&mut msg, None, WM_USER, WM_USER, PM_NOREMOVE);
        THREAD.store(GetCurrentThreadId(), Ordering::SeqCst);
        let _ = tx.send(());
        let mut actions: Vec<String> = Vec::new();
        while GetMessageW(&mut msg, None, 0, 0).as_bool() {
            if msg.message == WM_RELOAD {
                for i in 0..actions.len() {
                    let _ = UnregisterHotKey(None, i as i32 + 1);
                }
                actions.clear();
                let mut failed = Vec::new();
                let map: HashMap<String, String> = crate::store::read("shortcuts").unwrap_or_default();
                for (action, combo) in map {
                    if combo.is_empty() {
                        continue;
                    }
                    match parse(&combo) {
                        Some((mods, vk)) if RegisterHotKey(None, actions.len() as i32 + 1, mods | MOD_NOREPEAT, vk).is_ok() => {
                            actions.push(action)
                        }
                        _ => failed.push(action),
                    }
                }
                *KEYS.lock().unwrap() = actions.clone();
                if let Some(t) = FAILED.lock().unwrap().as_ref() {
                    let _ = t.send(failed);
                }
            } else if msg.message == WM_HOTKEY {
                let Some(action) = actions.get((msg.wParam.0 as usize).wrapping_sub(1)).cloned() else { continue };
                // la lecture se commande sans prendre le clavier du jeu ou de l'appli en cours
                if !matches!(action.as_str(), "play" | "next" | "captions") {
                    if let Some(w) = app.get_webview_window("island") {
                        let _ = w.set_focus();
                    }
                }
                let _ = app.emit("shortcut", action);
            }
        }
    });
    let _ = rx.recv_timeout(std::time::Duration::from_secs(2));
}

/// Fait relire les raccourcis au thread ; renvoie les actions refusees.
fn reload() -> Vec<String> {
    let (tx, rx) = std::sync::mpsc::channel();
    *FAILED.lock().unwrap() = Some(tx);
    let t = THREAD.load(Ordering::SeqCst);
    if t == 0 || unsafe { PostThreadMessageW(t, WM_RELOAD, WPARAM(0), LPARAM(0)) }.is_err() {
        return Vec::new();
    }
    rx.recv_timeout(std::time::Duration::from_secs(2)).unwrap_or_default()
}

/// Remplace les raccourcis configures ; renvoie ceux qui n'ont pas pu etre
/// pris (format inconnu, ou deja utilises par une autre appli).
pub fn shortcuts_set(map: HashMap<String, String>) -> Vec<String> {
    crate::store::write("shortcuts", &map);
    reload()
}

pub fn shortcuts_get() -> HashMap<String, String> {
    crate::store::read("shortcuts").unwrap_or_default()
}

/// Au demarrage : raccourcis enregistres.
pub fn init(app: &AppHandle) {
    start(*app);
    if !shortcuts_get().is_empty() {
        reload();
    }
}

// ----------------------------------------------------------- sauvegarde

/// Fichiers jamais exportes : mots de passe des mails, jetons Discord et Google.
const SECRET: &[&str] = &["mail", "discord", "google"];

/// Date du jour « AAAA-MM-JJ » (UTC), sans dependance de plus.
fn today() -> String {
    let secs = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs()) as i64;
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
}

/// Ecrit les reglages de l'ilot et tous ses petits fichiers (dossiers d'applis,
/// notes, soundboard, profils...) dans Telechargements\Ilot-reglages-<date>.json,
/// puis l'affiche dans l'Explorateur.
pub fn settings_export(app: AppHandle) -> Option<String> {
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
    let settings = serde_json::to_value(&*app.state::<crate::settings::Settings>().0.lock().unwrap()).ok()?;
    let out = serde_json::json!({ "ilot": 2, "files": files, "settings": settings });
    let dir = std::path::Path::new(&std::env::var("USERPROFILE").ok()?).join("Downloads");
    let path = dir.join(format!("Ilot-reglages-{}.json", today()));
    std::fs::write(&path, serde_json::to_string_pretty(&out).ok()?).ok()?;
    crate::games::reveal(&path);
    Some(path.to_string_lossy().to_string())
}

/// Restaure une sauvegarde choisie dans une boite « Ouvrir » ; Ok(false) si
/// rien n'a ete choisi. L'interface relance ensuite l'ilot.
pub fn settings_import(app: AppHandle) -> Result<bool, String> {
    let Some(path) = crate::games::pick_files(app, "Restaurer les réglages d'Ilot", "Sauvegarde d'Ilot", "*.json").into_iter().next() else {
        return Ok(false);
    };
    let content = std::fs::read_to_string(&path).map_err(|e| e.to_string())?;
    let v: serde_json::Value = serde_json::from_str(&content).map_err(|_| "fichier illisible".to_string())?;
    let files = v["files"].as_object().filter(|_| v["ilot"].is_number()).ok_or("ce n'est pas une sauvegarde d'Ilot")?;
    for (key, val) in files {
        if !SECRET.contains(&key.as_str()) {
            crate::store::write(key, val);
        }
    }
    // sauvegarde de l'ancienne interface : pas de reglages generaux
    if v["settings"].is_object() {
        crate::settings::settings_set(app, v["settings"].clone());
    }
    Ok(true)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn combos() {
        assert_eq!(parse("Ctrl+Alt+KeyM").map(|(m, k)| (m.0, k)), Some(((MOD_CONTROL | MOD_ALT).0, 'M' as u32)));
        assert_eq!(parse("F5").map(|(_, k)| k), Some(0x74));
        assert_eq!(parse("Shift+Digit1").map(|(_, k)| k), Some('1' as u32));
        assert_eq!(parse("Ctrl+VK188").map(|(_, k)| k), Some(188));
        assert!(parse("KeyM").is_none());
        assert!(parse("Ctrl+Pomme").is_none());
    }
}
