#![cfg_attr(not(debug_assertions), windows_subsystem = "windows")]

mod activity;
mod apps;
mod audio;
mod boost;
mod captions;
mod discord;
mod files;
mod games;
mod health;
mod mail;
mod lyrics;
mod media;
mod notify;
mod outputs;
mod soundboard;
mod pc;
mod dropfix;
mod pdh;
mod prefs;
mod privacy;
mod share;
mod status;
mod store;
mod system;
mod tasks;
mod translate;
mod viz;
mod wall;
mod we;

use std::collections::VecDeque;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use tauri::menu::{Menu, MenuItem};
use tauri::tray::TrayIconBuilder;
use tauri::{AppHandle, Emitter, LogicalSize, Manager, State, WebviewWindow, WindowEvent};
use tauri_plugin_global_shortcut::{Code, GlobalShortcutExt, Modifiers, Shortcut, ShortcutState};
use windows::Win32::Foundation::{HWND, POINT, RECT};
use windows::Win32::Graphics::Gdi::{GetMonitorInfoW, MonitorFromWindow, MONITORINFO, MONITOR_DEFAULTTONEAREST};
use windows::Win32::System::Com::{
    CoInitializeEx, COINIT_APARTMENTTHREADED, COINIT_MULTITHREADED,
};
use windows::Win32::UI::Input::KeyboardAndMouse::{GetAsyncKeyState, VK_LBUTTON};
use windows::Win32::UI::WindowsAndMessaging::{
    GetAncestor, GetClassNameW, GetCursorPos, GetForegroundWindow, GetWindowLongW, GetWindowRect,
    GetWindowThreadProcessId, IsZoomed, WindowFromPoint, GA_ROOT, GWL_EXSTYLE,
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

/// Client HTTPS (TLS de Windows) : ureq n'en configure aucun tout seul.
pub fn http() -> ureq::Agent {
    let mut b = ureq::AgentBuilder::new().timeout_connect(std::time::Duration::from_secs(6));
    if let Ok(tls) = native_tls::TlsConnector::new() {
        b = b.tls_connector(std::sync::Arc::new(tls));
    }
    b.build()
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

/// Taille de la fenetre (pixels CSS) pour le panneau agrandi, puis recentrage.
#[tauri::command]
fn win_resize(win: WebviewWindow, w: f64, h: f64) {
    let _ = win.set_size(LogicalSize::new(w, h));
    place(&win);
}

/// Place la fenetre (haut ou bas, ecran choisi : voir prefs.rs).
fn place(win: &WebviewWindow) {
    prefs::place(win);
}

/// Suit le curseur : active/desactive le passage des clics selon qu'il est
/// dans la zone de l'ilot, et previent l'interface (`hover`).
fn track_cursor(win: WebviewWindow, hit: Arc<Mutex<Hit>>) {
    std::thread::spawn(move || {
        let mut inside = false;
        let mut hidden = false;
        let mut tick = 0u32;
        let mut drag_logged = false;
        let own = win.hwnd().unwrap_or_default();
        let _ = win.set_ignore_cursor_events(true);
        loop {
            std::thread::sleep(Duration::from_millis(25));
            tick = tick.wrapping_add(1);
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
            // bouton gauche enfonce (fichier tire depuis l'Explorateur) : zone
            // elargie pour que le depot soit facile a viser
            let down = unsafe { GetAsyncKeyState(VK_LBUTTON.0 as i32) } as u16 & 0x8000 != 0;
            let m = if down { 30.0 } else { 0.0 };
            let now = cx >= h.x - m && cx <= h.x + h.w + m && cy >= h.y && cy <= h.y + h.h + m;
            if now != inside {
                inside = now;
                let _ = win.set_ignore_cursor_events(!now);
                let _ = win.emit("hover", now);
                drag_logged = false;
            } else if !inside && !down && tick % 20 == 0 {
                // un raccourci clavier a pu rendre la fenetre cliquable : hors de
                // l'ilot, elle doit laisser passer la souris
                let _ = win.set_ignore_cursor_events(true);
            }
            // diagnostic du glisser-deposer : fenetre que Windows voit sous le curseur
            if down && inside && !drag_logged {
                drag_logged = true;
                std::thread::sleep(Duration::from_millis(150));
                drop_log(&format!("drag-in {}", window_under(pt, own)));
            }
            if !down {
                drag_logged = false;
            }
        }
    });
}

/// Ajoute une ligne a %LOCALAPPDATA%\Ilot\drop.log (50 dernieres gardees).
pub fn drop_log(line: &str) {
    let path = store::data_dir().join("drop.log");
    let old = std::fs::read_to_string(&path).unwrap_or_default();
    let lines: Vec<&str> = old.lines().collect();
    let mut out: String = lines[lines.len().saturating_sub(50)..].iter().map(|l| format!("{l}\n")).collect();
    let t = std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_secs());
    out += &format!("{t} {line}\n");
    let _ = std::fs::write(path, out);
}

/// Fenetre que Windows trouve sous le curseur (classe, processus), pour le journal.
fn window_under(pt: POINT, own: HWND) -> String {
    unsafe {
        let h = WindowFromPoint(pt);
        let mut cls = [0u16; 64];
        let n = GetClassNameW(h, &mut cls) as usize;
        let mut pid = 0u32;
        GetWindowThreadProcessId(h, Some(&mut pid));
        let root = GetAncestor(h, GA_ROOT);
        format!(
            "{} pid={pid} racine_ilot={} exstyle_ilot=0x{:X}",
            String::from_utf16_lossy(&cls[..n]),
            root == own,
            GetWindowLongW(own, GWL_EXSTYLE) as u32
        )
    }
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

fn main() {
    // `ilot.exe --check-we <fichier>` : diagnostic Wallpaper Engine, sans interface
    let args: Vec<String> = std::env::args().collect();
    // `ilot.exe --check-audio <fichier>` : sessions audio par appli
    // `ilot.exe --set-audio <appli> <0..1>` : regle le volume d'une appli (test)
    if let Some(i) = args.iter().position(|a| a == "--set-audio") {
        let level = args.get(i + 2).and_then(|s| s.parse().ok());
        let ok = audio::app_volume_set(args.get(i + 1).cloned().unwrap_or_default(), None, level, None);
        std::process::exit(if ok { 0 } else { 1 });
    }
    // `ilot.exe --check-lyrics <fichier> <artiste> <titre>` : essai de recherche de paroles
    if let Some(i) = args.iter().position(|a| a == "--check-lyrics") {
        let g = |k: usize| args.get(i + k).cloned().unwrap_or_default();
        let r = match lyrics::lyrics_get(g(2), g(3), String::new(), 0.0) {
            Ok(l) => serde_json::to_string(&l).unwrap_or_default(),
            Err(e) => format!("ERR {e}"),
        };
        let _ = std::fs::write(g(1), r);
        return;
    }
    // `ilot.exe --check-outputs <fichier> [id]` : sorties audio, et essai de bascule vers [id]
    if let Some(i) = args.iter().position(|a| a == "--check-outputs") {
        let mut r = String::new();
        for o in outputs::audio_outputs() {
            r += &format!("{}\n", serde_json::to_string(&o).unwrap_or_default());
        }
        if let Some(id) = args.get(i + 2) {
            r += &format!("set {id} -> {}\n", outputs::audio_output_set(id.clone()));
        }
        let _ = std::fs::write(args.get(i + 1).map(String::as_str).unwrap_or("outputs-check.txt"), r);
        return;
    }
    if let Some(i) = args.iter().position(|a| a == "--check-audio") {
        let _ = std::fs::write(args.get(i + 1).map(String::as_str).unwrap_or("audio-check.txt"), audio::report());
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
    // `ilot.exe --check-imap <hote> <fichier>` : test de connexion IMAP
    if let Some(i) = args.iter().position(|a| a == "--check-imap") {
        let host = args.get(i + 1).map(String::as_str).unwrap_or("imap.gmail.com");
        let _ = std::fs::write(args.get(i + 2).map(String::as_str).unwrap_or("imap-check.txt"), mail::check(host));
        return;
    }
    // `ilot.exe --check-pc <fichier>` : mode d'alimentation, logiciels, volumes
    if let Some(i) = args.iter().position(|a| a == "--check-pc") {
        let names = ["DCv2", "ArmouryCrate", "lghub", "Discord", "Spotify"].map(String::from).to_vec();
        let vol = |app: &str, mic| audio::app_volume_get(app.into(), Some(mic)).map(|v| serde_json::to_string(&v).unwrap_or_default());
        let report = format!(
            "alimentation: {:?}
processus {:?}: {:?}
son discord: {:?}
micro discord: {:?}
son spotify: {:?}",
            pc::power_get(), names, pc::procs_running(names.clone()), vol("discord", false), vol("discord", true), vol("spotify", false)
        );
        let _ = std::fs::write(args.get(i + 1).map(String::as_str).unwrap_or("pc-check.txt"), report);
        return;
    }
    // `ilot.exe --check-games <fichier>` : jeux detectes, sans interface
    if let Some(i) = args.iter().position(|a| a == "--check-games") {
        let report = games::report();
        let _ = std::fs::write(args.get(i + 1).map(String::as_str).unwrap_or("games-check.txt"), report);
        return;
    }
    let hit = Arc::new(Mutex::new(Hit::default()));
    tauri::Builder::default()
        .plugin(
            tauri_plugin_global_shortcut::Builder::new()
                .with_handler(|app, sc, ev| {
                    if ev.state() == ShortcutState::Pressed && !prefs::on_shortcut(app, sc) {
                        toggle_launcher(app);
                    }
                })
                .build(),
        )
        .manage(HitState(hit.clone()))
        .manage(system::Clips(Mutex::new(VecDeque::new())))
        .manage(apps::Apps(Mutex::new(Vec::new())))
        .manage(games::Games(Mutex::new(Vec::new())))
        .manage(tasks::Tasks::default())
        .manage(share::Share::default())
        .manage(discord::Discord::default())
        .manage(mail::MailState(Mutex::new(Default::default())))
        .setup(move |app| {
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
            notify::watch(h.clone());
            activity::watch(h.clone());
            dropfix::start(h.clone());
            health::watch(h.clone());
            status::watch(h.clone());
            privacy::watch(h.clone());
            system::watch(h.clone());
            system::watch_clipboard(h.clone());
            we::watch(h.clone());
            mail::watch(h.clone());
            discord::start(h.clone());
            games::load(h.clone());
            apps::load(h);

            // Ctrl+Alt+Espace : lanceur d'applications
            let _ = app.global_shortcut().register(Shortcut::new(
                Some(Modifiers::CONTROL | Modifiers::ALT),
                Code::Space,
            ));
            prefs::load_shortcuts(app.handle());

            let reload = MenuItem::with_id(app, "reload", "Recharger", true, None::<&str>)?;
            let quit = MenuItem::with_id(app, "quit", "Quitter Ilot", true, None::<&str>)?;
            let menu = Menu::with_items(app, &[&reload, &quit])?;
            TrayIconBuilder::new()
                .icon(app.default_window_icon().unwrap().clone())
                .tooltip("Ilot")
                .menu(&menu)
                .on_menu_event(|app, e| match e.id.as_ref() {
                    "quit" => app.exit(0),
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
            win_resize,
            media::media_get,
            media::media_art,
            media::media_action,
            system::volume_get,
            system::volume_set,
            outputs::audio_outputs,
            outputs::audio_output_set,
            files::img_convert,
            files::img_shrink,
            files::zip_files,
            files::files_copy,
            files::file_reveal,
            translate::translate,
            lyrics::lyrics_get,
            share::share_start,
            share::share_stop,
            activity::game_focus,
            soundboard::sb_devices,
            soundboard::sb_config,
            soundboard::sb_save,
            soundboard::sb_delete,
            soundboard::sb_read,
            soundboard::sb_play,
            soundboard::sb_stop,
            boost::boost_get,
            boost::boost_set,
            system::clips_get,
            system::clip_copy,
            system::clips_clear,
            system::session_action,
            apps::apps_get,
            apps::apps_refresh,
            apps::app_launch,
            games::games_get,
            games::games_refresh,
            games::game_launch,
            games::game_folder,
            games::app_folder,
            games::folder_open,
            games::pick_folder,
            games::file_info,
            games::file_open,
            audio::app_volume_get,
            audio::app_volume_set,
            audio::mixer_get,
            viz::viz_set,
            audio::mixer_set,
            audio::fg_volume,
            health::health_get,
            health::health_clean,
            health::idle_secs,
            status::services_get,
            prefs::set_placement,
            captions::captions_set,
            captions::captions_on,
            pc::power_action,
            prefs::pet_walk,
            prefs::monitors_list,
            prefs::shortcuts_set,
            prefs::shortcuts_get,
            prefs::settings_export,
            prefs::settings_import,
            pc::power_get,
            pc::power_set,
            pc::procs_running,
            tasks::tasks_get,
            tasks::task_kill,
            tasks::taskmgr_open,
            discord::discord_get,
            discord::discord_setup,
            discord::discord_forget,
            discord::discord_self,
            discord::discord_user,
            discord::discord_mic,
            wall::walls_get,
            wall::wall_current,
            wall::wall_set,
            wall::walls_open_folder,
            we::we_state,
            we::we_walls,
            we::we_set,
            store::store_get,
            store::store_set,
            mail::mail_get,
            mail::mail_refresh,
            mail::mail_add,
            mail::mail_remove,
            mail::mail_read,
            mail::open_url,
        ])
        .run(tauri::generate_context!())
        .expect("erreur au lancement d'Ilot");
}
