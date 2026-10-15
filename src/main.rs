#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod apps;
mod audio;
mod display;
mod media;
mod net;
mod notif;
mod settings;
mod system;
mod theme;
mod wall;
mod we;

use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager, PhysicalPosition, State, WebviewWindow, WindowEvent};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};
use windows::Win32::Foundation::{HWND, POINT, RECT};
use windows::Win32::Graphics::Gdi::{GetMonitorInfoW, MonitorFromWindow, MONITORINFO, MONITOR_DEFAULTTONEAREST};
use windows::Win32::System::Com::{
    CoInitializeEx, COINIT_APARTMENTTHREADED, COINIT_MULTITHREADED,
};
use windows::Win32::UI::WindowsAndMessaging::{
    GetClassNameW, GetCursorPos, GetForegroundWindow, GetWindowRect, IsZoomed,
};

pub fn com_init_mta() {
    unsafe {
        let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
    }
}

pub fn com_init_sta() {
    unsafe {
        let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED);
    }
}

/// Zone interactive de l'ilot, en pixels CSS relatifs a la fenetre.
/// Hors de cette zone, la fenetre (transparente) laisse passer la souris.
#[derive(Default, Clone, Copy)]
struct Hit {
    x: f64,
    y: f64,
    w: f64,
    h: f64,
}

struct HitState(Arc<Mutex<Hit>>);

#[tauri::command]
fn set_hit(st: State<HitState>, x: f64, y: f64, w: f64, h: f64) {
    *st.0.lock().unwrap() = Hit { x, y, w, h };
}

/// `ilot.exe --open <onglet>` : ouvre le panneau au demarrage (tests, captures).
#[tauri::command]
fn startup_tab() -> Option<String> {
    let args: Vec<String> = std::env::args().collect();
    let i = args.iter().position(|a| a == "--open")?;
    Some(args.get(i + 1).cloned().unwrap_or_else(|| "home".into()))
}

#[tauri::command]
fn grab_focus(win: WebviewWindow) {
    let _ = win.set_ignore_cursor_events(false);
    let _ = win.set_focus();
}

/// Place la fenetre en haut, au centre de l'ecran choisi dans les reglages
/// (l'ecran principal par defaut, ou si l'ecran choisi est debranche).
pub fn place(win: &WebviewWindow) {
    let Some(mon) = settings::target_monitor(win) else { return };
    let Ok(size) = win.outer_size() else { return };
    let mpos = mon.position();
    let msize = mon.size();
    let x = mpos.x + (msize.width as i32 - size.width as i32) / 2;
    let target = PhysicalPosition::new(x, mpos.y);
    if win.outer_position().ok() != Some(target) {
        let _ = win.set_position(target);
    }
}

/// Suit le curseur : active/desactive le passage des clics selon qu'il est
/// dans la zone de l'ilot, et previent l'interface (`hover`).
fn track_cursor(win: WebviewWindow, hit: Arc<Mutex<Hit>>) {
    std::thread::spawn(move || {
        let mut inside = false;
        let mut hidden = false;
        let mut tick = 0u32;
        let own = win.hwnd().unwrap_or_default();
        let _ = win.set_ignore_cursor_events(true);
        loop {
            std::thread::sleep(Duration::from_millis(25));
            tick = tick.wrapping_add(1);
            // ecran branche / debranche, resolution modifiee : on se recale
            if tick % 80 == 0 && !hidden {
                place(&win);
            }
            if tick % 20 == 0 {
                let fs = fullscreen_foreground(own);
                if fs != hidden {
                    hidden = fs;
                    let _ = win.emit("fullscreen", fs);
                    // la fenetre est reellement masquee pour ne pas gener le jeu
                    if fs {
                        std::thread::sleep(Duration::from_millis(400));
                        let _ = win.hide();
                    } else {
                        let _ = win.show();
                    }
                }
            }
            if hidden {
                if inside {
                    inside = false;
                    let _ = win.set_ignore_cursor_events(true);
                }
                continue;
            }
            let mut pt = POINT::default();
            if unsafe { GetCursorPos(&mut pt) }.is_err() {
                continue;
            }
            let (Ok(pos), Ok(scale)) = (win.outer_position(), win.scale_factor()) else {
                continue;
            };
            let h = *hit.lock().unwrap();
            let cx = (pt.x - pos.x) as f64 / scale;
            let cy = (pt.y - pos.y) as f64 / scale;
            let now = cx >= h.x && cx <= h.x + h.w && cy >= h.y && cy <= h.y + h.h;
            if now != inside {
                inside = now;
                let _ = win.set_ignore_cursor_events(!now);
                let _ = win.emit("hover", now);
            }
        }
    });
}

/// Vrai si la fenetre au premier plan est en plein ecran (jeu, video...) sur
/// l'ecran de l'ilot. Les fenetres simplement maximisees ne comptent pas :
/// avec une barre des taches masquee, elles couvrent aussi tout l'ecran.
fn fullscreen_foreground(own: HWND) -> bool {
    unsafe {
        let fg = GetForegroundWindow();
        if fg.is_invalid() || fg == own || IsZoomed(fg).as_bool() {
            return false;
        }
        let mut cls = [0u16; 64];
        let n = GetClassNameW(fg, &mut cls) as usize;
        let cls = String::from_utf16_lossy(&cls[..n]);
        if matches!(cls.as_str(), "Progman" | "WorkerW" | "Shell_TrayWnd") {
            return false;
        }
        let mut r = RECT::default();
        if GetWindowRect(fg, &mut r).is_err() {
            return false;
        }
        let mut mi = MONITORINFO { cbSize: std::mem::size_of::<MONITORINFO>() as u32, ..Default::default() };
        let mon = MonitorFromWindow(fg, MONITOR_DEFAULTTONEAREST);
        if mon != MonitorFromWindow(own, MONITOR_DEFAULTTONEAREST) {
            return false;
        }
        if !GetMonitorInfoW(mon, &mut mi).as_bool() {
            return false;
        }
        let m = mi.rcMonitor;
        r.left <= m.left && r.top <= m.top && r.right >= m.right && r.bottom >= m.bottom
    }
}

fn toggle_launcher(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("island") {
        let _ = win.set_ignore_cursor_events(false);
        let _ = win.set_focus();
        let _ = win.emit("launcher", ());
    }
}

fn open_tab(app: &AppHandle, tab: &str) {
    if let Some(win) = app.get_webview_window("island") {
        let _ = win.set_ignore_cursor_events(false);
        let _ = win.set_focus();
        let _ = win.emit("open", tab);
    }
}

fn main() {
    // `ilot.exe --check-we <fichier>` : diagnostic Wallpaper Engine, sans interface
    let args: Vec<String> = std::env::args().collect();
    if let Some(i) = args.iter().position(|a| a == "--check-we") {
        let walls = we::we_walls();
        let st = we::we_state();
        let report = format!(
            "{}\n{} fonds, {} sans miniature\nactif: {:?}\n{}",
            serde_json::to_string(&st).unwrap_or_default(),
            walls.len(),
            walls.iter().filter(|w| w.thumb_is_empty()).count(),
            we::active().map(|a| a.0),
            walls.iter().take(5).map(|w| w.summary()).collect::<Vec<_>>().join("\n"),
        );
        let _ = std::fs::write(args.get(i + 1).map(String::as_str).unwrap_or("we-check.txt"), report);
        return;
    }
    // `ilot.exe --check-all <fichier>` : diagnostic des modules systeme
    if let Some(i) = args.iter().position(|a| a == "--check-all") {
        com_init_mta();
        let j = |v: serde_json::Result<String>| v.unwrap_or_default();
        let notifs = notif::snapshot();
        let report = [
            format!("devices: {}", j(serde_json::to_string(&audio::audio_devices()))),
            format!("mixer: {}", j(serde_json::to_string(&audio::mixer_get()).map(|s| s.chars().take(600).collect()))),
            format!("net: {}", j(serde_json::to_string(&net::net_get()))),
            format!("wifi: {}", j(serde_json::to_string(&net::wifi_list(false)))),
            format!("user: {}", j(serde_json::to_string(&system::user_info()).map(|s| s.chars().take(120).collect()))),
            format!("win_light: {}", theme::windows_light()),
            format!("peaks: {}", audio::peaks_report()),
            format!("viz: {:?}", audio::viz_probe(3)),
            // reapplique la sortie actuelle : verifie IPolicyConfig sans rien changer
            format!("set_default: {}", audio::default_id().map(audio::audio_set_default).unwrap_or(false)),
            format!("notifs: {}", match notifs {
                Ok(l) => format!("{} : {}", l.len(), j(serde_json::to_string(&l.iter().take(3).collect::<Vec<_>>()).map(|s| s.chars().take(600).collect()))),
                Err(e) => e,
            }),
            format!("http: {}", system::http_get("https://api.open-meteo.com/v1/forecast?latitude=45.75&longitude=4.85&current=temperature_2m".into()).map(|s| format!("{} o : {}", s.len(), s.chars().take(200).collect::<String>())).unwrap_or_else(|e| format!("ERR {e:?}"))),
        ]
        .join("\n");
        let _ = std::fs::write(args.get(i + 1).map(String::as_str).unwrap_or("check.txt"), report);
        return;
    }
    let hit = Arc::new(Mutex::new(Hit::default()));
    tauri::Builder::default()
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, _sc, ev| {
                    if ev.state() == ShortcutState::Pressed {
                        toggle_launcher(app);
                    }
                })
                .build(),
        )
        .manage(HitState(hit.clone()))
        .manage(system::Clips(Mutex::new(VecDeque::new())))
        .manage(apps::Apps(Mutex::new(Vec::new())))
        .manage(notif::Notifs(Mutex::new(Vec::new())))
        .setup(move |app| {
            settings::init(app.handle());
            let win = app.get_webview_window("island").expect("fenetre island");
            place(&win);
            let _ = win.show();
            track_cursor(win.clone(), hit.clone());

            let w2 = win.clone();
            win.on_window_event(move |e| match e {
                WindowEvent::Focused(false) => {
                    let _ = w2.emit("blur", ());
                }
                WindowEvent::ScaleFactorChanged { .. } => place(&w2),
                _ => {}
            });

            let h = app.handle().clone();
            media::watch(h.clone());
            system::watch(h.clone());
            system::watch_clipboard(h.clone());
            we::watch(h.clone());
            audio::watch_volume(h.clone());
            display::watch(h.clone());
            net::watch(h.clone());
            notif::watch(h.clone());
            theme::watch(h.clone());
            system::watch_keys(h.clone());
            wall::watch_rotation(h.clone());
            apps::load(h);

            // Ctrl+Alt+Espace : lanceur d'applications
            let _ = app.global_shortcut().register(Shortcut::new(
                Some(Modifiers::CONTROL | Modifiers::ALT),
                Code::Space,
            ));

            let prefs = MenuItem::with_id(app, "settings", "Réglages", true, None::<&str>)?;
            let reload = MenuItem::with_id(app, "reload", "Recharger", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quitter Ilot", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&prefs, &reload, &quit])?;
            TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .tooltip("Ilot")
                .menu(&menu)
                .on_menu_event(|app, e| match e.id.as_ref() {
                    "quit" => app.exit(0),
                    "settings" => open_tab(app, "settings"),
                    "reload" => {
                        if let Some(w) = app.get_webview_window("island") {
                            let _ = w.eval("location.reload()");
                            place(&w);
                        }
                    }
                    _ => {}
                })
                .build(app)?;
            Ok(())
        })
        .invoke_handler(tauri::generate_handler![
            set_hit,
            startup_tab,
            grab_focus,
            media::media_get,
            media::media_art,
            media::media_action,
            system::volume_get,
            system::volume_set,
            system::clips_get,
            system::clip_copy,
            system::clips_clear,
            system::clip_text,
            system::session_action,
            system::caffeine_set,
            system::caffeine_get,
            system::user_info,
            system::http_get,
            system::open_url,
            audio::audio_devices,
            audio::audio_set_default,
            audio::mixer_get,
            audio::mixer_set,
            audio::viz_set,
            display::brightness_get,
            display::brightness_set,
            net::net_get,
            net::radio_set,
            net::wifi_list,
            net::wifi_connect,
            net::wifi_disconnect,
            notif::notifs_get,
            notif::notifs_dismiss,
            notif::notif_open,
            theme::win_theme_get,
            theme::win_theme_apply,
            apps::apps_get,
            apps::apps_refresh,
            apps::app_launch,
            wall::walls_get,
            wall::wall_current,
            wall::wall_set,
            wall::walls_open_folder,
            wall::wall_random,
            we::we_state,
            we::we_walls,
            we::we_set,
            settings::settings_get,
            settings::settings_autostart,
            settings::settings_monitor,
            settings::settings_set,
        ])
        .run(tauri::generate_context!())
        .expect("erreur au lancement d'Ilot");
}
