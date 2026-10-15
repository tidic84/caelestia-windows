//! Onglet PC : mode d'alimentation de Windows 11 (Economie / Equilibre /
//! Performances) et etat des logiciels constructeur (MSI, ASUS, Logitech).

use sysinfo::{ProcessesToUpdate, System};
use windows::core::{s, w, GUID};
use windows::Win32::System::LibraryLoader::{GetProcAddress, LoadLibraryW};

/// Modes de Parametres > Systeme > Alimentation (« overlays » du mode Equilibre).
const MODES: &[(&str, GUID)] = &[
    ("eco", GUID::from_u128(0x961cc777_2547_4f9d_8174_7d86181b8a7a)),
    ("balanced", GUID::zeroed()),
    ("perf", GUID::from_u128(0xded574b5_45a0_4f42_8737_46345c09c238)),
];

type GetOverlay = unsafe extern "system" fn(*mut GUID) -> u32;
type SetOverlay = unsafe extern "system" fn(*const GUID) -> u32;

/// Fonctions non documentees de powrprof.dll (celles qu'utilise Parametres).
fn powrprof(name: windows::core::PCSTR) -> Option<unsafe extern "system" fn() -> isize> {
    unsafe {
        let lib = LoadLibraryW(w!("powrprof.dll")).ok()?;
        GetProcAddress(lib, name)
    }
}

#[tauri::command(async)]
pub fn power_get() -> String {
    let Some(f) = powrprof(s!("PowerGetEffectiveOverlayScheme")) else { return String::new() };
    let f: GetOverlay = unsafe { std::mem::transmute(f) };
    let mut g = GUID::zeroed();
    if unsafe { f(&mut g) } != 0 {
        return String::new();
    }
    MODES.iter().find(|(_, id)| *id == g).map(|(n, _)| n.to_string()).unwrap_or_default()
}

#[tauri::command(async)]
pub fn power_set(mode: String) -> bool {
    let Some((_, g)) = MODES.iter().find(|(n, _)| *n == mode) else { return false };
    let Some(f) = powrprof(s!("PowerSetActiveOverlayScheme")) else { return false };
    let f: SetOverlay = unsafe { std::mem::transmute(f) };
    unsafe { f(g) == 0 }
}

/// Pour chaque nom d'executable (sans .exe), vrai s'il tourne.
#[tauri::command(async)]
pub fn procs_running(names: Vec<String>) -> Vec<bool> {
    let mut sys = System::new();
    sys.refresh_processes(ProcessesToUpdate::All, true);
    let running: Vec<String> = sys
        .processes()
        .values()
        .map(|p| p.name().to_string_lossy().to_lowercase().trim_end_matches(".exe").to_string())
        .collect();
    names.iter().map(|n| running.iter().any(|r| r == &n.to_lowercase())).collect()
}
