//! Sante du PC (onglet PC) : espace libre et etat des disques, nettoyage en un
//! clic (fichiers temporaires, caches de shaders, corbeille) et pilote NVIDIA
//! a jour ou non. Une alerte (`disk-low`) part quand un disque passe sous 10 %.

use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;
use std::time::{Duration, Instant};

use serde::Serialize;
use sysinfo::Disks;
use crate::host::AppHandle;
use windows::core::PCWSTR;
use windows::Win32::UI::Shell::{
    SHEmptyRecycleBinW, SHQueryRecycleBinW, SHERB_NOCONFIRMATION, SHERB_NOPROGRESSUI, SHERB_NOSOUND, SHQUERYRBINFO,
};

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

#[derive(Serialize, Clone)]
pub struct Disk {
    /// « C: »
    mount: String,
    /// nom du volume, sinon modele du disque
    name: String,
    total: u64,
    free: u64,
    /// « Healthy », « Warning », « Unhealthy » ou vide si inconnu
    health: String,
    /// SSD / HDD / vide
    media: String,
}

#[derive(Serialize, Clone)]
pub struct CleanItem {
    id: &'static str,
    label: &'static str,
    bytes: u64,
}

#[derive(Serialize, Clone, Default)]
pub struct Driver {
    gpu: String,
    installed: String,
    /// derniere version Game Ready publiee (vide si inconnue)
    latest: String,
}

#[derive(Serialize)]
pub struct Health {
    disks: Vec<Disk>,
    clean: Vec<CleanItem>,
    driver: Driver,
}

fn env_path(var: &str, rest: &str) -> Option<PathBuf> {
    std::env::var(var).ok().map(|b| Path::new(&b).join(rest))
}

/// Dossiers vides par le nettoyage : (id, libelle, dossiers).
fn clean_dirs() -> Vec<(&'static str, &'static str, Vec<PathBuf>)> {
    let some = |v: Vec<Option<PathBuf>>| v.into_iter().flatten().filter(|p| p.is_dir()).collect::<Vec<_>>();
    vec![
        ("temp", "Fichiers temporaires", some(vec![std::env::var("TEMP").ok().map(PathBuf::from), env_path("SystemRoot", "Temp")])),
        (
            "shaders",
            "Caches de shaders (GPU)",
            some(vec![
                env_path("LOCALAPPDATA", "D3DSCache"),
                env_path("LOCALAPPDATA", "NVIDIA\\DXCache"),
                env_path("LOCALAPPDATA", "NVIDIA\\GLCache"),
                env_path("LOCALAPPDATA", "AMD\\DxCache"),
                env_path("LOCALAPPDATA", "AMD\\DxcCache"),
                env_path("LOCALAPPDATA", "AMD\\GLCache"),
            ]),
        ),
        (
            "thumbs",
            "Miniatures de l'Explorateur",
            some(vec![env_path("LOCALAPPDATA", "Microsoft\\Windows\\Explorer")]),
        ),
    ]
}

/// Taille d'un dossier (recursif, liens ignores).
fn dir_size(p: &Path) -> u64 {
    let Ok(rd) = std::fs::read_dir(p) else { return 0 };
    rd.flatten()
        .map(|e| match e.file_type() {
            Ok(t) if t.is_dir() => dir_size(&e.path()),
            Ok(t) if t.is_file() => e.metadata().map_or(0, |m| m.len()),
            _ => 0,
        })
        .sum()
}

/// Vide le contenu d'un dossier ; les fichiers en cours d'utilisation restent.
/// Pour les miniatures, seuls les thumbcache_*.db / iconcache_*.db partent.
fn empty_dir(p: &Path, only_db: bool) {
    let Ok(rd) = std::fs::read_dir(p) else { return };
    for e in rd.flatten() {
        let path = e.path();
        match e.file_type() {
            Ok(t) if t.is_dir() && !only_db => {
                empty_dir(&path, false);
                let _ = std::fs::remove_dir(&path);
            }
            Ok(t) if t.is_file() => {
                let n = e.file_name().to_string_lossy().to_lowercase();
                if !only_db || (n.ends_with(".db") && (n.starts_with("thumbcache_") || n.starts_with("iconcache_"))) {
                    let _ = std::fs::remove_file(&path);
                }
            }
            _ => {}
        }
    }
}

fn thumbs_size(p: &Path) -> u64 {
    let Ok(rd) = std::fs::read_dir(p) else { return 0 };
    rd.flatten()
        .filter(|e| {
            let n = e.file_name().to_string_lossy().to_lowercase();
            n.ends_with(".db") && (n.starts_with("thumbcache_") || n.starts_with("iconcache_"))
        })
        .map(|e| e.metadata().map_or(0, |m| m.len()))
        .sum()
}

fn recycle_size() -> u64 {
    let mut info = SHQUERYRBINFO { cbSize: std::mem::size_of::<SHQUERYRBINFO>() as u32, ..Default::default() };
    unsafe { SHQueryRecycleBinW(PCWSTR::null(), &mut info) }.map_or(0, |_| info.i64Size.max(0) as u64)
}

fn clean_items() -> Vec<CleanItem> {
    let mut out: Vec<CleanItem> = clean_dirs()
        .into_iter()
        .map(|(id, label, dirs)| {
            let bytes = dirs.iter().map(|d| if id == "thumbs" { thumbs_size(d) } else { dir_size(d) }).sum();
            CleanItem { id, label, bytes }
        })
        .collect();
    out.push(CleanItem { id: "recycle", label: "Corbeille", bytes: recycle_size() });
    out
}

/// Etat des disques physiques par lettre de lecteur (PowerShell, sans droits admin).
fn physical() -> Vec<(String, String, String, String)> {
    let script = "Get-Partition | ? DriveLetter | % { $d = Get-PhysicalDisk -DeviceNumber $_.DiskNumber -EA SilentlyContinue; \
                  \"$($_.DriveLetter)|$($d.FriendlyName)|$($d.HealthStatus)|$($d.MediaType)\" }";
    let Ok(o) = Command::new("powershell")
        .args(["-NoProfile", "-NonInteractive", "-Command", script])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
    else {
        return Vec::new();
    };
    String::from_utf8_lossy(&o.stdout)
        .lines()
        .filter_map(|l| {
            let v: Vec<&str> = l.trim().split('|').collect();
            (v.len() == 4).then(|| (format!("{}:", v[0]), v[1].into(), v[2].into(), v[3].into()))
        })
        .collect()
}

static PHYS: Mutex<Option<(Instant, Vec<(String, String, String, String)>)>> = Mutex::new(None);

fn disks() -> Vec<Disk> {
    let phys = {
        let mut c = PHYS.lock().unwrap();
        match &*c {
            Some((t, v)) if t.elapsed() < Duration::from_secs(600) => v.clone(),
            _ => {
                let v = physical();
                *c = Some((Instant::now(), v.clone()));
                v
            }
        }
    };
    let mut out: Vec<Disk> = Disks::new_with_refreshed_list()
        .iter()
        .filter(|d| d.total_space() > 0)
        .map(|d| {
            let mount = d.mount_point().to_string_lossy().trim_end_matches('\\').to_string();
            let p = phys.iter().find(|p| p.0.eq_ignore_ascii_case(&mount));
            let label = d.name().to_string_lossy().to_string();
            Disk {
                name: if label.is_empty() { p.map(|p| p.1.clone()).unwrap_or_default() } else { label },
                total: d.total_space(),
                free: d.available_space(),
                health: p.map(|p| p.2.clone()).unwrap_or_default(),
                media: p.map(|p| p.3.clone()).filter(|m| m == "SSD" || m == "HDD").unwrap_or_default(),
                mount,
            }
        })
        .collect();
    out.sort_by(|a, b| a.mount.cmp(&b.mount));
    out
}

/// Pilote NVIDIA installe (nvidia-smi) et dernier Game Ready publie.
fn driver() -> Driver {
    static CACHE: Mutex<Option<(Instant, Driver)>> = Mutex::new(None);
    if let Some((t, d)) = &*CACHE.lock().unwrap() {
        if t.elapsed() < Duration::from_secs(6 * 3600) {
            return d.clone();
        }
    }
    let mut d = Driver::default();
    if let Ok(o) = Command::new("nvidia-smi")
        .args(["--query-gpu=name,driver_version", "--format=csv,noheader"])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
    {
        let s = String::from_utf8_lossy(&o.stdout);
        if let Some((n, v)) = s.lines().next().and_then(|l| l.split_once(',')) {
            d.gpu = n.trim().to_string();
            d.installed = v.trim().to_string();
        }
    }
    if !d.installed.is_empty() {
        // le meme pilote Game Ready sert a toutes les GeForce recentes (famille RTX 30 ici)
        let url = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php\
                   ?func=DriverManualLookup&psid=120&pfid=930&osID=57&languageCode=1033&isWHQL=1&dch=1&sort1=0&numberOfResults=1";
        if let Ok(v) = crate::http().get(url).timeout(Duration::from_secs(8)).call().and_then(|r| Ok(r.into_json::<serde_json::Value>()?)) {
            d.latest = v["IDS"][0]["downloadInfo"]["Version"].as_str().unwrap_or_default().to_string();
        }
        *CACHE.lock().unwrap() = Some((Instant::now(), d.clone()));
    }
    d
}

pub fn health_get() -> Health {
    Health { disks: disks(), clean: clean_items(), driver: driver() }
}

/// Nettoie les elements choisis ; renvoie les octets liberes.
pub fn health_clean(ids: Vec<String>) -> u64 {
    let before: u64 = clean_items().iter().filter(|c| ids.iter().any(|i| i == c.id)).map(|c| c.bytes).sum();
    for (id, _, dirs) in clean_dirs() {
        if ids.iter().any(|i| i == id) {
            for d in dirs {
                empty_dir(&d, id == "thumbs");
            }
        }
    }
    if ids.iter().any(|i| i == "recycle") {
        unsafe {
            let _ = SHEmptyRecycleBinW(None, PCWSTR::null(), SHERB_NOCONFIRMATION | SHERB_NOPROGRESSUI | SHERB_NOSOUND);
        }
    }
    let after: u64 = clean_items().iter().filter(|c| ids.iter().any(|i| i == c.id)).map(|c| c.bytes).sum();
    before.saturating_sub(after)
}

#[derive(Serialize, Clone)]
struct DiskLow {
    mount: String,
    free: u64,
    total: u64,
}

/// Toutes les 15 min : alerte quand un disque passe sous 10 % libres
/// (une fois par disque, de nouveau s'il remonte au-dessus de 12 %).
pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        let mut warned: Vec<String> = Vec::new();
        std::thread::sleep(Duration::from_secs(60));
        loop {
            for d in Disks::new_with_refreshed_list().iter().filter(|d| d.total_space() > 0 && !d.is_removable()) {
                let mount = d.mount_point().to_string_lossy().trim_end_matches('\\').to_string();
                let ratio = d.available_space() as f64 / d.total_space() as f64;
                let was = warned.contains(&mount);
                if ratio < 0.10 && !was {
                    warned.push(mount.clone());
                    let _ = app.emit("disk-low", DiskLow { mount, free: d.available_space(), total: d.total_space() });
                } else if ratio > 0.12 && was {
                    warned.retain(|m| m != &mount);
                }
            }
            std::thread::sleep(Duration::from_secs(15 * 60));
        }
    });
}

/// Secondes depuis la derniere action clavier / souris.
pub fn idle_secs() -> u64 {
    use windows::Win32::System::SystemInformation::GetTickCount;
    use windows::Win32::UI::Input::KeyboardAndMouse::{GetLastInputInfo, LASTINPUTINFO};
    let mut li = LASTINPUTINFO { cbSize: std::mem::size_of::<LASTINPUTINFO>() as u32, dwTime: 0 };
    if !unsafe { GetLastInputInfo(&mut li) }.as_bool() {
        return 0;
    }
    (unsafe { GetTickCount() }.wrapping_sub(li.dwTime) / 1000) as u64
}
