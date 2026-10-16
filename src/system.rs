//! Volume, ressources, batterie, presse-papiers, anti-veille, profil,
//! activites (Verr. Maj, chargeur) et actions de session.

use std::collections::VecDeque;
use std::os::windows::process::CommandExt;
use std::process::Command;
use std::sync::Mutex;

use serde::Serialize;
use sysinfo::{Disks, System};
use crate::host::{AppHandle, State};
use windows::core::{HSTRING, PWSTR};
use windows::Win32::Foundation::{CloseHandle, LocalFree, HANDLE, HLOCAL};
use windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolume;
use windows::Win32::Security::Authentication::Identity::{GetUserNameExW, NameDisplay};
use windows::Win32::Security::Authorization::ConvertSidToStringSidW;
use windows::Win32::Security::{GetTokenInformation, TokenUser, TOKEN_QUERY, TOKEN_USER};
use windows::Win32::System::Power::{
    SetThreadExecutionState, ES_CONTINUOUS, ES_DISPLAY_REQUIRED, ES_SYSTEM_REQUIRED,
};
use windows::Win32::System::Registry::{RegGetValueW, HKEY, HKEY_LOCAL_MACHINE, RRF_RT_REG_SZ};
use windows::Win32::System::Threading::{GetCurrentProcess, OpenProcessToken};
use windows::Win32::UI::Input::KeyboardAndMouse::{GetKeyState, VK_CAPITAL};
use windows::Win32::Media::Audio::{eConsole, eRender, IMMDeviceEnumerator, MMDeviceEnumerator};
use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_ALL};
use windows::Win32::System::DataExchange::GetClipboardSequenceNumber;
use windows::Win32::System::Power::{GetSystemPowerStatus, SetSuspendState, SYSTEM_POWER_STATUS};
use windows::Win32::System::Shutdown::LockWorkStation;

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

// ------------------------------------------------------------------ volume

fn endpoint() -> windows::core::Result<IAudioEndpointVolume> {
    crate::com_init_mta();
    unsafe {
        let en: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
        let dev = en.GetDefaultAudioEndpoint(eRender, eConsole)?;
        dev.Activate::<IAudioEndpointVolume>(CLSCTX_ALL, None)
    }
}

#[derive(Serialize)]
pub struct Volume {
    level: f32,
    muted: bool,
}

pub fn volume_get() -> Volume {
    endpoint()
        .and_then(|ep| unsafe {
            Ok(Volume {
                level: ep.GetMasterVolumeLevelScalar()?,
                muted: ep.GetMute()?.as_bool(),
            })
        })
        .unwrap_or(Volume { level: 0.0, muted: false })
}

pub fn volume_set(level: Option<f32>, muted: Option<bool>) {
    if let Ok(ep) = endpoint() {
        unsafe {
            if let Some(l) = level {
                let _ = ep.SetMasterVolumeLevelScalar(l.clamp(0.0, 1.0), std::ptr::null());
            }
            if let Some(m) = muted {
                let _ = ep.SetMute(m, std::ptr::null());
            }
        }
    }
}

// --------------------------------------------------------------- ressources

#[derive(Serialize, Clone)]
pub struct Resources {
    cpu: f32,
    mem_used: u64,
    mem_total: u64,
    disk_used: u64,
    disk_total: u64,
    /// -1 = pas de batterie
    battery: i32,
    charging: bool,
    uptime: u64,
}

/// Emet `sys` toutes les deux secondes.
pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        let mut sys = System::new();
        let mut disks = Disks::new_with_refreshed_list();
        let mut last_ac: Option<bool> = None;
        loop {
            sys.refresh_cpu_usage();
            sys.refresh_memory();
            disks.refresh(true);
            let (mut du, mut dt) = (0, 0);
            for d in disks.list() {
                if d.mount_point().to_string_lossy().starts_with("C:") {
                    dt = d.total_space();
                    du = dt - d.available_space();
                }
            }
            let mut ps = SYSTEM_POWER_STATUS::default();
            let ok = unsafe { GetSystemPowerStatus(&mut ps) }.is_ok();
            let no_batt = !ok || ps.BatteryFlag & 128 != 0 || ps.BatteryLifePercent == 255;
            let r = Resources {
                cpu: sys.global_cpu_usage(),
                mem_used: sys.used_memory(),
                mem_total: sys.total_memory(),
                disk_used: du,
                disk_total: dt,
                battery: if no_batt { -1 } else { ps.BatteryLifePercent as i32 },
                charging: ps.ACLineStatus == 1,
                uptime: System::uptime(),
            };
            // branchement / debranchement du chargeur (portables)
            if !no_batt {
                if last_ac.is_some_and(|a| a != r.charging) {
                    let _ = app.emit("activity", serde_json::json!({ "kind": "power", "on": r.charging, "battery": r.battery }));
                }
                last_ac = Some(r.charging);
            }
            let _ = app.emit("sys", r);
            std::thread::sleep(std::time::Duration::from_secs(2));
        }
    });
}

// ----------------------------------------------------------- presse-papiers

/// Un element de l'historique : du texte ou une image.
#[derive(Clone)]
pub struct Clip {
    id: u64,
    text: Option<String>,
    /// image complete (RGBA), pour pouvoir la recopier
    image: Option<(usize, usize, std::sync::Arc<Vec<u8>>)>,
    thumb: String,
    hash: u64,
}

#[derive(Serialize, Clone)]
pub struct ClipView {
    id: u64,
    text: Option<String>,
    thumb: String,
    w: usize,
    h: usize,
}

impl Clip {
    fn view(&self) -> ClipView {
        let (w, h) = self.image.as_ref().map(|i| (i.0, i.1)).unwrap_or((0, 0));
        ClipView { id: self.id, text: self.text.clone(), thumb: self.thumb.clone(), w, h }
    }
}

pub struct Clips(pub Mutex<VecDeque<Clip>>);

const CLIP_MAX: usize = 40;
const CLIP_IMAGES: usize = 8;

fn hash_of(b: &[u8]) -> u64 {
    use std::hash::{Hash, Hasher};
    let mut h = std::collections::hash_map::DefaultHasher::new();
    b.hash(&mut h);
    h.finish()
}

/// Miniature PNG (URL du protocole `ilot`) d'une image RGBA.
fn rgba_thumb(w: usize, h: usize, bytes: &[u8], size: u32) -> Option<String> {
    let img = image::RgbaImage::from_raw(w as u32, h as u32, bytes.to_vec())?;
    let t = image::DynamicImage::ImageRgba8(img).thumbnail(size, size);
    let mut out = std::io::Cursor::new(Vec::new());
    t.write_to(&mut out, image::ImageFormat::Png).ok()?;
    Some(crate::img::CLIPS.url("image/png", out.into_inner()))
}

fn clips_view(q: &VecDeque<Clip>) -> Vec<ClipView> {
    q.iter().map(Clip::view).collect()
}

/// Surveille le presse-papiers (texte et images) et emet `clips`. Une image
/// copiee (capture d'ecran...) donne aussi une activite `shot`.
pub fn watch_clipboard(app: AppHandle) {
    std::thread::spawn(move || {
        let mut seq = 0u32;
        let mut next_id = 1u64;
        let mut first = true;
        loop {
            let s = unsafe { GetClipboardSequenceNumber() };
            if s != seq {
                seq = s;
                let mut cb = arboard::Clipboard::new();
                let entry = match cb.as_mut().map(|c| c.get_text()) {
                    Ok(Ok(t)) if !t.trim().is_empty() => {
                        Some(Clip { id: 0, hash: hash_of(t.as_bytes()), text: Some(t), image: None, thumb: String::new() })
                    }
                    _ => cb.as_mut().ok().and_then(|c| c.get_image().ok()).and_then(|img| {
                        let hash = hash_of(&img.bytes);
                        let thumb = rgba_thumb(img.width, img.height, &img.bytes, 360)?;
                        Some(Clip {
                            id: 0,
                            hash,
                            text: None,
                            image: Some((img.width, img.height, std::sync::Arc::new(img.bytes.into_owned()))),
                            thumb,
                        })
                    }),
                };
                if let Some(mut c) = entry {
                    let st = app.state::<Clips>();
                    let mut q = st.0.lock().unwrap();
                    let known = q.iter().any(|x| x.hash == c.hash);
                    if !known && c.image.is_some() && !first {
                        let _ = app.emit("activity", serde_json::json!({ "kind": "shot", "thumb": c.thumb }));
                    }
                    q.retain(|x| x.hash != c.hash);
                    c.id = next_id;
                    next_id += 1;
                    q.push_front(c);
                    q.truncate(CLIP_MAX);
                    // les images prennent de la place : on n'en garde que quelques-unes
                    let mut imgs = 0;
                    q.retain(|x| x.image.is_none() || { imgs += 1; imgs <= CLIP_IMAGES });
                    let _ = app.emit("clips", clips_view(&q));
                }
                first = false;
            }
            std::thread::sleep(std::time::Duration::from_millis(400));
        }
    });
}

pub fn clips_get(st: State<Clips>) -> Vec<ClipView> {
    clips_view(&st.0.lock().unwrap())
}

pub fn clip_copy(st: State<'_, Clips>, id: u64) -> bool {
    let Some(c) = st.0.lock().unwrap().iter().find(|c| c.id == id).cloned() else { return false };
    let Ok(mut cb) = arboard::Clipboard::new() else { return false };
    match (c.text, c.image) {
        (Some(t), _) => cb.set_text(t).is_ok(),
        (None, Some((w, h, bytes))) => cb
            .set_image(arboard::ImageData { width: w, height: h, bytes: std::borrow::Cow::Borrowed(&bytes) })
            .is_ok(),
        _ => false,
    }
}

pub fn clip_text(text: String) -> bool {
    arboard::Clipboard::new().and_then(|mut c| c.set_text(text)).is_ok()
}

pub fn clips_clear(app: AppHandle, st: State<Clips>) {
    st.0.lock().unwrap().clear();
    let _ = app.emit("clips", Vec::<ClipView>::new());
}

// -------------------------------------------------------------- anti-veille

static CAFFEINE: Mutex<Option<std::sync::mpsc::Sender<()>>> = Mutex::new(None);

/// Empeche la mise en veille (et l'extinction de l'ecran) tant que c'est
/// actif. L'etat d'execution est lie au thread : un thread le garde.
pub fn caffeine_set(app: AppHandle, on: bool) -> bool {
    let mut cur = CAFFEINE.lock().unwrap();
    if on && cur.is_none() {
        let (tx, rx) = std::sync::mpsc::channel::<()>();
        std::thread::spawn(move || unsafe {
            SetThreadExecutionState(ES_CONTINUOUS | ES_SYSTEM_REQUIRED | ES_DISPLAY_REQUIRED);
            let _ = rx.recv();
            SetThreadExecutionState(ES_CONTINUOUS);
        });
        *cur = Some(tx);
    } else if !on {
        if let Some(tx) = cur.take() {
            let _ = tx.send(());
        }
    }
    let state = cur.is_some();
    let _ = app.emit("caffeine", state);
    state
}

pub fn caffeine_get() -> bool {
    CAFFEINE.lock().unwrap().is_some()
}

// ------------------------------------------------------------- utilisateur

#[derive(Serialize)]
pub struct User {
    name: String,
    avatar: String,
}

fn user_sid() -> Option<String> {
    unsafe {
        let mut token = HANDLE::default();
        OpenProcessToken(GetCurrentProcess(), TOKEN_QUERY, &mut token).ok()?;
        let mut len = 0u32;
        let _ = GetTokenInformation(token, TokenUser, None, 0, &mut len);
        let mut buf = vec![0u8; len as usize];
        let ok = GetTokenInformation(token, TokenUser, Some(buf.as_mut_ptr() as _), len, &mut len).is_ok();
        let _ = CloseHandle(token);
        if !ok {
            return None;
        }
        let tu = &*(buf.as_ptr() as *const TOKEN_USER);
        let mut s = PWSTR::null();
        ConvertSidToStringSidW(tu.User.Sid, &mut s).ok()?;
        let r = s.to_string().ok();
        let _ = LocalFree(Some(HLOCAL(s.0 as _)));
        r
    }
}

fn reg_string(root: HKEY, key: &str, name: &str) -> Option<String> {
    let key = HSTRING::from(key);
    let name = HSTRING::from(name);
    let mut buf = [0u16; 520];
    let mut len = (buf.len() * 2) as u32;
    unsafe {
        RegGetValueW(root, &key, &name, RRF_RT_REG_SZ, None, Some(buf.as_mut_ptr() as _), Some(&mut len)).ok().ok()?;
    }
    let n = buf.iter().position(|&c| c == 0).unwrap_or(0);
    Some(String::from_utf16_lossy(&buf[..n]))
}

pub fn user_info() -> User {
    let mut buf = [0u16; 256];
    let mut len = buf.len() as u32;
    let display = unsafe { GetUserNameExW(NameDisplay, Some(PWSTR(buf.as_mut_ptr())), &mut len) };
    let name = if display && len > 0 {
        String::from_utf16_lossy(&buf[..len as usize])
    } else {
        std::env::var("USERNAME").unwrap_or_default()
    };
    let avatar = user_sid()
        .and_then(|sid| {
            let key = format!(r"SOFTWARE\Microsoft\Windows\CurrentVersion\AccountPicture\Users\{sid}");
            ["Image192", "Image448", "Image96"].iter().find_map(|k| reg_string(HKEY_LOCAL_MACHINE, &key, k))
        })
        .and_then(|p| crate::wall::thumb_sized(std::path::Path::new(&p), 160))
        .unwrap_or_default();
    User { name, avatar }
}

// ---------------------------------------------------------------- activites

/// Verr. Maj (activite `caps`).
pub fn watch_keys(app: AppHandle) {
    std::thread::spawn(move || {
        let caps = || unsafe { GetKeyState(VK_CAPITAL.0 as i32) & 1 != 0 };
        let mut last = caps();
        loop {
            std::thread::sleep(std::time::Duration::from_millis(120));
            let now = caps();
            if now != last {
                last = now;
                let _ = app.emit("activity", serde_json::json!({ "kind": "caps", "on": now }));
            }
        }
    });
}

// --------------------------------------------------------------------- web

/// Ouvre une adresse dans le navigateur par defaut, ou un lien d'appli
/// musicale (playlists favorites : spotify:, deezer://).
pub fn open_url(url: String) {
    const OK: &[&str] = &["https://", "http://", "spotify:", "deezer://"];
    if OK.iter().any(|p| url.starts_with(p)) {
        let _ = Command::new("explorer.exe").arg(url).creation_flags(CREATE_NO_WINDOW).spawn();
    }
}

/// GET HTTPS (meteo, calendriers iCal).
pub fn http_get(url: String) -> Result<String, String> {
    let url = url.replacen("webcal://", "https://", 1);
    if !url.starts_with("https://") {
        return Err("seules les adresses https sont acceptees".into());
    }
    ureq::get(&url)
        .timeout(std::time::Duration::from_secs(15))
        .set("User-Agent", "Ilot")
        .call()
        .map_err(|e| e.to_string())?
        .into_string()
        .map_err(|e| e.to_string())
}

// ------------------------------------------------------------------ session

pub fn session_action(action: String) {
    let shutdown = |args: &[&str]| {
        let _ = Command::new("shutdown")
            .args(args)
            .creation_flags(CREATE_NO_WINDOW)
            .spawn();
    };
    match action.as_str() {
        "lock" => unsafe {
            let _ = LockWorkStation();
        },
        "sleep" => unsafe {
            let _ = SetSuspendState(false, false, false);
        },
        "logout" => shutdown(&["/l"]),
        "restart" => shutdown(&["/r", "/t", "0"]),
        "shutdown" => shutdown(&["/s", "/t", "0"]),
        _ => {}
    }
}
