//! Evenements Windows (WinEvent) qui remplacent des sondages rapides : la
//! liste des fenetres de la barre n'est relue que quand une fenetre apparait,
//! disparait, change de titre ou de bureau, ou quand le premier plan change.
//!
//! Le curseur, lui, reste sonde (`track_cursor`) : un hook souris bas niveau
//! serait appele a chaque deplacement de la souris de tout le systeme (jusqu'a
//! 1000 fois par seconde avec une souris de jeu) et ajouterait de la latence
//! a la souris dans les jeux. Le sondage ne coute plus que deux appels
//! systeme toutes les 25 ms.

use std::sync::{Condvar, Mutex};
use std::time::Duration;

use windows::Win32::Foundation::HWND;
use windows::Win32::UI::Accessibility::{SetWinEventHook, HWINEVENTHOOK};
use windows::Win32::UI::WindowsAndMessaging::{
    DispatchMessageW, GetMessageW, TranslateMessage, CHILDID_SELF, EVENT_OBJECT_CLOAKED, EVENT_OBJECT_CREATE,
    EVENT_OBJECT_HIDE, EVENT_OBJECT_NAMECHANGE, EVENT_OBJECT_UNCLOAKED, EVENT_SYSTEM_FOREGROUND,
    EVENT_SYSTEM_MINIMIZEEND, EVENT_SYSTEM_MINIMIZESTART, MSG, OBJID_WINDOW, WINEVENT_OUTOFCONTEXT,
};

/// Compteur d'evenements qu'un thread peut attendre.
pub struct Wake {
    seq: Mutex<u64>,
    cv: Condvar,
}

impl Wake {
    const fn new() -> Self {
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
