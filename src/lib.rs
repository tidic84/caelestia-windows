//! Coeur de l'ilot : tout ce qui parle a Windows (lecteur, son, reseau,
//! notifications, applis, fonds...). L'interface est en Qt Quick (qt/) ;
//! elle appelle les commandes par `ilot_invoke` (memes noms et memes
//! arguments que les commandes Tauri d'avant) et recoit les evenements par
//! la fonction passee a `ilot_start`.

mod activity;
mod apps;
mod audio;
mod bar;
mod boost;
mod captions;
mod claude;
mod decode;
mod discord;
mod display;
mod events;
mod files;
mod games;
mod health;
mod host;
mod google;
mod img;
mod lyrics;
mod mail;
mod media;
mod net;
mod notif;
mod pc;
mod pdh;
mod prefs;
mod privacy;
mod settings;
mod quickshare;
mod soundboard;
mod status;
mod store;
mod system;
mod tasks;
mod theme;
mod translate;
mod update;
mod valorant;
mod wall;
mod we;
mod winkey;

use std::collections::VecDeque;
use std::ffi::{c_char, CStr, CString};
use std::sync::atomic::{AtomicBool, AtomicIsize, Ordering};
use std::sync::Mutex;

use serde::de::DeserializeOwned;
use serde_json::Value;
use windows::core::BOOL;
use windows::Win32::Foundation::{HWND, LPARAM, RECT};
use windows::Win32::Graphics::Gdi::{
    EnumDisplayMonitors, GetMonitorInfoW, MonitorFromWindow, HDC, HMONITOR, MONITORINFO, MONITORINFOEXW,
    MONITOR_DEFAULTTONEAREST,
};
use windows::Win32::System::Com::{CoInitializeEx, COINIT_APARTMENTTHREADED, COINIT_MULTITHREADED};
use windows::Win32::UI::WindowsAndMessaging::{
    GetClassNameW, GetForegroundWindow, GetWindowRect, IsIconic, IsWindow, IsZoomed, SetForegroundWindow,
    MONITORINFOF_PRIMARY,
};

use host::{AppHandle, WebviewWindow};

pub fn com_init_mta() {
    unsafe {
        let _ = CoInitializeEx(None, COINIT_MULTITHREADED);
    }
}

/// Attend une operation WinRT au plus `ms` millisecondes, puis l'annule. Un
/// service Windows bloque (une appli figee derriere le panneau media...) ne
/// doit pas retenir un thread de l'ilot indefiniment.
pub(crate) fn wait<T: windows_core::RuntimeType + 'static>(
    op: windows_future::IAsyncOperation<T>,
    ms: u64,
) -> windows_core::Result<T> {
    let (tx, rx) = std::sync::mpsc::sync_channel(1);
    op.SetCompleted(&windows_future::AsyncOperationCompletedHandler::new(move |_, _| {
        let _ = tx.try_send(());
        Ok(())
    }))?;
    if rx.recv_timeout(std::time::Duration::from_millis(ms)).is_err() {
        let _ = op.Cancel();
        // HRESULT_FROM_WIN32(ERROR_TIMEOUT)
        return Err(windows_core::HRESULT(0x8007_05B4_u32 as i32).into());
    }
    op.GetResults()
}

/// Client HTTPS (TLS de Windows) pour les services web (paroles, traduction,
/// etat des services, pilote NVIDIA).
pub fn http() -> ureq::Agent {
    let mut b = ureq::AgentBuilder::new().timeout_connect(std::time::Duration::from_secs(6));
    if let Ok(tls) = native_tls::TlsConnector::new() {
        b = b.tls_connector(std::sync::Arc::new(tls));
    }
    b.build()
}

pub fn com_init_sta() {
    unsafe {
        let _ = CoInitializeEx(None, COINIT_APARTMENTTHREADED);
    }
}

// ------------------------------------------------------------- fenetres

/// Panneau de l'ilot deplie (declare par l'interface)
static ISLAND_OPEN: AtomicBool = AtomicBool::new(false);

fn island_open(_app: &AppHandle) -> bool {
    ISLAND_OPEN.load(Ordering::Relaxed)
}

/// Panneau deplie : ce qu'il affiche (disques...) merite un releve frequent.
pub(crate) fn panel_open() -> bool {
    ISLAND_OPEN.load(Ordering::Relaxed)
}

/// Derniere fenetre d'application active avant l'ilot
static PREV_FG: AtomicIsize = AtomicIsize::new(0);

/// Premier plan change (hook WinEvent) : on retient la derniere appli
pub(crate) fn note_foreground(fg: HWND) {
    let own = AppHandle.get_webview_window("island").and_then(|w| w.hwnd().ok()).unwrap_or_default();
    let desk = matches!(bar::class_of(fg).as_str(), "Progman" | "WorkerW");
    if fg != own && (desk || bar::is_task(fg)) {
        PREV_FG.store(fg.0 as isize, Ordering::Relaxed);
    }
}

/// En se repliant, l'ilot rend le clavier a la fenetre qui l'avait avant lui
/// (comme le menu Demarrer), au lieu de le garder.
fn release_focus(own: HWND) {
    let prev = HWND(PREV_FG.load(Ordering::Relaxed) as _);
    unsafe {
        if GetForegroundWindow() == own && IsWindow(Some(prev)).as_bool() && !IsIconic(prev).as_bool() {
            let _ = SetForegroundWindow(prev);
        }
    }
}

/// Vrai si la fenetre au premier plan est en plein ecran (jeu, video...) sur
/// l'ecran de `own`. Les fenetres simplement maximisees ne comptent pas :
/// avec une barre des taches masquee, elles couvrent aussi tout l'ecran.
pub(crate) fn fullscreen_foreground(own: HWND) -> bool {
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

/// Touche Windows, Ctrl+Alt+Espace, bouton d'une barre : lanceur
pub(crate) fn toggle_launcher(app: &AppHandle) {
    if let Some(win) = app.get_webview_window("island") {
        // replie, l'ilot rendra lui-meme la main (release_focus)
        if !island_open(app) {
            let _ = win.set_focus();
        }
        let _ = app.emit("launcher", ());
    }
}

pub(crate) fn open_tab(app: &AppHandle, tab: &str) {
    if let Some(win) = app.get_webview_window("island") {
        let _ = win.set_focus();
        let _ = app.emit("open", tab);
    }
}

/// Un ecran branche, en pixels physiques
#[derive(Clone, serde::Serialize)]
pub(crate) struct Screen {
    /// Nom Windows : `\\.\DISPLAY2`
    pub name: String,
    pub x: i32,
    pub y: i32,
    pub width: i32,
    pub height: i32,
    pub primary: bool,
}

unsafe extern "system" fn add_screen(m: HMONITOR, _: HDC, _: *mut RECT, lp: LPARAM) -> BOOL {
    let v = &mut *(lp.0 as *mut Vec<Screen>);
    let mut mi = MONITORINFOEXW::default();
    mi.monitorInfo.cbSize = std::mem::size_of::<MONITORINFOEXW>() as u32;
    if GetMonitorInfoW(m, &mut mi as *mut MONITORINFOEXW as *mut MONITORINFO).as_bool() {
        let n = mi.szDevice.iter().position(|&c| c == 0).unwrap_or(mi.szDevice.len());
        let r = mi.monitorInfo.rcMonitor;
        v.push(Screen {
            name: String::from_utf16_lossy(&mi.szDevice[..n]),
            x: r.left,
            y: r.top,
            width: r.right - r.left,
            height: r.bottom - r.top,
            primary: mi.monitorInfo.dwFlags & MONITORINFOF_PRIMARY != 0,
        });
    }
    true.into()
}

pub(crate) fn screens() -> Vec<Screen> {
    let mut v: Vec<Screen> = Vec::new();
    unsafe {
        let _ = EnumDisplayMonitors(None, None, Some(add_screen), LPARAM(&mut v as *mut _ as isize));
    }
    v
}

// ------------------------------------------------------------ commandes

fn arg<T: DeserializeOwned>(a: &Value, k: &str) -> Result<T, String> {
    serde_json::from_value(a.get(k).cloned().unwrap_or(Value::Null)).map_err(|e| format!("argument {k} : {e}"))
}

fn json<T: serde::Serialize>(v: T) -> Result<Value, String> {
    serde_json::to_value(v).map_err(|e| e.to_string())
}

/// Une commande de l'interface, appelee depuis la fenetre `w`. Les noms
/// d'arguments sont ceux de JavaScript (camelCase), comme avec Tauri.
fn call(w: &WebviewWindow, cmd: &str, a: &Value) -> Result<Value, String> {
    let app = AppHandle;
    macro_rules! a {
        ($k:literal) => {
            arg(a, $k)?
        };
    }
    match cmd {
        // fenetres
        "release_focus" => json(release_focus(w.hwnd()?)),
        "winkey_status" => json(winkey::winkey_status(app)),
        "winkey_remap" => json(winkey::winkey_remap(app, a!("on"))),
        "screens" => json(screens()),
        "bar_reserve" => json(bar::reserve_rect(w, a!("rect"))),
        "bar_open" => {
            let tab: String = a!("tab");
            if tab == "launcher" {
                toggle_launcher(&app);
            } else {
                open_tab(&app, &tab);
            }
            json(())
        }
        // lecteur
        "media_get" => json(media::media_get()),
        "media_art" => json(media::media_art()),
        "media_action" => json(media::media_action(a!("action"), a!("value"))),
        // systeme
        "volume_get" => json(system::volume_get()),
        "volume_set" => json(system::volume_set(a!("level"), a!("muted"))),
        "clips_get" => json(system::clips_get(app.state())),
        "clip_copy" => json(system::clip_copy(app.state(), a!("id"))),
        "clips_clear" => json(system::clips_clear(app, app.state())),
        "clip_text" => json(system::clip_text(a!("text"))),
        "session_action" => json(system::session_action(a!("action"))),
        "caffeine_set" => json(system::caffeine_set(app, a!("on"))),
        "caffeine_get" => json(system::caffeine_get()),
        "user_info" => json(system::user_info()),
        "motion_reduced" => json(system::motion_reduced()),
        "http_get" => system::http_get(a!("url")).and_then(json),
        "open_url" => json(system::open_url(a!("url"))),
        // son
        "audio_devices" => json(audio::audio_devices()),
        "audio_set_default" => json(audio::audio_set_default(a!("id"))),
        "mixer_get" => json(audio::mixer_get()),
        "mixer_set" => json(audio::mixer_set(a!("pids"), a!("level"), a!("muted"))),
        "viz_set" => json(audio::viz_set(app, a!("on"))),
        "app_volume_get" => json(audio::app_volume_get(a!("app"), a!("mic"))),
        "app_volume_set" => json(audio::app_volume_set(a!("app"), a!("mic"), a!("level"), a!("muted"))),
        "fg_volume" => json(audio::fg_volume(a!("step"))),
        "boost_get" => json(boost::boost_get()),
        "boost_set" => json(boost::boost_set(a!("gain"))),
        // ecran, reseau
        "brightness_get" => json(display::brightness_get(w.clone())),
        "brightness_set" => json(display::brightness_set(w.clone(), a!("level"))),
        "net_get" => json(net::net_get()),
        "radios_get" => json(net::radios_get()),
        "radio_set" => json(net::radio_set(a!("kind"), a!("on"))),
        "wifi_list" => json(net::wifi_list(a!("scan"))),
        "wifi_connect" => net::wifi_connect(a!("ssidName"), a!("password")).and_then(json),
        "wifi_disconnect" => json(net::wifi_disconnect()),
        // notifications
        "notifs_get" => json(notif::notifs_get(app.state())),
        "notifs_dismiss" => json(notif::notifs_dismiss(app, a!("id"))),
        "notif_open" => json(notif::notif_open(a!("appId"))),
        // theme, fonds
        "win_theme_get" => json(theme::win_theme_get()),
        "win_theme_apply" => json(theme::win_theme_apply(a!("light"), a!("palette"))),
        "theme_source" => json(theme::theme_source(a!("url"), a!("max"))),
        "walls_get" => json(wall::walls_get()),
        "wall_current" => json(wall::wall_current()),
        "wall_set" => json(wall::wall_set(a!("path"))),
        "walls_open_folder" => json(wall::walls_open_folder()),
        "wall_random" => json(wall::wall_random(app)),
        "we_state" => json(we::we_state()),
        "we_walls" => json(we::we_walls()),
        "we_set" => json(we::we_set(a!("path"))),
        // applis, jeux, fichiers
        "apps_get" => json(apps::apps_get(app.state())),
        "apps_refresh" => json(apps::apps_refresh(app)),
        "app_launch" => json(apps::app_launch(a!("id"))),
        "games_get" => json(games::games_get(app.state())),
        "games_refresh" => json(games::games_refresh(app)),
        "game_launch" => json(games::game_launch(app.state(), a!("id"))),
        "game_folder" => json(games::game_folder(app.state(), a!("id"))),
        "app_folder" => json(games::app_folder(app, a!("id"), a!("name"))),
        "folder_open" => json(games::folder_open(a!("path"))),
        "pick_folder" => json(games::pick_folder(app, a!("title"))),
        "file_info" => json(games::file_info(a!("path"))),
        "file_open" => json(games::file_open(a!("path"))),
        "file_reveal" => json(files::file_reveal(a!("path"))),
        "img_convert" => files::img_convert(a!("path"), a!("to")).and_then(json),
        "img_shrink" => files::img_shrink(a!("path")).and_then(json),
        "zip_files" => files::zip_files(a!("paths")).and_then(json),
        "files_copy" => json(files::files_copy(a!("paths"))),
        // Quick Share
        "qs_get" => json(quickshare::qs_get(app.state())),
        "qs_config" => json(quickshare::qs_config(app.state(), a!("name"), a!("visibility"))),
        "qs_discover" => json(quickshare::qs_discover(app.state(), a!("on"))),
        "qs_send" => quickshare::qs_send(app.state(), a!("device"), a!("paths"), a!("text")).and_then(json),
        "qs_answer" => json(quickshare::qs_answer(app.state(), a!("id"), a!("accept"))),
        "qs_cancel" => json(quickshare::qs_cancel(app.state(), a!("id"))),
        "qs_clear" => json(quickshare::qs_clear(app.state(), a!("id"))),
        "qs_pending" => json(quickshare::qs_pending(app.state(), a!("paths"))),
        "qs_qr" => json(quickshare::qs_qr(app.state(), a!("on"))),
        // reglages
        "settings_get" => json(settings::settings_get(app.state())),
        "settings_autostart" => json(settings::settings_autostart(a!("on"))),
        "settings_monitor" => json(settings::settings_monitor(app, app.state(), a!("id"))),
        "settings_set" => json(settings::settings_set(app, a!("patch"))),
        "monitor_target" => json(settings::target_screen(&app)),
        "shortcuts_get" => json(prefs::shortcuts_get()),
        "shortcuts_set" => json(prefs::shortcuts_set(a!("map"))),
        "shortcuts_record" => json(winkey::shortcuts_record(app, a!("on"))),
        "settings_export" => json(prefs::settings_export(app)),
        "settings_import" => prefs::settings_import(app).and_then(json),
        // mises a jour, notes de version
        "update_get" => json(update::update_get()),
        "update_check" => json(update::update_check(app)),
        "update_download" => json(update::update_download(app)),
        "update_install" => update::update_install(app).and_then(json),
        "changelog" => json(update::changelog_get()),
        // barre
        "bar_windows" => json(bar::bar_windows(w.clone())),
        "task_icon" => json(bar::task_icon(a!("key"), a!("id"))),
        "task_activate" => json(bar::task_activate(a!("id"))),
        "task_close" => json(bar::task_close(a!("id"))),
        "task_thumb" => json(bar::task_thumb(a!("id"), a!("w"), a!("h"))),
        "desktop_go" => json(bar::desktop_go(a!("index"))),
        "taskbar_peek" => json(bar::taskbar_peek(app, a!("show"))),
        // PC, taches
        "power_get" => json(pc::power_get()),
        "power_set" => json(pc::power_set(a!("mode"))),
        "procs_running" => json(pc::procs_running(a!("names"))),
        "tasks_get" => json(tasks::tasks_get(app.state(), a!("expanded"))),
        "tasks_stop" => json(tasks::tasks_stop(app.state())),
        "task_kill" => json(tasks::task_kill(app.state(), a!("name"), a!("pid"), a!("created"))),
        "taskmgr_open" => json(tasks::taskmgr_open()),
        // sante, services, jeux en cours, inactivite
        "health_get" => json(health::health_get()),
        "health_clean" => json(health::health_clean(a!("ids"))),
        "idle_secs" => json(health::idle_secs()),
        "services_get" => json(status::services_get(app, a!("fresh"))),
        "game_focus" => json(activity::game_focus()),
        "valorant_focus" => json(valorant::valorant_focus()),
        // Claude Code : hooks dans ~/.claude/settings.json
        "cc_hooks_status" => json(claude::hooks_status()?),
        "cc_hooks_install" => json(claude::hooks_install()?),
        "cc_hooks_remove" => json(claude::hooks_remove()?),
        // soundboard
        "sb_devices" => json(soundboard::sb_devices()),
        "sb_config" => json(soundboard::sb_config(app, a!("cfg"))),
        "sb_import" => soundboard::sb_import(a!("path")).and_then(json),
        "sb_pick" => json(soundboard::sb_pick(app)),
        "sb_delete" => json(soundboard::sb_delete(a!("id"))),
        "sb_play" => json(soundboard::sb_play(app, a!("id"), a!("volume"), a!("exclusive"))),
        "sb_stop" => json(soundboard::sb_stop(a!("id"))),
        // paroles, traduction, sous-titres
        "lyrics_get" => lyrics::lyrics_get(a!("artist"), a!("title"), a!("album"), a!("duration")).and_then(json),
        "translate" => translate::translate(a!("text"), a!("from"), a!("to")).and_then(json),
        "captions_set" => json(captions::captions_set(app, a!("on"))),
        "captions_on" => json(captions::captions_on()),
        // Discord
        "discord_get" => json(discord::discord_get(app.state())),
        "discord_setup" => discord::discord_setup(app.state(), a!("clientId"), a!("secret")).and_then(json),
        "discord_forget" => json(discord::discord_forget(app.state())),
        "discord_self" => json(discord::discord_self(app.state(), a!("mute"), a!("deaf"))),
        "discord_mic" => json(discord::discord_mic(app.state(), a!("volume"))),
        "discord_user" => json(discord::discord_user(app.state(), a!("userId"), a!("volume"), a!("mute"))),
        // fichiers JSON, mail
        "store_get" => json(store::store_get(a!("key"))),
        "store_set" => json(store::store_set(a!("key"), a!("value"))),
        "mail_get" => json(mail::mail_get(app.state())),
        "mail_refresh" => json(mail::mail_refresh(app)),
        "mail_add" => mail::mail_add(app, a!("email"), a!("pass"), a!("host")).and_then(json),
        "mail_google" => mail::mail_google(app).and_then(json),
        "mail_google_cancel" => json(mail::mail_google_cancel()),
        "mail_google_setup" => mail::mail_google_setup(app, a!("clientId"), a!("secret")).and_then(json),
        "mail_google_forget" => json(mail::mail_google_forget(app)),
        "mail_remove" => json(mail::mail_remove(app, a!("email"))),
        "mail_read" => mail::mail_read(app, a!("account"), a!("uid")).and_then(json),
        _ => Err(format!("commande inconnue : {cmd}")),
    }
}

// ------------------------------------------------------------------ C ABI

unsafe fn str_of<'a>(p: *const c_char) -> &'a str {
    if p.is_null() {
        ""
    } else {
        CStr::from_ptr(p).to_str().unwrap_or("")
    }
}

/// Declare (ou met a jour) une fenetre de l'interface.
#[no_mangle]
pub unsafe extern "C" fn ilot_register(label: *const c_char, hwnd: isize) {
    host::register(str_of(label), hwnd);
}

#[no_mangle]
pub unsafe extern "C" fn ilot_unregister(label: *const c_char) {
    host::unregister(str_of(label));
}

/// Panneau de l'ilot deplie ou non (touche Windows : ouvrir ou refermer).
#[no_mangle]
pub extern "C" fn ilot_set_open(open: bool) {
    ISLAND_OPEN.store(open, Ordering::Relaxed);
}

/// Lance les modules (la fenetre `island` doit deja etre declaree).
#[no_mangle]
pub extern "C" fn ilot_start(emit: host::EmitFn) {
    host::set_emitter(emit);
    let app = AppHandle;
    app.manage(system::Clips(Mutex::new(VecDeque::new())));
    app.manage(apps::Apps(Mutex::new(Vec::new())));
    app.manage(notif::Notifs(Mutex::new(Vec::new())));
    app.manage(games::Games(Mutex::new(Vec::new())));
    app.manage(tasks::Tasks::default());
    app.manage(discord::Discord::default());
    app.manage(mail::MailState(Mutex::new(Default::default())));
    app.manage(quickshare::Qs::default());
    settings::init(&app);
    prefs::init(&app);
    winkey::init(&app);
    events::start();
    bar::sync(&app);
    if let Some(win) = app.get_webview_window("island") {
        bar::watch(win);
    }
    media::watch(app);
    system::watch(app);
    system::watch_clipboard(app);
    we::watch(app);
    audio::watch_volume(app);
    display::watch(app);
    net::watch(app);
    notif::watch(app);
    theme::watch(app);
    system::watch_keys(app);
    wall::watch_rotation(app);
    mail::watch(app);
    discord::start(app);
    games::load(app);
    apps::load(app);
    activity::watch(app);
    valorant::watch(app);
    health::watch(app);
    status::watch(app);
    privacy::watch(app);
    update::watch(app);
    quickshare::init(app.state());
}

/// Au moment de quitter : barre des taches Windows et ecran rendus.
#[no_mangle]
pub extern "C" fn ilot_shutdown() {
    bar::restore(&AppHandle);
}

/// Appelle une commande. Renvoie `{"ok": <resultat>}` ou `{"err": "..."}`
/// (a liberer avec `ilot_free`). Peut bloquer : a appeler hors du thread de
/// l'interface.
#[no_mangle]
pub unsafe extern "C" fn ilot_invoke(label: *const c_char, cmd: *const c_char, args: *const c_char) -> *mut c_char {
    let label = str_of(label);
    let win = AppHandle.get_webview_window(label).or_else(|| AppHandle.get_webview_window("island"));
    let args: Value = serde_json::from_str(str_of(args)).unwrap_or(Value::Null);
    let reply = match win {
        None => serde_json::json!({ "err": "fenetre inconnue" }),
        Some(w) => match std::panic::catch_unwind(|| call(&w, str_of(cmd), &args)) {
            Ok(Ok(v)) => serde_json::json!({ "ok": v }),
            Ok(Err(e)) => serde_json::json!({ "err": e }),
            Err(_) => serde_json::json!({ "err": "erreur interne" }),
        },
    };
    CString::new(reply.to_string()).unwrap_or_default().into_raw()
}

#[no_mangle]
pub unsafe extern "C" fn ilot_free(p: *mut c_char) {
    if !p.is_null() {
        drop(CString::from_raw(p));
    }
}

/// Image servie a l'interface (`image://ilot/<cle>.<ext>`) : octets du
/// fichier (PNG, JPEG...), a liberer avec `ilot_free_bytes`.
#[no_mangle]
pub unsafe extern "C" fn ilot_image(id: *const c_char, len: *mut usize) -> *mut u8 {
    match img::lookup(str_of(id)) {
        Some(b) => {
            let b = b.into_boxed_slice();
            *len = b.len();
            Box::into_raw(b) as *mut u8
        }
        None => {
            *len = 0;
            std::ptr::null_mut()
        }
    }
}

#[no_mangle]
pub unsafe extern "C" fn ilot_free_bytes(p: *mut u8, len: usize) {
    if !p.is_null() {
        drop(Box::from_raw(std::ptr::slice_from_raw_parts_mut(p, len)));
    }
}

/// Diagnostics en ligne de commande (`--check-*`, `--winkey-remap`).
/// Renvoie le code de sortie, ou -1 s'il faut lancer l'interface.
#[no_mangle]
pub extern "C" fn ilot_cli() -> i32 {
    let args: Vec<String> = std::env::args().collect();
    let out = |i: usize, def: &str| args.get(i + 1).cloned().unwrap_or_else(|| def.into());
    // `--winkey-remap on|off` : relance en administrateur pour (de)remapper la touche Windows
    if let Some(i) = args.iter().position(|a| a == "--winkey-remap") {
        return winkey::remap_cli(args.get(i + 1).is_some_and(|a| a == "on"));
    }
    // `--check-icons <fichier>` : icones des fenetres de la barre
    if let Some(i) = args.iter().position(|a| a == "--check-icons") {
        let _ = std::fs::write(out(i, "icons.txt"), bar::check_icons());
        return 0;
    }
    // `--check-we <fichier>` : diagnostic Wallpaper Engine
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
        let _ = std::fs::write(out(i, "we-check.txt"), report);
        return 0;
    }
    // `--check-all <fichier>` : diagnostic des modules systeme
    if let Some(i) = args.iter().position(|a| a == "--check-all") {
        com_init_mta();
        let j = |v: serde_json::Result<String>| v.unwrap_or_default();
        let notifs = notif::snapshot();
        let report = [
            format!("devices: {}", j(serde_json::to_string(&audio::audio_devices()))),
            format!("mixer: {}", j(serde_json::to_string(&audio::mixer_get()).map(|s| s.chars().take(600).collect()))),
            format!("net: {}", j(serde_json::to_string(&net::net_get()))),
            format!("media: {} ; pochette {} o", j(serde_json::to_string(&media::media_get())), media::media_art().len()),
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
        let _ = std::fs::write(out(i, "check.txt"), report);
        return 0;
    }
    // `--check-media <fichier> <secondes>` : releve le media chaque seconde
    // (reconnexion apres un redemarrage du service media de Windows)
    if let Some(i) = args.iter().position(|a| a == "--check-media") {
        com_init_mta();
        let secs: u64 = args.get(i + 2).and_then(|s| s.parse().ok()).unwrap_or(20);
        let mut log = String::new();
        let t0 = std::time::Instant::now();
        while t0.elapsed().as_secs() < secs {
            let t = std::time::Instant::now();
            let m = media::media_get();
            log += &format!("{:5.1}s {} ({} ms) {}\n", t0.elapsed().as_secs_f32(), if m.has { m.title.as_str() } else { "(rien)" }, t.elapsed().as_millis(), media::diag());
            let _ = std::fs::write(out(i, "media-check.txt"), &log);
            std::thread::sleep(std::time::Duration::from_secs(1));
        }
        return 0;
    }
    // `--check-imap <hote> <fichier>` : test de connexion IMAP
    if let Some(i) = args.iter().position(|a| a == "--check-imap") {
        let host = args.get(i + 1).map(String::as_str).unwrap_or("imap.gmail.com");
        let _ = std::fs::write(args.get(i + 2).cloned().unwrap_or_else(|| "imap-check.txt".into()), mail::check(host));
        return 0;
    }
    // `--check-games <fichier>` : jeux detectes
    if let Some(i) = args.iter().position(|a| a == "--check-games") {
        let _ = std::fs::write(out(i, "games-check.txt"), games::report());
        return 0;
    }
    // `--check-update <fichier>` : derniere version publiee et notes de version
    if let Some(i) = args.iter().position(|a| a == "--check-update") {
        let report = format!(
            "{}\n{}",
            serde_json::to_string_pretty(&update::update_check(AppHandle)).unwrap_or_default(),
            serde_json::to_string_pretty(&update::changelog()).unwrap_or_default()
        );
        let _ = std::fs::write(out(i, "update-check.txt"), report);
        return 0;
    }
    // mise a jour telechargee (mode automatique) : installee avant de lancer
    // l'interface, le script relance l'ilot
    if args.len() <= 1 && update::install_pending_at_start() {
        return 0;
    }
    -1
}
