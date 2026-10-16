//! Fichiers deposes sur l'ilot : conversion d'image (PNG <-> JPG), reduction
//! de taille, compression en .zip, copie dans le presse-papiers (a coller dans
//! Discord). Les resultats sont crees a cote du fichier d'origine.

use std::io::BufWriter;
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

use image::codecs::jpeg::JpegEncoder;
use image::{DynamicImage, ExtendedColorType, GenericImageView, ImageFormat};
use windows::Win32::Foundation::{HANDLE, POINT};
use windows::Win32::System::DataExchange::{CloseClipboard, EmptyClipboard, OpenClipboard, SetClipboardData};
use windows::Win32::System::Memory::{GlobalAlloc, GlobalLock, GlobalUnlock, GMEM_MOVEABLE};
use windows::Win32::UI::Shell::DROPFILES;

const CREATE_NO_WINDOW: u32 = 0x0800_0000;
const CF_HDROP: u32 = 15;
/// cote la plus longue d'une image reduite
const SHRINK_MAX: u32 = 1920;

/// `dossier\nom (suffixe).ext`, numerote s'il existe deja.
fn out_path(src: &Path, suffix: &str, ext: &str) -> PathBuf {
    let dir = src.parent().unwrap_or(Path::new("."));
    let stem = src.file_stem().map(|s| s.to_string_lossy().to_string()).unwrap_or_else(|| "fichier".into());
    let base = if suffix.is_empty() { stem } else { format!("{stem} ({suffix})") };
    let mut p = dir.join(format!("{base}.{ext}"));
    let mut n = 2;
    while p.exists() {
        p = dir.join(format!("{base} {n}.{ext}"));
        n += 1;
    }
    p
}

/// JPEG qualite 85 ; la transparence est posee sur du blanc.
fn save_jpeg(img: &DynamicImage, to: &Path) -> Result<(), String> {
    let mut rgb = image::RgbImage::new(img.width(), img.height());
    for (x, y, px) in img.to_rgba8().enumerate_pixels() {
        let a = px[3] as u32;
        let blend = |c: u8| ((c as u32 * a + 255 * (255 - a)) / 255) as u8;
        rgb.put_pixel(x, y, image::Rgb([blend(px[0]), blend(px[1]), blend(px[2])]));
    }
    let f = std::fs::File::create(to).map_err(|e| e.to_string())?;
    JpegEncoder::new_with_quality(BufWriter::new(f), 85)
        .encode(rgb.as_raw(), rgb.width(), rgb.height(), ExtendedColorType::Rgb8)
        .map_err(|e| e.to_string())
}

fn open(path: &str) -> Result<DynamicImage, String> {
    image::open(path).map_err(|e| format!("Image illisible : {e}"))
}

/// PNG <-> JPG (`to` : « jpg » ou « png »). Renvoie le chemin cree.
pub fn img_convert(path: String, to: String) -> Result<String, String> {
    let img = open(&path)?;
    let src = Path::new(&path);
    let out = if to == "jpg" {
        let p = out_path(src, "", "jpg");
        save_jpeg(&img, &p)?;
        p
    } else {
        let p = out_path(src, "", "png");
        img.save_with_format(&p, ImageFormat::Png).map_err(|e| e.to_string())?;
        p
    };
    Ok(out.to_string_lossy().to_string())
}

/// Image reduite (1920 px maxi) et compressee ; garde le PNG si l'image a de
/// la transparence, sinon JPEG.
pub fn img_shrink(path: String) -> Result<String, String> {
    let img = open(&path)?;
    let (w, h) = img.dimensions();
    let img = if w.max(h) > SHRINK_MAX { img.resize(SHRINK_MAX, SHRINK_MAX, image::imageops::FilterType::Lanczos3) } else { img };
    let alpha = img.color().has_alpha() && img.to_rgba8().pixels().any(|p| p[3] < 255);
    let src = Path::new(&path);
    let out = if alpha {
        let p = out_path(src, "réduite", "png");
        img.save_with_format(&p, ImageFormat::Png).map_err(|e| e.to_string())?;
        p
    } else {
        let p = out_path(src, "réduite", "jpg");
        save_jpeg(&img, &p)?;
        p
    };
    Ok(out.to_string_lossy().to_string())
}

/// Archive .zip (tar.exe de Windows) a cote du premier element.
pub fn zip_files(paths: Vec<String>) -> Result<String, String> {
    let first = Path::new(paths.first().ok_or("Aucun fichier")?);
    let out = if paths.len() == 1 { out_path(first, "", "zip") } else { out_path(&first.with_file_name("Archive"), "", "zip") };
    let mut cmd = Command::new("tar.exe");
    cmd.arg("-a").arg("-cf").arg(&out).creation_flags(CREATE_NO_WINDOW);
    // chaque element est ajoute depuis son dossier : l'archive n'a pas les chemins complets
    for p in &paths {
        let p = Path::new(p);
        let (Some(dir), Some(name)) = (p.parent(), p.file_name()) else { continue };
        cmd.arg("-C").arg(dir).arg(name);
    }
    let st = cmd.output().map_err(|e| e.to_string())?;
    if !st.status.success() || !out.exists() {
        return Err(String::from_utf8_lossy(&st.stderr).trim().to_string());
    }
    Ok(out.to_string_lossy().to_string())
}

/// Met les fichiers dans le presse-papiers, comme « Copier » dans l'Explorateur
/// (on peut ensuite les coller dans Discord avec Ctrl+V).
pub fn files_copy(paths: Vec<String>) -> bool {
    // DROPFILES puis les chemins UTF-16, chacun termine par 0, et un 0 final
    let mut list: Vec<u16> = Vec::new();
    for p in &paths {
        list.extend(p.encode_utf16());
        list.push(0);
    }
    list.push(0);
    let head = std::mem::size_of::<DROPFILES>();
    let size = head + list.len() * 2;
    unsafe {
        // le presse-papiers peut etre occupe un instant par une autre appli
        let mut opened = false;
        for _ in 0..10 {
            if OpenClipboard(None).is_ok() {
                opened = true;
                break;
            }
            std::thread::sleep(std::time::Duration::from_millis(30));
        }
        if !opened {
            return false;
        }
        let ok = (|| {
            let mem = GlobalAlloc(GMEM_MOVEABLE, size).ok()?;
            let ptr = GlobalLock(mem) as *mut u8;
            if ptr.is_null() {
                return None;
            }
            let df = DROPFILES { pFiles: head as u32, pt: POINT::default(), fNC: false.into(), fWide: true.into() };
            std::ptr::write_unaligned(ptr as *mut DROPFILES, df);
            std::ptr::copy_nonoverlapping(list.as_ptr() as *const u8, ptr.add(head), list.len() * 2);
            let _ = GlobalUnlock(mem);
            EmptyClipboard().ok()?;
            SetClipboardData(CF_HDROP, Some(HANDLE(mem.0))).ok()?;
            Some(())
        })()
        .is_some();
        let _ = CloseClipboard();
        ok
    }
}

/// Ouvre l'Explorateur sur le fichier, selectionne.
pub fn file_reveal(path: String) -> bool {
    crate::games::reveal(Path::new(&path))
}
