#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod apps;
mod audio;
mod bar;
mod display;
mod media;
mod net;
mod notif;
mod settings;
mod system;
mod theme;
mod wall;
mod we;
mod winkey;

use std::collections::VecDeque;
use std::sync::atomic::{AtomicIsize, Ordering};
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, Manager, PhysicalPosition, PhysicalSize, RunEvent, State, WebviewWindow, WindowEvent};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};
use windows::core::w;
use windows::Win32::Foundation::{GetLastError, ERROR_ALREADY_EXISTS, HWND, POINT, RECT};
use windows::Win32::Graphics::Gdi::{GetMonitorInfoW, MonitorFromWindow, MONITORINFO, MONITOR_DEFAULTTONEAREST};
use windows::Win32::System::Threading::CreateMutexW;
use windows::Win32::System::Com::{
    CoInitializeEx, COINIT_APARTMENTTHREADED, COINIT_MULTITHREADED,
};
use windows::Win32::UI::WindowsAndMessaging::{
    GetClassNameW, GetCursorPos, GetForegroundWindow, GetWindowRect, IsIconic, IsWindow, IsZoomed,
    SetForegroundWindow,
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

/// Zone interactive, en pixels CSS relatifs a la fenetre : l'ilot puis,
/// s'il y a lieu, la barre. Hors de ces zones, la fenetre (transparente)
/// laisse passer la souris.
#[derive(Default, Clone, Copy, serde::Deserialize)]
struct Hit {
    x: f64,
    y: f64,
    w: f64,
    h: f64,
}

impl Hit {
    fn contains(&self, x: f64, y: f64) -> bool {
        x >= self.x && x <= self.x + self.w && y >= self.y && y <= self.y + self.h
    }
}

/// Zones interactives et hauteur de la bande du haut de l'ecran qui affiche
/// la barre masquee automatiquement (0 : pas de bande).
#[derive(Default)]
struct Hits {
    rects: Vec<Hit>,
    top: f64,
}

struct HitState(Arc<Mutex<Hits>>);

#[tauri::command]
fn set_hit(st: State<HitState>, rects: Vec<Hit>, top: Option<f64>) {
    *st.0.lock().unwrap() = Hits { rects, top: top.unwrap_or(0.0) };
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
    let _ = win.set_focus();
}

/// Derniere fenetre d'application active avant l'ilot
static PREV_FG: AtomicIsize = AtomicIsize::new(0);

/// En se repliant, l'ilot rend le clavier a la fenetre qui l'avait avant lui
/// (comme le menu Demarrer), au lieu de le garder.
#[tauri::command]
fn release_focus(win: WebviewWindow) {
    let own = win.hwnd().unwrap_or_default();
    let prev = HWND(PREV_FG.load(Ordering::Relaxed) as _);
    unsafe {
        if GetForegroundWindow() == own && IsWindow(Some(prev)).as_bool() && !IsIconic(prev).as_bool() {
            let _ = SetForegroundWindow(prev);
        }
    }
}

/// Vrai si l'ilot est deplie, d'apres la zone que l'interface a declaree
fn island_open(app: &AppHandle) -> bool {
    app.state::<HitState>().0.lock().unwrap().rects.first().is_some_and(|r| r.h > 100.0)
}

/// Place la fenetre en haut, au centre de l'ecran choisi dans les reglages
/// (l'ecran principal par defaut, ou si l'ecran choisi est debranche).
/// Avec la barre, la fenetre prend toute la largeur et le haut de l'ecran
/// est reserve (sauf si elle se masque automatiquement).
pub fn place(win: &WebviewWindow) {
    let Some(mon) = settings::target_monitor(win) else { return };
    let bar = bar::enabled(win.app_handle());
    let scale = mon.scale_factor();
    let mpos = mon.position();
    let msize = mon.size();
    let width = if bar { msize.width } else { (800.0 * scale).round() as u32 };
    let size = PhysicalSize::new(width, (600.0 * scale).round() as u32);
    if win.outer_size().ok() != Some(size) {
        let _ = win.set_size(size);
    }
    let x = mpos.x + (msize.width as i32 - size.width as i32) / 2;
    let target = PhysicalPosition::new(x, mpos.y);
    if win.outer_position().ok() != Some(target) {
        let _ = win.set_position(target);
    }
    bar::reserve(
        win,
        (bar && !bar::autohide(win.app_handle())).then(|| RECT {
            left: mpos.x,
            top: mpos.y,
            right: mpos.x + msize.width as i32,
            bottom: mpos.y + (bar::BAR_H * scale).round() as i32,
        }),
    );
}

/// Suit le curseur : active/desactive le passage des clics selon qu'il est
/// dans une zone interactive, et previent l'interface quand il entre dans
/// l'ilot ou en sort (`hover`), ou dans la bande du haut (`top-hover`).
fn track_cursor(win: WebviewWindow, hit: Arc<Mutex<Hits>>) {
    std::thread::spawn(move || {
        let mut inside = false;
        let mut over = false;
        let mut at_top = false;
        let mut hidden = false;
        let mut tick = 0u32;
        let mut last_fg = HWND::default();
        let own = win.hwnd().unwrap_or_default();
        let _ = win.set_ignore_cursor_events(true);
        loop {
            std::thread::sleep(Duration::from_millis(25));
            tick = tick.wrapping_add(1);
            let fg = unsafe { GetForegroundWindow() };
            if fg != last_fg {
                last_fg = fg;
                let desk = matches!(bar::class_of(fg).as_str(), "Progman" | "WorkerW");
                if fg != own && (desk || bar::is_task(fg)) {
                    PREV_FG.store(fg.0 as isize, Ordering::Relaxed);
                }
            }
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
                if over {
                    over = false;
                    let _ = win.emit("hover", false);
                }
                if at_top {
                    at_top = false;
                    let _ = win.emit("top-hover", false);
                }
                continue;
            }
            let mut pt = POINT::default();
            if unsafe { GetCursorPos(&mut pt) }.is_err() {
                continue;
            }
            let (Ok(pos), Ok(size), Ok(scale)) = (win.outer_position(), win.outer_size(), win.scale_factor())
            else {
                continue;
            };
            let cx = (pt.x - pos.x) as f64 / scale;
            let cy = (pt.y - pos.y) as f64 / scale;
            let (now, island, top) = {
                let h = hit.lock().unwrap();
                let island = h.rects.first().is_some_and(|r| r.contains(cx, cy));
                let top = h.top > 0.0 && pt.x >= pos.x && pt.x < pos.x + size.width as i32 && cy >= 0.0 && cy <= h.top;
                (island || h.rects.iter().any(|r| r.contains(cx, cy)), island, top)
            };
            if top != at_top {
                at_top = top;
                let _ = win.emit("top-hover", top);
            }
            if now != inside {
                inside = now;
                let _ = win.set_ignore_cursor_events(!now);
            }
            if island != over {
                over = island;
                let _ = win.emit("hover", island);
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

/// Les clics restent geres par `track_cursor` : rendre ici la fenetre
/// cliquable bloquerait tout l'ecran qu'elle couvre, curseur hors de l'ilot.
fn toggle_launcher(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("island") {
        // replie, l'ilot rendra lui-meme la main (release_focus)
        if !island_open(app) {
            let _ = win.set_focus();
        }
        let _ = win.emit("launcher", ());
    }
}

fn open_tab(app: &AppHandle, tab: &str) {
    if let Some(win) = app.get_webview_window("island") {
        let _ = win.set_focus();
        let _ = win.emit("open", tab);
    }
}

fn main() {
    // `ilot.exe --check-we <fichier>` : diagnostic Wallpaper Engine, sans interface
    let args: Vec<String> = std::env::args().collect();
    // `ilot.exe --winkey-remap on|off` : relance en administrateur pour
    // (de)remapper la touche Windows
    if let Some(i) = args.iter().position(|a| a == "--winkey-remap") {
        std::process::exit(winkey::remap_cli(args.get(i + 1).is_some_and(|a| a == "on")));
    }
    // `ilot.exe --check-icons <fichier>` : icones des fenetres de la barre
    if let Some(i) = args.iter().position(|a| a == "--check-icons") {
        let _ = std::fs::write(args.get(i + 1).map(String::as_str).unwrap_or("icons.txt"), bar::check_icons());
        return;
    }
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
    // une seule instance : deux hooks clavier se disputeraient la touche
    // Windows (l'un verrait l'appui, l'autre le relachement)
    let _single = unsafe { CreateMutexW(None, true, w!("Local\\io.github.tidic84.ilot")) };
    if unsafe { GetLastError() } == ERROR_ALREADY_EXISTS {
        return;
    }
    let hit = Arc::new(Mutex::new(Hits::default()));
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
            winkey::init(app.handle());
            let win = app.get_webview_window("island").expect("fenetre island");
            place(&win);
            let _ = win.show();
            track_cursor(win.clone(), hit.clone());
            bar::sync(app.handle());
            bar::watch(win.clone());

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
            release_focus,
            winkey::winkey_status,
            winkey::winkey_remap,
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
            bar::tasks_get,
            bar::task_icon,
            bar::task_activate,
            bar::task_close,
            bar::task_thumb,
            bar::desktop_go,
            bar::taskbar_peek,
        ])
        .build(tauri::generate_context!())
        .expect("erreur au lancement d'Ilot")
        .run(|app, e| {
            // la barre des taches Windows revient quand l'ilot se ferme
            if let RunEvent::Exit = e {
                bar::restore(app);
            }
        });
}
