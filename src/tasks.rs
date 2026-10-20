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
use windows::core::{BOOL, HSTRING};
use windows::Win32::Foundation::{CloseHandle, HWND, LPARAM};
use windows::Win32::Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_CLOAKED};
use windows::Win32::NetworkManagement::IpHelper::{GetExtendedTcpTable, TCP_TABLE_OWNER_PID_ALL};
use windows::Win32::Networking::WinSock::{AF_INET, AF_INET6};
use windows::Win32::Storage::FileSystem::QueryDosDeviceW;
use windows::Win32::System::Threading::{OpenProcess, TerminateProcess, PROCESS_QUERY_LIMITED_INFORMATION, PROCESS_TERMINATE};
use windows::Win32::UI::Shell::{IShellItem, SHCreateItemFromParsingName};
use windows::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetWindow, GetWindowLongW, GetWindowTextLengthW, GetWindowTextW, GetWindowThreadProcessId, IsWindowVisible, GWL_EXSTYLE,
    GW_OWNER, WS_EX_TOOLWINDOW,
};

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// Processus vitaux de Windows : jamais de fin de tache depuis l'ilot.
const PROTECTED: &[&str] = &[
    "system", "registry", "smss", "csrss", "wininit", "winlogon", "services", "lsass",
    "svchost", "dwm", "fontdrvhost", "memory compression", "secure system", "lsaiso",
    "sihost", "ctfmon", "audiodg", "ilot",
];

#[derive(Serialize)]
pub struct Task {
    /// nom de l'executable sans .exe (cle pour la fin de tache)
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
    /// titre de sa fenetre principale, vide s'il n'en a pas
    title: String,
    cpu: f32,
    mem: u64,
    disk: u64,
    gpu: f32,
    net: u32,
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

/// Un processus tel que vu par le noyau a l'instant du releve.
struct Proc {
    pid: u32,
    /// pid du parent a la creation (peut avoir ete reutilise depuis)
    ppid: u32,
    name: String,
    create: i64,
    /// temps processeur noyau + utilisateur, en unites de 100 ns
    cpu: i64,
    mem: u64,
    io: u64,
}

/// Releve de tous les processus. `buf` est garde d'un appel a l'autre
/// (quelques centaines de Ko) pour ne pas le reallouer a chaque tick.
fn snapshot(buf: &mut Vec<u64>) -> Option<Vec<Proc>> {
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
        out.push(Proc {
            pid: e.unique_process_id as u32,
            ppid: e.inherited_from_unique_process_id as u32,
            name,
            create: e.create_time,
            cpu: e.kernel_time.saturating_add(e.user_time),
            mem: e.working_set_private_size.max(0) as u64,
            io: (e.read_transfer_count.max(0) as u64).saturating_add(e.write_transfer_count.max(0) as u64),
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
        set.entry(pid).or_insert(h);
        true.into()
    }
    let mut set = HashMap::new();
    unsafe {
        let _ = EnumWindows(Some(cb), LPARAM(&mut set as *mut _ as isize));
    }
    set
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
    /// chemin de l'exe par pid (avec l'heure de creation, contre la reutilisation des pid)
    paths: HashMap<u32, (i64, Option<PathBuf>)>,
}

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
    ])
}

/// Cartes comptees dans le debit total : ni la boucle locale ni les cartes
/// virtuelles Hyper-V / WSL (leur trafic passe aussi par la carte physique).
fn counted_net(name: &str) -> bool {
    let n = name.to_lowercase();
    !n.contains("loopback") && !n.starts_with("vethernet")
}

/// `expanded` : noms des groupes developpes dans l'interface, les seuls pour
/// lesquels le detail par processus est envoye.
pub fn tasks_get(st: State<Tasks>, expanded: Option<Vec<String>>) -> TasksReport {
    let expanded: HashSet<String> = expanded.unwrap_or_default().iter().map(|s| s.to_lowercase()).collect();
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
    let (cpu_total, disk_active, gpu_vals, phys) = match live.pdh.as_ref() {
        Some(q) => {
            q.collect();
            let active = q
                .values(1)
                .iter()
                .filter(|(n, _)| n != "_Total")
                .map(|(_, v)| (100.0 - v).clamp(0.0, 100.0))
                .fold(0.0, f64::max);
            (q.value(0, "_Total"), active, q.values(2), q.value(3, "_Total"))
        }
        None => (None, 0.0, Vec::new(), None),
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

    // regroupement par nom d'executable ; le chemin retenu pour l'icone et le
    // nom est celui d'un processus avec fenetre, sinon du plus petit pid
    struct Group {
        task: Task,
        path: Option<PathBuf>,
        path_pid: u32,
        path_win: bool,
    }
    let mut groups: HashMap<String, Group> = HashMap::new();
    let mut procs = 0;
    let mut cpu_sum = 0.0f32;
    let mut io_sum = 0.0f64;
    let mut next_prev = HashMap::with_capacity(procs_now.len());
    for p in &procs_now {
        if p.pid == 0 {
            continue;
        }
        procs += 1;
        let (dcpu, dio) = match live.prev.get(&p.pid) {
            Some(o) if o.create == p.create => ((p.cpu - o.cpu).max(0), p.io.saturating_sub(o.io)),
            // nouveau processus (ou pid reutilise) : pas encore d'ecart
            _ => (0, 0),
        };
        next_prev.insert(p.pid, Prev { create: p.create, cpu: p.cpu, io: p.io });

        // chemin de l'exe, une seule fois par processus
        let path = match live.paths.get(&p.pid) {
            Some((c, path)) if *c == p.create => path.clone(),
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
                live.paths.insert(p.pid, (p.create, path.clone()));
                path
            }
        };

        let name = base_name(&p.name);
        let key = name.to_lowercase();
        let g = groups.entry(key.clone()).or_insert_with(|| Group {
            task: Task {
                label: String::new(),
                name,
                kind: "bg",
                count: 0,
                cpu: 0.0,
                mem: 0,
                disk: 0,
                gpu: 0.0,
                net: 0,
                icon: String::new(),
                path: String::new(),
                protected: PROTECTED.contains(&key.as_str()),
                procs: Vec::new(),
            },
            path: None,
            path_pid: u32::MAX,
            path_win: false,
        });
        let t = &mut g.task;
        t.net += tcp.get(&p.pid).copied().unwrap_or(0);
        t.count += 1;
        // temps CPU brut / (duree x coeurs logiques), comme le Gestionnaire :
        // la somme des lignes rejoint l'en-tete (« % Processor Time »)
        let c = (dcpu as f64 / (secs * 1e7 * cores) * 100.0) as f32;
        cpu_sum += c;
        t.cpu += c;
        t.mem += p.mem;
        t.gpu = t.gpu.max(gpu_pid.get(&p.pid).copied().unwrap_or(0.0) as f32);
        let disk = (dio as f64 / secs) as u64;
        io_sum += disk as f64;
        t.disk += disk;
        let hwnd = windowed.get(&p.pid).copied();
        if expanded.contains(&key) {
            t.procs.push(Sub {
                pid: p.pid,
                created: created_ms(p.create),
                main: false,
                ppid: p.ppid,
                // pas notre propre fenetre : GetWindowTextW lui enverrait un message
                title: hwnd.filter(|_| p.pid != std::process::id()).map(window_title).unwrap_or_default(),
                cpu: c.min(100.0),
                mem: p.mem,
                disk,
                gpu: (gpu_pid.get(&p.pid).copied().unwrap_or(0.0) as f32).min(100.0),
                net: tcp.get(&p.pid).copied().unwrap_or(0),
            });
        }
        let win = hwnd.is_some();
        if win {
            t.kind = "app";
        }
        if path.is_some() && (g.path.is_none() || (win && !g.path_win) || (win == g.path_win && p.pid < g.path_pid)) {
            g.path = path;
            g.path_pid = p.pid;
            g.path_win = win;
        }
    }
    live.prev = next_prev;
    live.paths.retain(|pid, _| live.prev.contains_key(pid));

    // les compteurs d'E/S des processus comptent aussi les tubes et les
    // lectures servies par le cache ; Windows ne montre que le disque reel
    // (ETW, admin). Sans admin : on ramene la somme au debit physique total.
    if let Some(phys) = phys {
        let k = (phys / io_sum.max(1.0)).clamp(0.0, 1.0);
        if k < 1.0 {
            for g in groups.values_mut() {
                g.task.disk = (g.task.disk as f64 * k) as u64;
                for s in &mut g.task.procs {
                    s.disk = (s.disk as f64 * k) as u64;
                }
            }
        }
    }

    // icones et noms des executables pas encore vus
    let mut icons = lock(&st.icons);
    let mut labels = lock(&st.labels);
    let missing: Vec<PathBuf> = groups
        .values()
        .filter_map(|g| g.path.clone())
        .filter(|p| !icons.contains_key(p))
        .collect();
    for p in &missing {
        labels.entry(p.clone()).or_insert_with(|| crate::apps::file_description(&p.to_string_lossy()));
    }
    if !missing.is_empty() {
        icons.extend(icons_for(missing));
    }
    // principal : racine du groupe qui a au moins un enfant dans le groupe
    // (des instances independantes, comme plusieurs notepad, ne le sont pas)
    for g in groups.values_mut() {
        let procs = &g.task.procs;
        let born: HashMap<u32, u64> = procs.iter().map(|s| (s.pid, s.created)).collect();
        // parent du groupe ne avant l'enfant : sinon le pid a ete reutilise
        let has_parent = |s: &Sub| s.ppid != s.pid && born.get(&s.ppid).is_some_and(|&c| c <= s.created);
        let parents: HashSet<u32> = procs.iter().filter(|s| has_parent(s)).map(|s| s.ppid).collect();
        let mains: Vec<bool> = procs.iter().map(|s| !has_parent(s) && parents.contains(&s.pid)).collect();
        for (s, m) in g.task.procs.iter_mut().zip(mains) {
            s.main = m;
        }
    }
    let mut list: Vec<Task> = groups
        .into_values()
        .map(|Group { task: mut t, path, .. }| {
            t.cpu = t.cpu.min(100.0);
            t.gpu = t.gpu.min(100.0);
            match &path {
                Some(p) => {
                    t.icon = icons.get(p).cloned().unwrap_or_default();
                    let s = p.to_string_lossy();
                    if t.kind != "app" && s.to_lowercase().starts_with(&windir) {
                        t.kind = "win";
                    }
                    t.label = labels.get(p).cloned().flatten().unwrap_or_default();
                    t.path = s.into_owned();
                }
                // pas de chemin lisible : processus systeme protege
                None if t.kind != "app" => t.kind = "win",
                None => {}
            }
            if t.protected && t.kind != "app" {
                t.kind = "win";
            }
            if t.label.is_empty() {
                t.label = t.name.clone();
            }
            t
        })
        .collect();
    // ordre stable d'un appel a l'autre (l'interface trie ensuite)
    list.sort_by_key(|t| t.name.to_lowercase());
    let cpu = cpu_total.map_or(cpu_sum, |v| v as f32).clamp(0.0, 100.0);
    TasksReport { list, cpu, gpu: gpu_total as f32, disk_active: disk_active as f32, procs, net_down, net_up }
}

/// Onglet cache : libere les compteurs, le tampon et les caches par pid.
pub fn tasks_stop(st: State<Tasks>) {
    *lock(&st.live) = Live::default();
}

fn created_ms(create: i64) -> u64 {
    create.max(0) as u64 / 10_000
}

/// Fin de tache pour tous les processus de ce nom, ou pour le seul `pid`
/// s'il est donne. Les pid sont reutilises : il doit porter toujours ce nom
/// et, si `created` est donne, avoir ete cree a cette heure-la.
pub fn task_kill(_st: State<Tasks>, name: String, pid: Option<u32>, created: Option<u64>) -> KillReport {
    let key = name.to_lowercase();
    let mut r = KillReport { killed: 0, denied: 0 };
    if PROTECTED.contains(&key.as_str()) {
        return r;
    }
    let me = std::process::id();
    // tampon a part : ne pas attendre un `tasks_get` en cours (amorce, icones)
    let procs = snapshot(&mut Vec::new()).unwrap_or_default();
    let wanted = |p: &&Proc| p.pid != 0 && p.pid != me && pid.is_none_or(|w| w == p.pid)
        && created.is_none_or(|c| pid.is_some() && c == created_ms(p.create))
        && base_name(&p.name).to_lowercase() == key;
    for p in procs.iter().filter(wanted) {
        let ok = unsafe {
            match OpenProcess(PROCESS_TERMINATE, false, p.pid) {
                Ok(h) => {
                    let ok = TerminateProcess(h, 1).is_ok();
                    let _ = CloseHandle(h);
                    ok
                }
                Err(_) => false,
            }
        };
        if ok {
            r.killed += 1;
        } else {
            r.denied += 1;
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

    #[test]
    fn groupe_developpe_et_fin_d_un_seul_pid() {
        let spawn = || Command::new("ping").args(["-n", "60", "127.0.0.1"]).creation_flags(CREATE_NO_WINDOW).spawn().unwrap();
        let (mut a, mut b) = (spawn(), spawn());
        let tasks = Tasks::default();
        let r = tasks_get(State::of(&tasks), Some(vec!["PING".into()]));
        let g = r.list.iter().find(|t| t.name.eq_ignore_ascii_case("ping")).expect("groupe ping");
        let pids: Vec<u32> = g.procs.iter().map(|s| s.pid).collect();
        let created = g.procs.iter().find(|s| s.pid == a.id()).unwrap().created;
        assert!(pids.contains(&a.id()) && pids.contains(&b.id()), "{pids:?}");
        // deux ping independants, sans enfant : aucun n'est « principal »
        assert!(g.procs.iter().filter(|s| s.pid == a.id() || s.pid == b.id()).all(|s| !s.main));
        // les autres groupes n'envoient pas de detail
        assert!(r.list.iter().filter(|t| !t.name.eq_ignore_ascii_case("ping")).all(|t| t.procs.is_empty()));
        // un pid qui ne porte pas ce nom n'est pas termine
        let k = task_kill(State::of(&tasks), "notepad".into(), Some(a.id()), Some(created));
        assert_eq!(k.killed, 0);
        // ni un pid d'une autre heure de creation (pid reutilise)
        let k = task_kill(State::of(&tasks), "ping".into(), Some(a.id()), Some(created + 1));
        assert_eq!(k.killed, 0);
        let k = task_kill(State::of(&tasks), "ping".into(), Some(a.id()), Some(created));
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
        for _ in 0..20 {
            let r = tasks_get(State::of(&tasks), Some(vec!["cmd".into()]));
            let g = r.list.into_iter().find(|t| t.name.eq_ignore_ascii_case("cmd")).expect("groupe cmd");
            let o = g.procs.iter().find(|s| s.pid == outer.id()).map(|s| s.main);
            let i = g.procs.iter().find(|s| s.ppid == outer.id()).map(|s| (s.pid, s.main));
            if let (Some(o), Some(i)) = (o, i) {
                found = Some((o, i));
                break;
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        let snap = snapshot(&mut Vec::new()).unwrap_or_default();
        let (outer_main, (inner, inner_main)) = found.expect("cmd imbrique");
        // menage : le ping lance par le cmd interieur, puis les deux cmd
        for p in snap.iter().filter(|p| p.ppid == inner && p.name.eq_ignore_ascii_case("ping.exe")) {
            task_kill(State::of(&tasks), "ping".into(), Some(p.pid), None);
        }
        task_kill(State::of(&tasks), "cmd".into(), Some(inner), None);
        let _ = outer.kill();
        let _ = outer.wait();
        assert!(outer_main, "le cmd exterieur a un enfant cmd : principal");
        assert!(!inner_main, "le cmd interieur a son parent dans le groupe");
    }

    #[test]
    fn nom_sans_exe() {
        assert_eq!(base_name("Chrome.EXE"), "Chrome");
        assert_eq!(base_name("Registry"), "Registry");
        assert_eq!(base_name("é.exe"), "é");
        assert_eq!(base_name("exe"), "exe");
    }
}
