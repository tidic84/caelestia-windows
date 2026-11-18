//! Addon Akira : lance l'assistante vocale AkiraVoice (Python) et relaie son
//! etat a l'interface (evenement `akira`).
//!
//! L'ilot ecoute sur 127.0.0.1 (port choisi par Windows) et lance
//! `<dossier>\.venv\Scripts\python.exe -m akira`, avec `AKIRA_ILOT`
//! (adresse) et `AKIRA_ILOT_TOKEN` (jeton tire au hasard a chaque demarrage
//! de l'ilot). Akira se connecte, envoie `{"hello": jeton}`, puis des lignes
//! JSON `{"ev": …}` emises telles quelles vers l'interface. Une connexion
//! sans le bon jeton est fermee. Les commandes de l'interface (`akira_send`)
//! repartent par la meme connexion.
//!
//! Le processus est lance suspendu, place dans un Job « tue a la fermeture »,
//! puis reveille : le `python.exe` d'un venv est un lanceur qui demarre le
//! vrai Python, qui herite ainsi du Job. Tout disparait avec l'ilot, meme
//! apres un plantage. Sortie et erreurs : `akira.log` dans
//! `%LOCALAPPDATA%\Ilot` (vide a chaque lancement).

use std::io::{BufRead, BufReader, Read, Seek, SeekFrom, Write};
use std::net::{Shutdown, TcpListener, TcpStream};
use std::os::windows::io::AsRawHandle;
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::{Child, Command, Stdio};
use std::sync::atomic::{AtomicUsize, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use serde::Serialize;
use serde_json::{json, Value};
use windows::core::PCWSTR;
use windows::Win32::Foundation::{CloseHandle, HANDLE};
use windows::Win32::System::Diagnostics::ToolHelp::{
    CreateToolhelp32Snapshot, Thread32First, Thread32Next, TH32CS_SNAPTHREAD, THREADENTRY32,
};
use windows::Win32::System::JobObjects::{
    AssignProcessToJobObject, CreateJobObjectW, JobObjectExtendedLimitInformation, SetInformationJobObject,
    TerminateJobObject, JOBOBJECT_EXTENDED_LIMIT_INFORMATION, JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE,
};
use windows::Win32::System::Threading::{OpenThread, ResumeThread, THREAD_SUSPEND_RESUME};

use crate::host::AppHandle;

const CREATE_NO_WINDOW: u32 = 0x0800_0000;
const CREATE_SUSPENDED: u32 = 0x0000_0004;
/// Ligne la plus longue acceptee d'Akira (un sous-titre fait quelques Ko).
const MAX_LINE: u64 = 256 * 1024;
/// Presentation (`hello`) : courte, et peu de connexions en attente a la fois.
const MAX_HELLO: u64 = 1024;
const MAX_PENDING: usize = 8;
static PENDING: AtomicUsize = AtomicUsize::new(0);
/// Commandes que l'interface peut envoyer a Akira.
const COMMANDS: &[&str] = &["toggle"];

#[derive(Clone, Default, PartialEq, Serialize)]
pub struct Status {
    /// processus Python lance
    running: bool,
    /// Akira connectee (jeton verifie)
    online: bool,
    /// dernier probleme (dossier, demarrage, arret inattendu), vide sinon
    error: String,
    /// dossier d'AkiraVoice choisi dans les Reglages
    dir: String,
}

struct Proc {
    child: Child,
    /// Job (HANDLE en entier : `HANDLE` n'est pas `Send`)
    job: isize,
    dir: String,
    started: Instant,
}

#[derive(Default)]
struct Inner {
    port: u16,
    token: String,
    proc: Option<Proc>,
    /// moitie « ecriture » de la connexion d'Akira, et son numero
    conn: Option<(u64, TcpStream)>,
    serial: u64,
    status: Status,
    /// prochain essai de lancement apres un echec (reprise espacee)
    retry_at: Option<Instant>,
    backoff: u64,
    /// dossier voulu au tour precedent : un autre dossier repart de zero
    last_want: Option<String>,
    /// relance demandee depuis les Reglages
    restart: bool,
    /// l'ilot quitte : plus de lancement
    closing: bool,
}

#[derive(Default)]
pub struct Akira(Mutex<Inner>);

fn emit_status(app: &AppHandle, st: &Status) {
    let mut v = serde_json::to_value(st).unwrap_or(Value::Null);
    if let Some(o) = v.as_object_mut() {
        o.insert("ev".into(), "status".into());
    }
    let _ = app.emit("akira", v);
}

fn log_file() -> PathBuf {
    crate::store::data_dir().join("akira.log")
}

/// Fin du journal (64 Ko au plus), meme s'il contient des octets non UTF-8.
fn log_tail() -> String {
    let Ok(mut f) = std::fs::File::open(log_file()) else { return String::new() };
    let len = f.metadata().map(|m| m.len()).unwrap_or(0);
    let _ = f.seek(SeekFrom::Start(len.saturating_sub(64 * 1024)));
    let mut buf = Vec::new();
    let _ = f.read_to_end(&mut buf);
    String::from_utf8_lossy(&buf).into_owned()
}

/// Derniere ligne utile du journal (souvent l'erreur qui a arrete Akira).
fn last_error() -> String {
    log_tail()
        .lines()
        .rev()
        .map(str::trim)
        .find(|l| !l.is_empty() && !l.starts_with("Traceback") && !l.starts_with('^') && !l.starts_with('~'))
        .map(|l| l.chars().take(300).collect())
        .unwrap_or_default()
}

fn wanted_dir(app: &AppHandle) -> Option<String> {
    if !crate::settings::addon_on(app, "akira") {
        return None;
    }
    let st = app.state::<crate::settings::Settings>();
    let cfg = st.0.lock().unwrap();
    cfg.extra
        .get("akira_dir")
        .and_then(Value::as_str)
        .map(str::trim)
        // dossier local seulement (pas de partage reseau \\hote\...)
        .filter(|d| !d.is_empty() && !d.starts_with("\\\\") && !d.starts_with("//"))
        .map(String::from)
}

fn python(dir: &str) -> PathBuf {
    Path::new(dir).join(".venv").join("Scripts").join("python.exe")
}

unsafe fn new_job() -> Option<HANDLE> {
    let job = CreateJobObjectW(None, PCWSTR::null()).ok()?;
    let mut info = JOBOBJECT_EXTENDED_LIMIT_INFORMATION::default();
    info.BasicLimitInformation.LimitFlags = JOB_OBJECT_LIMIT_KILL_ON_JOB_CLOSE;
    let ok = SetInformationJobObject(
        job,
        JobObjectExtendedLimitInformation,
        &info as *const _ as *const core::ffi::c_void,
        std::mem::size_of::<JOBOBJECT_EXTENDED_LIMIT_INFORMATION>() as u32,
    );
    if ok.is_err() {
        let _ = CloseHandle(job);
        return None;
    }
    Some(job)
}

/// Reveille les threads d'un processus lance suspendu.
unsafe fn resume(pid: u32) -> bool {
    let Ok(snap) = CreateToolhelp32Snapshot(TH32CS_SNAPTHREAD, 0) else { return false };
    let mut e = THREADENTRY32 { dwSize: std::mem::size_of::<THREADENTRY32>() as u32, ..Default::default() };
    let mut n = 0;
    let mut more = Thread32First(snap, &mut e).is_ok();
    while more {
        if e.th32OwnerProcessID == pid {
            if let Ok(h) = OpenThread(THREAD_SUSPEND_RESUME, false, e.th32ThreadID) {
                if ResumeThread(h) != u32::MAX {
                    n += 1;
                }
                let _ = CloseHandle(h);
            }
        }
        more = Thread32Next(snap, &mut e).is_ok();
    }
    let _ = CloseHandle(snap);
    n > 0
}

fn spawn(inner: &Inner, dir: &str) -> Result<Proc, String> {
    let exe = python(dir);
    if !Path::new(dir).join("akira").is_dir() {
        return Err("Ce dossier ne contient pas AkiraVoice (dossier « akira » absent)".into());
    }
    if !exe.is_file() {
        return Err("Pas d'environnement Python dans ce dossier (.venv) : voir l'installation dans le README d'Akira".into());
    }
    let log = std::fs::File::create(log_file()).map_err(|e| format!("journal akira.log : {e}"))?;
    let err = log.try_clone().map_err(|e| e.to_string())?;
    let job = unsafe { new_job() }.ok_or("impossible de créer le Job Windows")?;
    let close_job = || unsafe {
        let _ = CloseHandle(job);
    };
    let child = Command::new(&exe)
        .args(["-m", "akira"])
        .current_dir(dir)
        .env("AKIRA_ILOT", format!("127.0.0.1:{}", inner.port))
        .env("AKIRA_ILOT_TOKEN", &inner.token)
        .env("PYTHONUNBUFFERED", "1")
        .env("PYTHONIOENCODING", "utf-8")
        .env("PYTHONUTF8", "1")
        .creation_flags(CREATE_NO_WINDOW | CREATE_SUSPENDED)
        .stdin(Stdio::null())
        .stdout(log)
        .stderr(err)
        .spawn();
    let mut child = match child {
        Ok(c) => c,
        Err(e) => {
            close_job();
            return Err(format!("lancement impossible : {e}"));
        }
    };
    // dans le Job avant de demarrer : ses enfants y seront aussi
    let fail = |child: &mut Child, why: &str| {
        let _ = child.kill();
        let _ = child.wait();
        close_job();
        Err(why.to_string())
    };
    if unsafe { AssignProcessToJobObject(job, HANDLE(child.as_raw_handle())) }.is_err() {
        return fail(&mut child, "impossible de placer Akira dans un Job Windows");
    }
    if !unsafe { resume(child.id()) } {
        return fail(&mut child, "impossible de démarrer Akira (processus resté suspendu)");
    }
    Ok(Proc { child, job: job.0 as isize, dir: dir.to_string(), started: Instant::now() })
}

/// Arrete Akira : `quit` (taches et navigateur fermes proprement), puis le
/// Job entier au bout de `grace`.
fn stop(app: &AppHandle, mut p: Proc, grace: Duration) {
    let sent = send_raw(app, &json!({ "cmd": "quit" }));
    let until = Instant::now() + if sent { grace } else { Duration::ZERO };
    while Instant::now() < until {
        if matches!(p.child.try_wait(), Ok(Some(_))) {
            break;
        }
        std::thread::sleep(Duration::from_millis(100));
    }
    unsafe {
        let job = HANDLE(p.job as *mut core::ffi::c_void);
        let _ = TerminateJobObject(job, 1);
        let _ = CloseHandle(job);
    }
    // au cas ou le Job n'aurait rien tue : jamais d'attente sans fin
    let _ = p.child.kill();
    let _ = p.child.wait();
}

/// Surveille l'addon (active, dossier) et le processus, une fois par seconde.
fn supervise(app: AppHandle) {
    loop {
        std::thread::sleep(Duration::from_secs(1));
        let want = wanted_dir(&app);
        let st = app.state::<Akira>();
        let mut g = st.0.lock().unwrap();
        if g.closing {
            return;
        }
        let before = g.status.clone();
        g.status.dir = want.clone().unwrap_or_default();
        // autre dossier, addon coupe ou rallume : l'attente d'un echec ne compte plus
        if g.last_want != want {
            g.last_want = want.clone();
            g.retry_at = None;
            g.backoff = 0;
            g.status.error.clear();
        }

        // arret : addon coupe, dossier change, relance demandee
        let restart = std::mem::take(&mut g.restart);
        let stale = g.proc.as_ref().is_some_and(|p| restart || want.as_deref() != Some(p.dir.as_str()));
        if stale {
            let p = g.proc.take().unwrap();
            drop(g);
            stop(&app, p, Duration::from_secs(4));
            g = st.0.lock().unwrap();
            g.status.running = false;
            g.status.error.clear();
            g.retry_at = None;
            g.backoff = 0;
            if g.closing {
                return;
            }
        }

        // sortie inattendue
        let exited = g.proc.as_mut().and_then(|p| p.child.try_wait().ok().flatten().map(|c| (c, p.started.elapsed())));
        if let Some((code, ran)) = exited {
            let p = g.proc.take().unwrap();
            unsafe {
                let _ = CloseHandle(HANDLE(p.job as *mut core::ffi::c_void));
            }
            g.status.running = false;
            let why = last_error();
            g.status.error = if why.is_empty() { format!("Akira s'est arrêtée (code {})", code.code().unwrap_or(-1)) } else { why };
            // plantage au demarrage (cle absente...) : essais espaces jusqu'a 5 min
            g.backoff = if ran < Duration::from_secs(30) { (g.backoff * 2).clamp(10, 300) } else { 3 };
            g.retry_at = Some(Instant::now() + Duration::from_secs(g.backoff));
        }

        // lancement
        if let (Some(dir), None) = (want.as_deref(), g.proc.as_ref()) {
            if g.retry_at.is_none_or(|t| Instant::now() >= t) {
                match spawn(&g, dir) {
                    Ok(p) => {
                        g.proc = Some(p);
                        g.status.running = true;
                        g.status.error.clear();
                        g.retry_at = None;
                    }
                    Err(e) => {
                        g.status.error = e;
                        g.backoff = 30;
                        g.retry_at = Some(Instant::now() + Duration::from_secs(30));
                    }
                }
            }
        }
        if want.is_none() {
            g.status.error.clear();
        }
        // sous le verrou : un etat plus ancien ne passe jamais apres (serve)
        if g.status != before {
            emit_status(&app, &g.status);
        }
    }
}

/// Une connexion entrante : jeton, puis les evenements d'Akira.
fn serve(app: AppHandle, stream: TcpStream) {
    let pending = Pending;
    let _ = stream.set_read_timeout(Some(Duration::from_secs(3)));
    let _ = stream.set_write_timeout(Some(Duration::from_secs(1)));
    let Ok(write) = stream.try_clone() else { return };
    let mut reader = BufReader::new(stream);
    let mut line = Vec::new();
    let ok = reader.by_ref().take(MAX_HELLO).read_until(b'\n', &mut line).unwrap_or(0) > 0;
    let token = app.state::<Akira>().0.lock().unwrap().token.clone();
    let hello: Value = serde_json::from_slice(&line).unwrap_or(Value::Null);
    if !ok || hello.get("hello").and_then(Value::as_str) != Some(token.as_str()) {
        let _ = write.shutdown(Shutdown::Both);
        return;
    }
    drop(pending);
    let _ = reader.get_ref().set_read_timeout(None);
    let id = {
        let st = app.state::<Akira>();
        let mut g = st.0.lock().unwrap();
        g.serial += 1;
        let id = g.serial;
        if let Some((_, old)) = g.conn.replace((id, write)) {
            let _ = old.shutdown(Shutdown::Both);
        }
        g.status.online = true;
        emit_status(&app, &g.status);
        id
    };
    loop {
        line.clear();
        match read_line(&mut reader, &mut line) {
            Ok(0) | Err(_) => break,
            Ok(_) => {}
        }
        if let Ok(v) = serde_json::from_slice::<Value>(&line) {
            if v.get("ev").and_then(Value::as_str).is_some_and(|e| e != "status") {
                let _ = app.emit("akira", v);
            }
        }
    }
    let st = app.state::<Akira>();
    let mut g = st.0.lock().unwrap();
    if g.conn.as_ref().is_some_and(|(n, _)| *n == id) {
        g.conn = None;
        g.status.online = false;
        emit_status(&app, &g.status);
    }
}

/// Lit une ligne de `MAX_LINE` octets au plus (au-dela : connexion fermee).
fn read_line(r: &mut BufReader<TcpStream>, buf: &mut Vec<u8>) -> std::io::Result<usize> {
    let n = r.by_ref().take(MAX_LINE).read_until(b'\n', buf)?;
    if n as u64 >= MAX_LINE && buf.last() != Some(&b'\n') {
        return Err(std::io::Error::other("ligne trop longue"));
    }
    Ok(n)
}

/// Ecrit une ligne a Akira (1 s au plus : la connexion a un delai d'ecriture).
fn send_raw(app: &AppHandle, v: &Value) -> bool {
    let st = app.state::<Akira>();
    let g = st.0.lock().unwrap();
    let Some((_, conn)) = g.conn.as_ref() else { return false };
    let mut w = conn;
    w.write_all(format!("{v}\n").as_bytes()).is_ok()
}

// -------------------------------------------------------------- commandes

pub fn akira_status(app: AppHandle) -> Status {
    app.state::<Akira>().0.lock().unwrap().status.clone()
}

/// Envoie une commande a Akira (`toggle` : reveil ou mise en veille).
pub fn akira_send(app: AppHandle, cmd: String) -> bool {
    COMMANDS.contains(&cmd.as_str()) && send_raw(&app, &json!({ "cmd": cmd }))
}

/// Relance Akira (Reglages), ou reessaie tout de suite apres un echec.
pub fn akira_restart(app: AppHandle) {
    let st = app.state::<Akira>();
    let mut g = st.0.lock().unwrap();
    g.restart = g.proc.is_some();
    g.retry_at = None;
    g.backoff = 0;
}

/// Fin du journal d'Akira (Reglages), 40 lignes au plus.
pub fn akira_log() -> String {
    let text = log_tail();
    let lines: Vec<&str> = text.lines().collect();
    lines[lines.len().saturating_sub(40)..].join("\n")
}

/// L'ilot quitte (ou se met a jour) : Akira s'arrete proprement (3 s au
/// plus), sinon le Job la tue avec l'ilot.
pub fn shutdown(app: &AppHandle) {
    // appele hors de `ilot_start` (diagnostic) : pas d'etat, rien a arreter
    let p = std::panic::catch_unwind(|| {
        let st = app.state::<Akira>();
        let mut g = st.0.lock().unwrap();
        g.closing = true;
        g.proc.take()
    });
    if let Ok(Some(p)) = p {
        stop(app, p, Duration::from_secs(3));
    }
}

pub fn init(app: AppHandle) {
    let listener = TcpListener::bind("127.0.0.1:0");
    let port = listener.as_ref().ok().and_then(|l| l.local_addr().ok()).map(|a| a.port()).unwrap_or(0);
    let mut key = [0u8; 24];
    rand::RngCore::fill_bytes(&mut rand::rngs::OsRng, &mut key);
    let token: String = key.iter().map(|b| format!("{b:02x}")).collect();
    // l'etat existe toujours : les commandes ne trouvent jamais d'etat absent
    app.manage(Akira(Mutex::new(Inner { port, token, ..Default::default() })));
    let listener = match listener {
        Ok(l) if port != 0 => l,
        _ => {
            app.state::<Akira>().0.lock().unwrap().status.error = "port local indisponible : Akira ne peut pas être reliée".into();
            return;
        }
    };
    std::thread::spawn(move || {
        for stream in listener.incoming().flatten() {
            // connexions pas encore presentees : quelques-unes a la fois
            if PENDING.fetch_add(1, Ordering::SeqCst) >= MAX_PENDING {
                PENDING.fetch_sub(1, Ordering::SeqCst);
                continue;
            }
            std::thread::spawn(move || serve(AppHandle, stream));
        }
    });
    std::thread::spawn(move || supervise(app));
}

/// Place parmi les connexions en attente, rendue des que la presentation est
/// faite ou ratee.
struct Pending;
impl Drop for Pending {
    fn drop(&mut self) {
        PENDING.fetch_sub(1, Ordering::SeqCst);
    }
}
