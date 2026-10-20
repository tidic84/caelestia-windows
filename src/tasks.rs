//! Onglet Taches : processus regroupes par programme, avec les memes chiffres
//! que l'onglet Processus du Gestionnaire des taches (CPU en temps processeur,
//! memoire privee, GPU, sections Applications / arriere-plan / Windows).
//!
//! Les chiffres par processus viennent d'un seul appel a
//! `NtQuerySystemInformation(SystemProcessInformation)`, comme le
//! Gestionnaire des taches : il couvre tous les processus, meme ceux qu'on ne
//! peut pas ouvrir sans droits admin (svchost, services tiers...).

use std::collections::{HashMap, HashSet};
use std::ffi::c_void;
use std::os::windows::process::CommandExt;
use std::path::PathBuf;
use std::process::Command;
use std::sync::{Mutex, MutexGuard};
use std::time::{Duration, Instant};

use serde::Serialize;
use sysinfo::Networks;
use crate::host::State;
use crate::procgroup::{self, created_ms};
use crate::svc;
use windows::core::{BOOL, HSTRING};
use windows::Win32::Foundation::{CloseHandle, ERROR_INVALID_PARAMETER, FILETIME, HANDLE, HWND, LPARAM, STILL_ACTIVE};
use windows::Win32::Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_CLOAKED};
use windows::Win32::NetworkManagement::IpHelper::{GetExtendedTcpTable, TCP_TABLE_OWNER_PID_ALL};
use windows::Win32::Networking::WinSock::{AF_INET, AF_INET6};
use windows::Win32::Storage::FileSystem::QueryDosDeviceW;
use windows::Win32::System::Threading::{
    GetExitCodeProcess, GetProcessInformation, GetProcessTimes, OpenProcess, ProcessPowerThrottling, TerminateProcess, PROCESS_POWER_THROTTLING_CURRENT_VERSION,
    PROCESS_POWER_THROTTLING_EXECUTION_SPEED, PROCESS_POWER_THROTTLING_STATE, PROCESS_QUERY_LIMITED_INFORMATION, PROCESS_TERMINATE,
};
use windows::Win32::UI::Shell::{IShellItem, SHCreateItemFromParsingName};
use windows::Win32::UI::WindowsAndMessaging::{
    EnumChildWindows, EnumWindows, GetClassNameW, GetWindow, GetWindowLongW, GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId,
    IsHungAppWindow, IsWindowVisible, GWL_EXSTYLE, GW_OWNER, WS_EX_TOOLWINDOW,
};

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// Processus vitaux de Windows : jamais de fin de tache depuis l'ilot.
pub(crate) const PROTECTED: &[&str] = &[
    "system", "registry", "smss", "csrss", "wininit", "winlogon", "services", "lsass",
    "svchost", "dwm", "fontdrvhost", "memory compression", "secure system", "lsaiso",
    "sihost", "ctfmon", "audiodg", "ilot",
];

#[derive(Serialize)]
pub struct Task {
    /// cle stable du groupe (voir `procgroup`) : tri, developpement, fin de tache
    key: String,
    /// nom de l'executable sans .exe (celui de la racine du groupe)
    name: String,
    /// nom affiche par le Gestionnaire des taches (description du fichier)
    label: String,
    /// « app » (fenetre ouverte), « bg » (arriere-plan) ou « win » (processus Windows)
    kind: &'static str,
    count: usize,
    /// % du processeur entier (0-100), en temps processeur comme Windows 11
    cpu: f32,
    /// memoire privee (jeu de travail prive), comme le Gestionnaire des taches
    mem: u64,
    /// lecture + ecriture, octets par seconde (toutes E/S, comme GetProcessIoCounters)
    disk: u64,
    /// % du moteur GPU le plus charge
    gpu: f32,
    /// connexions TCP etablies (le debit par processus demanderait ETW / admin)
    net: u32,
    icon: String,
    /// chemin de l'executable (« Ouvrir l'emplacement »), vide si inconnu
    path: String,
    protected: bool,
    /// "", "suspended", "hung" ou "eco" (voir `status_of`)
    status: &'static str,
    /// (pid, creation en ms) de tous les processus du groupe, racines d'abord
    members: Vec<(u32, u64)>,
    /// noms affiches des services, seulement pour un hote de service
    #[serde(skip_serializing_if = "Option::is_none")]
    services: Option<Vec<String>>,
    /// detail par processus, seulement pour les groupes developpes
    #[serde(skip_serializing_if = "Vec::is_empty")]
    procs: Vec<Sub>,
}

/// Un processus d'un groupe developpe (memes unites que `Task`).
#[derive(Serialize)]
pub struct Sub {
    pid: u32,
    /// heure de creation en ms (exacte en JavaScript), rendue a `task_kill`
    created: u64,
    /// processus principal : son parent n'est pas du groupe. Le terminer
    /// ferme en general tout le programme (les autres en dependent).
    main: bool,
    #[serde(skip)]
    ppid: u32,
    /// nom, nom affiche, icone et chemin propres au processus (une app peut
    /// contenir des enfants d'autres executables)
    name: String,
    label: String,
    icon: String,
    path: String,
    /// titre de sa fenetre principale, vide s'il n'en a pas
    title: String,
    /// exe vital (PROTECTED) : pas de fin de tache, meme dans une app
    protected: bool,
    cpu: f32,
    mem: u64,
    disk: u64,
    gpu: f32,
    net: u32,
    status: &'static str,
}

#[derive(Serialize)]
pub struct TasksReport {
    list: Vec<Task>,
    /// totaux de l'en-tete, calcules comme le Gestionnaire des taches
    cpu: f32,
    gpu: f32,
    /// % de temps d'activite du disque le plus occupe
    disk_active: f32,
    procs: usize,
    /// debit reseau total (cartes physiques), octets par seconde
    net_down: u64,
    net_up: u64,
}

#[derive(Serialize)]
pub struct KillReport {
    killed: usize,
    /// processus trouves mais refuses (droits admin, deja en train de quitter)
    denied: usize,
}

// ------------------------------------------------- NtQuerySystemInformation

#[link(name = "ntdll")]
extern "system" {
    fn NtQuerySystemInformation(class: u32, info: *mut c_void, len: u32, ret: *mut u32) -> i32;
}

const SYSTEM_PROCESS_INFORMATION: u32 = 5;
const SYSTEM_PROCESS_ID_INFORMATION: u32 = 88;
const STATUS_INFO_LENGTH_MISMATCH: i32 = 0xC000_0004_u32 as i32;

#[repr(C)]
struct UnicodeString {
    length: u16,
    maximum_length: u16,
    buffer: *mut u16,
}

/// SYSTEM_PROCESS_INFORMATION (winternl.h, champs documentes par ntdll).
#[repr(C)]
struct SpInfo {
    next_entry_offset: u32,
    number_of_threads: u32,
    working_set_private_size: i64,
    hard_fault_count: u32,
    number_of_threads_high_watermark: u32,
    cycle_time: u64,
    create_time: i64,
    user_time: i64,
    kernel_time: i64,
    image_name: UnicodeString,
    base_priority: i32,
    unique_process_id: usize,
    inherited_from_unique_process_id: usize,
    handle_count: u32,
    session_id: u32,
    unique_process_key: usize,
    peak_virtual_size: usize,
    virtual_size: usize,
    page_fault_count: u32,
    peak_working_set_size: usize,
    working_set_size: usize,
    quota_peak_paged_pool_usage: usize,
    quota_paged_pool_usage: usize,
    quota_peak_non_paged_pool_usage: usize,
    quota_non_paged_pool_usage: usize,
    pagefile_usage: usize,
    peak_pagefile_usage: usize,
    private_page_count: usize,
    read_operation_count: i64,
    write_operation_count: i64,
    other_operation_count: i64,
    read_transfer_count: i64,
    write_transfer_count: i64,
    other_transfer_count: i64,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(std::mem::size_of::<SpInfo>() == 256);

/// SYSTEM_THREAD_INFORMATION : `number_of_threads` entrees juste apres `SpInfo`.
#[repr(C)]
#[allow(dead_code)]
struct ThreadInfo {
    kernel_time: i64,
    user_time: i64,
    create_time: i64,
    wait_time: u32,
    start_address: usize,
    client_id: [usize; 2],
    priority: i32,
    base_priority: i32,
    context_switches: u32,
    thread_state: u32,
    wait_reason: u32,
}

#[cfg(target_pointer_width = "64")]
const _: () = assert!(
    std::mem::size_of::<ThreadInfo>() == 80
        && std::mem::offset_of!(ThreadInfo, thread_state) == 68
        && std::mem::offset_of!(ThreadInfo, wait_reason) == 72
);

/// KTHREAD_STATE Waiting et KWAIT_REASON Suspended (valent 5 toutes les deux).
const THREAD_WAITING: u32 = 5;
const WAIT_SUSPENDED: u32 = 5;

/// Un processus tel que vu par le noyau a l'instant du releve.
pub(crate) struct Proc {
    pub(crate) pid: u32,
    /// pid du parent a la creation (peut avoir ete reutilise depuis)
    pub(crate) ppid: u32,
    pub(crate) name: String,
    pub(crate) create: i64,
    /// temps processeur noyau + utilisateur, en unites de 100 ns
    pub(crate) cpu: i64,
    pub(crate) mem: u64,
    pub(crate) io: u64,
    /// au moins un thread, et tous en attente pour cause de suspension
    pub(crate) suspended: bool,
}

/// Releve de tous les processus. `buf` est garde d'un appel a l'autre
/// (quelques centaines de Ko) pour ne pas le reallouer a chaque tick.
pub(crate) fn snapshot(buf: &mut Vec<u64>) -> Option<Vec<Proc>> {
    if buf.is_empty() {
        buf.resize(64 * 1024, 0);
    }
    let mut ok = false;
    for _ in 0..4 {
        let bytes = (buf.len() * 8) as u32;
        let mut need = 0u32;
        let st = unsafe { NtQuerySystemInformation(SYSTEM_PROCESS_INFORMATION, buf.as_mut_ptr() as _, bytes, &mut need) };
        if st == STATUS_INFO_LENGTH_MISMATCH {
            // marge : des processus peuvent naitre entre deux appels
            buf.resize((need.max(bytes) as usize + 64 * 1024) / 8, 0);
            continue;
        }
        ok = st >= 0;
        break;
    }
    if !ok {
        return None;
    }
    let base = buf.as_ptr() as *const u8;
    let total = buf.len() * 8;
    let mut out = Vec::with_capacity(512);
    let mut off = 0usize;
    loop {
        if off + std::mem::size_of::<SpInfo>() > total {
            break;
        }
        // SAFETY : l'entree tient dans le tampon (verifie ci-dessus), ecrite par le noyau
        let e = unsafe { std::ptr::read_unaligned(base.add(off) as *const SpInfo) };
        let name = {
            let p = e.image_name.buffer as usize;
            let n = e.image_name.length as usize;
            // le nom pointe dans le tampon : on le verifie avant de le lire
            if p != 0 && n != 0 && p.is_multiple_of(2) && p >= base as usize && p + n <= base as usize + total {
                let s = unsafe { std::slice::from_raw_parts(p as *const u16, n / 2) };
                String::from_utf16_lossy(s)
            } else {
                String::new()
            }
        };
        // threads : bornes verifiees (tampon et entree suivante) avant lecture
        let suspended = {
            let n = e.number_of_threads as usize;
            let size = std::mem::size_of::<ThreadInfo>();
            let start = off + std::mem::size_of::<SpInfo>();
            let end = if e.next_entry_offset == 0 { total } else { (off + e.next_entry_offset as usize).min(total) };
            let fits = n.checked_mul(size).and_then(|b| start.checked_add(b)).is_some_and(|x| x <= end);
            n > 0
                && fits
                && (0..n).all(|i| {
                    // SAFETY : l'entree i tient dans [start, end), verifie par `fits`
                    let t = unsafe { std::ptr::read_unaligned(base.add(start + i * size) as *const ThreadInfo) };
                    t.thread_state == THREAD_WAITING && t.wait_reason == WAIT_SUSPENDED
                })
        };
        out.push(Proc {
            pid: e.unique_process_id as u32,
            ppid: e.inherited_from_unique_process_id as u32,
            name,
            create: e.create_time,
            cpu: e.kernel_time.saturating_add(e.user_time),
            mem: e.working_set_private_size.max(0) as u64,
            io: (e.read_transfer_count.max(0) as u64).saturating_add(e.write_transfer_count.max(0) as u64),
            suspended,
        });
        if e.next_entry_offset == 0 {
            break;
        }
        off += e.next_entry_offset as usize;
    }
    Some(out)
}

/// Chemin NT de l'image (« \Device\HarddiskVolume3\... »), sans ouvrir le
/// processus : marche aussi pour les services qu'on ne peut pas ouvrir.
fn nt_image_path(pid: u32) -> Option<String> {
    #[repr(C)]
    struct IdInfo {
        pid: usize,
        name: UnicodeString,
    }
    let mut buf = vec![0u16; 32768];
    let mut info = IdInfo {
        pid: pid as usize,
        name: UnicodeString { length: 0, maximum_length: (buf.len() * 2 - 2) as u16, buffer: buf.as_mut_ptr() },
    };
    let st = unsafe {
        NtQuerySystemInformation(SYSTEM_PROCESS_ID_INFORMATION, &mut info as *mut _ as _, std::mem::size_of::<IdInfo>() as u32, std::ptr::null_mut())
    };
    if st < 0 || info.name.length == 0 {
        return None;
    }
    let n = (info.name.length as usize / 2).min(buf.len());
    Some(String::from_utf16_lossy(&buf[..n]))
}

/// « \Device\HarddiskVolume3 » -> « C: », pour toutes les lettres montees.
fn dos_devices() -> Vec<(String, String)> {
    let mut out = Vec::new();
    for l in b'A'..=b'Z' {
        let drive = format!("{}:", l as char);
        let mut buf = [0u16; 512];
        let n = unsafe { QueryDosDeviceW(&HSTRING::from(drive.as_str()), Some(&mut buf)) } as usize;
        if n == 0 {
            continue;
        }
        // premiere chaine de la liste (terminee par un zero)
        let end = buf[..n].iter().position(|&c| c == 0).unwrap_or(n);
        out.push((String::from_utf16_lossy(&buf[..end]).to_lowercase(), drive));
    }
    out
}

fn nt_to_dos(nt: &str, devs: &[(String, String)]) -> Option<String> {
    devs.iter().find_map(|(dev, drive)| {
        let rest = nt.get(dev.len()..)?;
        (nt[..dev.len()].eq_ignore_ascii_case(dev) && rest.starts_with('\\')).then(|| format!("{drive}{rest}"))
    })
}

// ----------------------------------------------------------------- outils

/// Un mutex empoisonne (panique rattrapee par `ilot_invoke`) reste utilisable.
fn lock<T>(m: &Mutex<T>) -> MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

/// Connexions TCP etablies par processus (IPv4 + IPv6).
fn tcp_by_pid() -> HashMap<u32, u32> {
    const ERROR_INSUFFICIENT_BUFFER: u32 = 122;
    let mut out = HashMap::new();
    // (famille, taille d'une ligne, decalage de l'etat, decalage du pid)
    for (af, row, st_off, pid_off) in [(AF_INET.0 as u32, 24usize, 0usize, 20usize), (AF_INET6.0 as u32, 56, 48, 52)] {
        let mut size = 0u32;
        let mut buf = Vec::new();
        let mut ok = false;
        unsafe {
            GetExtendedTcpTable(None, &mut size, false, af, TCP_TABLE_OWNER_PID_ALL, 0);
            // la table peut grossir entre deux appels : quelques essais
            for _ in 0..3 {
                buf = vec![0u8; size as usize + 1024];
                size = buf.len() as u32;
                match GetExtendedTcpTable(Some(buf.as_mut_ptr() as _), &mut size, false, af, TCP_TABLE_OWNER_PID_ALL, 0) {
                    0 => {
                        ok = true;
                        break;
                    }
                    ERROR_INSUFFICIENT_BUFFER => continue,
                    _ => break,
                }
            }
        }
        if !ok || buf.len() < 4 {
            continue;
        }
        let rd = |o: usize| u32::from_ne_bytes(buf[o..o + 4].try_into().unwrap());
        let n = rd(0) as usize;
        for i in 0..n {
            let base = 4 + i * row;
            if base + row > buf.len() {
                break;
            }
            // 5 = ESTABLISHED
            if rd(base + st_off) == 5 {
                *out.entry(rd(base + pid_off)).or_insert(0) += 1;
            }
        }
    }
    out
}

/// Processus qui ont une vraie fenetre (barre des taches) : la section
/// « Applications » du Gestionnaire des taches. Valeur : sa premiere fenetre.
fn pids_with_window() -> HashMap<u32, HWND> {
    unsafe extern "system" fn cb(h: HWND, l: LPARAM) -> BOOL {
        let set = &mut *(l.0 as *mut HashMap<u32, HWND>);
        if !IsWindowVisible(h).as_bool() || GetWindowTextLengthW(h) == 0 {
            return true.into();
        }
        if GetWindow(h, GW_OWNER).is_ok_and(|o| !o.is_invalid()) {
            return true.into();
        }
        if GetWindowLongW(h, GWL_EXSTYLE) as u32 & WS_EX_TOOLWINDOW.0 != 0 {
            return true.into();
        }
        // fenetres « cachees » des applis du Store en veille
        let mut cloaked = 0u32;
        let _ = DwmGetWindowAttribute(h, DWMWA_CLOAKED, &mut cloaked as *mut _ as _, 4);
        if cloaked != 0 {
            return true.into();
        }
        let mut pid = 0u32;
        GetWindowThreadProcessId(h, Some(&mut pid));
        // appli du Store : le cadre appartient a ApplicationFrameHost, la
        // vraie appli est le processus de sa fenetre enfant CoreWindow
        // (GetClassNameW n'envoie pas de message : sans risque sur nos fenetres)
        // On garde la CoreWindow : IsHungAppWindow interroge alors le thread
        // de l'appli, pas celui d'ApplicationFrameHost.
        let mut win = h;
        if class_is(h, "ApplicationFrameWindow") {
            let mut found = (pid, 0u32, HWND::default());
            let _ = EnumChildWindows(Some(h), Some(core_cb), LPARAM(&mut found as *mut _ as isize));
            if found.1 != 0 {
                pid = found.1;
                win = found.2;
            }
        }
        set.entry(pid).or_insert(win);
        true.into()
    }
    /// (pid du cadre, pid trouve, sa fenetre) : s'arrete sur la premiere
    /// CoreWindow d'un autre processus.
    unsafe extern "system" fn core_cb(h: HWND, l: LPARAM) -> BOOL {
        let found = &mut *(l.0 as *mut (u32, u32, HWND));
        if class_is(h, "Windows.UI.Core.CoreWindow") {
            let mut pid = 0u32;
            GetWindowThreadProcessId(h, Some(&mut pid));
            if pid != 0 && pid != found.0 {
                found.1 = pid;
                found.2 = h;
                return false.into();
            }
        }
        true.into()
    }
    let mut set = HashMap::new();
    unsafe {
        let _ = EnumWindows(Some(cb), LPARAM(&mut set as *mut _ as isize));
    }
    set
}

fn class_is(h: HWND, class: &str) -> bool {
    let mut buf = [0u16; 64];
    let n = unsafe { GetClassNameW(h, &mut buf) }.max(0) as usize;
    String::from_utf16_lossy(&buf[..n.min(buf.len())]) == class
}

/// Fenetre qui ne traite plus ses messages (depuis 5 s), sans lui en envoyer.
fn is_hung(h: HWND) -> bool {
    unsafe { IsHungAppWindow(h) }.as_bool()
}

/// Mode efficacite (Windows 11) : limitation de la vitesse d'execution
/// demandee et active. Faux si le processus ne s'ouvre pas.
pub(crate) fn eco(pid: u32) -> bool {
    unsafe {
        let Ok(h) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) else {
            return false;
        };
        let mut s = PROCESS_POWER_THROTTLING_STATE { Version: PROCESS_POWER_THROTTLING_CURRENT_VERSION, ..Default::default() };
        let r = GetProcessInformation(
            h,
            ProcessPowerThrottling,
            &mut s as *mut _ as _,
            std::mem::size_of::<PROCESS_POWER_THROTTLING_STATE>() as u32,
        );
        let _ = CloseHandle(h);
        r.is_ok() && s.ControlMask & s.StateMask & PROCESS_POWER_THROTTLING_EXECUTION_SPEED != 0
    }
}

/// Statut affiche, par priorite : ne repond pas > suspendu > efficacite.
pub(crate) fn status_of(hung: bool, suspended: bool, eco: bool) -> &'static str {
    if hung {
        "hung"
    } else if suspended {
        "suspended"
    } else if eco {
        "eco"
    } else {
        ""
    }
}

fn window_title(h: HWND) -> String {
    let mut buf = [0u16; 512];
    let n = unsafe { GetWindowTextW(h, &mut buf) }.max(0) as usize;
    String::from_utf16_lossy(&buf[..n.min(buf.len())])
}

/// Chemin complet de l'executable d'un processus.
pub(crate) fn exe_path(pid: u32) -> Option<String> {
    use windows::core::PWSTR;
    use windows::Win32::System::Threading::{QueryFullProcessImageNameW, PROCESS_NAME_WIN32};
    unsafe {
        let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok()?;
        let mut buf = vec![0u16; 32768];
        let mut len = buf.len() as u32;
        let r = QueryFullProcessImageNameW(h, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &mut len);
        let _ = CloseHandle(h);
        r.ok()?;
        Some(String::from_utf16_lossy(&buf[..len as usize]))
    }
}

/// Identite d'un exe pour le regroupement : son chemin en minuscules, ou
/// « pkg:<famille> » pour une appli du Store (tous les exe du paquet forment
/// une seule ligne, comme le Gestionnaire des taches).
fn ident_of(path: &str) -> String {
    let low = path.to_lowercase();
    if let Some(i) = low.find(r"\windowsapps\") {
        // Nom_Version_Archi_Ressource_Editeur -> famille Nom_Editeur
        let dir = low[i + 13..].split('\\').next().unwrap_or("");
        let parts: Vec<&str> = dir.split('_').collect();
        if parts.len() >= 5 {
            return format!("pkg:{}_{}", parts[0], parts[parts.len() - 1]);
        }
    }
    low
}

fn base_name(s: &str) -> String {
    match s.len().checked_sub(4).and_then(|i| s.get(i..).map(|ext| (i, ext))) {
        Some((i, ext)) if ext.eq_ignore_ascii_case(".exe") => s[..i].to_string(),
        _ => s.to_string(),
    }
}

pub(crate) fn icons_for(paths: Vec<PathBuf>) -> Vec<(PathBuf, String)> {
    // icones via le Shell, dans un thread STA a part
    std::thread::spawn(move || {
        crate::com_init_sta();
        paths
            .into_iter()
            .map(|p| {
                let icon = unsafe {
                    SHCreateItemFromParsingName::<_, _, IShellItem>(&HSTRING::from(p.as_os_str()), None)
                        .map(|it| crate::apps::icon_of(&it))
                        .unwrap_or_default()
                };
                (p, icon)
            })
            .collect()
    })
    .join()
    .unwrap_or_default()
}

// ----------------------------------------------------------------- etat

/// Releve precedent d'un processus : les taux (CPU, disque) sont des ecarts.
struct Prev {
    create: i64,
    cpu: i64,
    io: u64,
}

/// Tout ce qui ne sert que tant que l'onglet est affiche : libere par `tasks_stop`.
#[derive(Default)]
struct Live {
    pdh: Option<crate::pdh::Query>,
    nets: Option<Networks>,
    buf: Vec<u64>,
    prev: HashMap<u32, Prev>,
    last: Option<Instant>,
    /// chemin de l'exe par pid (avec l'heure de creation, contre la
    /// reutilisation des pid, et l'heure de lecture : un echec est retente)
    paths: HashMap<u32, (i64, Option<PathBuf>, Instant)>,
    /// mode efficacite par pid : (creation, heure de lecture, valeur)
    eco: HashMap<u32, (i64, Instant, bool)>,
}

impl Live {
    /// Mode efficacite en cache, relu au plus toutes les `ECO_TTL`.
    pub(crate) fn eco(&mut self, pid: u32, create: i64) -> bool {
        let now = Instant::now();
        match self.eco.get(&pid) {
            Some(&(c, t, v)) if c == create && now.duration_since(t) < ECO_TTL => v,
            old => {
                // premiere lecture : date etalee selon le pid, pour que les
                // relectures ne tombent pas toutes sur le meme releve
                let t = match old {
                    Some(&(c, _, _)) if c == create => now,
                    _ => now.checked_sub(Duration::from_secs((pid as u64 / 4) % ECO_TTL.as_secs())).unwrap_or(now),
                };
                let v = eco(pid);
                self.eco.insert(pid, (create, t, v));
                v
            }
        }
    }
}

/// Duree de validite du cache du mode efficacite.
const ECO_TTL: Duration = Duration::from_secs(5);
/// Delai avant de retenter un chemin d'exe illisible.
const PATH_RETRY: Duration = Duration::from_secs(10);
/// Taille maximale des caches d'icones et de noms : vides au-dela.
const CACHE_MAX: usize = 512;

#[derive(Default)]
pub struct Tasks {
    live: Mutex<Live>,
    icons: Mutex<HashMap<PathBuf, String>>,
    labels: Mutex<HashMap<PathBuf, Option<String>>>,
}

/// Au-dela, les ecarts couvriraient une trop longue duree (onglet ferme) :
/// on repart d'un releve neuf.
const STALE: Duration = Duration::from_secs(6);
/// Ecart minimal entre deux releves : en dessous (clic sur un groupe, fin de
/// tache juste apres le minuteur), la granularite des temps CPU (15,6 ms)
/// rendrait les taux instables.
const MIN_GAP: Duration = Duration::from_millis(500);
/// Premier releve apres l'amorce : une seconde, comme le Gestionnaire. Sur
/// 500 ms, le CPU tombait en plein sur le pic d'ouverture de l'ilot (45 %
/// affiches pour 17 % reels).
const FIRST_GAP: Duration = Duration::from_secs(1);

fn pdh_query() -> Option<crate::pdh::Query> {
    crate::pdh::Query::new(&[
        // temps processeur, comme le Gestionnaire (pas « Utility », plus haut
        // avec le turbo : voir system.rs)
        r"\Processor Information(_Total)\% Processor Time",
        r"\PhysicalDisk(*)\% Idle Time",
        r"\GPU Engine(*)\Utilization Percentage",
        r"\PhysicalDisk(_Total)\Disk Bytes/sec",
        // ligne « Interruptions systeme » (a la suite : ne pas decaler les index)
        r"\Processor Information(_Total)\% Interrupt Time",
        r"\Processor Information(_Total)\% DPC Time",
    ])
}

/// Cartes comptees dans le debit total : ni la boucle locale ni les cartes
/// virtuelles Hyper-V / WSL (leur trafic passe aussi par la carte physique).
fn counted_net(name: &str) -> bool {
    let n = name.to_lowercase();
    !n.contains("loopback") && !n.starts_with("vethernet")
}

/// Chiffres d'un processus pour ce releve (avant regroupement).
struct Row<'a> {
    p: &'a Proc,
    cpu: f32,
    disk: u64,
    gpu: f32,
    net: u32,
    path: Option<PathBuf>,
    hwnd: Option<HWND>,
    hung: bool,
    eco: bool,
}

/// Nom d'une ligne « Hote de service » : son premier service, et le nombre
/// des autres.
fn svc_label(services: &[String]) -> String {
    match services {
        [] => "Hôte de service".into(),
        [a] => format!("Hôte de service : {a}"),
        [a, rest @ ..] => format!("Hôte de service : {a} +{}", rest.len()),
    }
}

/// Membre dont le chemin donne l'icone et le nom du groupe : la racine,
/// sinon un processus avec fenetre, sinon le plus petit pid.
fn path_member(rows: &[Row], members: &[usize]) -> Option<usize> {
    members.first().copied().filter(|&i| rows[i].path.is_some()).or_else(|| {
        members.iter().copied().filter(|&i| rows[i].path.is_some()).min_by_key(|&i| (rows[i].hwnd.is_none(), rows[i].p.pid))
    })
}

/// `expanded` : cles des groupes developpes dans l'interface, les seuls pour
/// lesquels le detail par processus est envoye.
pub fn tasks_get(st: State<Tasks>, expanded: Option<Vec<String>>) -> TasksReport {
    let expanded: HashSet<String> = expanded.unwrap_or_default().into_iter().collect();
    let mut live = lock(&st.live);
    let live = &mut *live;

    // premier releve (ou retour apres une pause) : un releve d'amorce, puis
    // un vrai FIRST_GAP plus tard, sinon CPU et disque seraient des moyennes
    // depuis le demarrage de chaque processus
    let fresh = live.last.is_none_or(|t| t.elapsed() > STALE);
    if fresh {
        live.pdh = pdh_query();
        let nets = live.nets.get_or_insert_with(Networks::new_with_refreshed_list);
        nets.refresh(true);
        live.prev = snapshot(&mut live.buf)
            .unwrap_or_default()
            .into_iter()
            .map(|p| (p.pid, Prev { create: p.create, cpu: p.cpu, io: p.io }))
            .collect();
        live.last = Some(Instant::now());
    }
    if let Some(t) = live.last {
        let (gap, min) = (t.elapsed(), if fresh { FIRST_GAP } else { MIN_GAP });
        if gap < min {
            std::thread::sleep(min - gap);
        }
    }

    // compteurs Windows : CPU, disques, GPU
    let (cpu_total, disk_active, gpu_vals, phys, interrupts) = match live.pdh.as_ref() {
        Some(q) => {
            q.collect();
            let active = q
                .values(1)
                .iter()
                .filter(|(n, _)| n != "_Total")
                .map(|(_, v)| (100.0 - v).clamp(0.0, 100.0))
                .fold(0.0, f64::max);
            let (i, d) = (q.value(4, "_Total"), q.value(5, "_Total"));
            let interrupts = (i.is_some() || d.is_some()).then(|| (i.unwrap_or(0.0) + d.unwrap_or(0.0)).clamp(0.0, 100.0) as f32);
            (q.value(0, "_Total"), active, q.values(2), q.value(3, "_Total"), interrupts)
        }
        None => (None, 0.0, Vec::new(), None, None),
    };
    let (gpu_pid, gpu_total) = crate::pdh::gpu_by_pid(&gpu_vals);

    let procs_now = snapshot(&mut live.buf).unwrap_or_default();
    let now = Instant::now();
    let secs = live.last.map_or(1.0, |t| (now - t).as_secs_f64().max(0.2));
    live.last = Some(now);
    let cores = std::thread::available_parallelism().map_or(1, |n| n.get()) as f64;

    let (net_down, net_up) = {
        let nets = live.nets.get_or_insert_with(Networks::new_with_refreshed_list);
        nets.refresh(true);
        nets.iter().filter(|(n, _)| counted_net(n)).fold((0, 0), |(d, u), (_, n)| {
            (d + (n.received() as f64 / secs) as u64, u + (n.transmitted() as f64 / secs) as u64)
        })
    };
    let tcp = tcp_by_pid();
    let windowed = pids_with_window();
    let windir = std::env::var("SystemRoot").unwrap_or_else(|_| r"C:\Windows".into()).to_lowercase();
    let mut devs: Option<Vec<(String, String)>> = None;

    // chiffres par processus, puis noeuds pour le regroupement (meme ordre)
    let mut rows: Vec<Row> = Vec::with_capacity(procs_now.len());
    let mut nodes: Vec<procgroup::Node> = Vec::with_capacity(procs_now.len());
    let mut cpu_sum = 0.0f32;
    let mut io_sum = 0.0f64;
    let mut next_prev = HashMap::with_capacity(procs_now.len());
    for p in &procs_now {
        if p.pid == 0 {
            continue;
        }
        let (dcpu, dio) = match live.prev.get(&p.pid) {
            Some(o) if o.create == p.create => ((p.cpu - o.cpu).max(0), p.io.saturating_sub(o.io)),
            // nouveau processus (ou pid reutilise) : pas encore d'ecart
            _ => (0, 0),
        };
        next_prev.insert(p.pid, Prev { create: p.create, cpu: p.cpu, io: p.io });

        // chemin de l'exe, une seule fois par processus
        let path = match live.paths.get(&p.pid) {
            Some((c, path, t)) if *c == p.create && (path.is_some() || t.elapsed() < PATH_RETRY) => path.clone(),
            _ => {
                let mut nt_dos = || {
                    let nt = nt_image_path(p.pid)?;
                    nt_to_dos(&nt, devs.get_or_insert_with(dos_devices))
                };
                let is_exe = |s: &str| s.to_lowercase().ends_with(".exe");
                let path = match exe_path(p.pid) {
                    // exe renomme pendant qu'il tourne (mise a jour :
                    // claude.exe.old.123) : le chemin d'origine garde
                    // l'icone et le nom, comme le Gestionnaire de Windows
                    Some(x) if !is_exe(&x) => nt_dos().filter(|d| is_exe(d) && std::path::Path::new(d).exists()).or(Some(x)),
                    Some(x) => Some(x),
                    None => nt_dos(),
                };
                let path = path.map(PathBuf::from);
                live.paths.insert(p.pid, (p.create, path.clone(), Instant::now()));
                path
            }
        };

        // temps CPU brut / (duree x coeurs logiques), comme le Gestionnaire :
        // la somme des lignes rejoint l'en-tete (« % Processor Time »)
        let cpu = (dcpu as f64 / (secs * 1e7 * cores) * 100.0) as f32;
        cpu_sum += cpu;
        let disk = (dio as f64 / secs) as u64;
        io_sum += disk as f64;
        let hwnd = windowed.get(&p.pid).copied();
        // un processus suspendu ne traite plus ses messages : c'est la
        // suspension qu'on affiche, pas « ne repond pas »
        let hung = !p.suspended && hwnd.is_some_and(is_hung);
        let eco = live.eco(p.pid, p.create);
        let exe = base_name(&p.name).to_lowercase();
        let ident = path.as_ref().map_or_else(|| exe.clone(), |x| ident_of(&x.to_string_lossy()));
        nodes.push(procgroup::Node { pid: p.pid, ppid: p.ppid, create: p.create, exe, ident, window: hwnd.is_some() });
        rows.push(Row {
            p,
            cpu,
            disk,
            gpu: gpu_pid.get(&p.pid).copied().unwrap_or(0.0) as f32,
            net: tcp.get(&p.pid).copied().unwrap_or(0),
            path,
            hwnd,
            hung,
            eco,
        });
    }
    live.prev = next_prev;
    live.paths.retain(|pid, _| live.prev.contains_key(pid));
    live.eco.retain(|pid, _| live.prev.contains_key(pid));
    let procs = rows.len();

    // les compteurs d'E/S des processus comptent aussi les tubes et les
    // lectures servies par le cache ; Windows ne montre que le disque reel
    // (ETW, admin). Sans admin : on ramene la somme au debit physique total.
    if let Some(phys) = phys {
        let k = (phys / io_sum.max(1.0)).clamp(0.0, 1.0);
        if k < 1.0 {
            for r in &mut rows {
                r.disk = (r.disk as f64 * k) as u64;
            }
        }
    }

    // regroupement comme le Gestionnaire des taches (voir procgroup)
    let groups = procgroup::group(&nodes);
    let services = svc::services_by_pid();

    // icones et noms des executables pas encore vus : chemin de chaque groupe,
    // et de chaque processus des groupes developpes
    let mut icons = lock(&st.icons);
    let mut labels = lock(&st.labels);
    if icons.len() > CACHE_MAX || labels.len() > CACHE_MAX {
        icons.clear();
        labels.clear();
    }
    let heads: Vec<Option<usize>> = groups.iter().map(|g| path_member(&rows, &g.members)).collect();
    let mut missing: HashSet<PathBuf> = HashSet::new();
    for (g, head) in groups.iter().zip(&heads) {
        let open = expanded.contains(&g.key);
        let paths = head.iter().chain(g.members.iter().filter(|_| open)).filter_map(|&i| rows[i].path.as_ref());
        missing.extend(paths.filter(|p| !icons.contains_key(*p)).cloned());
    }
    let missing: Vec<PathBuf> = missing.into_iter().collect();
    for p in &missing {
        labels.entry(p.clone()).or_insert_with(|| crate::apps::file_description(&p.to_string_lossy()));
    }
    if !missing.is_empty() {
        icons.extend(icons_for(missing));
    }
    let label_of = |path: Option<&PathBuf>, name: &str| {
        path.and_then(|p| labels.get(p).cloned().flatten()).filter(|l| !l.is_empty()).unwrap_or_else(|| name.to_string())
    };
    let icon_of = |path: Option<&PathBuf>| path.and_then(|p| icons.get(p).cloned()).unwrap_or_default();

    let mut list: Vec<Task> = Vec::with_capacity(groups.len() + 1);
    for (g, head) in groups.into_iter().zip(heads) {
        let Some(&root) = g.members.first() else { continue };
        let ms = &g.members;
        let name = base_name(&rows[root].p.name);
        let path = head.and_then(|i| rows[i].path.as_ref());
        let protected = PROTECTED.contains(&nodes[root].exe.as_str()) || g.key.starts_with("svc:") || g.key.starts_with("one:");
        let kind = if g.app {
            "app"
        } else if protected || path.is_none_or(|p| p.to_string_lossy().to_lowercase().starts_with(&windir)) {
            // pas de chemin lisible : processus systeme protege
            "win"
        } else {
            "bg"
        };
        let svcs = g.key.starts_with("svc:").then(|| services.get(&rows[root].p.pid).cloned().unwrap_or_default());
        let label = match &svcs {
            Some(s) => svc_label(s),
            None => label_of(path, &name),
        };
        // statut du groupe : ne repond pas si l'une de ses fenetres, suspendu
        // si tous ses membres, efficacite si sa racine
        let status = status_of(ms.iter().any(|&i| rows[i].hung), ms.iter().all(|&i| rows[i].p.suspended), rows[root].eco);
        let procs = if expanded.contains(&g.key) { subs(&rows, ms, &label_of, &icon_of) } else { Vec::new() };
        list.push(Task {
            key: g.key,
            name,
            label,
            kind,
            count: ms.len(),
            cpu: ms.iter().map(|&i| rows[i].cpu).sum::<f32>().min(100.0),
            mem: ms.iter().map(|&i| rows[i].p.mem).sum(),
            disk: ms.iter().map(|&i| rows[i].disk).sum(),
            gpu: ms.iter().map(|&i| rows[i].gpu).fold(0.0, f32::max).min(100.0),
            net: ms.iter().map(|&i| rows[i].net).sum(),
            icon: icon_of(path),
            path: path.map(|p| p.to_string_lossy().into_owned()).unwrap_or_default(),
            protected,
            status,
            members: ms.iter().map(|&i| (rows[i].p.pid, created_ms(rows[i].p.create))).collect(),
            services: svcs,
            procs,
        });
    }
    // temps passe en interruptions et DPC : une ligne a part, comme Windows
    // (comptee dans la somme, pas dans le nombre de processus)
    if let Some(c) = interrupts {
        cpu_sum += c;
        list.push(Task {
            key: "sys:interrupts".into(),
            name: "Interruptions système".into(),
            label: "Interruptions système".into(),
            kind: "win",
            count: 0,
            cpu: c,
            mem: 0,
            disk: 0,
            gpu: 0.0,
            net: 0,
            icon: String::new(),
            path: String::new(),
            protected: true,
            status: "",
            members: Vec::new(),
            services: None,
            procs: Vec::new(),
        });
    }
    // ordre stable d'un appel a l'autre (l'interface trie ensuite)
    list.sort_by(|a, b| a.key.cmp(&b.key));
    let cpu = cpu_total.map_or(cpu_sum, |v| v as f32).clamp(0.0, 100.0);
    TasksReport { list, cpu, gpu: gpu_total as f32, disk_active: disk_active as f32, procs, net_down, net_up }
}

/// Detail par processus d'un groupe developpe, dans l'ordre des membres.
fn subs(
    rows: &[Row],
    members: &[usize],
    label_of: &dyn Fn(Option<&PathBuf>, &str) -> String,
    icon_of: &dyn Fn(Option<&PathBuf>) -> String,
) -> Vec<Sub> {
    let mut procs: Vec<Sub> = members
        .iter()
        .map(|&i| {
            let r = &rows[i];
            let name = base_name(&r.p.name);
            Sub {
                pid: r.p.pid,
                created: created_ms(r.p.create),
                main: false,
                ppid: r.p.ppid,
                label: label_of(r.path.as_ref(), &name),
                icon: icon_of(r.path.as_ref()),
                path: r.path.as_ref().map(|p| p.to_string_lossy().into_owned()).unwrap_or_default(),
                protected: PROTECTED.contains(&name.to_lowercase().as_str()),
                name,
                // pas notre propre fenetre : GetWindowTextW lui enverrait un message
                title: r.hwnd.filter(|_| r.p.pid != std::process::id()).map(window_title).unwrap_or_default(),
                cpu: r.cpu.min(100.0),
                mem: r.p.mem,
                disk: r.disk,
                gpu: r.gpu.min(100.0),
                net: r.net,
                status: status_of(r.hung, r.p.suspended, r.eco),
            }
        })
        .collect();
    // principal : racine du groupe qui a au moins un enfant dans le groupe
    // (des instances independantes, comme plusieurs notepad, ne le sont pas)
    let born: HashMap<u32, u64> = procs.iter().map(|s| (s.pid, s.created)).collect();
    // parent du groupe ne avant l'enfant : sinon le pid a ete reutilise
    let has_parent = |s: &Sub| s.ppid != s.pid && born.get(&s.ppid).is_some_and(|&c| c <= s.created);
    let parents: HashSet<u32> = procs.iter().filter(|s| has_parent(s)).map(|s| s.ppid).collect();
    let mains: Vec<bool> = procs.iter().map(|s| !has_parent(s) && parents.contains(&s.pid)).collect();
    for (s, m) in procs.iter_mut().zip(mains) {
        s.main = m;
    }
    procs
}

/// Onglet cache : libere les compteurs, le tampon et les caches par pid.
pub fn tasks_stop(st: State<Tasks>) {
    *lock(&st.live) = Live::default();
}

/// Le processus ouvert est-il ne a `created` (ms, comme `created_ms`) ?
fn born_at(h: HANDLE, created: u64) -> bool {
    let (mut c, mut e, mut k, mut u) = (FILETIME::default(), FILETIME::default(), FILETIME::default(), FILETIME::default());
    if unsafe { GetProcessTimes(h, &mut c, &mut e, &mut k, &mut u) }.is_err() {
        return false;
    }
    created_ms(((c.dwHighDateTime as u64) << 32 | c.dwLowDateTime as u64) as i64) == created
}

/// Fin de tache pour les membres d'un groupe, dans l'ordre recu (racines
/// d'abord). Les pid sont reutilises : chacun doit exister avec cette heure
/// de creation, ne pas etre l'ilot, et son exe ne pas etre protege ; sinon
/// il est saute sans compter. Hotes de service et lignes systeme : refuses.
pub fn task_kill(_st: State<Tasks>, key: String, members: Vec<(u32, u64)>) -> KillReport {
    let mut r = KillReport { killed: 0, denied: 0 };
    if key.starts_with("svc:") || key.starts_with("sys:") {
        return r;
    }
    let me = std::process::id();
    // tampon a part : ne pas attendre un `tasks_get` en cours (amorce, icones)
    let procs = snapshot(&mut Vec::new()).unwrap_or_default();
    let by_pid: HashMap<u32, &Proc> = procs.iter().map(|p| (p.pid, p)).collect();
    let mut done = HashSet::new();
    for (pid, created) in members {
        let Some(p) = by_pid.get(&pid) else { continue };
        let exe = base_name(&p.name).to_lowercase();
        if pid == 0 || pid == me || created_ms(p.create) != created || PROTECTED.contains(&exe.as_str()) || !done.insert(pid) {
            continue;
        }
        // racines d'abord : leurs enfants peuvent sortir pendant la boucle ;
        // un processus deja sorti n'est ni termine ni refuse
        let res = unsafe {
            match OpenProcess(PROCESS_TERMINATE | PROCESS_QUERY_LIMITED_INFORMATION, false, pid) {
                // pid reutilise entre le releve et l'ouverture : saute
                Ok(h) if !born_at(h, created) => {
                    let _ = CloseHandle(h);
                    None
                }
                Ok(h) => {
                    let ok = TerminateProcess(h, 1).is_ok();
                    let mut code = 0u32;
                    let gone = !ok && GetExitCodeProcess(h, &mut code).is_ok() && code != STILL_ACTIVE.0 as u32;
                    let _ = CloseHandle(h);
                    if gone { None } else { Some(ok) }
                }
                // pid disparu depuis le releve
                Err(e) if e.code() == ERROR_INVALID_PARAMETER.to_hresult() => None,
                Err(_) => Some(false),
            }
        };
        match res {
            Some(true) => r.killed += 1,
            Some(false) => r.denied += 1,
            None => {}
        }
    }
    r
}

/// Ouvre le vrai Gestionnaire des taches de Windows.
pub fn taskmgr_open() {
    let _ = Command::new("cmd").args(["/c", "start", "", "taskmgr.exe"]).creation_flags(CREATE_NO_WINDOW).spawn();
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn snapshot_couvre_les_processus_proteges() {
        let mut buf = Vec::new();
        let procs = snapshot(&mut buf).expect("NtQuerySystemInformation");
        let me = procs.iter().find(|p| p.pid == std::process::id()).expect("processus courant");
        assert!(me.mem > 0 && me.cpu >= 0 && me.create > 0);
        // svchost ne s'ouvre pas sans admin : il doit quand meme avoir des chiffres
        let svc: Vec<_> = procs.iter().filter(|p| p.name.eq_ignore_ascii_case("svchost.exe")).collect();
        assert!(!svc.is_empty());
        assert!(svc.iter().any(|p| p.cpu > 0 && p.mem > 0));
        let nt = nt_image_path(me.pid).expect("chemin NT");
        let dos = nt_to_dos(&nt, &dos_devices()).expect("lettre de lecteur");
        assert!(dos.eq_ignore_ascii_case(&exe_path(me.pid).unwrap()), "{dos}");
    }

    /// Groupe dont les membres contiennent ce pid.
    fn group_of(list: &[Task], pid: u32) -> Option<&Task> {
        list.iter().find(|t| t.members.iter().any(|&(p, _)| p == pid))
    }

    #[test]
    fn groupe_developpe_et_fin_d_un_seul_pid() {
        let spawn = || Command::new("ping").args(["-n", "60", "127.0.0.1"]).creation_flags(CREATE_NO_WINDOW).spawn().unwrap();
        let (mut a, mut b) = (spawn(), spawn());
        let tasks = Tasks::default();
        let r = tasks_get(State::of(&tasks), None);
        let key = group_of(&r.list, a.id()).expect("groupe de ping").key.clone();
        let r = tasks_get(State::of(&tasks), Some(vec![key.clone()]));
        let g = group_of(&r.list, a.id()).expect("groupe de ping");
        assert_eq!(g.key, key);
        // deux ping sans parent ping : deux arbres, donc deux lignes (comme Windows)
        assert!(group_of(&r.list, b.id()).is_some_and(|t| t.key != key), "{key}");
        let pids: Vec<u32> = g.procs.iter().map(|s| s.pid).collect();
        let sa = g.procs.iter().find(|s| s.pid == a.id()).unwrap();
        let created = sa.created;
        assert!(sa.name.eq_ignore_ascii_case("ping") && !sa.label.is_empty() && !sa.path.is_empty());
        assert_eq!(pids, vec![a.id()]);
        // seul et sans enfant : pas « principal »
        assert!(!sa.main);
        // les autres groupes n'envoient pas de detail
        assert!(r.list.iter().filter(|t| t.key != key).all(|t| t.procs.is_empty()));
        // un hote de service ou une ligne systeme : refuses d'emblee
        let k = task_kill(State::of(&tasks), "svc:1:2".into(), vec![(a.id(), created)]);
        assert_eq!((k.killed, k.denied), (0, 0));
        // un pid d'une autre heure de creation (pid reutilise) : saute
        let k = task_kill(State::of(&tasks), key.clone(), vec![(a.id(), created + 1)]);
        assert_eq!((k.killed, k.denied), (0, 0));
        let k = task_kill(State::of(&tasks), key, vec![(a.id(), created)]);
        assert_eq!((k.killed, k.denied), (1, 0));
        assert!(a.wait().is_ok());
        assert!(b.try_wait().unwrap().is_none(), "l'autre ping doit survivre");
        let _ = b.kill();
        let _ = b.wait();
    }

    #[test]
    fn principal_seulement_pour_un_parent_du_groupe() {
        // cmd -> cmd -> ping : le premier cmd est le principal du groupe cmd
        let mut outer = Command::new("cmd")
            .args(["/c", "cmd", "/c", "ping", "-n", "60", "127.0.0.1"])
            .creation_flags(CREATE_NO_WINDOW)
            .spawn()
            .unwrap();
        let tasks = Tasks::default();
        let mut found = None;
        let mut expanded = None;
        for _ in 0..20 {
            let r = tasks_get(State::of(&tasks), expanded.clone());
            let g = group_of(&r.list, outer.id()).expect("groupe cmd");
            expanded = Some(vec![g.key.clone()]);
            let o = g.procs.iter().find(|s| s.pid == outer.id()).map(|s| s.main);
            let i = g.procs.iter().find(|s| s.ppid == outer.id()).map(|s| (s.pid, s.main));
            if let (Some(o), Some(i)) = (o, i) {
                let born = |pid: u32| g.procs.iter().find(|s| s.pid == pid).map_or(0, |s| s.created);
                found = Some((g.key.clone(), (outer.id(), born(outer.id())), o, (i.0, born(i.0), i.1)));
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        let snap = snapshot(&mut Vec::new()).unwrap_or_default();
        let (key, outer_m, outer_main, (inner, inner_c, inner_main)) = found.expect("cmd imbrique");
        // menage : seulement les processus du test (le groupe peut contenir
        // d'autres cmd du poste), le ping du cmd interieur puis les deux cmd
        for p in snap.iter().filter(|p| p.ppid == inner && p.name.eq_ignore_ascii_case("ping.exe")) {
            task_kill(State::of(&tasks), "tree:ping".into(), vec![(p.pid, created_ms(p.create))]);
        }
        task_kill(State::of(&tasks), key.clone(), vec![(inner, inner_c), outer_m]);
        let _ = outer.kill();
        let _ = outer.wait();
        // le cmd exterieur est la racine de son arbre d'arriere-plan
        assert!(outer_main || !key.starts_with("tree:"), "le cmd exterieur a un enfant cmd : principal ({key})");
        assert!(!inner_main, "le cmd interieur a son parent dans le groupe");
    }

    #[test]
    fn hotes_de_service_et_membres() {
        let tasks = Tasks::default();
        let r = tasks_get(State::of(&tasks), None);
        let svc: Vec<&Task> = r.list.iter().filter(|t| t.key.starts_with("svc:")).collect();
        assert!(!svc.is_empty());
        assert!(svc.iter().all(|t| t.label.starts_with("Hôte de service") && t.services.is_some() && t.protected && t.count == 1));
        assert!(svc.iter().any(|t| t.services.as_ref().is_some_and(|s| !s.is_empty())), "aucun service nomme");
        assert!(r.list.iter().filter(|t| !t.key.starts_with("svc:")).all(|t| t.services.is_none()));
        // chaque processus du releve (pid != 0) dans exactement un groupe
        let mut seen = HashSet::new();
        for t in &r.list {
            assert_eq!(t.count, t.members.len(), "{}", t.key);
            for &(pid, _) in &t.members {
                assert!(pid != 0 && seen.insert(pid), "pid {pid} en double ({})", t.key);
            }
        }
        assert_eq!(seen.len(), r.procs);
        // cles uniques, liste triee par cle
        assert!(r.list.windows(2).all(|w| w[0].key < w[1].key));
        let json = serde_json::to_value(&r).unwrap();
        let first = &json["list"].as_array().unwrap().iter().find(|t| t["key"] != "sys:interrupts").unwrap()["members"][0];
        assert!(first.as_array().is_some_and(|m| m.len() == 2), "{first}");
    }

    #[test]
    fn threads_suspendus() {
        let mut buf = Vec::new();
        let procs = snapshot(&mut buf).expect("NtQuerySystemInformation");
        let me = procs.iter().find(|p| p.pid == std::process::id()).expect("processus courant");
        assert!(!me.suspended, "le processus de test tourne");
        // CREATE_SUSPENDED : le thread principal attend, raison Suspended
        let mut child = Command::new("ping")
            .args(["-n", "60", "127.0.0.1"])
            .creation_flags(CREATE_NO_WINDOW | 0x4)
            .spawn()
            .unwrap();
        let procs = snapshot(&mut buf).expect("NtQuerySystemInformation");
        let seen = procs.iter().find(|p| p.pid == child.id()).map(|p| p.suspended);
        let _ = child.kill();
        let _ = child.wait();
        assert_eq!(seen, Some(true), "ping lance suspendu");
    }

    #[test]
    fn mode_efficacite() {
        use windows::Win32::System::Threading::{SetProcessInformation, PROCESS_SET_INFORMATION};
        let mut child = Command::new("ping").args(["-n", "60", "127.0.0.1"]).creation_flags(CREATE_NO_WINDOW).spawn().unwrap();
        let before = eco(child.id());
        let set = unsafe {
            let h = OpenProcess(PROCESS_SET_INFORMATION, false, child.id()).unwrap();
            let s = PROCESS_POWER_THROTTLING_STATE {
                Version: PROCESS_POWER_THROTTLING_CURRENT_VERSION,
                ControlMask: PROCESS_POWER_THROTTLING_EXECUTION_SPEED,
                StateMask: PROCESS_POWER_THROTTLING_EXECUTION_SPEED,
            };
            let r = SetProcessInformation(
                h,
                ProcessPowerThrottling,
                &s as *const _ as _,
                std::mem::size_of::<PROCESS_POWER_THROTTLING_STATE>() as u32,
            );
            let _ = CloseHandle(h);
            r.is_ok()
        };
        let after = eco(child.id());
        let _ = child.kill();
        let _ = child.wait();
        assert!(set);
        assert!(!before && after, "avant {before}, apres {after}");
        assert!(!eco(u32::MAX - 3), "pid inexistant");
    }

    #[test]
    fn ligne_interruptions() {
        let tasks = Tasks::default();
        tasks_get(State::of(&tasks), None);
        let r = tasks_get(State::of(&tasks), None);
        let t = r.list.iter().find(|t| t.key == "sys:interrupts").expect("ligne interruptions");
        assert!(t.kind == "win" && t.protected && t.count == 0 && t.procs.is_empty() && t.members.is_empty());
        assert!((0.0..=100.0).contains(&t.cpu), "{}", t.cpu);
        // statut toujours renseigne, avec une valeur connue
        assert!(r.list.iter().all(|t| ["", "suspended", "hung", "eco"].contains(&t.status)));
    }

    #[test]
    fn priorite_des_statuts() {
        assert_eq!(status_of(true, true, true), "hung");
        assert_eq!(status_of(false, true, true), "suspended");
        assert_eq!(status_of(false, false, true), "eco");
        assert_eq!(status_of(false, false, false), "");
    }

    /// Mesure : `cargo test --release tasks::tests::cout_tasks_get -- --ignored --nocapture`
    #[test]
    #[ignore]
    fn cout_tasks_get() {
        let tasks = Tasks::default();
        tasks_get(State::of(&tasks), None);
        let mut total = Duration::ZERO;
        for _ in 0..5 {
            // hors chrono : evite l'attente de MIN_GAP
            std::thread::sleep(Duration::from_millis(1100));
            let t = Instant::now();
            tasks_get(State::of(&tasks), None);
            total += t.elapsed();
        }
        println!("tasks_get : {:?} en moyenne", total / 5);
    }

    #[test]
    fn identite_paquet_du_store() {
        let a = ident_of(r"C:\Program Files\WindowsApps\SpotifyAB.SpotifyMusic_1.296.518.0_x64__zpdnekdrzrea0\Spotify.exe");
        let b = ident_of(r"C:\Program Files\WindowsApps\SpotifyAB.SpotifyMusic_1.296.518.0_x64__zpdnekdrzrea0\SpotifyLauncher.exe");
        assert_eq!(a, "pkg:spotifyab.spotifymusic_zpdnekdrzrea0");
        assert_eq!(a, b);
        assert_eq!(ident_of(r"C:\Windows\Explorer.EXE"), r"c:\windows\explorer.exe");
    }

    #[test]
    fn nom_sans_exe() {
        assert_eq!(base_name("Chrome.EXE"), "Chrome");
        assert_eq!(base_name("Registry"), "Registry");
        assert_eq!(base_name("é.exe"), "é");
        assert_eq!(base_name("exe"), "exe");
    }
}
