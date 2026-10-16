//! Barre facon Waybar : fenetres ouvertes, bureaux virtuels, reservation du
//! haut des ecrans (AppBar) et masquage des barres des taches Windows.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, AtomicIsize, Ordering};
use std::sync::Mutex;
use std::time::Duration;

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, WebviewWindow};
use windows::core::{w, BOOL, GUID, HSTRING, PCWSTR, PWSTR};
use windows::Win32::Foundation::{CloseHandle, HWND, LPARAM, PROPERTYKEY, RECT, WPARAM};
use windows::Win32::Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_CLOAKED, DWMWA_EXTENDED_FRAME_BOUNDS};
use windows::Win32::Graphics::Gdi::{
    CreateCompatibleBitmap, CreateCompatibleDC, DeleteDC, DeleteObject, GetDC, GetDIBits, ReleaseDC,
    SelectObject, BITMAPINFO, BITMAPINFOHEADER, BI_RGB, DIB_RGB_COLORS, HGDIOBJ,
};
use windows::Win32::Storage::Xps::{PrintWindow, PRINT_WINDOW_FLAGS};
use windows::Win32::System::Com::CoTaskMemFree;
use windows::Win32::System::Com::StructuredStorage::PropVariantToStringAlloc;
use windows::Win32::System::Registry::{RegGetValueW, HKEY_CURRENT_USER, RRF_RT_REG_BINARY};
use windows::Win32::System::RemoteDesktop::ProcessIdToSessionId;
use windows::Win32::System::Threading::{
    GetCurrentProcessId, OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32,
    PROCESS_QUERY_LIMITED_INFORMATION,
};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYBD_EVENT_FLAGS, KEYEVENTF_EXTENDEDKEY,
    KEYEVENTF_KEYUP, VIRTUAL_KEY, VK_LCONTROL, VK_LEFT, VK_LWIN, VK_MENU, VK_RIGHT,
};
use windows::Win32::UI::Shell::PropertiesSystem::{IPropertyStore, SHGetPropertyStoreForWindow};
use windows::Win32::UI::Shell::{
    ExtractIconExW, SHAppBarMessage, ABE_TOP, ABM_GETSTATE, ABM_NEW, ABM_QUERYPOS, ABM_REMOVE, ABM_SETPOS,
    ABM_SETSTATE, ABS_ALWAYSONTOP, ABS_AUTOHIDE, APPBARDATA,
};
use windows::Win32::UI::WindowsAndMessaging::{
    GetClassLongPtrW, GetIconInfo, SendMessageTimeoutW, GCLP_HICON, GCLP_HICONSM, HICON, ICONINFO, ICON_BIG,
    ICON_SMALL, ICON_SMALL2, SMTO_ABORTIFHUNG, WM_GETICON,
    EnumWindows, FindWindowW, GetClassNameW, GetForegroundWindow, GetWindow, GetWindowLongPtrW, GetWindowRect,
    GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId, IsIconic, IsWindowVisible,
    PostMessageW, SetForegroundWindow, ShowWindow, GWL_EXSTYLE, GW_OWNER, SW_HIDE, SW_MINIMIZE,
    SW_RESTORE, SW_SHOWNA, WM_APP, WM_CLOSE, WS_EX_APPWINDOW, WS_EX_NOACTIVATE, WS_EX_TOOLWINDOW,
};

use crate::settings::Settings;

/// Hauteur de la barre, en pixels CSS (la meme que l'ilot replie).
pub const BAR_H: f64 = 30.0;

#[derive(Serialize, Clone, PartialEq)]
pub struct Task {
    id: isize,
    title: String,
    /// Cle d'icone, a passer a `task_icon`
    icon: String,
}

#[derive(Serialize, Clone, PartialEq)]
pub struct Tasks {
    windows: Vec<Task>,
    /// Fenetre active (hors ilot), 0 si aucune
    active: isize,
    desktops: usize,
    desktop: usize,
}

/// Derniere fenetre au premier plan autre que l'ilot : un clic sur la barre
/// donne le focus a l'ilot, il faut donc s'en souvenir.
static ACTIVE: AtomicIsize = AtomicIsize::new(0);
static ICONS: Mutex<Option<HashMap<String, String>>> = Mutex::new(None);
/// Barre des taches Windows affichee temporairement (bouton de la barre).
static PEEK: AtomicBool = AtomicBool::new(false);
/// Vrai quand la barre des taches doit rester masquee.
static HIDE: AtomicBool = AtomicBool::new(false);
/// Barres des taches masquees par l'ilot, a reafficher.
static HIDDEN: Mutex<Vec<isize>> = Mutex::new(Vec::new());
/// Zone reservee en haut de chaque ecran (AppBar), par fenetre.
static RESERVED: Mutex<Vec<(isize, RECT)>> = Mutex::new(Vec::new());

fn hwnd(id: isize) -> HWND {
    HWND(id as _)
}

pub fn enabled(app: &AppHandle) -> bool {
    app.state::<Settings>().0.lock().unwrap().bar
}

/// Barre masquee automatiquement : le haut de l'ecran n'est pas reserve.
pub fn autohide(app: &AppHandle) -> bool {
    app.state::<Settings>().0.lock().unwrap().bar_autohide
}

// ------------------------------------------------------------- fenetres

pub(crate) fn class_of(h: HWND) -> String {
    let mut cls = [0u16; 64];
    let n = unsafe { GetClassNameW(h, &mut cls) } as usize;
    String::from_utf16_lossy(&cls[..n])
}

fn title_of(h: HWND) -> String {
    unsafe {
        let n = GetWindowTextLengthW(h);
        if n <= 0 {
            return String::new();
        }
        let mut buf = vec![0u16; n as usize + 1];
        let n = GetWindowTextW(h, &mut buf) as usize;
        String::from_utf16_lossy(&buf[..n])
    }
}

unsafe extern "system" fn collect(h: HWND, lp: LPARAM) -> BOOL {
    (*(lp.0 as *mut Vec<HWND>)).push(h);
    true.into()
}

fn top_windows() -> Vec<HWND> {
    let mut v: Vec<HWND> = Vec::new();
    unsafe {
        let _ = EnumWindows(Some(collect), LPARAM(&mut v as *mut _ as isize));
    }
    v
}

/// Memes regles que la barre des taches : visible, non masquee par DWM
/// (autre bureau virtuel, appli UWP suspendue), sans proprietaire et pas une
/// fenetre outil.
pub(crate) fn is_task(h: HWND) -> bool {
    unsafe {
        if !IsWindowVisible(h).as_bool() {
            return false;
        }
        let ex = GetWindowLongPtrW(h, GWL_EXSTYLE) as u32;
        let app = ex & WS_EX_APPWINDOW.0 != 0;
        if !app && (ex & WS_EX_TOOLWINDOW.0 != 0 || ex & WS_EX_NOACTIVATE.0 != 0) {
            return false;
        }
        if !app && GetWindow(h, GW_OWNER).is_ok_and(|o| !o.is_invalid()) {
            return false;
        }
        let mut cloaked = 0u32;
        let _ = DwmGetWindowAttribute(h, DWMWA_CLOAKED, &mut cloaked as *mut _ as _, 4);
        if cloaked != 0 {
            return false;
        }
        GetWindowTextLengthW(h) > 0
    }
}

fn exe_of(h: HWND) -> String {
    unsafe {
        let mut pid = 0u32;
        GetWindowThreadProcessId(h, Some(&mut pid));
        let Ok(p) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) else {
            return String::new();
        };
        let mut buf = [0u16; 1024];
        let mut len = buf.len() as u32;
        let ok = QueryFullProcessImageNameW(p, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &mut len).is_ok();
        let _ = CloseHandle(p);
        if ok { String::from_utf16_lossy(&buf[..len as usize]) } else { String::new() }
    }
}

/// AppUserModelID de la fenetre (applis UWP, Chrome...), s'il y en a un.
fn aumid_of(h: HWND) -> Option<String> {
    const PKEY_APPUSERMODEL_ID: PROPERTYKEY = PROPERTYKEY {
        fmtid: GUID::from_u128(0x9f4c2855_9f79_4b39_a8d0_e1d42de1d5f3),
        pid: 5,
    };
    unsafe {
        let store: IPropertyStore = SHGetPropertyStoreForWindow(h).ok()?;
        let v = store.GetValue(&PKEY_APPUSERMODEL_ID).ok()?;
        let p = PropVariantToStringAlloc(&v).ok()?;
        let s = p.to_string().ok();
        CoTaskMemFree(Some(p.0 as _));
        s.filter(|s| !s.is_empty())
    }
}

/// Cle d'icone : l'appli du menu Demarrer (AUMID) puis l'executable.
fn icon_key(h: HWND) -> String {
    let exe = exe_of(h);
    match aumid_of(h) {
        Some(id) => format!("shell:AppsFolder\\{id}\n{exe}"),
        None => exe,
    }
}

/// Nombre d'icones dans un executable : sans icone, le shell rend celle d'un
/// fichier quelconque (Voicemeeter...), mieux vaut alors celle de la fenetre.
fn has_icons(path: &str) -> bool {
    if path.starts_with("shell:") || !path.to_ascii_lowercase().ends_with(".exe") {
        return true;
    }
    unsafe { ExtractIconExW(&HSTRING::from(path), -1, None, None, 0) > 0 }
}

/// Icone donnee par la fenetre elle-meme, comme la barre des taches Windows.
fn window_icon(h: HWND) -> String {
    unsafe {
        let mut icon = 0usize;
        for kind in [ICON_BIG, ICON_SMALL2, ICON_SMALL] {
            let mut r = 0usize;
            let ok = SendMessageTimeoutW(h, WM_GETICON, WPARAM(kind as usize), LPARAM(0), SMTO_ABORTIFHUNG, 200, Some(&mut r));
            if ok.0 != 0 && r != 0 {
                icon = r;
                break;
            }
        }
        for idx in [GCLP_HICON, GCLP_HICONSM] {
            if icon == 0 {
                icon = GetClassLongPtrW(h, idx);
            }
        }
        if icon == 0 {
            return String::new();
        }
        let mut ii = ICONINFO::default();
        if GetIconInfo(HICON(icon as _), &mut ii).is_err() {
            return String::new();
        }
        let color = crate::apps::bitmap_bgra(ii.hbmColor);
        let mask = crate::apps::bitmap_bgra(ii.hbmMask);
        let _ = DeleteObject(HGDIOBJ(ii.hbmColor.0));
        let _ = DeleteObject(HGDIOBJ(ii.hbmMask.0));
        let Some((w, ht, mut buf)) = color else { return String::new() };
        // icone ancienne sans alpha : la transparence vient du masque (blanc)
        let has_alpha = buf.chunks(4).any(|p| p[3] != 0);
        for (i, p) in buf.chunks_mut(4).enumerate() {
            p.swap(0, 2);
            if !has_alpha {
                let clear = mask.as_ref().is_some_and(|(mw, _, m)| *mw == w && m.get(i * 4).is_some_and(|&v| v != 0));
                p[3] = if clear { 0 } else { 255 };
            } else if p[3] > 0 && p[3] < 255 {
                let a = p[3] as u32;
                for c in &mut p[..3] {
                    *c = ((*c as u32 * 255) / a).min(255) as u8;
                }
            }
        }
        crate::apps::rgba_png(w, ht, buf).unwrap_or_default()
    }
}

/// Icone d'une appli : celle du menu Demarrer (AUMID), de l'executable, ou a
/// defaut celle que la fenetre `id` affiche.
fn resolve_icon(key: &str, id: isize) -> String {
    let k = key.to_string();
    // les icones passent par le shell : thread STA dedie
    let icon = std::thread::spawn(move || {
        crate::com_init_sta();
        k.split('\n')
            .filter(|s| !s.is_empty() && has_icons(s))
            .map(crate::apps::file_icon)
            .find(|i| !i.is_empty())
            .unwrap_or_default()
    })
    .join()
    .unwrap_or_default();
    if icon.is_empty() && id != 0 {
        return window_icon(hwnd(id));
    }
    icon
}

#[tauri::command(async)]
pub fn task_icon(key: String, id: Option<isize>) -> String {
    if let Some(v) = ICONS.lock().unwrap().as_ref().and_then(|m| m.get(&key)) {
        return v.clone();
    }
    let icon = resolve_icon(&key, id.unwrap_or(0));
    // un echec (shell pas pret au demarrage, appli qui se lance) n'est pas
    // garde : l'interface reessaiera
    if !icon.is_empty() {
        ICONS.lock().unwrap().get_or_insert_with(HashMap::new).insert(key, icon.clone());
    }
    icon
}

/// Clic sur une fenetre de la barre : la met au premier plan, ou la reduit si
/// elle y est deja (comme la barre des taches).
#[tauri::command]
pub fn task_activate(id: isize) {
    let h = hwnd(id);
    unsafe {
        if IsIconic(h).as_bool() {
            let _ = ShowWindow(h, SW_RESTORE);
        } else if ACTIVE.load(Ordering::Relaxed) == id {
            let _ = ShowWindow(h, SW_MINIMIZE);
            ACTIVE.store(0, Ordering::Relaxed);
            return;
        }
        if !SetForegroundWindow(h).as_bool() || GetForegroundWindow() != h {
            // Windows refuse parfois : un appui sur Alt leve la restriction
            send(&[key(VK_MENU, false), key(VK_MENU, true)]);
            let _ = SetForegroundWindow(h);
        }
    }
    ACTIVE.store(id, Ordering::Relaxed);
}

/// Capture d'une fenetre pour l'apercu de la barre, en JPEG (data URL)
/// tenant dans `w` x `h` pixels. `min` si elle est reduite, vide si elle
/// refuse la capture (fenetre d'un processus administrateur...).
#[tauri::command(async)]
pub fn task_thumb(id: isize, w: u32, h: u32) -> String {
    if unsafe { IsIconic(hwnd(id)) }.as_bool() {
        return "min".into();
    }
    capture(hwnd(id))
        .and_then(|img| {
            let t = image::DynamicImage::ImageRgba8(img).thumbnail(w.max(1), h.max(1)).to_rgb8();
            let mut out = std::io::Cursor::new(Vec::new());
            t.write_to(&mut out, image::ImageFormat::Jpeg).ok()?;
            Some(crate::img::THUMBS.url("image/jpeg", out.into_inner()))
        })
        .unwrap_or_default()
}

fn capture(h: HWND) -> Option<image::RgbaImage> {
    unsafe {
        let mut wr = RECT::default();
        GetWindowRect(h, &mut wr).ok()?;
        // sans les bordures invisibles de redimensionnement (Windows 10/11)
        let mut fr = wr;
        let _ = DwmGetWindowAttribute(h, DWMWA_EXTENDED_FRAME_BOUNDS, &mut fr as *mut _ as _, std::mem::size_of::<RECT>() as u32);
        let (ww, wh) = (wr.right - wr.left, wr.bottom - wr.top);
        if ww <= 0 || wh <= 0 || ww > 16384 || wh > 16384 {
            return None;
        }
        let screen = GetDC(None);
        let dc = CreateCompatibleDC(Some(screen));
        let bmp = CreateCompatibleBitmap(screen, ww, wh);
        let old = SelectObject(dc, HGDIOBJ(bmp.0));
        // PW_RENDERFULLCONTENT : marche aussi pour les fenetres accelerees (Chrome...)
        let ok = PrintWindow(h, dc, PRINT_WINDOW_FLAGS(2)).as_bool();
        SelectObject(dc, old);
        let mut bmi = BITMAPINFO {
            bmiHeader: BITMAPINFOHEADER {
                biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
                biWidth: ww,
                biHeight: -wh,
                biPlanes: 1,
                biBitCount: 32,
                biCompression: BI_RGB.0,
                ..Default::default()
            },
            ..Default::default()
        };
        let mut buf = vec![0u8; (ww * wh * 4) as usize];
        let lines = if ok {
            GetDIBits(dc, bmp, 0, wh as u32, Some(buf.as_mut_ptr() as _), &mut bmi, DIB_RGB_COLORS)
        } else {
            0
        };
        let _ = DeleteObject(HGDIOBJ(bmp.0));
        let _ = DeleteDC(dc);
        ReleaseDC(None, screen);
        if lines == 0 {
            return None;
        }
        for p in buf.chunks_mut(4) {
            p.swap(0, 2);
            p[3] = 255;
        }
        let img = image::RgbaImage::from_raw(ww as u32, wh as u32, buf)?;
        let x = (fr.left - wr.left).clamp(0, ww - 1) as u32;
        let y = (fr.top - wr.top).clamp(0, wh - 1) as u32;
        let cw = ((fr.right - fr.left) as u32).min(ww as u32 - x).max(1);
        let ch = ((fr.bottom - fr.top) as u32).min(wh as u32 - y).max(1);
        Some(image::imageops::crop_imm(&img, x, y, cw, ch).to_image())
    }
}

#[tauri::command]
pub fn task_close(id: isize) {
    unsafe {
        let _ = PostMessageW(Some(hwnd(id)), WM_CLOSE, WPARAM(0), LPARAM(0));
    }
}

// ------------------------------------------------------ bureaux virtuels

const VD: &str = r"Software\Microsoft\Windows\CurrentVersion\Explorer\VirtualDesktops";

fn reg_bin(key: &str, name: &str) -> Option<Vec<u8>> {
    let (k, n) = (HSTRING::from(key), HSTRING::from(name));
    let mut len = 0u32;
    unsafe {
        RegGetValueW(HKEY_CURRENT_USER, &k, &n, RRF_RT_REG_BINARY, None, None, Some(&mut len)).ok().ok()?;
        let mut buf = vec![0u8; len as usize];
        RegGetValueW(HKEY_CURRENT_USER, &k, &n, RRF_RT_REG_BINARY, None, Some(buf.as_mut_ptr() as _), Some(&mut len))
            .ok()
            .ok()?;
        buf.truncate(len as usize);
        Some(buf)
    }
}

/// (nombre de bureaux, index du bureau courant), lus dans le registre :
/// Windows n'a pas d'API publique pour les enumerer.
fn desktops() -> (usize, usize) {
    let ids = reg_bin(VD, "VirtualDesktopIDs").unwrap_or_default();
    // Windows 11 : dans VirtualDesktops ; Windows 10 : par session
    let cur = reg_bin(VD, "CurrentVirtualDesktop").or_else(|| {
        let mut sid = 0u32;
        unsafe { ProcessIdToSessionId(GetCurrentProcessId(), &mut sid) }.ok()?;
        reg_bin(
            &format!(r"Software\Microsoft\Windows\CurrentVersion\Explorer\SessionInfo\{sid}\VirtualDesktops"),
            "CurrentVirtualDesktop",
        )
    });
    let n = (ids.len() / 16).max(1);
    let i = cur.and_then(|c| ids.chunks(16).position(|g| g == c.as_slice())).unwrap_or(0);
    (n, i)
}

fn key(vk: VIRTUAL_KEY, up: bool) -> INPUT {
    let ext = matches!(vk, VK_LEFT | VK_RIGHT | VK_LWIN);
    let mut flags = KEYBD_EVENT_FLAGS(0);
    if up {
        flags |= KEYEVENTF_KEYUP;
    }
    if ext {
        flags |= KEYEVENTF_EXTENDEDKEY;
    }
    INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT { wVk: vk, wScan: 0, dwFlags: flags, time: 0, dwExtraInfo: 0 },
        },
    }
}

fn send(keys: &[INPUT]) {
    unsafe {
        SendInput(keys, std::mem::size_of::<INPUT>() as i32);
    }
}

/// Va au bureau `index` avec Ctrl+Win+Gauche/Droite (seul moyen public).
#[tauri::command(async)]
pub fn desktop_go(index: usize) {
    let (n, cur) = desktops();
    let target = index.min(n - 1);
    let arrow = if target > cur { VK_RIGHT } else { VK_LEFT };
    for _ in 0..target.abs_diff(cur) {
        send(&[
            key(VK_LCONTROL, false),
            key(VK_LWIN, false),
            key(arrow, false),
            key(arrow, true),
            key(VK_LWIN, true),
            key(VK_LCONTROL, true),
        ]);
        std::thread::sleep(Duration::from_millis(120));
    }
}

// ------------------------------------------------- reservation de l'ecran

/// Reserve le haut de l'ecran (`Some`) ou le libere (`None`) : les fenetres
/// maximisees s'arretent alors sous la barre.
pub fn reserve(win: &WebviewWindow, rect: Option<RECT>) {
    let Ok(h) = win.hwnd() else { return };
    let mut st = RESERVED.lock().unwrap();
    let i = st.iter().position(|s| s.0 == h.0 as isize);
    if i.map(|i| st[i].1) == rect {
        return;
    }
    let mut d = APPBARDATA {
        cbSize: std::mem::size_of::<APPBARDATA>() as u32,
        hWnd: h,
        uCallbackMessage: WM_APP + 0x1b,
        uEdge: ABE_TOP,
        ..Default::default()
    };
    unsafe {
        match rect {
            None => {
                SHAppBarMessage(ABM_REMOVE, &mut d);
                st.retain(|s| s.0 != h.0 as isize);
            }
            Some(r) => {
                if i.is_none() {
                    SHAppBarMessage(ABM_NEW, &mut d);
                }
                d.rc = r;
                SHAppBarMessage(ABM_QUERYPOS, &mut d);
                d.rc.bottom = d.rc.top + (r.bottom - r.top);
                SHAppBarMessage(ABM_SETPOS, &mut d);
                match i {
                    Some(i) => st[i].1 = r,
                    None => st.push((h.0 as isize, r)),
                }
            }
        }
    }
}

// --------------------------------------------- barre des taches Windows

fn autohide_get() -> bool {
    let mut d = APPBARDATA { cbSize: std::mem::size_of::<APPBARDATA>() as u32, ..Default::default() };
    unsafe { SHAppBarMessage(ABM_GETSTATE, &mut d) as u32 & ABS_AUTOHIDE != 0 }
}

fn autohide_set(on: bool) {
    unsafe {
        let Ok(tray) = FindWindowW(w!("Shell_TrayWnd"), PCWSTR::null()) else { return };
        let mut d = APPBARDATA {
            cbSize: std::mem::size_of::<APPBARDATA>() as u32,
            hWnd: tray,
            lParam: LPARAM((if on { ABS_AUTOHIDE } else { ABS_ALWAYSONTOP }) as isize),
            ..Default::default()
        };
        SHAppBarMessage(ABM_SETSTATE, &mut d);
    }
}

/// Barres des taches de tous les ecrans (principale et secondaires) : les
/// autres ecrans ont chacun leur barre (voir `screens`).
fn trays() -> Vec<HWND> {
    top_windows()
        .into_iter()
        .filter(|&h| matches!(class_of(h).as_str(), "Shell_TrayWnd" | "Shell_SecondaryTrayWnd"))
        .collect()
}

fn show_trays() {
    for h in HIDDEN.lock().unwrap().drain(..) {
        unsafe {
            let _ = ShowWindow(hwnd(h), SW_SHOWNA);
        }
    }
}

/// Masque les barres des taches. Windows les reaffiche parfois (menu
/// Demarrer...) : appele en boucle.
fn hide_trays() {
    let now = trays();
    let mut hidden = HIDDEN.lock().unwrap();
    // barre disparue (ecran debranche, explorer relance) : rien a rendre
    hidden.retain(|&h| now.iter().any(|n| n.0 as isize == h));
    for h in now {
        unsafe {
            if IsWindowVisible(h).as_bool() {
                let _ = ShowWindow(h, SW_HIDE);
            }
        }
        if !hidden.contains(&(h.0 as isize)) {
            hidden.push(h.0 as isize);
        }
    }
}

/// Applique les reglages : barre des taches Windows masquee ou non.
pub fn sync(app: &AppHandle) {
    let (bar, hide, prev) = {
        let st = app.state::<Settings>();
        let c = st.0.lock().unwrap();
        (c.bar, c.hide_taskbar, c.taskbar_autohide)
    };
    let want = bar && hide && !PEEK.load(Ordering::Relaxed);
    HIDE.store(want, Ordering::Relaxed);
    if want {
        // masquage automatique : sinon la place de la barre resterait vide
        let cur = autohide_get();
        if prev.is_none() {
            crate::settings::update(app, |c| c.taskbar_autohide = Some(cur));
        }
        if !cur {
            autohide_set(true);
        }
        hide_trays();
    } else {
        show_trays();
        if let Some(p) = prev {
            if autohide_get() != p {
                autohide_set(p);
            }
            if !(bar && hide) {
                crate::settings::update(app, |c| c.taskbar_autohide = None);
            }
        }
    }
    let _ = app.emit("taskbar-peek", PEEK.load(Ordering::Relaxed));
}

/// Affiche / remasque la barre des taches Windows (bouton de la barre).
#[tauri::command]
pub fn taskbar_peek(app: AppHandle, show: bool) {
    PEEK.store(show, Ordering::Relaxed);
    sync(&app);
}

/// A la fermeture : tout remettre comme avant.
pub fn restore(app: &AppHandle) {
    HIDE.store(false, Ordering::Relaxed);
    show_trays();
    let prev = app.state::<Settings>().0.lock().unwrap().taskbar_autohide;
    if let Some(p) = prev {
        autohide_set(p);
        crate::settings::update(app, |c| c.taskbar_autohide = None);
    }
    for win in app.webview_windows().into_values() {
        reserve(&win, None);
    }
}

// ----------------------------------------------------------------- suivi

/// Fenetres pour lesquelles Windows reaffiche la barre des taches : on ne la
/// remasque pas tant qu'elles ont le focus.
const SHELL_UI: &[&str] = &[
    "Windows.UI.Core.CoreWindow",
    "Shell_TrayWnd",
    "Shell_SecondaryTrayWnd",
    "XamlExplorerHostIslandWindow",
    "TopLevelWindowForOverflowXamlIsland",
    "NotifyIconOverflowWindow",
];

fn snapshot(own: HWND, order: &mut Vec<isize>, keys: &mut HashMap<isize, String>) -> Tasks {
    let live: Vec<HWND> = top_windows().into_iter().filter(|&h| h != own && is_task(h)).collect();
    let ids: Vec<isize> = live.iter().map(|h| h.0 as isize).collect();
    // ordre d'apparition stable (EnumWindows suit l'ordre Z)
    order.retain(|i| ids.contains(i));
    keys.retain(|i, _| ids.contains(i));
    for &i in &ids {
        if !order.contains(&i) {
            order.push(i);
        }
    }
    let windows = order
        .iter()
        .map(|&i| Task {
            id: i,
            title: title_of(hwnd(i)),
            icon: keys.entry(i).or_insert_with(|| icon_key(hwnd(i))).clone(),
        })
        .collect();
    let fg = unsafe { GetForegroundWindow() };
    if fg != own {
        let id = fg.0 as isize;
        ACTIVE.store(if ids.contains(&id) { id } else { 0 }, Ordering::Relaxed);
    }
    let (desktops, desktop) = desktops();
    Tasks { windows, active: ACTIVE.load(Ordering::Relaxed), desktops, desktop }
}

/// Diagnostic : cle d'icone de chaque fenetre et taille de l'icone obtenue.
pub fn check_icons() -> String {
    crate::com_init_sta();
    top_windows()
        .into_iter()
        .filter(|&h| is_task(h))
        .map(|h| {
            let key = icon_key(h);
            let parts: Vec<String> = key
                .split('\n')
                .filter(|s| !s.is_empty())
                .map(|p| format!("{} o <- {p} (icones: {})", crate::apps::file_icon(p).len(), has_icons(p)))
                .collect();
            let win = window_icon(h);
            let used = resolve_icon(&key, h.0 as isize);
            if let Some(dir) = std::env::var_os("ILOT_ICON_DIR") {
                if let Some(bytes) = crate::img::bytes(&used) {
                    let _ = std::fs::write(std::path::Path::new(&dir).join(format!("{}.png", h.0 as isize)), bytes);
                }
            }
            format!(
                "{} [{}]\n  {}\n  fenetre: {} o\n  retenue: {} o",
                title_of(h),
                h.0 as isize,
                if parts.is_empty() { "(cle vide)".into() } else { parts.join("\n  ") },
                win.len(),
                used.len()
            )
        })
        .collect::<Vec<_>>()
        .join("\n")
}

#[tauri::command]
pub fn bar_windows(win: WebviewWindow) -> Tasks {
    crate::com_init_sta();
    let own = win.hwnd().unwrap_or_default();
    snapshot(own, &mut Vec::new(), &mut HashMap::new())
}

/// Emet `tasks` quand les fenetres ou le bureau changent, et garde la barre
/// des taches Windows masquee. Reveille par les evenements de fenetres
/// (`events::WINDOWS`), au plus toutes les 250 ms ; sans evenement, un
/// releve toutes les 3 s rattrape ce qu'ils ne signalent pas.
pub fn watch(win: WebviewWindow) {
    std::thread::spawn(move || {
        crate::com_init_sta();
        let app = win.app_handle().clone();
        let own = win.hwnd().unwrap_or_default();
        let mut order = Vec::new();
        let mut keys = HashMap::new();
        let mut last: Option<Tasks> = None;
        let mut seen = crate::events::WINDOWS.seq();
        loop {
            std::thread::sleep(Duration::from_millis(250));
            seen = crate::events::WINDOWS.wait(seen, Duration::from_secs(3));
            if HIDE.load(Ordering::Relaxed) {
                let fg = unsafe { GetForegroundWindow() };
                if !SHELL_UI.contains(&class_of(fg).as_str()) {
                    hide_trays();
                }
            }
            if !enabled(&app) {
                last = None;
                continue;
            }
            let now = snapshot(own, &mut order, &mut keys);
            if last.as_ref() != Some(&now) {
                let _ = app.emit("tasks", &now);
                last = Some(now);
            }
        }
    });
}
