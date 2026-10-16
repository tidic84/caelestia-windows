//! Barre sur les autres ecrans : une fenetre `bar-*` (ui/bar.html) en haut de
//! chaque ecran qui n'a pas l'ilot, avec les memes reglages que la barre de
//! l'ilot. Ses boutons ouvrent l'ilot, sur son ecran a lui.

use std::collections::HashMap;
use std::time::{Duration, Instant};

use tauri::{AppHandle, Emitter, Manager, PhysicalPosition, PhysicalSize, WebviewUrl, WebviewWindow, WebviewWindowBuilder};
use windows::Win32::Foundation::{POINT, RECT};
use windows::Win32::UI::WindowsAndMessaging::GetCursorPos;

use crate::{bar, HitMap};

/// Hauteur de la fenetre, en pixels CSS : la barre et l'apercu des fenetres
/// qui s'ouvre dessous. Hors des zones declarees, les clics passent.
const WIN_H: f64 = 240.0;

/// Memes options que la fenetre de l'ilot (tauri.conf.json) : WebView2 refuse
/// deux webviews du meme profil lancees avec des options differentes.
const BROWSER_ARGS: &str =
    "--disable-features=msWebOOUI,msPdfOOUI,msSmartScreenProtection --autoplay-policy=no-user-gesture-required";

/// `\\.\DISPLAY2` -> `bar-DISPLAY2` (un label n'accepte pas les antislashs)
fn label_for(m: &tauri::Monitor) -> String {
    let name: String = m.name().map(String::as_str).unwrap_or("").chars().filter(char::is_ascii_alphanumeric).collect();
    format!("bar-{name}")
}

/// Bouton de la barre d'un autre ecran : ouvre l'onglet `tab` de l'ilot, ou
/// le lanceur.
#[tauri::command]
pub fn bar_open(app: AppHandle, tab: String) {
    if tab == "launcher" {
        crate::toggle_launcher(&app);
    } else {
        crate::open_tab(&app, &tab);
    }
}

fn create(app: &AppHandle, label: &str) -> Option<WebviewWindow> {
    WebviewWindowBuilder::new(app, label, WebviewUrl::App("bar.html".into()))
        .title("Ilot")
        .decorations(false)
        .transparent(true)
        .shadow(false)
        .always_on_top(true)
        .skip_taskbar(true)
        .resizable(false)
        .focused(false)
        .visible(false)
        .additional_browser_args(BROWSER_ARGS)
        .build()
        .ok()
}

/// En haut de l'ecran, sur toute sa largeur ; le haut de l'ecran est reserve
/// sauf si la barre se masque automatiquement.
fn place(win: &WebviewWindow, m: &tauri::Monitor) {
    let scale = m.scale_factor();
    let (pos, size) = (m.position(), m.size());
    let target = PhysicalSize::new(size.width, ((WIN_H * scale).round() as u32).min(size.height));
    if win.outer_size().ok() != Some(target) {
        let _ = win.set_size(target);
    }
    let at = PhysicalPosition::new(pos.x, pos.y);
    if win.outer_position().ok() != Some(at) {
        let _ = win.set_position(at);
    }
    bar::reserve(
        win,
        (!bar::autohide(win.app_handle())).then(|| RECT {
            left: pos.x,
            top: pos.y,
            right: pos.x + size.width as i32,
            bottom: pos.y + (bar::BAR_H * scale).round() as i32,
        }),
    );
}

/// Cree, place ou ferme les barres selon les ecrans branches et les reglages.
fn sync(app: &AppHandle) {
    let Some(island) = app.get_webview_window("island") else { return };
    let own = crate::settings::target_monitor(&island).and_then(|m| m.name().cloned());
    let wanted: Vec<tauri::Monitor> = if bar::enabled(app) {
        island
            .available_monitors()
            .unwrap_or_default()
            .into_iter()
            .filter(|m| m.name().is_some() && m.name() != own.as_ref())
            .collect()
    } else {
        Vec::new()
    };
    for (label, win) in app.webview_windows() {
        if label.starts_with("bar-") && !wanted.iter().any(|m| label_for(m) == label) {
            bar::reserve(&win, None);
            let _ = win.destroy();
        }
    }
    for m in &wanted {
        let label = label_for(m);
        if let Some(win) = app.get_webview_window(&label) {
            place(&win, m);
        } else if let Some(win) = create(app, &label) {
            let _ = win.set_ignore_cursor_events(true);
            place(&win, m);
            let _ = win.show();
        }
    }
}

/// Etat d'une barre suivi par la boucle
#[derive(Default)]
struct Track {
    inside: bool,
    top: bool,
    hidden: bool,
}

/// Suit les ecrans et le curseur pour les barres des autres ecrans, comme
/// `track_cursor` pour l'ilot : passage des clics hors des zones declarees,
/// bande du haut (`bar-top`) et plein ecran (`bar-fullscreen`). Les
/// evenements portent le label de la barre visee. Les barres ne sont
/// recreees / replacees que quand les ecrans changent (ou toutes les 3 s
/// pour les reglages), et sans barre la boucle ralentit.
pub fn watch(app: AppHandle, hit: HitMap) {
    std::thread::spawn(move || {
        let mut tracks: HashMap<String, Track> = HashMap::new();
        let mut screens = None;
        let mut next_sync = Instant::now();
        let mut next_fs = Instant::now();
        loop {
            let now = Instant::now();
            if now >= next_sync || tracks.is_empty() || now >= next_fs {
                let sig = crate::monitors_sig();
                if screens.as_ref() != Some(&sig) || now >= next_sync {
                    screens = Some(sig);
                    next_sync = now + Duration::from_secs(3);
                    sync(&app);
                }
            }
            let wins: Vec<(String, WebviewWindow)> =
                app.webview_windows().into_iter().filter(|(l, _)| l.starts_with("bar-")).collect();
            tracks.retain(|l, _| wins.iter().any(|(w, _)| w == l));
            if wins.is_empty() {
                std::thread::sleep(Duration::from_millis(500));
                continue;
            }
            std::thread::sleep(Duration::from_millis(25));
            let fs_check = now >= next_fs;
            if fs_check {
                next_fs = now + Duration::from_millis(500);
            }
            let mut pt = POINT::default();
            let cursor = unsafe { GetCursorPos(&mut pt) }.is_ok();
            for (label, win) in wins {
                let t = tracks.entry(label.clone()).or_default();
                let Ok(h) = win.hwnd() else { continue };
                if fs_check {
                    let fs = crate::fullscreen_foreground(h);
                    if fs != t.hidden {
                        t.hidden = fs;
                        let _ = app.emit("bar-fullscreen", (&label, fs));
                        if fs {
                            let _ = win.hide();
                        } else {
                            let _ = win.show();
                        }
                    }
                }
                let Some((x, y, w, scale)) = crate::geom(h) else { continue };
                let (inside, top) = if t.hidden || !cursor {
                    (false, false)
                } else {
                    let cx = (pt.x - x) as f64 / scale;
                    let cy = (pt.y - y) as f64 / scale;
                    hit.lock()
                        .unwrap()
                        .get(&label)
                        .map_or((false, false), |h| {
                            let (inside, _, top) = h.test(cx, cy, w as f64 / scale);
                            (inside, top)
                        })
                };
                if inside != t.inside {
                    t.inside = inside;
                    let _ = win.set_ignore_cursor_events(!inside);
                }
                if top != t.top {
                    t.top = top;
                    let _ = app.emit("bar-top", (&label, top));
                }
            }
        }
    });
}
