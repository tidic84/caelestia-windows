//! Onglet Taches : processus regroupes par programme, avec les memes chiffres
//! que l'onglet Processus du Gestionnaire des taches (CPU en « utilite »,
//! memoire privee, GPU, sections Applications / arriere-plan / Windows).

use std::collections::{HashMap, HashSet};
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;
use std::time::Instant;

use serde::Serialize;
use sysinfo::{Networks, ProcessRefreshKind, ProcessesToUpdate, System, UpdateKind};
use tauri::State;
use windows::core::{w, BOOL, HSTRING};
use windows::Win32::Foundation::{CloseHandle, HWND, LPARAM};
use windows::Win32::Graphics::Dwm::{DwmGetWindowAttribute, DWMWA_CLOAKED};
use windows::Win32::NetworkManagement::IpHelper::{GetExtendedTcpTable, TCP_TABLE_OWNER_PID_ALL};
use windows::Win32::Networking::WinSock::{AF_INET, AF_INET6};
use windows::Win32::Storage::FileSystem::{GetFileVersionInfoSizeW, GetFileVersionInfoW, VerQueryValueW};
use windows::Win32::System::ProcessStatus::{GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS, PROCESS_MEMORY_COUNTERS_EX2};
use windows::Win32::System::Threading::{OpenProcess, PROCESS_QUERY_LIMITED_INFORMATION};
use windows::Win32::UI::Shell::{IShellItem, SHCreateItemFromParsingName};
use windows::Win32::UI::WindowsAndMessaging::{
    EnumWindows, GetWindow, GetWindowLongW, GetWindowTextLengthW, GetWindowThreadProcessId, IsWindowVisible, GWL_EXSTYLE,
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
    /// % du processeur entier (0-100), en « utilite » comme Windows 11
    cpu: f32,
    /// memoire privee (jeu de travail prive), comme le Gestionnaire des taches
    mem: u64,
    /// lecture + ecriture disque, octets par seconde
    disk: u64,
    /// % du moteur GPU le plus charge
    gpu: f32,
    /// connexions TCP etablies (le debit par processus demanderait ETW / admin)
    net: u32,
    icon: String,
    protected: bool,
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

/// Processus qui ont une vraie fenetre (barre des taches) : la section
/// « Applications » du Gestionnaire des taches.
fn pids_with_window() -> HashSet<u32> {
    unsafe extern "system" fn cb(h: HWND, l: LPARAM) -> BOOL {
        let set = &mut *(l.0 as *mut HashSet<u32>);
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
        set.insert(pid);
        true.into()
    }
    let mut set = HashSet::new();
    unsafe {
        let _ = EnumWindows(Some(cb), LPARAM(&mut set as *mut _ as isize));
    }
    set
}

/// Jeu de travail prive (colonne Memoire du Gestionnaire des taches).
fn private_ws(pid: u32) -> Option<u64> {
    unsafe {
        let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok()?;
        let mut c = PROCESS_MEMORY_COUNTERS_EX2 {
            cb: std::mem::size_of::<PROCESS_MEMORY_COUNTERS_EX2>() as u32,
            ..Default::default()
        };
        let ok = GetProcessMemoryInfo(h, &mut c as *mut _ as *mut PROCESS_MEMORY_COUNTERS, c.cb).is_ok();
        let _ = CloseHandle(h);
        ok.then_some(c.PrivateWorkingSetSize as u64)
    }
}

/// Description du fichier (« Google Chrome » pour chrome.exe), comme Windows.
fn file_description(p: &Path) -> Option<String> {
    unsafe {
        let path = HSTRING::from(p.as_os_str());
        let size = GetFileVersionInfoSizeW(&path, None);
        if size == 0 {
            return None;
        }
        let mut buf = vec![0u8; size as usize];
        GetFileVersionInfoW(&path, None, size, buf.as_mut_ptr() as _).ok()?;
        let mut ptr = std::ptr::null_mut();
        let mut len = 0u32;
        // langue + page de code de la premiere traduction, puis les plus courantes
        let mut subs = Vec::new();
        if VerQueryValueW(buf.as_ptr() as _, w!("\\VarFileInfo\\Translation"), &mut ptr, &mut len).as_bool() && len >= 4 {
            let t = std::slice::from_raw_parts(ptr as *const u16, 2);
            subs.push(format!("\\StringFileInfo\\{:04x}{:04x}\\FileDescription", t[0], t[1]));
        }
        subs.extend(["040904b0", "040904e4", "040c04b0"].map(|l| format!("\\StringFileInfo\\{l}\\FileDescription")));
        for sub in subs {
            if VerQueryValueW(buf.as_ptr() as _, &HSTRING::from(sub), &mut ptr, &mut len).as_bool() && len > 1 {
                let s = String::from_utf16_lossy(std::slice::from_raw_parts(ptr as *const u16, len as usize));
                let s = s.trim_end_matches('\0').trim().to_string();
                if !s.is_empty() {
                    return Some(s);
                }
            }
        }
        None
    }
}

/// Le disque aussi : octets lus/ecrits depuis le dernier appel (d'ou `last`).
#[derive(Default)]
pub struct Tasks {
    sys: Mutex<Option<System>>,
    nets: Mutex<Option<Networks>>,
    pdh: Mutex<Option<crate::pdh::Query>>,
    last: Mutex<Option<Instant>>,
    icons: Mutex<HashMap<PathBuf, String>>,
    labels: Mutex<HashMap<PathBuf, Option<String>>>,
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

#[tauri::command(async)]
pub fn tasks_get(st: State<Tasks>) -> TasksReport {
    // compteurs Windows : CPU (utilite), frequence, disques, GPU
    let (cpu_total, perf, disk_active, gpu_vals) = {
        let mut g = st.pdh.lock().unwrap();
        if g.is_none() {
            *g = crate::pdh::Query::new(&[
                r"\Processor Information(_Total)\% Processor Utility",
                r"\Processor Information(_Total)\% Processor Performance",
                r"\PhysicalDisk(*)\% Idle Time",
                r"\GPU Engine(*)\Utilization Percentage",
            ]);
        }
        match g.as_ref() {
            Some(q) => {
                q.collect();
                let active = q
                    .values(2)
                    .iter()
                    .filter(|(n, _)| n != "_Total")
                    .map(|(_, v)| (100.0 - v).clamp(0.0, 100.0))
                    .fold(0.0, f64::max);
                (q.value(0, "_Total"), q.value(1, "_Total"), active, q.values(3))
            }
            None => (None, None, 0.0, Vec::new()),
        }
    };
    let (gpu_pid, gpu_total) = crate::pdh::gpu_by_pid(&gpu_vals);
    // le CPU par processus suit la frequence reelle (turbo), comme Windows 11
    let boost = perf.map_or(1.0, |p| (p / 100.0).clamp(0.3, 3.0)) as f32;

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
    let windowed = pids_with_window();
    let windir = std::env::var("SystemRoot").unwrap_or_else(|_| r"C:\Windows".into()).to_lowercase();

    // regroupement par nom d'executable
    let mut groups: HashMap<String, (Task, Option<PathBuf>)> = HashMap::new();
    let mut procs = 0;
    let mut cpu_sum = 0.0f32;
    for (pid, p) in sys.processes() {
        let pid = pid.as_u32();
        if pid == 0 {
            continue;
        }
        procs += 1;
        let name = base_name(p.name());
        let key = name.to_lowercase();
        let e = groups.entry(key.clone()).or_insert_with(|| {
            let protected = PROTECTED.contains(&key.as_str());
            let t = Task {
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
                protected,
            };
            (t, None)
        });
        e.0.net += tcp.get(&pid).copied().unwrap_or(0);
        e.0.count += 1;
        let c = p.cpu_usage() / cores * boost;
        cpu_sum += c;
        e.0.cpu += c;
        e.0.mem += private_ws(pid).unwrap_or_else(|| p.memory());
        e.0.gpu = e.0.gpu.max(gpu_pid.get(&pid).copied().unwrap_or(0.0) as f32);
        let du = p.disk_usage();
        e.0.disk += ((du.read_bytes + du.written_bytes) as f64 / secs) as u64;
        if windowed.contains(&pid) {
            e.0.kind = "app";
        }
        if e.1.is_none() {
            e.1 = p.exe().map(|x| x.to_path_buf());
        }
    }
    drop(guard);

    // icones et noms des executables pas encore vus
    let mut icons = st.icons.lock().unwrap();
    let mut labels = st.labels.lock().unwrap();
    let missing: Vec<PathBuf> = groups
        .values()
        .filter_map(|(_, p)| p.clone())
        .filter(|p| !icons.contains_key(p))
        .collect();
    for p in &missing {
        labels.entry(p.clone()).or_insert_with(|| file_description(p));
    }
    if !missing.is_empty() {
        icons.extend(icons_for(missing));
    }
    let list = groups
        .into_values()
        .map(|(mut t, p)| {
            t.cpu = t.cpu.min(100.0);
            t.gpu = t.gpu.min(100.0);
            match &p {
                Some(p) => {
                    t.icon = icons.get(p).cloned().unwrap_or_default();
                    if t.kind != "app" && p.to_string_lossy().to_lowercase().starts_with(&windir) {
                        t.kind = "win";
                    }
                    t.label = labels.get(p).cloned().flatten().unwrap_or_default();
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
    let cpu = cpu_total.map_or(cpu_sum, |v| v as f32).clamp(0.0, 100.0);
    TasksReport { list, cpu, gpu: gpu_total as f32, disk_active: disk_active as f32, procs, net_down, net_up }
}

/// Fin de tache pour tous les processus de ce nom ; renvoie combien ont ete arretes.
#[tauri::command(async)]
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
#[tauri::command]
pub fn taskmgr_open() {
    let _ = Command::new("cmd").args(["/c", "start", "", "taskmgr.exe"]).creation_flags(CREATE_NO_WINDOW).spawn();
}
