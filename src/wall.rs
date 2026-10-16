//! Fonds d'ecran : liste, miniatures (cache disque) et application.

use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};

use serde::Serialize;
use windows::core::{HSTRING, PCWSTR};
use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_ALL};
use windows::Win32::UI::Shell::{DesktopWallpaper, IDesktopWallpaper};
use windows::Win32::UI::WindowsAndMessaging::{
    SystemParametersInfoW, SPIF_SENDCHANGE, SPIF_UPDATEINIFILE, SPI_GETDESKWALLPAPER,
    SPI_SETDESKWALLPAPER, SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS,
};

/// Empreinte rapide d'un fichier (taille + premiers octets) pour reperer
/// les doublons : Windows livre la meme image sous plusieurs noms.
fn fingerprint(p: &Path) -> Option<(u64, u64)> {
    use std::io::Read;
    let len = std::fs::metadata(p).ok()?.len();
    let mut head = vec![0u8; 8192];
    let n = std::fs::File::open(p).ok()?.read(&mut head).ok()?;
    let mut h = std::collections::hash_map::DefaultHasher::new();
    head[..n].hash(&mut h);
    Some((len, h.finish()))
}

const EXTS: &[&str] = &["jpg", "jpeg", "png", "bmp", "webp"];

#[derive(Serialize)]
pub struct Wall {
    path: String,
    thumb: String,
    /// vrai si c'est un fond Wallpaper Engine
    we: bool,
    /// fond Windows actuellement choisi
    cur: bool,
}

/// Dossier personnel des fonds d'ecran (cree au besoin).
pub fn user_dir() -> PathBuf {
    let home = std::env::var("USERPROFILE").unwrap_or_else(|_| ".".into());
    let d = Path::new(&home).join("Pictures").join("Wallpapers");
    let _ = std::fs::create_dir_all(&d);
    d
}

fn cache_dir() -> PathBuf {
    let base = std::env::var("LOCALAPPDATA").unwrap_or_else(|_| ".".into());
    let d = Path::new(&base).join("Ilot").join("thumbs");
    let _ = std::fs::create_dir_all(&d);
    d
}

fn collect(dir: &Path, depth: u32, out: &mut Vec<PathBuf>) {
    let Ok(rd) = std::fs::read_dir(dir) else { return };
    for e in rd.flatten() {
        let p = e.path();
        if p.is_dir() {
            if depth > 0 {
                collect(&p, depth - 1, out);
            }
        } else if p
            .extension()
            .and_then(|x| x.to_str())
            .is_some_and(|x| EXTS.contains(&x.to_lowercase().as_str()))
        {
            out.push(p);
        }
    }
}

/// Miniature JPEG en data URL, mise en cache selon chemin + date de modif.
pub(crate) fn thumb(p: &Path) -> Option<String> {
    thumb_sized(p, 400)
}

pub(crate) fn thumb_sized(p: &Path, size: u32) -> Option<String> {
    let meta = std::fs::metadata(p).ok()?;
    let mut h = std::collections::hash_map::DefaultHasher::new();
    p.hash(&mut h);
    meta.modified().ok().hash(&mut h);
    size.hash(&mut h);
    let cached = cache_dir().join(format!("{:016x}.jpg", h.finish()));
    if !cached.is_file() {
        let img = image::ImageReader::open(p).ok()?.with_guessed_format().ok()?.decode().ok()?;
        let t = img.thumbnail(size, size).to_rgb8();
        let mut out = std::io::Cursor::new(Vec::new());
        t.write_to(&mut out, image::ImageFormat::Jpeg).ok()?;
        let b = out.into_inner();
        if std::fs::write(&cached, &b).is_err() {
            return Some(crate::img::url("image/jpeg", b));
        }
    }
    Some(crate::img::file_url("image/jpeg", cached))
}

fn current_path() -> String {
    let mut buf = [0u16; 520];
    unsafe {
        let _ = SystemParametersInfoW(
            SPI_GETDESKWALLPAPER,
            buf.len() as u32,
            Some(buf.as_mut_ptr() as _),
            SYSTEM_PARAMETERS_INFO_UPDATE_FLAGS(0),
        );
    }
    let n = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
    String::from_utf16_lossy(&buf[..n])
}

#[tauri::command(async)]
pub fn walls_get() -> Vec<Wall> {
    let mut files = Vec::new();
    // le fond actuel d'abord, puis le dossier perso, puis ceux de Windows
    let cur = current_path();
    if !cur.is_empty() && Path::new(&cur).is_file() {
        files.push(PathBuf::from(&cur));
    }
    collect(&user_dir(), 2, &mut files);
    collect(Path::new(r"C:\Windows\Web\Wallpaper"), 2, &mut files);
    let mut seen = std::collections::HashSet::new();
    files.retain(|p| fingerprint(p).is_some_and(|f| seen.insert(f)));
    files
        .iter()
        .filter_map(|p| {
            Some(Wall {
                path: p.to_string_lossy().into_owned(),
                thumb: thumb(p)?,
                we: false,
                cur: p.to_string_lossy().eq_ignore_ascii_case(&cur),
            })
        })
        .collect()
}

#[tauri::command(async)]
pub fn wall_current() -> Option<Wall> {
    // si Wallpaper Engine tourne, c'est son fond qui est visible
    if let Some((path, thumb)) = crate::we::active() {
        return Some(Wall { path, thumb, we: true, cur: true });
    }
    let path = current_path();
    if path.is_empty() {
        return None;
    }
    Some(Wall {
        thumb: thumb(Path::new(&path))?,
        path,
        we: false,
        cur: true,
    })
}

#[tauri::command(async)]
pub fn wall_set(path: String) -> bool {
    // IDesktopWallpaper (comme l'appli Parametres) : Windows fait un fondu.
    // Thread dedie : les threads du runtime async sont deja en MTA.
    let p2 = path.clone();
    let via_shell = std::thread::spawn(move || unsafe {
        crate::com_init_sta();
        CoCreateInstance::<_, IDesktopWallpaper>(&DesktopWallpaper, None, CLSCTX_ALL)
            .and_then(|dw| dw.SetWallpaper(PCWSTR::null(), &HSTRING::from(p2.as_str())))
            .is_ok()
    })
    .join()
    .unwrap_or(false);
    if via_shell {
        return true;
    }
    let wide: Vec<u16> = path.encode_utf16().chain(std::iter::once(0)).collect();
    unsafe {
        SystemParametersInfoW(
            SPI_SETDESKWALLPAPER,
            0,
            Some(PCWSTR(wide.as_ptr()).0 as _),
            SPIF_UPDATEINIFILE | SPIF_SENDCHANGE,
        )
        .is_ok()
    }
}

#[tauri::command(async)]
pub fn walls_open_folder() {
    let _ = std::process::Command::new("explorer.exe").arg(user_dir()).spawn();
}

// ---------------------------------------------------------------- rotation

/// Petit generateur pseudo-aleatoire (pas besoin de crate pour ca).
fn random(n: usize) -> usize {
    let t = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default()
        .as_nanos() as u64;
    let mut x = t ^ 0x9E37_79B9_7F4A_7C15;
    x ^= x << 13;
    x ^= x >> 7;
    x ^= x << 17;
    (x % n.max(1) as u64) as usize
}

/// Passe a un autre fond, au hasard, dans la source visible (Wallpaper
/// Engine s'il tourne, sinon Windows).
#[tauri::command(async)]
pub fn wall_random(app: tauri::AppHandle) -> bool {
    use tauri::Emitter;
    let ok = if crate::we::install_dir().is_some() && crate::we::running() {
        let cur = crate::we::we_state().current;
        let list: Vec<String> = crate::we::we_walls()
            .into_iter()
            .map(|w| w.path().to_string())
            .filter(|p| !p.eq_ignore_ascii_case(&cur))
            .collect();
        !list.is_empty() && crate::we::we_set(list[random(list.len())].clone())
    } else {
        let list: Vec<String> = walls_get().into_iter().filter(|w| !w.cur).map(|w| w.path).collect();
        !list.is_empty() && wall_set(list[random(list.len())].clone())
    };
    if ok {
        // Wallpaper Engine met un instant a charger le fond
        std::thread::sleep(std::time::Duration::from_millis(900));
        let _ = app.emit("wall-changed", ());
    }
    ok
}

/// Change de fond toutes les `rotate_min` minutes (0 = jamais).
pub fn watch_rotation(app: tauri::AppHandle) {
    use tauri::Manager;
    std::thread::spawn(move || {
        let mut elapsed = 0u32;
        loop {
            std::thread::sleep(std::time::Duration::from_secs(60));
            let every = app.state::<crate::settings::Settings>().0.lock().unwrap().rotate_min;
            if every == 0 {
                elapsed = 0;
                continue;
            }
            elapsed += 1;
            if elapsed >= every {
                elapsed = 0;
                wall_random(app.clone());
            }
        }
    });
}
