//! Lanceur : enumere le dossier virtuel « shell:AppsFolder » (le meme que le
//! menu Demarrer : applis classiques et UWP), avec leurs icones.

use std::os::windows::process::CommandExt;
use std::path::Path;
use std::process::Command;
use std::sync::Mutex;
use std::time::UNIX_EPOCH;

use base64::Engine;
use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, State};
use windows::core::Interface;
use windows::Win32::Foundation::{PROPERTYKEY, SIZE};
use windows::Win32::UI::Shell::IShellItem2;
use windows::Win32::UI::Shell::PropertiesSystem::PSGetPropertyKeyFromName;
use windows::Win32::Graphics::Gdi::{
    DeleteObject, GetDC, GetDIBits, GetObjectW, ReleaseDC, BITMAP, BITMAPINFO,
    BITMAPINFOHEADER, BI_RGB, DIB_RGB_COLORS, HBITMAP, HGDIOBJ,
};
use windows::core::{HSTRING, PCWSTR};
use windows::Win32::Storage::FileSystem::{GetFileVersionInfoSizeW, GetFileVersionInfoW, VerQueryValueW};
use windows::Win32::System::Com::CoTaskMemFree;
use windows::Win32::UI::Shell::{
    BHID_EnumItems, FOLDERID_AppsFolder, IEnumShellItems, IShellItem, IShellItemImageFactory,
    SHCreateItemFromParsingName, SHGetKnownFolderItem, KF_FLAG_DEFAULT, SIGDN, SIGDN_NORMALDISPLAY,
    SIGDN_PARENTRELATIVEPARSING, SIIGBF_ICONONLY,
};

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

#[derive(Serialize, Clone)]
pub struct App {
    name: String,
    id: String,
    icon: String,
    /// date d'installation approximative (ms depuis 1970), 0 si inconnue
    added: i64,
}

pub struct Apps(pub Mutex<Vec<App>>);

fn prop_str(item: &IShellItem2, name: &str) -> Option<String> {
    unsafe {
        let mut key = PROPERTYKEY::default();
        PSGetPropertyKeyFromName(&HSTRING::from(name), &mut key).ok()?;
        let p = item.GetString(&key).ok()?;
        let s = p.to_string().ok();
        CoTaskMemFree(Some(p.0 as _));
        s
    }
}

/// Date de creation du dossier de l'appli : cible du raccourci (applis
/// classiques) ou dossier du paquet (Store, recree a chaque mise a jour).
fn added_of(item: &IShellItem) -> i64 {
    let Ok(item2) = item.cast::<IShellItem2>() else { return 0 };
    for key in ["System.Link.TargetParsingPath", "System.AppUserModel.PackageInstallPath"] {
        let Some(path) = prop_str(&item2, key) else { continue };
        let p = Path::new(&path);
        let Some(dir) = (if p.is_dir() { Some(p) } else { p.parent() }) else { continue };
        if let Ok(t) = std::fs::metadata(dir).and_then(|m| m.created()) {
            return t.duration_since(UNIX_EPOCH).map(|d| d.as_millis() as i64).unwrap_or(0);
        }
    }
    0
}

fn name_of(item: &IShellItem, kind: SIGDN) -> Option<String> {
    unsafe {
        let p = item.GetDisplayName(kind).ok()?;
        let s = p.to_string().ok();
        CoTaskMemFree(Some(p.0 as _));
        s
    }
}

/// HBITMAP 32 bits (alpha premultiplie) -> PNG en data URL.
fn bitmap_png(hbmp: HBITMAP) -> Option<String> {
    unsafe {
        let mut bm = BITMAP::default();
        let n = GetObjectW(
            HGDIOBJ(hbmp.0),
            std::mem::size_of::<BITMAP>() as i32,
            Some(&mut bm as *mut _ as _),
        );
        if n == 0 {
            return None;
        }
        let (w, h) = (bm.bmWidth, bm.bmHeight.abs());
        let mut bmi = BITMAPINFO {
            bmiHeader: BITMAPINFOHEADER {
                biSize: std::mem::size_of::<BITMAPINFOHEADER>() as u32,
                biWidth: w,
                biHeight: -h, // force l'ordre haut -> bas
                biPlanes: 1,
                biBitCount: 32,
                biCompression: BI_RGB.0,
                ..Default::default()
            },
            ..Default::default()
        };
        let mut buf = vec![0u8; (w * h * 4) as usize];
        let hdc = GetDC(None);
        let lines = GetDIBits(
            hdc,
            hbmp,
            0,
            h as u32,
            Some(buf.as_mut_ptr() as _),
            &mut bmi,
            DIB_RGB_COLORS,
        );
        ReleaseDC(None, hdc);
        if lines == 0 {
            return None;
        }
        let has_alpha = buf.chunks(4).any(|p| p[3] != 0);
        for p in buf.chunks_mut(4) {
            p.swap(0, 2); // BGRA -> RGBA
            if !has_alpha {
                p[3] = 255;
            } else if p[3] > 0 && p[3] < 255 {
                let a = p[3] as u32;
                for c in &mut p[..3] {
                    *c = ((*c as u32 * 255) / a).min(255) as u8;
                }
            }
        }
        let img = image::RgbaImage::from_raw(w as u32, h as u32, buf)?;
        let mut out = std::io::Cursor::new(Vec::new());
        img.write_to(&mut out, image::ImageFormat::Png).ok()?;
        Some(format!(
            "data:image/png;base64,{}",
            base64::engine::general_purpose::STANDARD.encode(out.into_inner())
        ))
    }
}

pub(crate) fn icon_of(item: &IShellItem) -> String {
    unsafe {
        let Ok(f) = item.cast::<IShellItemImageFactory>() else {
            return String::new();
        };
        match f.GetImage(SIZE { cx: 64, cy: 64 }, SIIGBF_ICONONLY) {
            Ok(hbmp) => {
                let r = bitmap_png(hbmp).unwrap_or_default();
                let _ = DeleteObject(HGDIOBJ(hbmp.0));
                r
            }
            Err(_) => String::new(),
        }
    }
}

/// Icone d'un fichier (executable...) en data URL.
pub(crate) fn file_icon(path: &str) -> String {
    unsafe { SHCreateItemFromParsingName::<_, _, IShellItem>(&HSTRING::from(path), None) }
        .map(|item| icon_of(&item))
        .unwrap_or_default()
}

/// « Description du fichier » d'un executable (ex. « Google Chrome »).
pub(crate) fn file_description(path: &str) -> Option<String> {
    if path.is_empty() {
        return None;
    }
    let wide = HSTRING::from(path);
    unsafe {
        let size = GetFileVersionInfoSizeW(&wide, None);
        if size == 0 {
            return None;
        }
        let mut buf = vec![0u8; size as usize];
        GetFileVersionInfoW(&wide, None, size, buf.as_mut_ptr() as _).ok()?;
        let mut ptr = std::ptr::null_mut();
        let mut len = 0u32;
        let tr = HSTRING::from(r"\VarFileInfo\Translation");
        let lang = if VerQueryValueW(buf.as_ptr() as _, PCWSTR(tr.as_ptr()), &mut ptr, &mut len).as_bool() && len >= 4 {
            let p = ptr as *const u16;
            format!("{:04x}{:04x}", *p, *p.add(1))
        } else {
            "040904b0".into()
        };
        let key = HSTRING::from(format!(r"\StringFileInfo\{lang}\FileDescription"));
        if !VerQueryValueW(buf.as_ptr() as _, PCWSTR(key.as_ptr()), &mut ptr, &mut len).as_bool() || len == 0 {
            return None;
        }
        let s = String::from_utf16_lossy(std::slice::from_raw_parts(ptr as *const u16, len as usize));
        let s = s.trim_end_matches('\0').trim().to_string();
        (!s.is_empty()).then_some(s)
    }
}

const SKIP: &[&str] = &[
    "uninstall", "désinstall", "desinstall", "readme", "lisez-moi", "release notes",
    "documentation", "help", "aide", "website", "site web", "license", "licence",
];

fn scan() -> windows::core::Result<Vec<App>> {
    crate::com_init_sta();
    let mut out: Vec<App> = Vec::new();
    unsafe {
        let folder: IShellItem = SHGetKnownFolderItem(&FOLDERID_AppsFolder, KF_FLAG_DEFAULT, None)?;
        let en: IEnumShellItems = folder.BindToHandler(None, &BHID_EnumItems)?;
        loop {
            let mut items = [None];
            let mut fetched = 0u32;
            let _ = en.Next(&mut items, Some(&mut fetched));
            if fetched == 0 {
                break;
            }
            let Some(item) = items[0].take() else { break };
            let (Some(name), Some(id)) = (
                name_of(&item, SIGDN_NORMALDISPLAY),
                name_of(&item, SIGDN_PARENTRELATIVEPARSING),
            ) else {
                continue;
            };
            let low = name.to_lowercase();
            if SKIP.iter().any(|s| low.contains(s)) || id.starts_with("http") {
                continue;
            }
            if out.iter().any(|a| a.name == name) {
                continue;
            }
            let icon = icon_of(&item);
            let added = added_of(&item);
            out.push(App { name, id, icon, added });
        }
    }
    out.sort_by_key(|a| a.name.to_lowercase());
    Ok(out)
}

/// Charge la liste en arriere-plan puis emet `apps`.
pub fn load(app: AppHandle) {
    std::thread::spawn(move || {
        if let Ok(list) = scan() {
            *app.state::<Apps>().0.lock().unwrap() = list.clone();
            let _ = app.emit("apps", list);
        }
    });
}

#[tauri::command]
pub fn apps_get(st: State<Apps>) -> Vec<App> {
    st.0.lock().unwrap().clone()
}

#[tauri::command]
pub fn apps_refresh(app: AppHandle) {
    load(app);
}

#[tauri::command(async)]
pub fn app_launch(id: String) {
    let _ = Command::new("explorer.exe")
        .arg(format!("shell:AppsFolder\\{id}"))
        .creation_flags(CREATE_NO_WINDOW)
        .spawn();
}
