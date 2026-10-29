//! Lanceur : enumere le dossier virtuel « shell:AppsFolder » (le meme que le
//! menu Demarrer : applis classiques et UWP), avec leurs icones.

use std::os::windows::process::CommandExt;
use std::path::Path;
use std::process::Command;
use std::sync::Mutex;
use std::time::UNIX_EPOCH;

use serde::Serialize;
use crate::host::{AppHandle, State};
use windows::core::Interface;
use windows::Win32::Foundation::{PROPERTYKEY, SIZE};
use windows::Win32::UI::Shell::IShellItem2;
use windows::Win32::UI::Shell::PropertiesSystem::PSGetPropertyKeyFromName;
use windows::Win32::Graphics::Gdi::{
    DeleteObject, GetDC, GetDIBits, GetObjectW, ReleaseDC, BITMAP, BITMAPINFO,
    BITMAPINFOHEADER, BI_RGB, DIB_RGB_COLORS, HBITMAP, HGDIOBJ,
};
use windows::core::{w, HSTRING, PCWSTR};
use windows::Win32::UI::WindowsAndMessaging::SW_SHOWNORMAL;
use windows::Win32::Storage::FileSystem::{GetFileVersionInfoSizeW, GetFileVersionInfoW, VerQueryValueW};
use windows::Win32::System::Com::CoTaskMemFree;
use windows::Win32::UI::Shell::{
    BHID_EnumItems, FOLDERID_AppsFolder, IEnumShellItems, IShellItem, IShellItemImageFactory,
    SHCreateItemFromParsingName, SHGetKnownFolderItem, SHParseDisplayName, ShellExecuteExW,
    KF_FLAG_DEFAULT, SEE_MASK_INVOKEIDLIST, SEE_MASK_NOASYNC, SHELLEXECUTEINFOW, SIGDN, SIGDN_NORMALDISPLAY,
    SIGDN_DESKTOPABSOLUTEPARSING, SIGDN_PARENTRELATIVEPARSING, SIIGBF_ICONONLY,
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
pub(crate) fn bitmap_png(hbmp: HBITMAP) -> Option<String> {
    let (w, h, mut buf) = bitmap_bgra(hbmp)?;
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
    rgba_png(w, h, buf)
}

/// Pixels RGBA -> PNG, servi par le protocole `ilot` (URL).
pub(crate) fn rgba_png(w: u32, h: u32, buf: Vec<u8>) -> Option<String> {
    let img = image::RgbaImage::from_raw(w, h, buf)?;
    let mut out = std::io::Cursor::new(Vec::new());
    img.write_to(&mut out, image::ImageFormat::Png).ok()?;
    Some(crate::img::url("image/png", out.into_inner()))
}

/// Pixels d'un HBITMAP en BGRA 32 bits, de haut en bas.
pub(crate) fn bitmap_bgra(hbmp: HBITMAP) -> Option<(u32, u32, Vec<u8>)> {
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
        Some((w as u32, h as u32, buf))
    }
}

/// Le shell rate des icones (vides ou generiques) quand plusieurs threads en
/// demandent en meme temps : une seule extraction a la fois.
static ICON_LOCK: Mutex<()> = Mutex::new(());

pub(crate) fn icon_of(item: &IShellItem) -> String {
    let _one = ICON_LOCK.lock().unwrap_or_else(|e| e.into_inner());
    unsafe {
        let Ok(f) = item.cast::<IShellItemImageFactory>() else {
            return String::new();
        };
        // 48 px au plus : au-dela, le shell decode chaque icone en 256 x 256
        // dans sa liste « jumbo », gardee tant que l'ilot tourne (~80 Mo pour
        // 300 applis, docs/perf-memoire.md)
        match f.GetImage(SIZE { cx: 48, cy: 48 }, SIIGBF_ICONONLY) {
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
        // la longueur annoncee deborde parfois apres le zero final (Spotify) :
        // on coupe au premier zero
        let s = s.split('\0').next().unwrap_or_default().trim().to_string();
        (!s.is_empty()).then_some(s)
    }
}

const SKIP: &[&str] = &[
    "uninstall", "désinstall", "desinstall", "readme", "lisez-moi", "release notes",
    "documentation", "help", "aide", "website", "site web", "license", "licence",
];

/// Outils absents du menu Demarrer et des dossiers ci-dessous (fichier de
/// System32, nom affiche).
const TOOLS: &[(&str, &str)] = &[
    ("diskmgmt.msc", "Gestion des disques"),
    ("ncpa.cpl", "Connexions réseau"),
    ("gpedit.msc", "Éditeur de stratégie de groupe locale"),
    ("lusrmgr.msc", "Utilisateurs et groupes locaux"),
    ("certmgr.msc", "Gestionnaire de certificats"),
    ("SystemPropertiesAdvanced.exe", "Paramètres système avancés (variables d'environnement)"),
    ("optionalfeatures.exe", "Fonctionnalités de Windows"),
    ("rstrui.exe", "Restauration du système"),
    ("netplwiz.exe", "Comptes d'utilisateurs (avancé)"),
];

fn tool_path(file: &str) -> String {
    let sys = std::env::var("SystemRoot").unwrap_or_else(|_| r"C:\Windows".into());
    format!(r"{sys}\System32\{file}")
}

/// Ajoute les elements d'un dossier du shell. `abs` : l'identifiant est le
/// chemin complet (« shell:... »), lance tel quel, et non un nom d'AppsFolder.
fn push_items(folder: &IShellItem, abs: bool, out: &mut Vec<App>) -> windows::core::Result<()> {
    unsafe {
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
                name_of(&item, if abs { SIGDN_DESKTOPABSOLUTEPARSING } else { SIGDN_PARENTRELATIVEPARSING }),
            ) else {
                continue;
            };
            let low = name.to_lowercase();
            // sans nom, le shell rend le chemin « ::{...} »
            if name.trim().is_empty() || name.starts_with("::{") || SKIP.iter().any(|s| low.contains(s)) || id.starts_with("http") {
                continue;
            }
            // Polices (dossier reel, nom traduit) ne s'ouvre pas par ce chemin
            if out.iter().any(|a| a.name == name) || (abs && !id.rsplit('\\').next().is_some_and(|c| c.starts_with("::{"))) {
                continue;
            }
            let id = if abs { format!("shell:{id}") } else { id };
            let icon = icon_of(&item);
            let added = added_of(&item);
            out.push(App { name, id, icon, added });
        }
    }
    Ok(())
}

fn scan() -> windows::core::Result<Vec<App>> {
    crate::com_init_sta();
    let mut out: Vec<App> = Vec::new();
    unsafe {
        let folder: IShellItem = SHGetKnownFolderItem(&FOLDERID_AppsFolder, KF_FLAG_DEFAULT, None)?;
        push_items(&folder, false, &mut out)?;
        // Outils Windows (Observateur d'evenements, Gestion de l'ordinateur,
        // Editeur du Registre...) : caches du menu Demarrer, mais lances par
        // AppsFolder comme les autres
        if let Ok(f) = SHCreateItemFromParsingName::<_, _, IShellItem>(w!("shell:::{D20EA4E1-3957-11d2-A40B-0C5020524153}"), None) {
            let _ = push_items(&f, false, &mut out);
        }
        // pages des Parametres, avec l'icone de l'appli Parametres. Avant le
        // Panneau de configuration : son « Resolution des problemes » renvoie
        // aux Parametres, mais pas toujours
        let settings = out.iter().find(|a| a.id.starts_with("windows.immersivecontrolpanel")).map(|a| a.icon.clone());
        if let Some(icon) = settings {
            for (id, name) in [("ms-settings:windowsupdate", "Windows Update"), ("ms-settings:troubleshoot", "Résolution des problèmes")] {
                if !out.iter().any(|a| a.name == name) {
                    out.push(App { name: name.into(), id: id.into(), icon: icon.clone(), added: 0 });
                }
            }
        }
        // Panneau de configuration, tous les elements (Gestionnaire de
        // peripheriques, Son, Connexions reseau...)
        if let Ok(f) = SHCreateItemFromParsingName::<_, _, IShellItem>(w!("shell:::{21EC2020-3AEA-1069-A2DD-08002B30309D}"), None) {
            let _ = push_items(&f, true, &mut out);
        }
        // Windows Famille a lusrmgr.msc mais la console y affiche une erreur :
        // gpedit.msc, absent de cette edition, sert de temoin
        let pro = Path::new(&tool_path("gpedit.msc")).exists();
        for (file, name) in TOOLS {
            let path = tool_path(file);
            if Path::new(&path).exists() && (pro || *file != "lusrmgr.msc") && !out.iter().any(|a| a.name == *name) {
                let icon = file_icon(&path);
                out.push(App { name: name.to_string(), id: path, icon, added: 0 });
            }
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

pub fn apps_get(st: State<Apps>) -> Vec<App> {
    st.0.lock().unwrap().clone()
}

pub fn apps_refresh(app: AppHandle) {
    load(app);
}

pub fn app_launch(id: String) {
    // element du Panneau de configuration : verbe par defaut de l'element,
    // comme un double-clic. `explorer.exe <chemin>` ignore certains
    // (Espaces de stockage, Dossiers de travail)
    if let Some(path) = id.strip_prefix("shell:") {
        let path = path.to_string();
        std::thread::spawn(move || {
            crate::com_init_sta();
            unsafe {
                let mut pidl = std::ptr::null_mut();
                if SHParseDisplayName(&HSTRING::from(path), None, &mut pidl, 0, None).is_err() {
                    return;
                }
                let mut info = SHELLEXECUTEINFOW {
                    cbSize: std::mem::size_of::<SHELLEXECUTEINFOW>() as u32,
                    // NOASYNC : le thread (et son STA) s'arrete juste apres
                    fMask: SEE_MASK_INVOKEIDLIST | SEE_MASK_NOASYNC,
                    lpIDList: pidl as _,
                    nShow: SW_SHOWNORMAL.0,
                    ..Default::default()
                };
                let _ = ShellExecuteExW(&mut info);
                CoTaskMemFree(Some(pidl as _));
            }
        });
        return;
    }
    // page des Parametres ou outil de System32 (chemin complet) : ouvert tel quel
    let direct = id.starts_with("ms-settings:") || TOOLS.iter().any(|(f, _)| id == tool_path(f));
    let _ = Command::new("explorer.exe")
        .arg(if direct { id } else { format!("shell:AppsFolder\\{id}") })
        .creation_flags(CREATE_NO_WINDOW)
        .spawn();
}
