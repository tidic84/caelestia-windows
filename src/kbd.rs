//! Disposition du clavier (AZERTY / QWERTY...) : liste, disposition en cours,
//! changement. La barre des taches Windows et son indicateur « FRA » sont
//! masques par l'ilot : la barre de l'ilot affiche une puce, et l'ilot
//! annonce chaque changement (activite `kbd`).
//!
//! La disposition est celle de la fenetre au premier plan. Un clic sur la
//! barre met l'ilot au premier plan : on garde donc la derniere fenetre au
//! premier plan qui n'est pas a nous (`target`), et c'est elle qui change.

use std::sync::atomic::{AtomicIsize, Ordering};

use serde::Serialize;
use crate::host::AppHandle;
use windows::core::PCWSTR;
use windows::Win32::Foundation::{HWND, LPARAM, WPARAM};
use windows::Win32::Globalization::{GetLocaleInfoEx, LCIDToLocaleName, LOCALE_SLOCALIZEDDISPLAYNAME};
use windows::Win32::UI::Input::KeyboardAndMouse::{
    GetKeyboardLayout, GetKeyboardLayoutList, MapVirtualKeyExW, HKL, MAPVK_VSC_TO_VK,
};
use windows::Win32::UI::WindowsAndMessaging::{
    GetForegroundWindow, GetWindowThreadProcessId, IsWindow, PostMessageW, WM_INPUTLANGCHANGEREQUEST,
};

#[derive(Serialize, Clone, PartialEq)]
pub struct Layout {
    /// HKL en hexadecimal (rendu a `kbd_set`)
    pub id: String,
    /// etiquette de la barre : FR, EN... ou AZ / QW si deux dispositions
    /// ont la meme langue
    pub short: String,
    /// AZERTY, QWERTY, QWERTZ, ou vide (autre disposition)
    pub name: String,
    /// langue, dans la langue de Windows : « Français (France) »
    pub lang: String,
}

#[derive(Serialize, Clone, PartialEq, Default)]
pub struct Kbd {
    pub layouts: Vec<Layout>,
    pub cur: String,
}

/// derniere fenetre au premier plan qui n'est pas a l'ilot
static TARGET: AtomicIsize = AtomicIsize::new(0);

fn target() -> Option<HWND> {
    unsafe {
        let fg = GetForegroundWindow();
        if !fg.is_invalid() {
            let mut pid = 0u32;
            GetWindowThreadProcessId(fg, Some(&mut pid));
            if pid != 0 && pid != std::process::id() {
                TARGET.store(fg.0 as isize, Ordering::Relaxed);
                return Some(fg);
            }
        }
        let h = HWND(TARGET.load(Ordering::Relaxed) as _);
        (!h.is_invalid() && IsWindow(Some(h)).as_bool()).then_some(h)
    }
}

fn current(t: Option<HWND>) -> HKL {
    unsafe {
        let tid = t.map(|h| GetWindowThreadProcessId(h, None)).unwrap_or(0);
        GetKeyboardLayout(tid)
    }
}

fn list() -> Vec<HKL> {
    unsafe {
        let n = GetKeyboardLayoutList(None);
        if n <= 0 {
            return Vec::new();
        }
        let mut v = vec![HKL::default(); n as usize];
        let got = GetKeyboardLayoutList(Some(&mut v));
        v.truncate(got.max(0) as usize);
        v
    }
}

fn hex(h: HKL) -> String {
    format!("{:x}", h.0 as usize)
}

/// AZERTY / QWERTY / QWERTZ d'apres les touches de la rangee du haut
fn kind(h: HKL) -> &'static str {
    let vk = |scan: u32| unsafe { MapVirtualKeyExW(scan, MAPVK_VSC_TO_VK, Some(h)) };
    // codes de touche physiques : 0x10 = A en AZERTY, 0x15 = Y en QWERTY
    match (vk(0x10), vk(0x15)) {
        (0x41, _) => "AZERTY",
        (0x51, 0x5A) => "QWERTZ",
        (0x51, 0x59) => "QWERTY",
        _ => "",
    }
}

/// (« fr », « Français (France) ») pour la langue du HKL
fn locale(h: HKL) -> (String, String) {
    let lcid = (h.0 as usize & 0xFFFF) as u32;
    let mut name = [0u16; 85];
    let n = unsafe { LCIDToLocaleName(lcid, Some(&mut name), 0) };
    if n <= 1 {
        return (String::new(), String::new());
    }
    let tag = String::from_utf16_lossy(&name[..n as usize - 1]);
    let mut disp = [0u16; 128];
    let m = unsafe { GetLocaleInfoEx(PCWSTR(name.as_ptr()), LOCALE_SLOCALIZEDDISPLAYNAME, Some(&mut disp)) };
    let disp = if m > 1 { String::from_utf16_lossy(&disp[..m as usize - 1]) } else { tag.clone() };
    (tag.split('-').next().unwrap_or("").to_string(), disp)
}

fn build(hkls: &[HKL], cur: HKL) -> Kbd {
    let raw: Vec<(HKL, String, &str, String)> = hkls
        .iter()
        .map(|&h| {
            let (lang, disp) = locale(h);
            (h, lang, kind(h), disp)
        })
        .collect();
    let layouts = raw
        .iter()
        .enumerate()
        .map(|(i, (h, lang, kind, disp))| {
            let twin = raw.iter().filter(|r| &r.1 == lang).count() > 1;
            let short = if twin && !kind.is_empty() {
                // AZERTY -> AZ, QWERTY -> QW, QWERTZ -> QZ
                if *kind == "QWERTZ" { "QZ".to_string() } else { kind[..2].to_string() }
            } else if twin {
                format!("{}{}", lang.to_uppercase(), i + 1)
            } else if lang.is_empty() {
                "?".to_string()
            } else {
                lang.to_uppercase()
            };
            Layout { id: hex(*h), short, name: kind.to_string(), lang: disp.clone() }
        })
        .collect();
    Kbd { layouts, cur: hex(cur) }
}

pub fn kbd_get() -> Kbd {
    build(&list(), current(target()))
}

/// Change la disposition de la fenetre au premier plan (hors ilot).
/// Faux si la disposition n'est pas installee ou si Windows refuse le
/// message (fenetre lancee en administrateur).
pub fn kbd_set(id: String) -> bool {
    let Some(h) = list().into_iter().find(|h| hex(*h) == id) else {
        return false;
    };
    let Some(t) = target() else {
        return false;
    };
    unsafe { PostMessageW(Some(t), WM_INPUTLANGCHANGEREQUEST, WPARAM(0), LPARAM(h.0 as isize)).is_ok() }
}

/// Emet `kbd` quand la liste ou la disposition change, et l'activite `kbd`
/// quand la disposition change dans la meme fenetre (un changement de
/// fenetre avec « une disposition par appli » n'est pas annonce).
pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        let mut last_hkls: Vec<HKL> = Vec::new();
        let mut last_cur = HKL::default();
        let mut last_t: Option<HWND> = None;
        let mut first = true;
        loop {
            let hkls = list();
            let t = target();
            let cur = current(t);
            if first || hkls != last_hkls || cur != last_cur {
                let k = build(&hkls, cur);
                let _ = app.emit("kbd", &k);
                if !first && cur != last_cur && t == last_t && hkls.len() > 1 {
                    if let Some(l) = k.layouts.iter().find(|l| l.id == k.cur) {
                        let _ = app.emit("activity", serde_json::json!({
                            "kind": "kbd", "short": l.short, "name": l.name, "lang": l.lang,
                        }));
                    }
                }
                first = false;
            }
            let many = hkls.len() > 1;
            last_hkls = hkls;
            last_cur = cur;
            last_t = t;
            // une seule disposition : la liste est relue de temps en temps
            std::thread::sleep(std::time::Duration::from_millis(if many { 300 } else { 3000 }));
        }
    });
}
