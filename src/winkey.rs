//! Touche Windows : appuyee seule, elle ouvre le lanceur de l'ilot au lieu du
//! menu Demarrer. Les raccourcis (Win+E, Win+D, Win+Maj+S...) restent ceux de
//! Windows.
//!
//! Depuis 2023, Windows 11 detecte la touche Windows physique avant les hooks
//! clavier : les intercepter ne suffit plus a empecher le menu Demarrer. Les
//! deux touches Windows sont donc remappees en F24 au niveau du pilote clavier
//! (« Scancode Map », droits administrateur et redemarrage necessaires), et le
//! hook ci-dessous retraduit F24 : seule, elle ouvre l'ilot ; avec une autre
//! touche, ou quand l'ilot ne la prend pas, elle redevient une vraie touche
//! Windows. Tant que le remappage n'est pas actif, le hook intercepte la vraie
//! touche Windows et referme le menu Demarrer s'il s'ouvre quand meme.
//!
//! Le hook prend aussi les raccourcis configures avec la touche Windows
//! (Win+T pour un terminal...), que `RegisterHotKey` refuse quand Windows se
//! les reserve, et capte la combinaison tapee dans Reglages > Raccourcis
//! (Windows la garderait pour lui, l'ilot ne la verrait pas).

use std::os::windows::ffi::OsStrExt;
use std::sync::atomic::{AtomicBool, AtomicIsize, AtomicU16, AtomicU32, AtomicU64, Ordering};
use std::sync::{Mutex, OnceLock};
use std::time::{Duration, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use crate::host::{AppHandle};
use windows::core::{w, PCWSTR, PWSTR};
use windows::Win32::Foundation::{CloseHandle, ERROR_FILE_NOT_FOUND, HINSTANCE, HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::System::LibraryLoader::GetModuleHandleW;
use windows::Win32::System::Registry::{
    RegDeleteKeyValueW, RegGetValueW, RegSetKeyValueW, HKEY_LOCAL_MACHINE, REG_BINARY, RRF_RT_REG_BINARY,
};
use windows::Win32::System::Shutdown::LockWorkStation;
use windows::Win32::System::SystemInformation::GetTickCount64;
use windows::Win32::System::Threading::{
    GetExitCodeProcess, OpenProcess, QueryFullProcessImageNameW, WaitForSingleObject, INFINITE,
    PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION,
};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    GetAsyncKeyState, SendInput, INPUT, INPUT_0, INPUT_KEYBOARD, KEYBDINPUT, KEYBD_EVENT_FLAGS,
    KEYEVENTF_EXTENDEDKEY, KEYEVENTF_KEYUP, MOD_ALT, MOD_CONTROL, MOD_SHIFT, VIRTUAL_KEY, VK_CAPITAL, VK_CONTROL,
    VK_ESCAPE, VK_F24, VK_L, VK_LWIN, VK_MENU, VK_RWIN, VK_SHIFT,
};
use windows::Win32::UI::Shell::{ShellExecuteExW, SEE_MASK_NOCLOSEPROCESS, SHELLEXECUTEINFOW};
use windows::Win32::UI::WindowsAndMessaging::{
    CallNextHookEx, DispatchMessageW, GetForegroundWindow, GetMessageW, GetWindowThreadProcessId,
    SetTimer, SetWindowsHookExW, TranslateMessage, UnhookWindowsHookEx, HC_ACTION, KBDLLHOOKSTRUCT,
    LLKHF_EXTENDED, MSG, SW_HIDE, WH_KEYBOARD_LL, WM_KEYDOWN, WM_SYSKEYDOWN, WM_TIMER,
};

/// Touche non attribuee, sans effet (meme astuce que PowerToys)
const MASK: VIRTUAL_KEY = VIRTUAL_KEY(0xE8);
/// Marque nos propres frappes simulees pour que le hook les ignore.
const OURS: usize = 0x494C_4F54; // « ILOT »
/// Codes clavier (scancodes) : touches Windows gauche et droite, et F24
const LWIN_SC: u32 = 0xE05B;
const RWIN_SC: u32 = 0xE05C;
const F24_SC: u32 = 0x76;
const LAYOUT: PCWSTR = w!(r"SYSTEM\CurrentControlSet\Control\Keyboard Layout");
const MAP: PCWSTR = w!("Scancode Map");

static APP: OnceLock<AppHandle> = OnceLock::new();
/// Fenetre de l'ilot, lue une fois pour toutes : le hook doit repondre en
/// quelques millisecondes, sinon Windows passe outre.
static ISLAND: AtomicIsize = AtomicIsize::new(0);
static ENABLED: AtomicBool = AtomicBool::new(false);
static STARTED: AtomicBool = AtomicBool::new(false);
/// Win enfoncee et retenue par l'ilot
static HELD: AtomicBool = AtomicBool::new(false);
/// Une autre touche a ete pressee pendant que Win etait enfoncee
static COMBO: AtomicBool = AtomicBool::new(false);
/// L'appui sur Win a ete rendu a Windows (raccourci)
static SENT: AtomicBool = AtomicBool::new(false);
/// F24 enfoncee que l'ilot ne prend pas : rendue telle quelle comme touche Windows
static PASS: AtomicBool = AtomicBool::new(false);
/// Touche Win retenue (gauche ou droite)
static WIN: AtomicU16 = AtomicU16::new(0);
/// Une touche Windows est enfoncee (vraie touche ou F24 remappee)
static WIN_DOWN: AtomicBool = AtomicBool::new(false);
/// Raccourcis avec la touche Windows : (autres modificateurs MOD_*, touche, action)
static COMBOS: Mutex<Vec<(u32, u32, String)>> = Mutex::new(Vec::new());
/// Touche du dernier raccourci declenche, tant qu'elle reste enfoncee
/// (la repetition automatique ne relance pas l'appli)
static FIRED: AtomicU32 = AtomicU32::new(0);
/// Enregistrement d'une combinaison dans les reglages, jusqu'a cette heure
/// (GetTickCount64) : sans reponse de l'interface, il s'arrete tout seul
static RECORD: AtomicU64 = AtomicU64::new(0);

// ------------------------------------------------------------------ hook

/// Au demarrage de l'ilot
pub fn init(app: &AppHandle) {
    let on = app.state::<crate::settings::Settings>().0.lock().unwrap().win_key;
    set(app, on);
}

/// Active ou desactive l'ilot sur la touche Windows. Le hook tourne aussi
/// reglage coupe tant que la touche est remappee : il la retraduit alors en
/// vraie touche Windows.
pub fn set(app: &AppHandle, on: bool) {
    ENABLED.store(on, Ordering::Relaxed);
    if on || remap_configured() || pending(app) {
        start(app);
    }
}

/// Raccourcis avec la touche Windows (prefs) ; le hook tourne s'il y en a.
pub fn set_combos(app: &AppHandle, list: Vec<(u32, u32, String)>) {
    let any = !list.is_empty();
    *COMBOS.lock().unwrap() = list;
    if any {
        start(app);
    }
}

/// Reglages > Raccourcis : la prochaine combinaison avec la touche Windows
/// n'est pas executee mais envoyee a l'interface (`keyrec` : touche et
/// modificateurs), Windows ne la voyant jamais.
pub fn shortcuts_record(app: AppHandle, on: bool) {
    let until = if on { unsafe { GetTickCount64() + 20_000 } } else { 0 };
    RECORD.store(until, Ordering::Relaxed);
    if on {
        start(&app);
    }
}

fn recording() -> bool {
    let now = unsafe { GetTickCount64() };
    now < RECORD.load(Ordering::Relaxed)
}

/// Ctrl, Alt, Maj enfoncees (MOD_*)
fn held_mods() -> u32 {
    let down = |k: VIRTUAL_KEY| unsafe { GetAsyncKeyState(k.0 as i32) } as u16 & 0x8000 != 0;
    [(VK_MENU, MOD_ALT), (VK_CONTROL, MOD_CONTROL), (VK_SHIFT, MOD_SHIFT)]
        .iter()
        .filter(|(k, _)| down(*k))
        .fold(0, |m, (_, f)| m | f.0)
}

/// Maj, Ctrl, Alt (gauche ou droite), Windows, Verr. Maj
fn is_modifier(vk: u32) -> bool {
    matches!(vk, 0x10..=0x12 | 0x14 | 0x5B | 0x5C | 0xA0..=0xA5)
}

/// Crochet clavier installe (il previent des appuis sur Verr. Maj)
pub fn running() -> bool {
    STARTED.load(Ordering::Relaxed)
}

fn start(app: &AppHandle) {
    if STARTED.swap(true, Ordering::Relaxed) {
        return;
    }
    let _ = APP.set(app.clone());
    if let Some(h) = app.get_webview_window("island").and_then(|w| w.hwnd().ok()) {
        ISLAND.store(h.0 as isize, Ordering::Relaxed);
    }
    std::thread::spawn(|| unsafe {
        let Ok(mut hook_id) = SetWindowsHookExW(WH_KEYBOARD_LL, Some(hook), module(), 0) else {
            STARTED.store(false, Ordering::Relaxed);
            return;
        };
        // Windows retire sans prevenir un hook juge trop lent (machine tres
        // chargee...) : on le reinstalle regulierement par securite
        let _ = SetTimer(None, 0, 5000, None);
        // un hook bas niveau n'est appele que si son thread traite ses messages
        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).as_bool() {
            if msg.message == WM_TIMER {
                // pas pendant un appui : l'ancien hook verrait la suite
                if !HELD.load(Ordering::Relaxed) && !PASS.load(Ordering::Relaxed) {
                    if let Ok(h) = SetWindowsHookExW(WH_KEYBOARD_LL, Some(hook), module(), 0) {
                        let _ = UnhookWindowsHookEx(hook_id);
                        hook_id = h;
                    }
                }
                continue;
            }
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    });
}

/// Hook global : Windows attend le module qui contient la procedure
fn module() -> Option<HINSTANCE> {
    unsafe { GetModuleHandleW(None) }.ok().map(Into::into)
}

fn key(vk: VIRTUAL_KEY, flags: KEYBD_EVENT_FLAGS) -> INPUT {
    INPUT {
        r#type: INPUT_KEYBOARD,
        Anonymous: INPUT_0 {
            ki: KEYBDINPUT { wVk: vk, dwFlags: flags, dwExtraInfo: OURS, ..Default::default() },
        },
    }
}

/// Les frappes simulees depuis le hook passent apres l'evenement en cours :
/// l'ordre avec les vraies frappes est garanti.
fn send(inputs: &[INPUT]) {
    unsafe { SendInput(inputs, std::mem::size_of::<INPUT>() as i32) };
}

fn win_key(up: bool) -> INPUT {
    let flags = if up { KEYEVENTF_EXTENDEDKEY | KEYEVENTF_KEYUP } else { KEYEVENTF_EXTENDEDKEY };
    key(VIRTUAL_KEY(WIN.load(Ordering::Relaxed)), flags)
}

fn island_hwnd() -> HWND {
    HWND(ISLAND.load(Ordering::Relaxed) as _)
}

unsafe extern "system" fn hook(code: i32, wp: WPARAM, lp: LPARAM) -> LRESULT {
    let next = || unsafe { CallNextHookEx(None, code, wp, lp) };
    if code != HC_ACTION as i32 {
        return next();
    }
    let kb = unsafe { &*(lp.0 as *const KBDLLHOOKSTRUCT) };
    if kb.dwExtraInfo == OURS {
        return next();
    }
    let vk = VIRTUAL_KEY(kb.vkCode as u16);
    let msg = wp.0 as u32;
    let down = msg == WM_KEYDOWN || msg == WM_SYSKEYDOWN;
    if (vk == VK_CAPITAL && !down) || (down && matches!(kb.vkCode, 0x10 | 0xA0 | 0xA1)) {
        crate::events::CAPS.notify();
    }
    // touche Windows remappee en F24 par le pilote
    let remapped = vk == VK_F24 && kb.scanCode == F24_SC;
    let is_win = remapped || vk == VK_LWIN || vk == VK_RWIN;
    let held = HELD.load(Ordering::Relaxed);
    if is_win {
        WIN_DOWN.store(down, Ordering::Relaxed);
    }

    if !is_win {
        let code = kb.vkCode;
        if !down {
            if FIRED.load(Ordering::Relaxed) == code {
                FIRED.store(0, Ordering::Relaxed);
            }
            return next();
        }
        // raccourci avec la touche Windows (ou enregistrement dans les reglages)
        if WIN_DOWN.load(Ordering::Relaxed) && !is_modifier(code) {
            if FIRED.load(Ordering::Relaxed) == code {
                return LRESULT(1);
            }
            let mods = held_mods();
            let rec = recording();
            let action = if rec {
                None
            } else {
                COMBOS.lock().unwrap().iter().find(|c| c.0 == mods && c.1 == code).map(|c| c.2.clone())
            };
            if rec || action.is_some() {
                FIRED.store(code, Ordering::Relaxed);
                COMBO.store(true, Ordering::Relaxed);
                if rec {
                    RECORD.store(0, Ordering::Relaxed);
                }
                // si Windows a vu Win enfoncee : une touche sans effet, pour
                // qu'il n'ouvre pas le menu Demarrer au relachement
                send(&[key(MASK, KEYBD_EVENT_FLAGS(0)), key(MASK, KEYEVENTF_KEYUP)]);
                if let Some(&app) = APP.get() {
                    // hors du hook : il doit rendre la main tres vite
                    std::thread::spawn(move || match action {
                        Some(a) => crate::prefs::fire(&app, a),
                        None => {
                            let _ = app.emit("keyrec", serde_json::json!({ "vk": code, "mods": mods }));
                        }
                    });
                }
                return LRESULT(1);
            }
        }
        if !held || COMBO.swap(true, Ordering::Relaxed) {
            return next();
        }
        // Premiere touche d'un raccourci : on rend Win a Windows, suivie de
        // cette touche (avalee ici pour garder l'ordre)
        if vk == VK_L {
            // Win+L simule est ignore par Windows : on verrouille nous-memes
            std::thread::spawn(|| unsafe { LockWorkStation() });
            return LRESULT(1);
        }
        SENT.store(true, Ordering::Relaxed);
        let mut k = key(vk, KEYBD_EVENT_FLAGS(kb.flags.0 & LLKHF_EXTENDED.0));
        k.Anonymous.ki.wScan = kb.scanCode as u16;
        send(&[win_key(false), k]);
        return LRESULT(1);
    }
    if down {
        if held || PASS.load(Ordering::Relaxed) {
            // repetition automatique : Windows a deja eu son appui, ou ne doit rien voir
            return if !remapped && SENT.load(Ordering::Relaxed) { next() } else { LRESULT(1) };
        }
        WIN.store(if remapped { VK_LWIN.0 } else { vk.0 }, Ordering::Relaxed);
        // Ctrl+Win+fleches, Maj+Win, jeu en plein ecran... : on ne s'en mele pas
        let mods = [VK_CONTROL, VK_SHIFT, VK_MENU]
            .iter()
            .any(|&m| unsafe { GetAsyncKeyState(m.0 as i32) } as u16 & 0x8000 != 0);
        if !ENABLED.load(Ordering::Relaxed) || mods || crate::fullscreen_foreground(island_hwnd()) {
            if !remapped {
                return next();
            }
            PASS.store(true, Ordering::Relaxed);
            send(&[win_key(false)]);
            return LRESULT(1);
        }
        // Win est retenue : aucune fenetre ne la voit tant qu'on ne sait pas
        // si c'est un raccourci ou un appui seul
        HELD.store(true, Ordering::Relaxed);
        COMBO.store(false, Ordering::Relaxed);
        SENT.store(false, Ordering::Relaxed);
        if !remapped {
            // une touche sans effet entre l'appui et le relachement : pour
            // l'ancienne detection de Windows, ce n'est plus un appui « seul »
            send(&[key(MASK, KEYBD_EVENT_FLAGS(0)), key(MASK, KEYEVENTF_KEYUP)]);
        }
        return LRESULT(1);
    }
    // relachement
    if PASS.swap(false, Ordering::Relaxed) {
        send(&[win_key(true)]);
        return LRESULT(1);
    }
    if !HELD.swap(false, Ordering::Relaxed) {
        return if remapped { LRESULT(1) } else { next() };
    }
    if SENT.load(Ordering::Relaxed) {
        // raccourci : Windows a recu l'appui, il recoit le relachement
        if !remapped {
            return next();
        }
        send(&[win_key(true)]);
        return LRESULT(1);
    }
    // appui seul pendant l'enregistrement d'un raccourci : rien
    if !COMBO.load(Ordering::Relaxed) && !recording() {
        if let Some(app) = APP.get() {
            // hors du hook : il doit rendre la main tres vite
            let app = app.clone();
            std::thread::spawn(move || {
                let opening = !crate::island_open(&app);
                crate::toggle_launcher(&app);
                if !remapped {
                    close_start_menu(&app, opening);
                }
            });
        }
    }
    LRESULT(1)
}

/// Sans remappage, Windows ouvre quand meme le menu Demarrer un peu apres
/// l'appui : on le referme (Echap) et l'ilot reprend la main s'il s'ouvrait.
fn close_start_menu(app: &AppHandle, opening: bool) {
    let mut tries = 0;
    for i in 0..150 {
        std::thread::sleep(Duration::from_millis(10));
        if !is_start_menu(unsafe { GetForegroundWindow() }) {
            if tries > 0 {
                break;
            }
            continue;
        }
        // le menu ignore Echap tant qu'il s'anime : on insiste
        if i % 6 == 0 {
            send(&[key(VK_ESCAPE, KEYBD_EVENT_FLAGS(0)), key(VK_ESCAPE, KEYEVENTF_KEYUP)]);
            tries += 1;
        }
    }
    if tries > 0 && opening {
        if let Some(win) = app.get_webview_window("island") {
            let _ = win.set_focus();
        }
    }
}

fn is_start_menu(h: HWND) -> bool {
    unsafe {
        let mut pid = 0;
        GetWindowThreadProcessId(h, Some(&mut pid));
        let Ok(p) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) else { return false };
        let mut buf = [0u16; 260];
        let mut n = buf.len() as u32;
        let ok = QueryFullProcessImageNameW(p, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &mut n).is_ok();
        let _ = CloseHandle(p);
        let path = String::from_utf16_lossy(&buf[..n as usize]).to_ascii_lowercase();
        ok && (path.ends_with("\\startmenuexperiencehost.exe") || path.ends_with("\\searchhost.exe"))
    }
}

// ------------------------------------------------------------- remappage

/// Entrees du « Scancode Map » : (code d'origine << 16) | nouveau code
fn read_map() -> Vec<u32> {
    unsafe {
        let mut size = 0u32;
        if RegGetValueW(HKEY_LOCAL_MACHINE, LAYOUT, MAP, RRF_RT_REG_BINARY, None, None, Some(&mut size)).is_err() {
            return Vec::new();
        }
        let mut buf = vec![0u8; size as usize];
        let data = Some(buf.as_mut_ptr() as _);
        if RegGetValueW(HKEY_LOCAL_MACHINE, LAYOUT, MAP, RRF_RT_REG_BINARY, None, data, Some(&mut size)).is_err()
            || buf.len() < 12
        {
            return Vec::new();
        }
        // 8 octets d'en-tete, le nombre d'entrees (+1), les entrees, un zero final
        let count = u32::from_le_bytes([buf[8], buf[9], buf[10], buf[11]]) as usize;
        buf[12..]
            .chunks_exact(4)
            .take(count.saturating_sub(1))
            .map(|c| u32::from_le_bytes([c[0], c[1], c[2], c[3]]))
            .filter(|&e| e != 0)
            .collect()
    }
}

fn is_win_entry(e: u32) -> bool {
    matches!(e >> 16, LWIN_SC | RWIN_SC)
}

/// Le remappage est enregistre (actif apres redemarrage)
pub fn remap_configured() -> bool {
    read_map().iter().any(|&e| is_win_entry(e) && e & 0xFFFF == F24_SC)
}

/// Ecrit le remappage en gardant les autres (SharpKeys...). Droits admin requis.
fn write_map(on: bool) -> bool {
    let mut entries: Vec<u32> = read_map().into_iter().filter(|&e| !is_win_entry(e)).collect();
    if on {
        entries.extend([LWIN_SC << 16 | F24_SC, RWIN_SC << 16 | F24_SC]);
    }
    unsafe {
        if entries.is_empty() {
            let r = RegDeleteKeyValueW(HKEY_LOCAL_MACHINE, LAYOUT, MAP);
            return r.is_ok() || r == ERROR_FILE_NOT_FOUND;
        }
        let mut data = vec![0u8; 8];
        data.extend((entries.len() as u32 + 1).to_le_bytes());
        for e in &entries {
            data.extend(e.to_le_bytes());
        }
        data.extend(0u32.to_le_bytes());
        RegSetKeyValueW(HKEY_LOCAL_MACHINE, LAYOUT, MAP, REG_BINARY.0, Some(data.as_ptr() as _), data.len() as u32)
            .is_ok()
    }
}

/// `ilot.exe --winkey-remap on|off`, lance avec les droits administrateur
pub fn remap_cli(on: bool) -> i32 {
    if write_map(on) { 0 } else { 1 }
}

/// Relance l'ilot en administrateur (invite UAC) pour ecrire le remappage
fn run_elevated(on: bool) -> bool {
    let Ok(exe) = std::env::current_exe() else { return false };
    let exe: Vec<u16> = exe.as_os_str().encode_wide().chain([0]).collect();
    let args: Vec<u16> = format!("--winkey-remap {}", if on { "on" } else { "off" })
        .encode_utf16()
        .chain([0])
        .collect();
    let mut info = SHELLEXECUTEINFOW {
        cbSize: std::mem::size_of::<SHELLEXECUTEINFOW>() as u32,
        fMask: SEE_MASK_NOCLOSEPROCESS,
        hwnd: island_hwnd(),
        lpVerb: w!("runas"),
        lpFile: PCWSTR(exe.as_ptr()),
        lpParameters: PCWSTR(args.as_ptr()),
        nShow: SW_HIDE.0,
        ..Default::default()
    };
    unsafe {
        // invite refusee : echec
        if ShellExecuteExW(&mut info).is_err() || info.hProcess.is_invalid() {
            return false;
        }
        WaitForSingleObject(info.hProcess, INFINITE);
        let mut code = 1u32;
        let _ = GetExitCodeProcess(info.hProcess, &mut code);
        let _ = CloseHandle(info.hProcess);
        code == 0
    }
}

/// Heure de demarrage de Windows (secondes), pour savoir si un changement
/// attend un redemarrage
fn boot_secs() -> u64 {
    let now = SystemTime::now().duration_since(UNIX_EPOCH).unwrap_or_default().as_secs();
    now.saturating_sub(unsafe { GetTickCount64() } / 1000)
}

/// Etat du remappage au demarrage de Windows pendant lequel il a change
#[derive(Clone, Copy, Serialize, Deserialize)]
pub struct BootRemap {
    boot: u64,
    before: bool,
}

/// Le remappage enregistre differe de celui charge au demarrage de Windows
fn pending(app: &AppHandle) -> bool {
    let rec = app.state::<crate::settings::Settings>().0.lock().unwrap().win_key_boot;
    rec.is_some_and(|r| r.boot.abs_diff(boot_secs()) < 120 && r.before != remap_configured())
}

#[derive(Serialize)]
pub struct Status {
    remap: bool,
    pending: bool,
}

pub fn winkey_status(app: AppHandle) -> Status {
    Status { remap: remap_configured(), pending: pending(&app) }
}

/// Installe ou retire le remappage (invite UAC). Faux si refuse ou en echec.
pub fn winkey_remap(app: AppHandle, on: bool) -> bool {
    let before = remap_configured();
    if before != on {
        if !run_elevated(on) || remap_configured() != on {
            return false;
        }
        let boot = boot_secs();
        crate::settings::update(&app, |c| {
            // on garde l'etat d'origine si plusieurs changements pendant ce demarrage
            if !c.win_key_boot.is_some_and(|r| r.boot.abs_diff(boot) < 120) {
                c.win_key_boot = Some(BootRemap { boot, before });
            }
        });
    }
    true
}
