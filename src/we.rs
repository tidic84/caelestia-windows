//! Compatibilite Wallpaper Engine : liste des fonds (Workshop + projets
//! locaux), fond actif, application via la ligne de commande officielle
//! (`-control openWallpaper`) et suivi des changements faits dans WE.

use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::time::{Duration, SystemTime};

use serde::Serialize;
use sysinfo::{ProcessesToUpdate, System};
use tauri::{AppHandle, Emitter};
use windows::core::w;
use windows::Win32::System::Registry::{RegGetValueW, HKEY_CURRENT_USER, RRF_RT_REG_SZ};

const CREATE_NO_WINDOW: u32 = 0x0800_0000;
const APP_ID: &str = "431960";

#[derive(Serialize)]
pub struct WeWall {
    /// dossier du projet
    path: String,
    thumb: String,
    title: String,
    /// scene, video, web...
    kind: String,
}

impl WeWall {
    pub fn thumb_is_empty(&self) -> bool {
        self.thumb.is_empty()
    }
    pub fn summary(&self) -> String {
        format!("{} [{}] {} (miniature {} o)", self.title, self.kind, self.path, self.thumb.len())
    }
}

fn steam_dir() -> PathBuf {
    let mut buf = [0u16; 520];
    let mut len = (buf.len() * 2) as u32;
    let r = unsafe {
        RegGetValueW(
            HKEY_CURRENT_USER,
            w!(r"Software\Valve\Steam"),
            w!("SteamPath"),
            RRF_RT_REG_SZ,
            None,
            Some(buf.as_mut_ptr() as _),
            Some(&mut len),
        )
    };
    if r.is_ok() {
        let n = buf.iter().position(|&c| c == 0).unwrap_or(0);
        let s = String::from_utf16_lossy(&buf[..n]).replace('/', "\\");
        if !s.is_empty() {
            return PathBuf::from(s);
        }
    }
    PathBuf::from(r"C:\Program Files (x86)\Steam")
}

/// Bibliotheques Steam (libraryfolders.vdf), bibliotheque principale incluse.
fn libraries() -> Vec<PathBuf> {
    let steam = steam_dir();
    let mut libs = vec![steam.clone()];
    if let Ok(vdf) = std::fs::read_to_string(steam.join(r"steamapps\libraryfolders.vdf")) {
        for line in vdf.lines() {
            let parts: Vec<&str> = line.split('"').filter(|s| !s.trim().is_empty()).collect();
            if parts.len() == 2 && parts[0] == "path" {
                let p = PathBuf::from(parts[1].replace("\\\\", "\\"));
                if !libs.iter().any(|l| same(l, &p)) {
                    libs.push(p);
                }
            }
        }
    }
    libs
}

fn same(a: &Path, b: &Path) -> bool {
    norm(&a.to_string_lossy()) == norm(&b.to_string_lossy())
}

fn norm(s: &str) -> String {
    s.replace('/', "\\").trim_end_matches('\\').to_lowercase()
}

/// Dossier d'installation de Wallpaper Engine, s'il existe.
pub fn install_dir() -> Option<PathBuf> {
    libraries()
        .into_iter()
        .map(|l| l.join(r"steamapps\common\wallpaper_engine"))
        .find(|d| d.join("config.json").is_file())
}

fn project_dirs(install: &Path) -> Vec<PathBuf> {
    let mut roots: Vec<PathBuf> = libraries()
        .into_iter()
        .map(|l| l.join(r"steamapps\workshop\content").join(APP_ID))
        .collect();
    roots.push(install.join(r"projects\myprojects"));
    roots.push(install.join(r"projects\defaultprojects"));
    let mut out = Vec::new();
    for root in roots {
        let Ok(rd) = std::fs::read_dir(&root) else { continue };
        for e in rd.flatten() {
            let p = e.path();
            if p.join("project.json").is_file() {
                out.push(p);
            }
        }
    }
    out
}

fn read_json(p: &Path) -> Option<serde_json::Value> {
    let raw = std::fs::read_to_string(p).ok()?;
    serde_json::from_str(raw.trim_start_matches('\u{feff}')).ok()
}

fn project(dir: &Path) -> Option<WeWall> {
    let j = read_json(&dir.join("project.json"))?;
    let preview = j.get("preview").and_then(|v| v.as_str()).unwrap_or("preview.jpg");
    Some(WeWall {
        path: dir.to_string_lossy().into_owned(),
        thumb: crate::wall::thumb(&dir.join(preview)).unwrap_or_default(),
        title: j.get("title").and_then(|v| v.as_str()).unwrap_or("Sans titre").trim().to_string(),
        kind: j.get("type").and_then(|v| v.as_str()).unwrap_or("").to_lowercase(),
    })
}

/// Dossier du fond affiche sur l'ecran 0, d'apres config.json.
fn current_dir(install: &Path) -> Option<PathBuf> {
    let cfg = read_json(&install.join("config.json"))?;
    for (_, user) in cfg.as_object()? {
        let file = user
            .pointer("/general/wallpaperconfig/selectedwallpapers/Monitor0/file")
            .and_then(|v| v.as_str());
        if let Some(f) = file {
            return Path::new(&f.replace('/', "\\")).parent().map(|p| p.to_path_buf());
        }
    }
    None
}

pub fn running() -> bool {
    let mut sys = System::new();
    sys.refresh_processes(ProcessesToUpdate::All, true);
    sys.processes().values().any(|p| {
        let n = p.name().to_string_lossy().to_lowercase();
        n == "wallpaper32.exe" || n == "wallpaper64.exe"
    })
}

/// Fond WE actif, seulement si Wallpaper Engine tourne (sinon c'est le fond
/// Windows qu'on voit).
pub fn active() -> Option<(String, String)> {
    let install = install_dir()?;
    if !running() {
        return None;
    }
    let w = project(&current_dir(&install)?)?;
    Some((w.path, w.thumb))
}

#[derive(Serialize)]
pub struct WeState {
    installed: bool,
    running: bool,
    current: String,
}

#[tauri::command(async)]
pub fn we_state() -> WeState {
    match install_dir() {
        Some(i) => WeState {
            installed: true,
            running: running(),
            current: current_dir(&i).map(|p| p.to_string_lossy().into_owned()).unwrap_or_default(),
        },
        None => WeState { installed: false, running: false, current: String::new() },
    }
}

#[tauri::command(async)]
pub fn we_walls() -> Vec<WeWall> {
    let Some(install) = install_dir() else { return Vec::new() };
    let mut list: Vec<WeWall> = project_dirs(&install).iter().filter_map(|d| project(d)).collect();
    list.sort_by_key(|w| w.title.to_lowercase());
    list
}

#[tauri::command(async)]
pub fn we_set(path: String) -> bool {
    let Some(install) = install_dir() else { return false };
    // l'executable choisi dans les reglages de WE (32 bits par defaut)
    let x64 = read_json(&install.join("config.json"))
        .map(|c| c.to_string().contains("\"autostartx64\":true"))
        .unwrap_or(false);
    let exe = install.join(if x64 { "wallpaper64.exe" } else { "wallpaper32.exe" });
    Command::new(exe)
        .args(["-control", "openWallpaper", "-file"])
        .arg(Path::new(&path).join("project.json"))
        .args(["-monitor", "0"])
        .creation_flags(CREATE_NO_WINDOW)
        .spawn()
        .is_ok()
}

/// Previent l'interface (`wall-changed`) quand le fond change dans WE ou
/// quand WE demarre / s'arrete.
pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        let Some(install) = install_dir() else { return };
        let cfg = install.join("config.json");
        let mut last: (Option<SystemTime>, bool) = (None, false);
        loop {
            let m = std::fs::metadata(&cfg).and_then(|m| m.modified()).ok();
            let now = (m, running());
            if last.0.is_some() && now != last {
                let _ = app.emit("wall-changed", ());
            }
            last = now;
            std::thread::sleep(Duration::from_secs(2));
        }
    });
}
