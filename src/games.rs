//! Launcher de jeux : jeux installes via Steam, Epic Games, Ubisoft Connect
//! et GOG, avec jaquette (Steam) ou icone de l'executable. Aussi : ouvrir le
//! dossier d'une appli du menu Demarrer (clic droit > Ouvrir l'emplacement).

use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;
use std::sync::Mutex;

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager, State};
use windows::core::{Interface, GUID, HSTRING};
use windows::Win32::System::Com::{
    CoCreateInstance, CoTaskMemFree, IPersistFile, CLSCTX_INPROC_SERVER, STGM_READ,
};
use windows::Win32::System::Registry::{
    RegCloseKey, RegEnumKeyExW, RegGetValueW, RegOpenKeyExW, HKEY, HKEY_LOCAL_MACHINE, KEY_READ,
    RRF_RT_REG_SZ,
};
use windows::Win32::UI::Shell::{
    IShellItem, IShellLinkW, SHCreateItemFromParsingName, SHGetKnownFolderPath, ShellLink,
    KF_FLAG_DEFAULT, SLGP_RAWPATH,
};

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

#[derive(Serialize, Clone)]
pub struct Game {
    pub(crate) id: String,
    pub(crate) name: String,
    /// steam, epic, ubisoft, gog
    source: String,
    /// jaquette verticale (data URL) ou vide
    cover: String,
    /// icone de l'executable (data URL) ou vide
    icon: String,
    /// date d'installation (creation du dossier du jeu, ms depuis 1970), 0 si inconnue
    added: i64,
    #[serde(skip)]
    launch: String,
    #[serde(skip)]
    pub(crate) dir: PathBuf,
}

pub struct Games(pub Mutex<Vec<Game>>);

// ------------------------------------------------------------------- Steam

/// Outils Steam qui ne sont pas des jeux.
const STEAM_SKIP: &[&str] = &["228980", "431960", "1070560", "1391110", "1628350", "1493710", "2180100"];

pub(crate) fn acf_value<'a>(acf: &'a str, key: &str) -> Option<&'a str> {
    acf.lines().find_map(|l| {
        let parts: Vec<&str> = l.split('"').filter(|s| !s.trim().is_empty()).collect();
        (parts.len() == 2 && parts[0].eq_ignore_ascii_case(key)).then(|| parts[1])
    })
}

/// Jaquette verticale du cache Steam. Selon la version de Steam elle s'appelle
/// `library_600x900.jpg` ou `library_capsule.jpg`, a la racine du dossier de
/// l'appli ou dans un sous-dossier nomme par un hash.
fn steam_cover(appid: &str) -> String {
    let cache = crate::we::steam_dir().join(r"appcache\librarycache");
    let dir = cache.join(appid);
    let mut dirs = vec![dir.clone()];
    if let Ok(rd) = std::fs::read_dir(&dir) {
        dirs.extend(rd.flatten().map(|e| e.path()).filter(|p| p.is_dir()));
    }
    let mut cands = vec![cache.join(format!("{appid}_library_600x900.jpg"))];
    for name in ["library_600x900.jpg", "library_capsule.jpg"] {
        cands.extend(dirs.iter().map(|d| d.join(name)));
    }
    cands
        .iter()
        .find(|p| p.is_file())
        .and_then(|p| crate::wall::thumb(p))
        .unwrap_or_default()
}

fn steam_games() -> Vec<Game> {
    let mut out = Vec::new();
    for lib in crate::we::libraries() {
        let apps = lib.join("steamapps");
        let Ok(rd) = std::fs::read_dir(&apps) else { continue };
        for e in rd.flatten() {
            let fname = e.file_name().to_string_lossy().to_string();
            if !fname.starts_with("appmanifest_") || !fname.ends_with(".acf") {
                continue;
            }
            let Ok(acf) = std::fs::read_to_string(e.path()) else { continue };
            let (Some(appid), Some(name), Some(dir)) =
                (acf_value(&acf, "appid"), acf_value(&acf, "name"), acf_value(&acf, "installdir"))
            else {
                continue;
            };
            let low = name.to_lowercase();
            if STEAM_SKIP.contains(&appid)
                || low.contains("redistributable")
                || low.contains("runtime")
                || low.starts_with("proton")
                || low.contains("dedicated server")
                || low.contains("bonus content")
                || low.contains("soundtrack")
                || low.ends_with(" sdk")
            {
                continue;
            }
            let dir = apps.join("common").join(dir);
            let cover = steam_cover(appid);
            // pas de jaquette en cache : icone de l'executable principal
            let icon = if cover.is_empty() { main_exe(&dir).map(|e| file_icon(&e)).unwrap_or_default() } else { String::new() };
            out.push(Game {
                id: format!("steam:{appid}"),
                name: name.to_string(),
                source: "steam".into(),
                cover,
                icon,
                launch: format!("steam://rungameid/{appid}"),
                dir,
                added: 0,
            });
        }
    }
    out
}

// -------------------------------------------------------------------- Epic

fn epic_games() -> Vec<Game> {
    let mut out = Vec::new();
    let Ok(rd) = std::fs::read_dir(r"C:\ProgramData\Epic\EpicGamesLauncher\Data\Manifests") else {
        return out;
    };
    for e in rd.flatten() {
        if e.path().extension().and_then(|x| x.to_str()) != Some("item") {
            continue;
        }
        let Ok(s) = std::fs::read_to_string(e.path()) else { continue };
        let Ok(v) = serde_json::from_str::<serde_json::Value>(&s) else { continue };
        let get = |k: &str| v.get(k).and_then(|x| x.as_str()).unwrap_or_default().to_string();
        let is_game = v
            .get("AppCategories")
            .and_then(|c| c.as_array())
            .is_some_and(|c| c.iter().any(|x| x.as_str() == Some("games")));
        let (name, dir) = (get("DisplayName"), get("InstallLocation"));
        if !is_game || name.is_empty() || dir.is_empty() {
            continue;
        }
        let exe = Path::new(&dir).join(get("LaunchExecutable"));
        out.push(Game {
            id: format!("epic:{}", get("AppName")),
            name,
            source: "epic".into(),
            cover: String::new(),
            icon: Some(file_icon(&exe)).filter(|i| !i.is_empty())
                .or_else(|| main_exe(Path::new(&dir)).map(|e| file_icon(&e)))
                .unwrap_or_default(),
            launch: format!(
                "com.epicgames.launcher://apps/{}%3A{}%3A{}?action=launch&silent=true",
                get("CatalogNamespace"),
                get("CatalogItemId"),
                get("AppName")
            ),
            dir: PathBuf::from(dir),
            added: 0,
        });
    }
    out
}

// ------------------------------------------------------- Ubisoft et GOG

fn reg_str(key: HKEY, sub: &str, name: &str) -> Option<String> {
    let mut buf = [0u16; 1024];
    let mut len = (buf.len() * 2) as u32;
    unsafe {
        RegGetValueW(
            key,
            &HSTRING::from(sub),
            &HSTRING::from(name),
            RRF_RT_REG_SZ,
            None,
            Some(buf.as_mut_ptr() as _),
            Some(&mut len),
        )
        .ok()
        .ok()?;
    }
    let n = buf.iter().position(|&c| c == 0).unwrap_or(0);
    Some(String::from_utf16_lossy(&buf[..n])).filter(|s| !s.is_empty())
}

fn reg_subkeys(path: &str) -> Vec<String> {
    let mut out = Vec::new();
    unsafe {
        let mut k = HKEY::default();
        if RegOpenKeyExW(HKEY_LOCAL_MACHINE, &HSTRING::from(path), None, KEY_READ, &mut k).is_err() {
            return out;
        }
        for i in 0.. {
            let mut buf = [0u16; 256];
            let mut len = buf.len() as u32;
            if RegEnumKeyExW(k, i, Some(windows::core::PWSTR(buf.as_mut_ptr())), &mut len, None, None, None, None)
                .is_err()
            {
                break;
            }
            out.push(String::from_utf16_lossy(&buf[..len as usize]));
        }
        let _ = RegCloseKey(k);
    }
    out
}

/// Plus gros .exe d'un dossier (et de ses sous-dossiers proches) : sert d'icone.
fn main_exe(dir: &Path) -> Option<PathBuf> {
    fn walk(d: &Path, depth: u32, best: &mut Option<(u64, PathBuf)>) {
        let Ok(rd) = std::fs::read_dir(d) else { return };
        for e in rd.flatten() {
            let p = e.path();
            if p.is_dir() {
                if depth > 0 {
                    walk(&p, depth - 1, best);
                }
            } else if p.extension().is_some_and(|x| x.eq_ignore_ascii_case("exe")) {
                let n = p.file_name().unwrap_or_default().to_string_lossy().to_lowercase();
                if n.contains("unins") || n.contains("crash") || n.contains("setup") || n.contains("redist") {
                    continue;
                }
                let len = e.metadata().map(|m| m.len()).unwrap_or(0);
                if best.as_ref().is_none_or(|(l, _)| len > *l) {
                    *best = Some((len, p));
                }
            }
        }
    }
    let mut best = None;
    walk(dir, 2, &mut best);
    best.map(|(_, p)| p)
}

fn ubisoft_games() -> Vec<Game> {
    let base = r"SOFTWARE\WOW6432Node\Ubisoft\Launcher\Installs";
    reg_subkeys(base)
        .into_iter()
        .filter_map(|id| {
            let dir = reg_str(HKEY_LOCAL_MACHINE, &format!(r"{base}\{id}"), "InstallDir")?.replace('/', "\\");
            let dir = PathBuf::from(dir.trim_end_matches('\\'));
            if !dir.is_dir() {
                return None;
            }
            let name = dir.file_name()?.to_string_lossy().to_string();
            Some(Game {
                id: format!("ubisoft:{id}"),
                name,
                source: "ubisoft".into(),
                cover: String::new(),
                icon: main_exe(&dir).map(|e| file_icon(&e)).unwrap_or_default(),
                launch: format!("uplay://launch/{id}/0"),
                dir,
                added: 0,
            })
        })
        .collect()
}

fn gog_games() -> Vec<Game> {
    let base = r"SOFTWARE\WOW6432Node\GOG.com\Games";
    reg_subkeys(base)
        .into_iter()
        .filter_map(|id| {
            let key = format!(r"{base}\{id}");
            let name = reg_str(HKEY_LOCAL_MACHINE, &key, "gameName")?;
            let exe = PathBuf::from(reg_str(HKEY_LOCAL_MACHINE, &key, "exe")?);
            let dir = reg_str(HKEY_LOCAL_MACHINE, &key, "path").map(PathBuf::from)?;
            Some(Game {
                id: format!("gog:{id}"),
                name,
                source: "gog".into(),
                cover: String::new(),
                icon: file_icon(&exe),
                launch: exe.to_string_lossy().into_owned(),
                dir,
                added: 0,
            })
        })
        .collect()
}

// ------------------------------------------------------------------ icones

fn file_icon(p: &Path) -> String {
    if !p.is_file() {
        return String::new();
    }
    unsafe {
        SHCreateItemFromParsingName::<_, _, IShellItem>(&HSTRING::from(p.as_os_str()), None)
            .map(|it| crate::apps::icon_of(&it))
            .unwrap_or_default()
    }
}

// --------------------------------------------------------------- commandes

fn scan() -> Vec<Game> {
    crate::com_init_sta();
    let mut all = steam_games();
    all.extend(epic_games());
    all.extend(ubisoft_games());
    all.extend(gog_games());
    all.sort_by_key(|g| g.name.to_lowercase());
    all.dedup_by(|a, b| a.id == b.id);
    for g in &mut all {
        g.added = std::fs::metadata(&g.dir)
            .and_then(|m| m.created())
            .ok()
            .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
            .map_or(0, |d| d.as_millis() as i64);
    }
    all
}

/// Diagnostic texte (`--check-games`).
pub fn report() -> String {
    scan()
        .iter()
        .map(|g| format!("[{}] {} | {} | jaquette {} o, icone {} o", g.source, g.name, g.dir.display(), g.cover.len(), g.icon.len()))
        .collect::<Vec<_>>()
        .join("
")
}

/// Charge la liste en arriere-plan puis emet `games`.
pub fn load(app: AppHandle) {
    std::thread::spawn(move || {
        let list = scan();
        *app.state::<Games>().0.lock().unwrap() = list.clone();
        let _ = app.emit("games", list);
    });
}

#[tauri::command]
pub fn games_get(st: State<Games>) -> Vec<Game> {
    st.0.lock().unwrap().clone()
}

#[tauri::command]
pub fn games_refresh(app: AppHandle) {
    load(app);
}

#[tauri::command(async)]
pub fn game_launch(st: State<Games>, id: String) -> bool {
    let Some(g) = st.0.lock().unwrap().iter().find(|g| g.id == id).cloned() else {
        return false;
    };
    let r = if g.launch.contains("://") {
        Command::new("explorer.exe").arg(&g.launch).creation_flags(CREATE_NO_WINDOW).spawn()
    } else {
        Command::new(&g.launch).current_dir(&g.dir).spawn()
    };
    r.is_ok()
}

#[tauri::command(async)]
pub fn game_folder(st: State<Games>, id: String) -> bool {
    let dir = st.0.lock().unwrap().iter().find(|g| g.id == id).map(|g| g.dir.clone());
    dir.is_some_and(|d| open_dir(&d))
}

// --------------------------------------- emplacement d'une appli (clic droit)

fn open_dir(d: &Path) -> bool {
    d.is_dir() && Command::new("explorer.exe").arg(d).spawn().is_ok()
}

/// Ouvre l'Explorateur sur le fichier, selectionne.
pub(crate) fn reveal(p: &Path) -> bool {
    if p.is_dir() {
        return open_dir(p);
    }
    p.is_file()
        && Command::new("explorer.exe")
            .raw_arg(format!("/select,\"{}\"", p.display()))
            .spawn()
            .is_ok()
}

/// `{GUID}\reste` (dossier connu, ex. Program Files) -> chemin reel.
fn known_folder_path(id: &str) -> Option<PathBuf> {
    let (g, rest) = id.strip_prefix('{')?.split_once("}\\")?;
    let guid = GUID::try_from(g).ok()?;
    unsafe {
        let p = SHGetKnownFolderPath(&guid, KF_FLAG_DEFAULT, None).ok()?;
        let base = p.to_string().ok();
        CoTaskMemFree(Some(p.0 as _));
        Some(PathBuf::from(base?).join(rest))
    }
}

fn find_lnk(dir: &Path, name: &str, depth: u32) -> Option<PathBuf> {
    for e in std::fs::read_dir(dir).ok()?.flatten() {
        let p = e.path();
        if p.is_dir() {
            if depth > 0 {
                if let Some(f) = find_lnk(&p, name, depth - 1) {
                    return Some(f);
                }
            }
        } else if p.extension().is_some_and(|x| x.eq_ignore_ascii_case("lnk"))
            && p.file_stem().is_some_and(|s| s.to_string_lossy().eq_ignore_ascii_case(name))
        {
            return Some(p);
        }
    }
    None
}

/// Cible d'un raccourci .lnk.
fn lnk_target(lnk: &Path) -> Option<PathBuf> {
    unsafe {
        let link: IShellLinkW = CoCreateInstance(&ShellLink, None, CLSCTX_INPROC_SERVER).ok()?;
        link.cast::<IPersistFile>().ok()?.Load(&HSTRING::from(lnk.as_os_str()), STGM_READ).ok()?;
        let mut buf = [0u16; 1024];
        link.GetPath(&mut buf, std::ptr::null_mut(), SLGP_RAWPATH.0 as u32).ok()?;
        let n = buf.iter().position(|&c| c == 0).unwrap_or(0);
        let s = String::from_utf16_lossy(&buf[..n]);
        // les chemins bruts peuvent contenir des %VARIABLES%
        let s = std::env::vars().fold(s, |s, (k, v)| s.replace(&format!("%{k}%"), &v));
        Some(PathBuf::from(s)).filter(|p| !p.as_os_str().is_empty())
    }
}

fn locate(st: &Games, id: &str, name: &str) -> bool {
    // jeu Steam epingle au menu Demarrer
    if let Some(appid) = id.strip_prefix("steam://rungameid/") {
        let dir = st.0.lock().unwrap().iter().find(|g| g.id == format!("steam:{appid}")).map(|g| g.dir.clone());
        if dir.is_some_and(|d| open_dir(&d)) {
            return true;
        }
    }
    if let Some(p) = known_folder_path(id) {
        if reveal(&p) {
            return true;
        }
    }
    if Path::new(id).is_absolute() && reveal(Path::new(id)) {
        return true;
    }
    // raccourci du menu Demarrer portant le nom de l'appli
    let roots = [
        std::env::var("APPDATA").map(|a| PathBuf::from(a).join(r"Microsoft\Windows\Start Menu\Programs")),
        std::env::var("ProgramData").map(|a| PathBuf::from(a).join(r"Microsoft\Windows\Start Menu\Programs")),
    ];
    for root in roots.into_iter().flatten() {
        if let Some(lnk) = find_lnk(&root, name, 4) {
            if lnk_target(&lnk).is_some_and(|t| reveal(&t)) {
                return true;
            }
            return reveal(&lnk);
        }
    }
    // appli du Store : dossier de donnees du paquet
    if let Some((family, _)) = id.split_once('!') {
        if let Ok(local) = std::env::var("LOCALAPPDATA") {
            return open_dir(&Path::new(&local).join("Packages").join(family));
        }
    }
    false
}

#[tauri::command(async)]
pub fn app_folder(app: AppHandle, id: String, name: String) -> bool {
    // thread dedie en STA pour les objets COM du shell
    std::thread::spawn(move || {
        crate::com_init_sta();
        locate(&app.state::<Games>(), &id, &name)
    })
    .join()
    .unwrap_or(false)
}

// ------------------------------------------- dossiers d'apps : emplacement reel

/// Ouvre un dossier dans l'Explorateur.
#[tauri::command(async)]
pub fn folder_open(path: String) -> bool {
    open_dir(Path::new(&path))
}

// ------------------------------- fichiers glisses dans un dossier d'apps

#[derive(Serialize)]
pub struct FileInfo {
    name: String,
    icon: String,
}

/// Nom et icone d'un fichier ou dossier depose dans l'ilot (None s'il n'existe plus).
#[tauri::command(async)]
pub fn file_info(path: String) -> Option<FileInfo> {
    let p = PathBuf::from(&path);
    let special = special_name(&path);
    if special.is_none() && !p.exists() {
        return None;
    }
    let name = match special {
        Some(n) => n.to_string(),
        None => if p.is_dir() { p.file_name() } else { p.file_stem() }
            .map(|s| s.to_string_lossy().into_owned())
            .unwrap_or(path),
    };
    // icone via le Shell, dans un thread STA a part
    let icon = std::thread::spawn(move || unsafe {
        crate::com_init_sta();
        SHCreateItemFromParsingName::<_, _, IShellItem>(&HSTRING::from(p.as_os_str()), None)
            .map(|it| crate::apps::icon_of(&it))
            .unwrap_or_default()
    })
    .join()
    .unwrap_or_default();
    Some(FileInfo { name, icon })
}

/// Ouvre un fichier (programme, raccourci, document) ou un dossier.
#[tauri::command(async)]
pub fn file_open(path: String) -> bool {
    (special_name(&path).is_some() || Path::new(&path).exists()) && Command::new("explorer.exe").arg(&path).spawn().is_ok()
}

/// Emplacements speciaux du Shell (Corbeille, Ce PC...) : pas de vrai chemin,
/// on les range sous leur nom « shell:... ».
fn special_name(path: &str) -> Option<&'static str> {
    Some(match path.to_ascii_lowercase().as_str() {
        "shell:recyclebinfolder" => "Corbeille",
        "shell:mycomputerfolder" => "Ce PC",
        "shell:controlpanelfolder" => "Panneau de configuration",
        "shell:downloads" => "Téléchargements",
        "shell:networkplacesfolder" => "Réseau",
        _ => return None,
    })
}

/// Boite « Choisir un dossier » de Windows ; renvoie le chemin choisi.
#[tauri::command(async)]
pub fn pick_folder(app: AppHandle, title: Option<String>) -> Option<String> {
    use windows::Win32::UI::Shell::{FileOpenDialog, IFileOpenDialog, FOS_FORCEFILESYSTEM, FOS_PICKFOLDERS, SIGDN_FILESYSPATH};
    let owner = app.get_webview_window("island").and_then(|w| w.hwnd().ok()).map(|h| h.0 as isize);
    std::thread::spawn(move || unsafe {
        crate::com_init_sta();
        let dlg: IFileOpenDialog = CoCreateInstance(&FileOpenDialog, None, CLSCTX_INPROC_SERVER).ok()?;
        let opts = dlg.GetOptions().ok()?;
        dlg.SetOptions(opts | FOS_PICKFOLDERS | FOS_FORCEFILESYSTEM).ok()?;
        if let Some(t) = title {
            let _ = dlg.SetTitle(&HSTRING::from(t));
        }
        let owner = owner.map(|h| windows::Win32::Foundation::HWND(h as _));
        dlg.Show(owner).ok()?;
        let item = dlg.GetResult().ok()?;
        let p = item.GetDisplayName(SIGDN_FILESYSPATH).ok()?;
        let s = p.to_string().ok();
        CoTaskMemFree(Some(p.0 as _));
        s
    })
    .join()
    .ok()
    .flatten()
}
