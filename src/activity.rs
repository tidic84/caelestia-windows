//! Activites en cours (evenement `gaming`), affichees dans la pilule :
//! telechargements Steam, jeu lance (mode jeu) et charge / temperature de la
//! carte graphique NVIDIA.
//!
//! Steam ne reecrit ses manifestes (appmanifest_*.acf) que de temps en temps et
//! les laisse « en cours » meme en pause. L'etat reel vient donc de son journal
//! logs/content_log.txt : etape (telechargement, installation), pause, octets
//! deja recus au demarrage et debit annonce par Steam. Entre deux releves, la
//! progression avance avec ce debit. Une mise a jour se fait en deux temps :
//! telechargement (quelques Go), puis installation (ecriture des fichiers sur
//! le disque, souvent bien plus longue).

use std::collections::HashMap;
use std::sync::atomic::{AtomicU32, AtomicU64, Ordering};
use std::fs::File;
use std::io::{Read, Seek, SeekFrom};
use std::os::windows::process::CommandExt;
use std::path::PathBuf;
use std::process::Command;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde::Serialize;
use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System, UpdateKind};
use crate::host::AppHandle;

use windows::core::{w, BOOL};
use windows::Win32::Foundation::{CloseHandle, HWND, LPARAM, LRESULT, WPARAM};
use windows::Win32::System::Threading::{GetProcessIoCounters, OpenProcess, IO_COUNTERS, PROCESS_QUERY_LIMITED_INFORMATION};
use windows::Win32::UI::WindowsAndMessaging::{
    CreateWindowExW, DefWindowProcW, DispatchMessageW, EnumWindows, GetForegroundWindow, GetMessageW, GetWindowTextLengthW,
    GetWindowThreadProcessId, IsIconic, IsWindowVisible, RegisterClassW, RegisterShellHookWindow, RegisterWindowMessageW,
    SetForegroundWindow, ShowWindow, TranslateMessage, MSG, SW_RESTORE, WINDOW_EX_STYLE, WINDOW_STYLE, WNDCLASSW,
};

use crate::games::{acf_value, Games};

const CREATE_NO_WINDOW: u32 = 0x0800_0000;
/// StateFlags Steam : mise a jour commencee (en cours ou en pause).
const UPDATE_STARTED: u64 = 1024;

#[derive(Serialize, Clone, Default, PartialEq)]
pub struct Download {
    appid: String,
    name: String,
    /// « download » (reception) ou « install » (ecriture sur le disque)
    phase: String,
    done: u64,
    total: u64,
    /// false = en pause / en file d'attente
    active: bool,
    /// octets par seconde (debit annonce par Steam)
    speed: u64,
}

#[derive(Serialize, Clone, Default, PartialEq)]
pub struct Gpu {
    name: String,
    /// degres Celsius
    temp: u32,
    /// %
    load: u32,
}

/// Jeu du Launcher en cours d'execution.
#[derive(Serialize, Clone, Default, PartialEq)]
pub struct Playing {
    id: String,
    name: String,
    /// debut, ms depuis 1970
    since: u64,
    /// le joueur est sur une autre fenetre depuis (ms depuis 1970), 0 = dans le jeu
    away: u64,
}

#[derive(Serialize, Clone, Default, PartialEq)]
pub struct Activity {
    downloads: Vec<Download>,
    gpu: Option<Gpu>,
    game: Option<Playing>,
}

// --------------------------------------------------- journal de Steam

#[derive(Default)]
struct AppLog {
    active: bool,
    /// etape « Downloading » en cours (sinon : installation)
    downloading: bool,
    /// (recu, a recevoir, installe, a installer) au dernier demarrage
    base: Option<(u64, u64, u64, u64)>,
}

/// Lit content_log.txt au fil de l'eau (seulement les lignes ajoutees).
struct LogTail {
    path: PathBuf,
    pos: Option<u64>,
    apps: HashMap<String, AppLog>,
    /// debit annonce par Steam, octets/s
    rate: f64,
}

/// « 1698103296/6254487888 » -> (1698103296, 6254487888)
fn pair(s: &str) -> Option<(u64, u64)> {
    let (a, b) = s.trim().split_once('/')?;
    Some((a.trim().parse().ok()?, b.trim().parse().ok()?))
}

impl LogTail {
    fn new() -> Self {
        Self {
            path: crate::we::steam_dir().join(r"logs\content_log.txt"),
            pos: None,
            apps: HashMap::new(),
            rate: 0.0,
        }
    }

    fn poll(&mut self) {
        let Ok(mut f) = File::open(&self.path) else { return };
        let len = f.metadata().map(|m| m.len()).unwrap_or(0);
        // premier passage : la fin du journal suffit ; journal recree : on repart du debut
        let pos = match self.pos {
            None => len.saturating_sub(512 * 1024),
            Some(p) if p > len => 0,
            Some(p) => p,
        };
        if pos == len || f.seek(SeekFrom::Start(pos)).is_err() {
            self.pos = Some(pos);
            return;
        }
        let mut buf = Vec::new();
        if f.take(len - pos).read_to_end(&mut buf).is_err() {
            return;
        }
        // seulement des lignes completes : la derniere peut etre en cours d'ecriture
        let end = buf.iter().rposition(|&b| b == b'\n').map_or(0, |i| i + 1);
        self.pos = Some(pos + end as u64);
        for line in String::from_utf8_lossy(&buf[..end]).lines() {
            self.line(line);
        }
    }

    fn line(&mut self, l: &str) {
        // « Current download rate: 116.681 Mbps »
        if let Some(i) = l.find("Current download rate: ") {
            let v = l[i + 23..].split_whitespace().next().and_then(|v| v.parse::<f64>().ok());
            if let Some(mbps) = v {
                self.rate = mbps * 1_000_000.0 / 8.0;
            }
            return;
        }
        let Some(i) = l.find("AppID ") else { return };
        let Some((id, what)) = l[i + 6..].split_once(' ') else { return };
        if id.is_empty() || !id.bytes().all(|b| b.is_ascii_digit()) {
            return;
        }
        let app = self.apps.entry(id.to_string()).or_default();
        if let Some(s) = what.strip_prefix("App update changed : ") {
            app.active = s.contains("Running Update") && !s.contains("Stopping");
            app.downloading = app.active && s.contains("Downloading");
        } else if let Some(s) = what.strip_prefix("update started : ") {
            // « download 1698103296/6254487888, store 0/0, reuse ..., stage 4914088301/47577723649 »
            let mut dl = None;
            let mut st = None;
            for part in s.split(',') {
                let part = part.trim();
                if let Some(v) = part.strip_prefix("download ") {
                    dl = pair(v);
                } else if let Some(v) = part.strip_prefix("stage ") {
                    st = pair(v);
                }
            }
            if let Some((a, b)) = dl {
                let (c, d) = st.unwrap_or((0, 0));
                app.base = Some((a, b, c, d));
            }
            app.active = true;
        } else if let Some(s) = what.strip_prefix("state changed : ") {
            // « Fully Installed, » a la fin d'une mise a jour, « Update Running » pendant
            if !s.contains("Update Running") {
                app.active = false;
                app.downloading = false;
            }
        } else if what.starts_with("update canceled") || what.starts_with("finished update") {
            app.active = false;
            app.downloading = false;
        }
    }
}

// ------------------------------------------------------- manifestes

struct Manifest {
    appid: String,
    name: String,
    flags: u64,
    done: u64,
    total: u64,
    staged: u64,
    to_stage: u64,
}

fn manifests() -> Vec<Manifest> {
    let mut out = Vec::new();
    for lib in crate::we::libraries() {
        let Ok(rd) = std::fs::read_dir(lib.join("steamapps")) else { continue };
        for e in rd.flatten() {
            let fname = e.file_name().to_string_lossy().to_string();
            let Some(appid) = fname.strip_prefix("appmanifest_").and_then(|s| s.strip_suffix(".acf")) else { continue };
            let Ok(acf) = std::fs::read_to_string(e.path()) else { continue };
            let num = |k| acf_value(&acf, k).and_then(|v| v.parse::<u64>().ok()).unwrap_or(0);
            out.push(Manifest {
                appid: appid.to_string(),
                name: acf_value(&acf, "name").unwrap_or("Steam").to_string(),
                flags: num("StateFlags"),
                done: num("BytesDownloaded"),
                total: num("BytesToDownload"),
                staged: num("BytesStaged"),
                to_stage: num("BytesToStage"),
            });
        }
    }
    out
}

// ---------------------------------------------------------------- GPU

/// NVML (`nvml.dll`, installee avec le pilote NVIDIA), chargee une fois :
/// un releve ne coute que quelques microsecondes, la ou `nvidia-smi` cree un
/// processus et initialise le pilote a chaque appel.
struct Nvml {
    dev: NvmlDevice,
    name: String,
    temp: unsafe extern "C" fn(NvmlDevice, u32, *mut u32) -> i32,
    util: unsafe extern "C" fn(NvmlDevice, *mut NvmlUtil) -> i32,
}

type NvmlDevice = *mut std::ffi::c_void;

#[repr(C)]
#[derive(Default)]
struct NvmlUtil {
    gpu: u32,
    memory: u32,
}

impl Nvml {
    fn open() -> Option<Nvml> {
        use windows::core::{s, HSTRING};
        use windows::Win32::System::LibraryLoader::{GetProcAddress, LoadLibraryExW, LOAD_LIBRARY_SEARCH_SYSTEM32};
        unsafe {
            // System32 (pilotes DCH), sinon le dossier NVSMI des anciens pilotes
            let lib = LoadLibraryExW(w!("nvml.dll"), None, LOAD_LIBRARY_SEARCH_SYSTEM32).ok().or_else(|| {
                let pf = std::env::var("ProgramW6432").or_else(|_| std::env::var("ProgramFiles")).ok()?;
                LoadLibraryExW(&HSTRING::from(format!(r"{pf}\NVIDIA Corporation\NVSMI\nvml.dll")), None, Default::default()).ok()
            })?;
            let init: unsafe extern "C" fn() -> i32 = std::mem::transmute(GetProcAddress(lib, s!("nvmlInit_v2"))?);
            let handle: unsafe extern "C" fn(u32, *mut NvmlDevice) -> i32 =
                std::mem::transmute(GetProcAddress(lib, s!("nvmlDeviceGetHandleByIndex_v2"))?);
            let name: unsafe extern "C" fn(NvmlDevice, *mut u8, u32) -> i32 =
                std::mem::transmute(GetProcAddress(lib, s!("nvmlDeviceGetName"))?);
            let n = Nvml {
                dev: std::ptr::null_mut(),
                name: String::new(),
                temp: std::mem::transmute(GetProcAddress(lib, s!("nvmlDeviceGetTemperature"))?),
                util: std::mem::transmute(GetProcAddress(lib, s!("nvmlDeviceGetUtilizationRates"))?),
            };
            if init() != 0 {
                return None;
            }
            let mut dev = std::ptr::null_mut();
            if handle(0, &mut dev) != 0 {
                return None;
            }
            let mut buf = [0u8; 96];
            let label = if name(dev, buf.as_mut_ptr(), buf.len() as u32) == 0 {
                let end = buf.iter().position(|&c| c == 0).unwrap_or(buf.len());
                String::from_utf8_lossy(&buf[..end]).trim_start_matches("NVIDIA ").to_string()
            } else {
                String::new()
            };
            let n = Nvml { dev, name: label, ..n };
            // une carte sans capteur (ou un pilote trop ancien) : nvidia-smi
            n.read().map(|_| n)
        }
    }

    fn read(&self) -> Option<Gpu> {
        let (mut temp, mut util) = (0u32, NvmlUtil::default());
        // 0 = NVML_TEMPERATURE_GPU
        let ok = unsafe { (self.temp)(self.dev, 0, &mut temp) == 0 && (self.util)(self.dev, &mut util) == 0 };
        ok.then(|| Gpu { name: self.name.clone(), temp, load: util.gpu })
    }
}

/// Repli sans NVML : un processus `nvidia-smi` par releve.
fn smi() -> Option<Gpu> {
    let out = Command::new("nvidia-smi")
        .args(["--query-gpu=name,temperature.gpu,utilization.gpu", "--format=csv,noheader,nounits"])
        .creation_flags(CREATE_NO_WINDOW)
        .output()
        .ok()?;
    let line = String::from_utf8_lossy(&out.stdout).lines().next()?.to_string();
    let f: Vec<&str> = line.split(',').map(str::trim).collect();
    Some(Gpu {
        name: f.first()?.trim_start_matches("NVIDIA ").to_string(),
        temp: f.get(1)?.parse().ok()?,
        load: f.get(2)?.parse().ok()?,
    })
}

// ------------------------------------------------------- jeu en cours

/// Executables qui tournent dans le dossier d'un jeu (hors outils courants).
const NOT_GAME: &[&str] = &["unitycrashhandler", "crashreport", "crashpad", "easyanticheat", "battleye", "redist", "setup", "unins"];

fn playing(app: &AppHandle, sys: &mut System) -> Option<(String, String, u32)> {
    let games: Vec<(String, String, PathBuf)> = app
        .state::<Games>()
        .0
        .lock()
        .ok()?
        .iter()
        // un dossier trop court (C:\) engloberait tout le disque
        .filter(|g| g.dir.components().count() > 2)
        .map(|g| (g.id.clone(), g.name.clone(), g.dir.clone()))
        .collect();
    sys.refresh_processes_specifics(
        ProcessesToUpdate::All,
        true,
        ProcessRefreshKind::nothing().with_exe(UpdateKind::OnlyIfNotSet),
    );
    for p in sys.processes().values() {
        let Some(exe) = p.exe() else { continue };
        let low = exe.to_string_lossy().to_lowercase();
        if NOT_GAME.iter().any(|n| low.contains(n)) {
            continue;
        }
        if let Some((id, name, _)) = games.iter().find(|(_, _, d)| exe.starts_with(d)) {
            return Some((id.clone(), name.clone(), p.pid().as_u32()));
        }
    }
    None
}

fn now_ms() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_millis() as u64)
}

// ------------------------------------------- partie trouvee (matchmaking)

/// Processus du jeu en cours (0 = aucun).
static GAME_PID: AtomicU32 = AtomicU32::new(0);
/// Dernier processus dont la fenetre a clignote dans la barre des taches, et quand.
static FLASH_PID: AtomicU32 = AtomicU32::new(0);
static FLASH_AT: AtomicU64 = AtomicU64::new(0);

fn fg_pid() -> u32 {
    let mut pid = 0u32;
    unsafe {
        GetWindowThreadProcessId(GetForegroundWindow(), Some(&mut pid));
    }
    pid
}

fn read_bytes(pid: u32) -> Option<u64> {
    unsafe {
        let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok()?;
        let mut io = IO_COUNTERS::default();
        let ok = GetProcessIoCounters(h, &mut io).is_ok();
        let _ = CloseHandle(h);
        ok.then_some(io.ReadTransferCount)
    }
}

/// Partie trouvee pendant que le joueur est ailleurs : le jeu fait clignoter sa
/// fenetre (CS2, LoL, Dota...) ou se met a charger la carte (lecture disque
/// soutenue, cas d'Apex).
struct MatchWatch {
    last: Option<u64>,
    hot: u32,
    since: u64,
    fired: bool,
}

/// lecture disque du jeu au-dela de laquelle on considere qu'il charge une carte
const LOAD_RATE: f64 = 25.0 * 1024.0 * 1024.0;

impl MatchWatch {
    fn new(pid: u32) -> Self {
        MatchWatch { last: if pid != 0 { read_bytes(pid) } else { None }, hot: 0, since: now_ms(), fired: false }
    }

    fn check(&mut self, pid: u32, dt: f64) -> bool {
        if self.fired {
            return false;
        }
        let flashed = FLASH_PID.load(Ordering::Relaxed) == pid && FLASH_AT.load(Ordering::Relaxed) > self.since;
        let now = read_bytes(pid);
        let loading = match (self.last, now) {
            (Some(a), Some(b)) if dt > 0.2 => (b.saturating_sub(a) as f64 / dt) > LOAD_RATE,
            _ => false,
        };
        self.last = now;
        self.hot = if loading { self.hot + 1 } else { 0 };
        // quelques secondes de calme d'abord : la sortie du jeu ne compte pas
        let settled = now_ms().saturating_sub(self.since) > 5000;
        if settled && (flashed || self.hot >= 2) {
            self.fired = true;
        }
        self.fired
    }
}

/// Ecoute les clignotements de fenetres (HSHELL_FLASH) via un crochet Shell.
fn flash_hook() {
    std::thread::spawn(|| unsafe {
        static MSG_ID: AtomicU32 = AtomicU32::new(0);
        unsafe extern "system" fn proc(h: HWND, m: u32, w: WPARAM, l: LPARAM) -> LRESULT {
            let id = MSG_ID.load(Ordering::Relaxed);
            // HSHELL_FLASH = HSHELL_REDRAW | HSHELL_HIGHBIT
            if id != 0 && m == id && (w.0 & 0x7fff) == 6 && w.0 & 0x8000 != 0 {
                let mut pid = 0u32;
                GetWindowThreadProcessId(HWND(l.0 as _), Some(&mut pid));
                FLASH_PID.store(pid, Ordering::Relaxed);
                FLASH_AT.store(now_ms(), Ordering::Relaxed);
            }
            DefWindowProcW(h, m, w, l)
        }
        let cls = w!("IlotFlashHook");
        let wc = WNDCLASSW { lpfnWndProc: Some(proc), lpszClassName: cls, ..Default::default() };
        RegisterClassW(&wc);
        let Ok(hwnd) = CreateWindowExW(WINDOW_EX_STYLE(0), cls, w!(""), WINDOW_STYLE(0), 0, 0, 0, 0, None, None, None, None) else {
            return;
        };
        MSG_ID.store(RegisterWindowMessageW(w!("SHELLHOOK")), Ordering::Relaxed);
        if !RegisterShellHookWindow(hwnd).as_bool() {
            return;
        }
        let mut msg = MSG::default();
        while GetMessageW(&mut msg, None, 0, 0).as_bool() {
            let _ = TranslateMessage(&msg);
            DispatchMessageW(&msg);
        }
    });
}

/// Ramene la fenetre du jeu au premier plan (clic sur « Partie trouvee »).
pub fn game_focus() -> bool {
    focus_pid(GAME_PID.load(Ordering::Relaxed))
}

/// Ramene au premier plan la fenetre principale d'un processus.
pub fn focus_pid(pid: u32) -> bool {
    if pid == 0 {
        return false;
    }
    unsafe extern "system" fn cb(h: HWND, l: LPARAM) -> BOOL {
        let st = &mut *(l.0 as *mut (u32, HWND));
        let mut pid = 0u32;
        GetWindowThreadProcessId(h, Some(&mut pid));
        if pid == st.0 && IsWindowVisible(h).as_bool() && GetWindowTextLengthW(h) > 0 {
            st.1 = h;
            return false.into();
        }
        true.into()
    }
    let mut st = (pid, HWND::default());
    unsafe {
        let _ = EnumWindows(Some(cb), LPARAM(&mut st as *mut _ as isize));
        if st.1.is_invalid() {
            return false;
        }
        if IsIconic(st.1).as_bool() {
            let _ = ShowWindow(st.1, SW_RESTORE);
        }
        SetForegroundWindow(st.1).as_bool()
    }
}

// ------------------------------------------------ bilan de session

/// Releves pris toutes les 3 s pendant qu'un jeu tourne.
#[derive(Default)]
struct Session {
    n: u32,
    cpu_sum: f64,
    cpu_max: f32,
    gpu_n: u32,
    gpu_sum: f64,
    gpu_max: u32,
    temp_max: u32,
    ram_max: u64,
}

/// Envoye a la fermeture du jeu : resume affiche dans l'ilot.
#[derive(Serialize, Clone)]
pub struct SessionReport {
    id: String,
    name: String,
    since: u64,
    secs: u64,
    cpu_avg: f32,
    cpu_max: f32,
    /// -1 sans carte NVIDIA
    gpu_avg: i32,
    gpu_max: i32,
    temp_max: i32,
    ram_max: u64,
    ram_total: u64,
}

/// Mise a jour Steam terminee : notification avec bouton Jouer.
#[derive(Serialize, Clone)]
pub struct SteamDone {
    appid: String,
    name: String,
}

// ------------------------------------------------------------- boucle

pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        // pas de carte NVIDIA (ou pilote sans NVML ni nvidia-smi) : on n'insiste pas
        let nvml = Nvml::open();
        let has_smi = nvml.is_none() && smi().is_some();
        let gpu = || nvml.as_ref().map_or_else(|| if has_smi { smi() } else { None }, Nvml::read);
        let mut gpu_now = None;
        let mut slow_at: Option<Instant> = None;
        let mut sys = System::new();
        let mut game: Option<Playing> = None;
        let mut log = LogTail::new();
        let mut at = Instant::now();
        // octets recus estimes par jeu
        let mut est: HashMap<String, u64> = HashMap::new();
        let mut last = None;
        // jeux en cours de mise a jour au tour precedent
        let mut updating: HashMap<String, String> = HashMap::new();
        let mut session = Session::default();
        let mut watch_mm = MatchWatch::new(0);
        flash_hook();
        // CPU en « utilite », comme le Gestionnaire des taches
        let pdh = crate::pdh::Query::new(&[r"\Processor Information(_Total)\% Processor Utility"]);
        loop {
            log.poll();
            let dt = at.elapsed().as_secs_f64();
            at = Instant::now();

            let mut downloads = Vec::new();
            for m in manifests() {
                let l = log.apps.get(&m.appid);
                let active = l.is_some_and(|l| l.active);
                let base = l.and_then(|l| l.base);
                let total = if m.total > 0 { m.total } else { base.map_or(0, |b| b.1) };
                let floor = m.done.max(base.map_or(0, |b| b.0));
                let to_stage = if m.to_stage > 0 { m.to_stage } else { base.map_or(0, |b| b.3) };
                let staged = m.staged.max(base.map_or(0, |b| b.2));
                let pending = (total > 0 && floor < total) || (to_stage > 0 && staged < to_stage);
                // le manifeste fait foi : sans « mise a jour commencee », rien en cours
                if !pending || m.flags & UPDATE_STARTED == 0 {
                    est.remove(&m.appid);
                    // plus rien a recevoir ni a installer : mise a jour finie
                    if let Some(name) = updating.remove(&m.appid) {
                        if !pending {
                            let _ = app.emit("steam-done", SteamDone { appid: m.appid.clone(), name });
                        }
                    }
                    continue;
                }
                updating.insert(m.appid.clone(), m.name.clone());
                let receiving = active && l.is_some_and(|l| l.downloading) && total > 0;
                // Steam ne recoit plus (le manifeste peut avoir du retard) : reception
                // finie si on en etait presque au bout, sinon simple preparation
                let got = est.get(&m.appid).copied().unwrap_or(floor).max(floor);
                let in_download = receiving || (total > 0 && got < total - total / 100);
                let d = if in_download {
                    // reception : avance au debit de Steam, sans jamais annoncer 100 %
                    // tant que Steam n'a pas fini de recevoir
                    let e = est.entry(m.appid.clone()).or_insert(floor);
                    *e = (*e).max(floor);
                    if receiving {
                        *e = (*e + (log.rate * dt) as u64).min(total - total / 1000);
                    }
                    Download { appid: m.appid, name: m.name, phase: "download".into(), done: *e, total, active, speed: if receiving { log.rate as u64 } else { 0 } }
                } else {
                    // installation : progression relevee par Steam (BytesStaged)
                    Download { appid: m.appid, name: m.name, phase: "install".into(), done: staged.min(to_stage), total: to_stage.max(1), active, speed: 0 }
                };
                downloads.push(d);
            }
            let busy = downloads.iter().any(|d| d.active);
            // le telechargement en cours d'abord
            downloads.sort_by_key(|d| !d.active);

            // releves plus lents (processus, GPU) : toutes les 3 s
            if slow_at.is_none_or(|t: Instant| t.elapsed() >= Duration::from_millis(2900)) {
                slow_at = Some(Instant::now());
                gpu_now = gpu();
                let found = playing(&app, &mut sys);
                GAME_PID.store(found.as_ref().map_or(0, |f| f.2), Ordering::Relaxed);
                let now = match found {
                    Some((id, _, _)) if game.as_ref().is_some_and(|g| g.id == id) => game.clone(),
                    Some((id, name, _)) => Some(Playing { id, name, since: now_ms(), away: 0 }),
                    None => None,
                };
                // jeu ferme (ou remplace) : bilan de la session
                if let Some(g) = game.as_ref().filter(|g| now.as_ref().is_none_or(|n| n.id != g.id)) {
                    if session.n > 0 {
                        let s = &session;
                        let r = SessionReport {
                            id: g.id.clone(),
                            name: g.name.clone(),
                            since: g.since,
                            secs: now_ms().saturating_sub(g.since) / 1000,
                            cpu_avg: (s.cpu_sum / s.n as f64) as f32,
                            cpu_max: s.cpu_max,
                            gpu_avg: if s.gpu_n > 0 { (s.gpu_sum / s.gpu_n as f64).round() as i32 } else { -1 },
                            gpu_max: if s.gpu_n > 0 { s.gpu_max as i32 } else { -1 },
                            temp_max: if s.gpu_n > 0 { s.temp_max as i32 } else { -1 },
                            ram_max: s.ram_max,
                            ram_total: sys.total_memory(),
                        };
                        let _ = app.emit("game-session", r);
                    }
                    session = Session::default();
                }
                game = now;
                if game.is_some() {
                    sys.refresh_memory();
                    let cpu = pdh
                        .as_ref()
                        .and_then(|q| {
                            q.collect();
                            q.value(0, "_Total")
                        })
                        .unwrap_or(0.0)
                        .clamp(0.0, 100.0) as f32;
                    let s = &mut session;
                    s.n += 1;
                    s.cpu_sum += cpu as f64;
                    s.cpu_max = s.cpu_max.max(cpu);
                    s.ram_max = s.ram_max.max(sys.used_memory());
                    if let Some(g) = &gpu_now {
                        s.gpu_n += 1;
                        s.gpu_sum += g.load as f64;
                        s.gpu_max = s.gpu_max.max(g.load);
                        s.temp_max = s.temp_max.max(g.temp);
                    }
                }
            }
            // joueur sorti du jeu (autre fenetre) : guette la partie trouvee
            if let Some(g) = game.as_mut() {
                let pid = GAME_PID.load(Ordering::Relaxed);
                let away = pid != 0 && fg_pid() != pid;
                if away && g.away == 0 {
                    g.away = now_ms();
                    watch_mm = MatchWatch::new(pid);
                } else if !away && g.away != 0 {
                    g.away = 0;
                }
                if away && watch_mm.check(pid, dt) {
                    let _ = app.emit("match-found", g.name.clone());
                }
            }
            let a = Activity { downloads, gpu: gpu_now.clone(), game: game.clone() };
            if last.as_ref() != Some(&a) {
                let _ = app.emit("gaming", &a);
                last = Some(a);
            }
            // chaque seconde pendant un telechargement, sinon toutes les 3 s
            // chaque seconde aussi quand le joueur attend hors du jeu
            let waiting = game.as_ref().is_some_and(|g| g.away != 0);
            std::thread::sleep(Duration::from_secs(if busy || waiting { 1 } else { 3 }));
        }
    });
}
