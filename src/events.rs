//! Evenements Windows (WinEvent) qui remplacent des sondages rapides : la
//! liste des fenetres de la barre n'est relue que quand une fenetre apparait,
//! disparait, change de titre ou de bureau, ou quand le premier plan change.
//!
//! Le curseur, lui, reste sonde (`track_cursor`) : un hook souris bas niveau
//! serait appele a chaque deplacement de la souris de tout le systeme (jusqu'a
//! 1000 fois par seconde avec une souris de jeu) et ajouterait de la latence
//! a la souris dans les jeux. Le sondage ne coute plus que deux appels
//! systeme toutes les 25 ms.

use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Condvar, Mutex};
use std::time::Duration;

use windows::core::{w, PCWSTR};
use windows::Win32::Foundation::{CloseHandle, HANDLE, HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::System::DataExchange::AddClipboardFormatListener;
use windows::Win32::System::Registry::{
    RegCloseKey, RegNotifyChangeKeyValue, RegOpenKeyExW, HKEY, HKEY_CURRENT_USER, KEY_NOTIFY, REG_NOTIFY_CHANGE_LAST_SET,
    REG_NOTIFY_CHANGE_NAME,
};
use windows::Win32::System::Threading::{CreateEventW, WaitForSingleObject};
use windows::Win32::UI::Accessibility::{SetWinEventHook, HWINEVENTHOOK};
use windows::Win32::UI::WindowsAndMessaging::{
    DispatchMessageW, GetMessageW, TranslateMessage, CHILDID_SELF, EVENT_OBJECT_CLOAKED, EVENT_OBJECT_CREATE,
    EVENT_OBJECT_HIDE, EVENT_OBJECT_NAMECHANGE, EVENT_OBJECT_UNCLOAKED, EVENT_SYSTEM_FOREGROUND,
    EVENT_SYSTEM_MINIMIZEEND, EVENT_SYSTEM_MINIMIZESTART, MSG, OBJID_WINDOW, WINEVENT_OUTOFCONTEXT,
    CreateWindowExW, DefWindowProcW, RegisterClassW, HWND_MESSAGE, WINDOW_EX_STYLE, WINDOW_STYLE, WM_CLIPBOARDUPDATE,
    WNDCLASSW,
};

/// Compteur d'evenements qu'un thread peut attendre.
pub struct Wake {
    seq: Mutex<u64>,
    cv: Condvar,
}

impl Wake {
    pub const fn new() -> Self {
        Wake { seq: Mutex::new(0), cv: Condvar::new() }
    }

    pub fn notify(&self) {
        *self.seq.lock().unwrap() += 1;
        self.cv.notify_all();
    }

    /// Attend un evenement posterieur a `seen`, au plus `timeout` ; renvoie
    /// le nouveau compteur.
    pub fn wait(&self, seen: u64, timeout: Duration) -> u64 {
        let g = self.seq.lock().unwrap();
        let (g, _) = self.cv.wait_timeout_while(g, timeout, |s| *s == seen).unwrap();
        *g
    }

    pub fn seq(&self) -> u64 {
        *self.seq.lock().unwrap()
    }
}

/// Fenetres creees, detruites, montrees, masquees, renommees, changees de
/// bureau virtuel, reduites ; premier plan
pub static WINDOWS: Wake = Wake::new();

unsafe extern "system" fn on_event(
    _hook: HWINEVENTHOOK,
    event: u32,
    hwnd: HWND,
    object: i32,
    child: i32,
    _thread: u32,
    _time: u32,
) {
    // la fenetre elle-meme, pas un de ses elements (curseur texte, barre de defilement...)
    if object == OBJID_WINDOW.0 && child == CHILDID_SELF as i32 {
        if event == EVENT_SYSTEM_FOREGROUND {
            crate::note_foreground(hwnd);
        }
        WINDOWS.notify();
    }
}

/// Installe les hooks sur un thread qui traite leurs messages.
pub fn start() {
    std::thread::spawn(|| unsafe {
        for (lo, hi) in [
            (EVENT_SYSTEM_FOREGROUND, EVENT_SYSTEM_FOREGROUND),
            (EVENT_SYSTEM_MINIMIZESTART, EVENT_SYSTEM_MINIMIZEEND),
            // CREATE, DESTROY, SHOW, HIDE
            (EVENT_OBJECT_CREATE, EVENT_OBJECT_HIDE),
            (EVENT_OBJECT_NAMECHANGE, EVENT_OBJECT_NAMECHANGE),
            (EVENT_OBJECT_CLOAKED, EVENT_OBJECT_UNCLOAKED),
        ] {
            let _ = SetWinEventHook(lo, hi, None, Some(on_event), 0, 0, WINEVENT_OUTOFCONTEXT);
        }
        // un hook « hors contexte » n'est appele que si son thread traite ses messages
        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).as_bool() {
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    });
}

// --------------------------------------------------------- presse-papiers

/// Presse-papiers modifie (WM_CLIPBOARDUPDATE)
pub static CLIPBOARD: Wake = Wake::new();
/// La fenetre d'ecoute du presse-papiers est en place (sinon : sondage)
pub static CLIPBOARD_EVENTS: AtomicBool = AtomicBool::new(false);

/// Fenetre de messages qui recoit les changements du presse-papiers.
pub fn watch_clipboard() {
    std::thread::spawn(|| unsafe {
        unsafe extern "system" fn proc(h: HWND, m: u32, w: WPARAM, l: LPARAM) -> LRESULT {
            if m == WM_CLIPBOARDUPDATE {
                CLIPBOARD.notify();
                return LRESULT(0);
            }
            DefWindowProcW(h, m, w, l)
        }
        let cls = w!("IlotClipboard");
        let wc = WNDCLASSW { lpfnWndProc: Some(proc), lpszClassName: cls, ..Default::default() };
        RegisterClassW(&wc);
        let Ok(hwnd) = CreateWindowExW(WINDOW_EX_STYLE(0), cls, w!(""), WINDOW_STYLE(0), 0, 0, 0, 0, Some(HWND_MESSAGE), None, None, None)
        else {
            return;
        };
        if AddClipboardFormatListener(hwnd).is_err() {
            return;
        }
        CLIPBOARD_EVENTS.store(true, Ordering::Relaxed);
        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).as_bool() {
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
        CLIPBOARD_EVENTS.store(false, Ordering::Relaxed);
    });
}

// ---------------------------------------------------------------- registre

/// Cle du registre (HKCU) surveillee : `wait` rend la main des que Windows y
/// ecrit (valeurs, sous-cles avec `subtree`), ou au bout du delai.
pub struct RegWatch {
    key: HKEY,
    event: HANDLE,
    subtree: bool,
    armed: bool,
}

impl RegWatch {
    pub fn open(path: PCWSTR, subtree: bool) -> Option<RegWatch> {
        unsafe {
            let mut key = HKEY::default();
            RegOpenKeyExW(HKEY_CURRENT_USER, path, None, KEY_NOTIFY, &mut key).ok().ok()?;
            let Ok(event) = CreateEventW(None, false, false, None) else {
                let _ = RegCloseKey(key);
                return None;
            };
            Some(RegWatch { key, event, subtree, armed: false })
        }
    }

    /// A appeler avant de relire la cle : un changement pendant la lecture
    /// reveille quand meme le `wait` suivant (la notification ne sert qu'une fois).
    pub fn arm(&mut self) {
        let filter = REG_NOTIFY_CHANGE_NAME | REG_NOTIFY_CHANGE_LAST_SET;
        self.armed = unsafe { RegNotifyChangeKeyValue(self.key, self.subtree, filter, Some(self.event), true) }.is_ok();
    }

    /// Attend un changement, au plus `timeout` (2 s si la surveillance a echoue).
    pub fn wait(&self, timeout: Duration) {
        if self.armed {
            unsafe { WaitForSingleObject(self.event, timeout.as_millis().min(u32::MAX as u128 - 1) as u32) };
        } else {
            std::thread::sleep(timeout.min(Duration::from_secs(2)));
        }
    }
}

impl Drop for RegWatch {
    fn drop(&mut self) {
        unsafe {
            let _ = RegCloseKey(self.key);
            let _ = CloseHandle(self.event);
        }
    }
}
