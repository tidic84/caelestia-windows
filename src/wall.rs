//! Fonds d'ecran : liste, miniatures (cache disque) et application.

use std::hash::{Hash, Hasher};
use std::path::{Path, PathBuf};

use base64::Engine;
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
    let meta = std::fs::metadata(p).ok()?;
    let mut h = std::collections::hash_map::DefaultHasher::new();
    p.hash(&mut h);
    meta.modified().ok().hash(&mut h);
    let cached = cache_dir().join(format!("{:016x}.jpg", h.finish()));
    let bytes = match std::fs::read(&cached) {
        Ok(b) => b,
        Err(_) => {
            let img = image::ImageReader::open(p).ok()?.with_guessed_format().ok()?.decode().ok()?;
            let t = img.thumbnail(400, 400).to_rgb8();
            let mut out = std::io::Cursor::new(Vec::new());
            t.write_to(&mut out, image::ImageFormat::Jpeg).ok()?;
            let b = out.into_inner();
            let _ = std::fs::write(&cached, &b);
            b
        }
    };
    Some(format!(
        "data:image/jpeg;base64,{}",
        base64::engine::general_purpose::STANDARD.encode(bytes)
    ))
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
