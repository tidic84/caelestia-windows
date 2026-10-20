//! Services Windows par processus : pid -> noms affiches des services actifs.
//! Sert a nommer les lignes « Hote de service » de l'onglet Taches.

use std::collections::HashMap;
use std::sync::{Mutex, MutexGuard};
use std::time::{Duration, Instant};

use windows::core::PCWSTR;
use windows::Win32::Foundation::ERROR_MORE_DATA;
use windows::Win32::System::Services::{
    CloseServiceHandle, EnumServicesStatusExW, OpenSCManagerW, ENUM_SERVICE_STATUS_PROCESSW, SC_ENUM_PROCESS_INFO,
    SC_HANDLE, SC_MANAGER_ENUMERATE_SERVICE, SERVICE_ACTIVE, SERVICE_WIN32,
};

/// Duree de vie du cache : la liste des services bouge peu.
const TTL: Duration = Duration::from_secs(5);

type Map = HashMap<u32, Vec<String>>;

static CACHE: Mutex<Option<(Instant, Map)>> = Mutex::new(None);

fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

/// pid -> noms affiches (DisplayName) des services en cours dans ce processus, tries.
/// Resultat mis en cache 5 s. Map vide en cas d'echec.
pub fn services_by_pid() -> Map {
    let mut c = lock(&CACHE);
    if let Some((t, m)) = c.as_ref() {
        if t.elapsed() < TTL {
            return m.clone();
        }
    }
    let m = query();
    *c = Some((Instant::now(), m.clone()));
    m
}

/// Ferme le handle du gestionnaire de services dans tous les cas.
struct Scm(SC_HANDLE);

impl Drop for Scm {
    fn drop(&mut self) {
        unsafe {
            let _ = CloseServiceHandle(self.0);
        }
    }
}

/// Lit une chaine UTF-16 terminee par 0, seulement si elle est entierement dans le tampon.
fn read_str(p: *const u16, base: *const u8, len: usize) -> Option<String> {
    if p.is_null() {
        return None;
    }
    let (start, end) = (base as usize, base as usize + len);
    let a = p as usize;
    if a < start || a >= end || !(a - start).is_multiple_of(2) {
        return None;
    }
    let max = (end - a) / 2;
    // SAFETY : [a, a + 2*max) est dans le tampon, aligne sur 2 octets
    let s = unsafe { std::slice::from_raw_parts(p, max) };
    let n = s.iter().position(|&c| c == 0)?;
    Some(String::from_utf16_lossy(&s[..n]))
}

/// Interroge le gestionnaire de services (sans cache).
fn query() -> Map {
    let mut out: Map = HashMap::new();
    let scm = match unsafe { OpenSCManagerW(PCWSTR::null(), PCWSTR::null(), SC_MANAGER_ENUMERATE_SERVICE) } {
        Ok(h) if !h.is_invalid() => Scm(h),
        _ => return out,
    };
    const ENTRY: usize = std::mem::size_of::<ENUM_SERVICE_STATUS_PROCESSW>();
    // tampon aligne sur 8 octets ; 64 Kio suffisent en general en un appel
    let mut buf: Vec<u64> = vec![0; 64 * 1024 / 8];
    let mut resume = 0u32;
    // garde-fou contre une boucle infinie
    for _ in 0..32 {
        let bytes = buf.len() * 8;
        let mut needed = 0u32;
        let mut count = 0u32;
        // SAFETY : vue en octets du Vec<u64>, meme longueur en octets
        let slice = unsafe { std::slice::from_raw_parts_mut(buf.as_mut_ptr() as *mut u8, bytes) };
        let r = unsafe {
            EnumServicesStatusExW(
                scm.0,
                SC_ENUM_PROCESS_INFO,
                SERVICE_WIN32,
                SERVICE_ACTIVE,
                Some(slice),
                &mut needed,
                &mut count,
                Some(&mut resume),
                PCWSTR::null(),
            )
        };
        let more = match &r {
            Ok(()) => false,
            Err(e) if e.code() == ERROR_MORE_DATA.to_hresult() => true,
            Err(_) => break,
        };
        let base = buf.as_ptr() as *const u8;
        let n = (count as usize).min(bytes / ENTRY);
        for i in 0..n {
            // SAFETY : i < bytes / ENTRY, tampon aligne sur 8
            let e = unsafe { &*(base as *const ENUM_SERVICE_STATUS_PROCESSW).add(i) };
            let pid = e.ServiceStatusProcess.dwProcessId;
            if pid == 0 {
                continue;
            }
            let name = read_str(e.lpDisplayName.0, base, bytes)
                .filter(|s| !s.is_empty())
                .or_else(|| read_str(e.lpServiceName.0, base, bytes));
            if let Some(name) = name {
                out.entry(pid).or_default().push(name);
            }
        }
        if !more {
            break;
        }
        // agrandit le tampon si une seule entree ne tenait pas
        if count == 0 {
            let want = (needed as usize).max(bytes * 2).min(16 * 1024 * 1024);
            if want <= bytes {
                break;
            }
            buf = vec![0; want.div_ceil(8)];
        }
    }
    for v in out.values_mut() {
        v.sort_by_key(|s| s.to_lowercase());
        v.dedup();
    }
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn svc_services_par_pid() {
        let t = Instant::now();
        let m = query();
        let dt = t.elapsed();
        let total: usize = m.values().map(|v| v.len()).sum();
        println!("svc : {} pid, {} services, {:?} (sans cache)", m.len(), total, dt);
        assert!(!m.is_empty(), "aucun service trouve");
        assert!(!m.contains_key(&0));
        assert!(m.values().all(|v| !v.is_empty() && v.iter().all(|s| !s.is_empty())));
        // au moins un hote partage plusieurs services
        assert!(m.values().any(|v| v.len() >= 2), "aucun pid avec plusieurs services");
        // un svchost porte au moins un service
        let mut sys = sysinfo_svchost_pids();
        sys.retain(|p| m.contains_key(p));
        assert!(!sys.is_empty(), "aucun svchost avec service");
        // le cache renvoie la meme chose, vite
        let a = services_by_pid();
        let t = Instant::now();
        let b = services_by_pid();
        println!("svc : appel en cache {:?}", t.elapsed());
        assert_eq!(a, b);
    }

    /// pid des svchost.exe, via Toolhelp (pas de dependance aux autres modules).
    fn sysinfo_svchost_pids() -> Vec<u32> {
        use windows::Win32::Foundation::CloseHandle;
        use windows::Win32::System::Diagnostics::ToolHelp::{
            CreateToolhelp32Snapshot, Process32FirstW, Process32NextW, PROCESSENTRY32W, TH32CS_SNAPPROCESS,
        };
        let mut v = Vec::new();
        unsafe {
            let Ok(snap) = CreateToolhelp32Snapshot(TH32CS_SNAPPROCESS, 0) else { return v };
            let mut e = PROCESSENTRY32W { dwSize: std::mem::size_of::<PROCESSENTRY32W>() as u32, ..Default::default() };
            let mut ok = Process32FirstW(snap, &mut e).is_ok();
            while ok {
                let n = e.szExeFile.iter().position(|&c| c == 0).unwrap_or(e.szExeFile.len());
                if String::from_utf16_lossy(&e.szExeFile[..n]).eq_ignore_ascii_case("svchost.exe") {
                    v.push(e.th32ProcessID);
                }
                ok = Process32NextW(snap, &mut e).is_ok();
            }
            let _ = CloseHandle(snap);
        }
        v
    }
}
