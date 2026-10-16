//! Voyant camera / micro : Windows note dans le registre quelle appli utilise
//! la webcam ou le micro (ConsentStore, comme l'icone de la barre des taches).
//! Une appli s'en sert en ce moment si LastUsedTimeStop vaut 0. Releve toutes
//! les 2 s, envoye a l'interface (`privacy`) a chaque changement.

use serde::Serialize;
use crate::host::AppHandle;
use windows::core::{HSTRING, PCWSTR, PWSTR};
use windows::Win32::System::Registry::{
    RegCloseKey, RegEnumKeyExW, RegOpenKeyExW, RegQueryValueExW, HKEY, HKEY_CURRENT_USER, KEY_READ,
};

const BASE: &str = r"Software\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore";

#[derive(Serialize, Clone, PartialEq, Default)]
pub struct Privacy {
    cam: Vec<String>,
    mic: Vec<String>,
}

fn open(path: &str) -> Option<HKEY> {
    let mut h = HKEY::default();
    let p = HSTRING::from(path);
    unsafe { RegOpenKeyExW(HKEY_CURRENT_USER, PCWSTR(p.as_ptr()), None, KEY_READ, &mut h) }.ok().ok()?;
    Some(h)
}

fn subkeys(h: HKEY) -> Vec<String> {
    let mut out = Vec::new();
    for i in 0.. {
        let mut buf = [0u16; 512];
        let mut len = buf.len() as u32;
        let r = unsafe { RegEnumKeyExW(h, i, Some(PWSTR(buf.as_mut_ptr())), &mut len, None, None, None, None) };
        if r.is_err() {
            break;
        }
        out.push(String::from_utf16_lossy(&buf[..len as usize]));
    }
    out
}

fn qword(h: HKEY, name: &str) -> Option<u64> {
    let n = HSTRING::from(name);
    let mut v = 0u64;
    let mut size = 8u32;
    unsafe { RegQueryValueExW(h, PCWSTR(n.as_ptr()), None, None, Some(&mut v as *mut u64 as *mut u8), Some(&mut size)) }
        .ok()
        .ok()?;
    Some(v)
}

/// En cours d'utilisation : demarre et pas encore arrete.
fn in_use(path: &str) -> bool {
    let Some(h) = open(path) else { return false };
    let r = qword(h, "LastUsedTimeStart").unwrap_or(0) != 0 && qword(h, "LastUsedTimeStop") == Some(0);
    unsafe {
        let _ = RegCloseKey(h);
    }
    r
}

/// « C:#Program Files#Discord#Discord.exe » -> « Discord » ;
/// « Microsoft.WindowsCamera_8wekyb3d8bbwe » -> « WindowsCamera ».
fn app_name(key: &str, packaged: bool) -> String {
    if packaged {
        let fam = key.split('_').next().unwrap_or(key);
        fam.rsplit('.').next().unwrap_or(fam).to_string()
    } else {
        let file = key.rsplit('#').next().unwrap_or(key);
        file.strip_suffix(".exe").or_else(|| file.strip_suffix(".EXE")).unwrap_or(file).to_string()
    }
}

fn users(kind: &str) -> Vec<String> {
    let root = format!(r"{BASE}\{kind}");
    let mut out = Vec::new();
    let Some(h) = open(&root) else { return out };
    for k in subkeys(h) {
        if k == "NonPackaged" {
            let np = format!(r"{root}\NonPackaged");
            if let Some(h2) = open(&np) {
                for k2 in subkeys(h2) {
                    if in_use(&format!(r"{np}\{k2}")) {
                        out.push(app_name(&k2, false));
                    }
                }
                unsafe {
                    let _ = RegCloseKey(h2);
                }
            }
        } else if in_use(&format!(r"{root}\{k}")) {
            out.push(app_name(&k, true));
        }
    }
    unsafe {
        let _ = RegCloseKey(h);
    }
    out.sort();
    out.dedup();
    out
}

pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        let mut last = Privacy::default();
        loop {
            let now = Privacy { cam: users("webcam"), mic: users("microphone") };
            if now != last {
                let _ = app.emit("privacy", &now);
                last = now;
            }
            std::thread::sleep(std::time::Duration::from_secs(2));
        }
    });
}
