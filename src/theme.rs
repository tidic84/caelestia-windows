//! Lien avec le theme de Windows : lecture / ecriture du mode clair ou
//! sombre et de la couleur d'accent (barre des taches, menu Demarrer...).

use std::time::Duration;

use crate::host::{AppHandle};
use windows::core::{w, PCWSTR};
use windows::Win32::Foundation::{LPARAM, WPARAM};
use windows::Win32::System::Registry::{
    RegGetValueW, RegSetKeyValueW, HKEY_CURRENT_USER, REG_BINARY, REG_DWORD, RRF_RT_REG_DWORD,
};
use windows::Win32::UI::WindowsAndMessaging::{
    SendMessageTimeoutW, HWND_BROADCAST, SMTO_ABORTIFHUNG, WM_SETTINGCHANGE,
};

const PERSONALIZE: PCWSTR = w!(r"Software\Microsoft\Windows\CurrentVersion\Themes\Personalize");
const ACCENT: PCWSTR = w!(r"Software\Microsoft\Windows\CurrentVersion\Explorer\Accent");
const DWM: PCWSTR = w!(r"Software\Microsoft\Windows\DWM");
const DESKTOP: PCWSTR = w!(r"Control Panel\Desktop");

fn get_dword(key: PCWSTR, name: PCWSTR) -> Option<u32> {
    let mut v = 0u32;
    let mut len = 4u32;
    unsafe {
        RegGetValueW(HKEY_CURRENT_USER, key, name, RRF_RT_REG_DWORD, None, Some(&mut v as *mut _ as _), Some(&mut len))
            .ok()
            .ok()?;
    }
    Some(v)
}

fn set_dword(key: PCWSTR, name: PCWSTR, v: u32) {
    unsafe {
        let _ = RegSetKeyValueW(HKEY_CURRENT_USER, key, name, REG_DWORD.0, Some(&v as *const _ as _), 4);
    }
}

/// Vrai si les applis Windows sont en mode clair.
pub fn windows_light() -> bool {
    get_dword(PERSONALIZE, w!("AppsUseLightTheme")).unwrap_or(0) == 1
}

pub fn win_theme_get() -> bool {
    windows_light()
}

fn broadcast() {
    let msg: Vec<u16> = "ImmersiveColorSet".encode_utf16().chain([0]).collect();
    unsafe {
        let _ = SendMessageTimeoutW(
            HWND_BROADCAST,
            WM_SETTINGCHANGE,
            WPARAM(0),
            LPARAM(msg.as_ptr() as isize),
            SMTO_ABORTIFHUNG,
            300,
            None,
        );
    }
}

/// `0xRRGGBB` -> DWORD ABGR opaque, l'ordre qu'attend le registre.
fn abgr(rgb: u32) -> u32 {
    let (r, g, b) = ((rgb >> 16) & 0xff, (rgb >> 8) & 0xff, rgb & 0xff);
    0xff00_0000 | (b << 16) | (g << 8) | r
}

/// Applique a Windows le mode clair / sombre et / ou l'accent. `palette`
/// contient 8 teintes `0xRRGGBB`, de la plus claire a la plus foncee ; la
/// 4e est l'accent lui-meme (meme disposition que le registre).
pub fn win_theme_apply(light: Option<bool>, palette: Option<Vec<u32>>) {
    if let Some(l) = light {
        if windows_light() != l {
            set_dword(PERSONALIZE, w!("AppsUseLightTheme"), l as u32);
            set_dword(PERSONALIZE, w!("SystemUsesLightTheme"), l as u32);
        }
    }
    if let Some(p) = palette.filter(|p| p.len() == 8) {
        let mut bytes = Vec::with_capacity(32);
        for c in &p {
            bytes.extend_from_slice(&[(c >> 16) as u8, (c >> 8) as u8, *c as u8, 0]);
        }
        unsafe {
            let _ = RegSetKeyValueW(
                HKEY_CURRENT_USER,
                ACCENT,
                w!("AccentPalette"),
                REG_BINARY.0,
                Some(bytes.as_ptr() as _),
                bytes.len() as u32,
            );
        }
        set_dword(ACCENT, w!("AccentColorMenu"), abgr(p[4]));
        set_dword(ACCENT, w!("StartColorMenu"), abgr(p[5]));
        set_dword(DWM, w!("AccentColor"), abgr(p[3]));
        set_dword(DWM, w!("ColorizationColor"), 0xc400_0000 | (p[3] & 0xff_ffff));
        set_dword(DWM, w!("ColorizationAfterglow"), 0xc400_0000 | (p[3] & 0xff_ffff));
        // sinon Windows reprend l'accent tire du fond d'ecran
        set_dword(DESKTOP, w!("AutoColorization"), 0);
    }
    broadcast();
}

/// Emet `win-theme` quand Windows passe en clair / sombre.
pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        let mut last = windows_light();
        loop {
            std::thread::sleep(Duration::from_secs(2));
            let now = windows_light();
            if now != last {
                last = now;
                let _ = app.emit("win-theme", now);
            }
        }
    });
}
