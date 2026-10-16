//! Onglet Taches : processus regroupes par programme (comme l'onglet
//! Processus du Gestionnaire des taches), avec CPU, memoire et fin de tache.

use std::collections::HashMap;
use std::os::windows::process::CommandExt;
use std::path::PathBuf;
use std::process::Command;
use std::sync::Mutex;
use std::time::Instant;

use serde::Serialize;
use sysinfo::{Networks, ProcessRefreshKind, ProcessesToUpdate, System, UpdateKind};
use crate::host::State;
use windows::core::HSTRING;
use windows::Win32::NetworkManagement::IpHelper::{GetExtendedTcpTable, TCP_TABLE_OWNER_PID_ALL};
use windows::Win32::Networking::WinSock::{AF_INET, AF_INET6};
use windows::Win32::UI::Shell::{IShellItem, SHCreateItemFromParsingName};

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// Processus vitaux de Windows : jamais de fin de tache depuis l'ilot.
const PROTECTED: &[&str] = &[
    "system", "registry", "smss", "csrss", "wininit", "winlogon", "services", "lsass",
    "svchost", "dwm", "fontdrvhost", "memory compression", "secure system", "lsaiso",
    "sihost", "ctfmon", "audiodg", "ilot",
];

#[derive(Serialize)]
pub struct Task {
    /// nom de l'executable sans .exe
    name: String,
    count: usize,
    /// % du processeur entier (0-100)
    cpu: f32,
    /// octets
    mem: u64,
    /// lecture + ecriture disque, octets par seconde
    disk: u64,
    /// connexions TCP etablies (le debit par processus demanderait ETW / admin)
    net: u32,
    icon: String,
    protected: bool,
}

/// Garde le `System` entre deux appels : sysinfo calcule le CPU par difference.
#[derive(Serialize)]
pub struct TasksReport {
    list: Vec<Task>,
    /// debit reseau total (toutes cartes), octets par seconde
    net_down: u64,
    net_up: u64,
}

/// Connexions TCP etablies par processus (IPv4 + IPv6).
fn tcp_by_pid() -> HashMap<u32, u32> {
    let mut out = HashMap::new();
    // (famille, taille d'une ligne, decalage de l'etat, decalage du pid)
    for (af, row, st_off, pid_off) in [(AF_INET.0 as u32, 24usize, 0usize, 20usize), (AF_INET6.0 as u32, 56, 48, 52)] {
        let mut size = 0u32;
        unsafe {
            GetExtendedTcpTable(None, &mut size, false, af, TCP_TABLE_OWNER_PID_ALL, 0);
            let mut buf = vec![0u8; size as usize + 1024];
            size = buf.len() as u32;
            if GetExtendedTcpTable(Some(buf.as_mut_ptr() as _), &mut size, false, af, TCP_TABLE_OWNER_PID_ALL, 0) != 0 {
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
    }
    out
}

/// Le disque aussi : octets lus/ecrits depuis le dernier appel (d'ou `last`).
#[derive(Default)]
pub struct Tasks {
    sys: Mutex<Option<System>>,
    nets: Mutex<Option<Networks>>,
    last: Mutex<Option<Instant>>,
    icons: Mutex<HashMap<PathBuf, String>>,
}

fn base_name(n: &std::ffi::OsStr) -> String {
    let s = n.to_string_lossy();
    s.strip_suffix(".exe").or(s.strip_suffix(".EXE")).unwrap_or(&s).to_string()
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

pub fn tasks_get(st: State<Tasks>) -> TasksReport {
    let mut guard = st.sys.lock().unwrap();
    let sys = guard.get_or_insert_with(System::new);
    sys.refresh_processes_specifics(
        ProcessesToUpdate::All,
        true,
        ProcessRefreshKind::nothing().with_cpu().with_memory().with_disk_usage().with_exe(UpdateKind::OnlyIfNotSet),
    );
    let cores = std::thread::available_parallelism().map_or(1, |n| n.get()) as f32;
    let secs = {
        let mut last = st.last.lock().unwrap();
        let s = last.map_or(1.0, |t| t.elapsed().as_secs_f64().max(0.2));
        *last = Some(Instant::now());
        s
    };
    let (net_down, net_up) = {
        let mut g = st.nets.lock().unwrap();
        let nets = g.get_or_insert_with(Networks::new_with_refreshed_list);
        nets.refresh(true);
        nets.values().fold((0, 0), |(d, u), n| {
            (d + (n.received() as f64 / secs) as u64, u + (n.transmitted() as f64 / secs) as u64)
        })
    };
    let tcp = tcp_by_pid();

    // regroupement par nom d'executable
    let mut groups: HashMap<String, (Task, Option<PathBuf>)> = HashMap::new();
    for (pid, p) in sys.processes() {
        if pid.as_u32() == 0 {
            continue;
        }
        let name = base_name(p.name());
        let key = name.to_lowercase();
        let e = groups.entry(key.clone()).or_insert_with(|| {
            let protected = PROTECTED.contains(&key.as_str());
            (Task { name, count: 0, cpu: 0.0, mem: 0, disk: 0, net: 0, icon: String::new(), protected }, None)
        });
        e.0.net += tcp.get(&pid.as_u32()).copied().unwrap_or(0);
        e.0.count += 1;
        e.0.cpu += p.cpu_usage() / cores;
        e.0.mem += p.memory();
        let du = p.disk_usage();
        e.0.disk += ((du.read_bytes + du.written_bytes) as f64 / secs) as u64;
        if e.1.is_none() {
            e.1 = p.exe().map(|x| x.to_path_buf());
        }
    }
    drop(guard);

    // icones des executables pas encore vus
    let mut icons = st.icons.lock().unwrap();
    let missing: Vec<PathBuf> = groups
        .values()
        .filter_map(|(_, p)| p.clone())
        .filter(|p| !icons.contains_key(p))
        .collect();
    if !missing.is_empty() {
        icons.extend(icons_for(missing));
    }
    let list = groups
        .into_values()
        .map(|(mut t, p)| {
            t.cpu = t.cpu.min(100.0);
            if let Some(p) = p {
                t.icon = icons.get(&p).cloned().unwrap_or_default();
            }
            t
        })
        .collect();
    TasksReport { list, net_down, net_up }
}

/// Fin de tache pour tous les processus de ce nom ; renvoie combien ont ete arretes.
pub fn task_kill(st: State<Tasks>, name: String) -> usize {
    let key = name.to_lowercase();
    if PROTECTED.contains(&key.as_str()) {
        return 0;
    }
    let mut guard = st.sys.lock().unwrap();
    let sys = guard.get_or_insert_with(System::new);
    sys.refresh_processes(ProcessesToUpdate::All, true);
    sys.processes()
        .values()
        .filter(|p| base_name(p.name()).to_lowercase() == key)
        .filter(|p| p.kill())
        .count()
}

/// Ouvre le vrai Gestionnaire des taches de Windows.
pub fn taskmgr_open() {
    let _ = Command::new("cmd").args(["/c", "start", "", "taskmgr.exe"]).creation_flags(CREATE_NO_WINDOW).spawn();
}
