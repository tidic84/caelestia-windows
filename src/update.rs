//! Mises a jour : derniere version publiee sur GitHub (Releases), archive
//! telechargee dans `%LOCALAPPDATA%\Ilot\update`, puis installee par un petit
//! script PowerShell qui attend la fin de l'ilot, remplace ses fichiers et le
//! relance. Notes de version : `CHANGELOG.md`, embarque dans le coeur.
//! Releve au demarrage puis toutes les 6 h, envoye a l'interface (`update`).

use std::io::{Read, Write};
use std::os::windows::process::CommandExt;
use std::path::PathBuf;
use std::process::Command;
use std::sync::Mutex;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use crate::host::AppHandle;

const REPO: &str = "tidic84/caelestia-windows";
pub const VERSION: &str = env!("CARGO_PKG_VERSION");
const CHANGELOG: &str = include_str!("../CHANGELOG.md");
const CREATE_NO_WINDOW: u32 = 0x0800_0000;
const EVERY: Duration = Duration::from_secs(6 * 3600);

/// Etat envoye a l'interface
#[derive(Serialize, Clone, Default)]
pub struct Update {
    current: &'static str,
    /// derniere version publiee (« 0.4.0 »), vide si jamais relevee
    latest: String,
    available: bool,
    /// notes de la version publiee (Markdown)
    notes: String,
    /// page de la version sur GitHub
    url: String,
    published: String,
    size: u64,
    /// idle, checking, downloading, ready, installing, error
    status: &'static str,
    /// avancement du telechargement (0-1)
    progress: f32,
    error: String,
    /// dernier releve, en secondes depuis 1970
    checked: u64,
    #[serde(skip)]
    asset: String,
    #[serde(skip)]
    sha256: String,
    /// signature de l'archive (`<archive>.sig`), vide si la version n'en a pas
    #[serde(skip)]
    sig: String,
}

static STATE: Mutex<Option<Update>> = Mutex::new(None);

fn with<R>(f: impl FnOnce(&mut Update) -> R) -> R {
    let mut st = STATE.lock().unwrap();
    let u = st.get_or_insert_with(|| Update { current: VERSION, status: "idle", ..Default::default() });
    f(u)
}

fn snapshot() -> Update {
    with(|u| u.clone())
}

fn publish(app: &AppHandle) -> Update {
    let u = snapshot();
    let _ = app.emit("update", &u);
    u
}

fn dir() -> PathBuf {
    let d = crate::store::data_dir().join("update");
    let _ = std::fs::create_dir_all(&d);
    d
}

/// « v0.4.0 » -> [0, 4, 0] (suffixe -beta... ignore)
fn parse(v: &str) -> Vec<u32> {
    v.trim()
        .trim_start_matches(['v', 'V'])
        .split(['-', '+'])
        .next()
        .unwrap_or("")
        .split('.')
        .map(|p| p.parse().unwrap_or(0))
        .collect()
}

pub fn newer(a: &str, b: &str) -> bool {
    let (mut a, mut b) = (parse(a), parse(b));
    let n = a.len().max(b.len());
    a.resize(n, 0);
    b.resize(n, 0);
    a > b
}

fn now() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map(|d| d.as_secs()).unwrap_or(0)
}

// ------------------------------------------------------------------ GitHub

#[derive(Deserialize)]
struct Release {
    tag_name: String,
    #[serde(default)]
    body: Option<String>,
    #[serde(default)]
    html_url: String,
    #[serde(default)]
    published_at: Option<String>,
    #[serde(default)]
    assets: Vec<Asset>,
}

#[derive(Deserialize)]
struct Asset {
    name: String,
    browser_download_url: String,
    #[serde(default)]
    size: u64,
    /// « sha256:... » (GitHub le calcule pour chaque fichier publie)
    #[serde(default)]
    digest: Option<String>,
}

fn latest_release() -> Result<Release, String> {
    crate::http()
        .get(&format!("https://api.github.com/repos/{REPO}/releases/latest"))
        .set("User-Agent", "ilot")
        .set("Accept", "application/vnd.github+json")
        .timeout(Duration::from_secs(15))
        .call()
        .map_err(|e| match e {
            ureq::Error::Status(404, _) => "Aucune version publiée".to_string(),
            ureq::Error::Status(code, _) => format!("GitHub a répondu {code}"),
            e => format!("GitHub injoignable ({e})"),
        })?
        .into_json()
        .map_err(|e| format!("Réponse illisible ({e})"))
}

/// Archive Windows de la version : `ilot-<version>-win64.zip`
fn pick_asset(r: &Release) -> Option<&Asset> {
    let zips = || r.assets.iter().filter(|a| a.name.to_ascii_lowercase().ends_with(".zip"));
    zips().find(|a| a.name.to_ascii_lowercase().contains("win")).or_else(|| zips().next())
}

fn check(app: &AppHandle) -> Update {
    let busy = with(|u| {
        let busy = matches!(u.status, "downloading" | "installing");
        if !busy {
            u.status = "checking";
            u.error.clear();
        }
        busy
    });
    if busy {
        return snapshot();
    }
    publish(app);
    match latest_release() {
        Ok(r) => with(|u| {
            let latest = r.tag_name.trim_start_matches(['v', 'V']).to_string();
            let asset = pick_asset(&r);
            // la meme version deja telechargee reste prete
            let ready = pending().is_some_and(|p| p.version == latest);
            u.available = newer(&latest, VERSION) && asset.is_some();
            u.latest = latest;
            u.notes = r.body.clone().unwrap_or_default();
            u.url = r.html_url.clone();
            u.published = r.published_at.clone().unwrap_or_default();
            u.asset = asset.map(|a| a.browser_download_url.clone()).unwrap_or_default();
            u.size = asset.map(|a| a.size).unwrap_or(0);
            u.sha256 = asset
                .and_then(|a| a.digest.as_deref())
                .and_then(|d| d.strip_prefix("sha256:"))
                .unwrap_or_default()
                .to_string();
            u.sig = asset
                .and_then(|a| {
                    let name = format!("{}.sig", a.name);
                    r.assets.iter().find(|s| s.name.eq_ignore_ascii_case(&name))
                })
                .map(|s| s.browser_download_url.clone())
                .unwrap_or_default();
            u.checked = now();
            u.status = if ready { "ready" } else { "idle" };
        }),
        Err(e) => with(|u| {
            u.status = "error";
            u.error = e;
            u.checked = now();
        }),
    }
    publish(app)
}

// ----------------------------------------------------------- telechargement

/// Archive telechargee, en attente d'installation
#[derive(Serialize, Deserialize)]
struct Pending {
    version: String,
    zip: PathBuf,
    sha256: String,
    /// signature verifiee (une archive telechargee par une version qui ne
    /// verifiait pas n'est pas installee)
    #[serde(default)]
    signed: bool,
}

fn pending() -> Option<Pending> {
    let p: Pending = serde_json::from_str(&std::fs::read_to_string(dir().join("pending.json")).ok()?).ok()?;
    (p.signed && p.zip.exists() && newer(&p.version, VERSION)).then_some(p)
}

// ---------------------------------------------------------------- signature

/// Cle publique des versions (ECDSA P-256, SEC1 en base64). La cle privee
/// reste sur le poste qui publie (`release.ps1`, `examples/sign.rs`) : un
/// compte GitHub pirate ne suffit pas a faire installer une fausse archive.
const SIGN_KEY: &str = "AvUM28q7Ibz+YxT55VoBno1wrvC8P8TOX6StiTxYVZjY";

/// Message signe : l'archive, puis `\nilot <version>` (une archive signee
/// ne peut pas etre republiee sous un autre numero). Meme calcul que
/// `examples/sign.rs`.
fn signed_message(zip: &Sha256, version: &str) -> Sha256 {
    let mut h = zip.clone();
    h.update(format!("\nilot {version}").as_bytes());
    h
}

fn verify(msg: Sha256, sig_b64: &str) -> Result<(), String> {
    verify_with(SIGN_KEY, msg, sig_b64)
}

fn verify_with(key_b64: &str, msg: Sha256, sig_b64: &str) -> Result<(), String> {
    use base64::Engine;
    use p256::ecdsa::signature::DigestVerifier;
    use p256::ecdsa::{Signature, VerifyingKey};
    let b64 = base64::engine::general_purpose::STANDARD;
    let key = b64.decode(key_b64).ok().and_then(|k| VerifyingKey::from_sec1_bytes(&k).ok()).ok_or("Clé de signature invalide")?;
    let sig = b64
        .decode(sig_b64.trim())
        .ok()
        .and_then(|s| Signature::from_slice(&s).ok())
        .ok_or("Signature illisible")?;
    key.verify_digest(msg, &sig).map_err(|_| "Signature invalide : archive refusée".to_string())
}

fn hex(b: &[u8]) -> String {
    b.iter().map(|x| format!("{x:02X}")).collect()
}

fn download(app: &AppHandle) -> Result<(), String> {
    let (url, version, size, digest, sig_url) =
        with(|u| (u.asset.clone(), u.latest.clone(), u.size, u.sha256.clone(), u.sig.clone()));
    if url.is_empty() || !newer(&version, VERSION) {
        return Err("Pas de mise à jour à télécharger".into());
    }
    if sig_url.is_empty() {
        return Err("Version non signée : mise à jour refusée".into());
    }
    let sig = crate::http()
        .get(&sig_url)
        .set("User-Agent", "ilot")
        .timeout(Duration::from_secs(30))
        .call()
        .map_err(|e| format!("Signature introuvable ({e})"))?
        .into_string()
        .map_err(|e| format!("Signature illisible ({e})"))?;
    let resp = crate::http()
        .get(&url)
        .set("User-Agent", "ilot")
        // une archive d'une centaine de Mo sur une connexion lente
        .timeout(Duration::from_secs(30 * 60))
        .call()
        .map_err(|e| format!("Téléchargement impossible ({e})"))?;
    let total = resp.header("Content-Length").and_then(|s| s.parse::<u64>().ok()).unwrap_or(size).max(1);
    let zip = dir().join(format!("ilot-{version}.zip"));
    let part = zip.with_extension("zip.part");
    let mut out = std::fs::File::create(&part).map_err(|e| e.to_string())?;
    let mut rd = resp.into_reader();
    let mut buf = vec![0u8; 64 * 1024];
    let mut got = 0u64;
    let mut hash = Sha256::new();
    let mut last = Instant::now();
    loop {
        let n = rd.read(&mut buf).map_err(|e| format!("Téléchargement interrompu ({e})"))?;
        if n == 0 {
            break;
        }
        out.write_all(&buf[..n]).map_err(|e| e.to_string())?;
        hash.update(&buf[..n]);
        got += n as u64;
        if last.elapsed() > Duration::from_millis(250) {
            last = Instant::now();
            with(|u| u.progress = (got as f32 / total as f32).min(1.0));
            publish(app);
        }
    }
    drop(out);
    if size > 0 && got != size {
        let _ = std::fs::remove_file(&part);
        return Err("Archive incomplète".into());
    }
    // somme de l'archive recue : le script d'installation la reverifie
    let sha256 = hex(&hash.clone().finalize());
    let checked = if !digest.is_empty() && !digest.eq_ignore_ascii_case(&sha256) {
        Err("Archive corrompue (somme SHA-256)".to_string())
    } else {
        verify(signed_message(&hash, &version), &sig)
    };
    if let Err(e) = checked {
        let _ = std::fs::remove_file(&part);
        return Err(e);
    }
    std::fs::rename(&part, &zip).map_err(|e| e.to_string())?;
    let p = Pending { version, zip, sha256, signed: true };
    std::fs::write(dir().join("pending.json"), serde_json::to_string(&p).unwrap_or_default()).map_err(|e| e.to_string())?;
    Ok(())
}

fn fetch(app: &AppHandle) {
    let go = with(|u| {
        let go = u.available && !matches!(u.status, "downloading" | "installing" | "ready");
        if go {
            u.status = "downloading";
            u.progress = 0.0;
            u.error.clear();
        }
        go
    });
    if !go {
        return;
    }
    publish(app);
    let r = download(app);
    with(|u| match r {
        Ok(()) => {
            u.status = "ready";
            u.progress = 1.0;
        }
        Err(e) => {
            u.status = "error";
            u.error = e;
        }
    });
    publish(app);
}

// ------------------------------------------------------------- installation

/// Attend la fin de l'ilot, verifie l'archive, la decompresse, copie les
/// fichiers par-dessus l'installation et relance l'ilot (meme en cas d'echec).
const SCRIPT: &str = r#"param([int]$Wait, [string]$Zip, [string]$Dest, [string]$Sha, [string]$Version)
$ErrorActionPreference = "Stop"
$dir = Split-Path -Parent $Zip
$log = Join-Path $dir "update.log"
try {
    Wait-Process -Id $Wait -Timeout 30 -ErrorAction SilentlyContinue
    Start-Sleep -Milliseconds 300
    if ($Sha -and (Get-FileHash -LiteralPath $Zip -Algorithm SHA256).Hash -ne $Sha) { throw "Archive corrompue (somme SHA-256)" }
    $tmp = Join-Path $dir "extract"
    if (Test-Path $tmp) { Remove-Item $tmp -Recurse -Force }
    Expand-Archive -LiteralPath $Zip -DestinationPath $tmp -Force
    $exe = Get-ChildItem $tmp -Recurse -Filter ilot.exe | Select-Object -First 1
    if (-not $exe) { throw "ilot.exe absent de l'archive" }
    robocopy $exe.DirectoryName $Dest /E /R:5 /W:1 /NFL /NDL /NJH /NJS /NP | Out-Null
    if ($LASTEXITCODE -ge 8) { throw "Copie impossible dans $Dest (robocopy $LASTEXITCODE)" }
    Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath $Zip -Force -ErrorAction SilentlyContinue
    Remove-Item -LiteralPath (Join-Path $dir "pending.json") -Force -ErrorAction SilentlyContinue
    "ok $Version" | Out-File -LiteralPath $log -Encoding utf8
} catch {
    "$_" | Out-File -LiteralPath $log -Encoding utf8
}
Start-Process -FilePath (Join-Path $Dest "ilot.exe") -WorkingDirectory $Dest
"#;

/// Lance l'installation de l'archive telechargee ; l'interface quitte ensuite
/// l'ilot (le script attend sa fin).
fn install() -> Result<(), String> {
    let p = pending().ok_or("Aucune mise à jour téléchargée")?;
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    let dest = exe.parent().ok_or("Dossier de l'îlot introuvable")?;
    let script = dir().join("install.ps1");
    // BOM : PowerShell 5 lit sinon le script en ANSI (accents des messages)
    let mut body = vec![0xEF, 0xBB, 0xBF];
    body.extend_from_slice(SCRIPT.as_bytes());
    std::fs::write(&script, body).map_err(|e| e.to_string())?;
    let _ = std::fs::remove_file(dir().join("update.log"));
    let mut cmd = Command::new("powershell.exe");
    cmd.args(["-NoProfile", "-ExecutionPolicy", "Bypass", "-WindowStyle", "Hidden", "-File"])
        .arg(&script)
        .arg("-Wait")
        .arg(std::process::id().to_string())
        .arg("-Zip")
        .arg(&p.zip)
        .arg("-Dest")
        .arg(dest)
        .arg("-Version")
        .arg(&p.version);
    if !p.sha256.is_empty() {
        cmd.arg("-Sha").arg(&p.sha256);
    }
    cmd.creation_flags(CREATE_NO_WINDOW)
        .spawn()
        .map_err(|e| format!("Installation impossible ({e})"))?;
    Ok(())
}

// --------------------------------------------------------- notes de version

#[derive(Serialize)]
pub struct Notes {
    version: String,
    date: String,
    /// Markdown
    notes: String,
}

/// `CHANGELOG.md` : une section `## 0.4.0 — 2026-10-16` par version.
pub fn changelog() -> Vec<Notes> {
    let mut out: Vec<Notes> = Vec::new();
    for line in CHANGELOG.lines() {
        if let Some(h) = line.strip_prefix("## ") {
            let mut parts = h.splitn(2, ['—', '–']);
            let version = parts.next().unwrap_or("").trim().trim_start_matches(['v', 'V']).to_string();
            let date = parts.next().unwrap_or("").trim().to_string();
            out.push(Notes { version, date, notes: String::new() });
        } else if let Some(n) = out.last_mut() {
            n.notes.push_str(line);
            n.notes.push('\n');
        }
    }
    for n in &mut out {
        n.notes = n.notes.trim().to_string();
    }
    out
}

// ---------------------------------------------------------------- commandes

pub fn update_get() -> Update {
    snapshot()
}

/// Nouveau releve (bouton « Rechercher »)
pub fn update_check(app: AppHandle) -> Update {
    check(&app)
}

/// Telecharge l'archive en arriere-plan (avancement par `update`)
pub fn update_download(app: AppHandle) -> Update {
    std::thread::spawn(move || fetch(&app));
    snapshot()
}

pub fn update_install(app: AppHandle) -> Result<bool, String> {
    with(|u| u.status = "installing");
    publish(&app);
    if let Err(e) = install() {
        with(|u| {
            u.status = "error";
            u.error = e.clone();
        });
        publish(&app);
        return Err(e);
    }
    Ok(true)
}

pub fn changelog_get() -> Vec<Notes> {
    changelog()
}

/// Releve au demarrage puis toutes les 6 h, selon Reglages > Mises a jour :
/// `auto` telecharge aussi l'archive (installee par l'interface quand tu
/// ne fais rien, ou au prochain lancement), `notify` previent seulement.
pub fn watch(app: AppHandle) {
    // compte rendu de la derniere installation (ecrit par le script)
    let log = dir().join("update.log");
    if let Ok(s) = std::fs::read_to_string(&log) {
        let s = s.trim_start_matches('\u{feff}').trim().to_string();
        if !s.starts_with("ok") {
            with(|u| {
                u.status = "error";
                u.error = format!("Dernière installation : {s}");
            });
        }
        let _ = std::fs::remove_file(&log);
    }
    if pending().is_none() {
        let _ = std::fs::remove_file(dir().join("pending.json"));
    }
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(40));
        loop {
            let mode = app.state::<crate::settings::Settings>().0.lock().unwrap().update_mode.clone();
            if mode != "off" {
                let u = check(&app);
                if u.available && mode == "auto" {
                    fetch(&app);
                }
            }
            std::thread::sleep(EVERY);
        }
    });
}

/// Au lancement, mode `auto` : une mise a jour deja telechargee est
/// installee avant d'ouvrir l'interface. Vrai si l'ilot doit quitter.
pub fn install_pending_at_start() -> bool {
    let mode = crate::settings::load(&AppHandle).update_mode;
    mode == "auto" && pending().is_some() && !running() && install().is_ok()
}

/// Un autre ilot tourne deja (ses fichiers ne pourraient pas etre remplaces)
fn running() -> bool {
    use windows::core::w;
    use windows::Win32::Foundation::CloseHandle;
    use windows::Win32::System::Threading::{OpenMutexW, SYNCHRONIZATION_SYNCHRONIZE};
    match unsafe { OpenMutexW(SYNCHRONIZATION_SYNCHRONIZE, false, w!("Local\\io.github.tidic84.ilot")) } {
        Ok(h) => {
            unsafe {
                let _ = CloseHandle(h);
            }
            true
        }
        Err(_) => false,
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use base64::Engine;
    use p256::ecdsa::signature::DigestSigner;
    use p256::ecdsa::{Signature, SigningKey};

    #[test]
    fn sign_key_valid() {
        let k = base64::engine::general_purpose::STANDARD.decode(SIGN_KEY).unwrap();
        assert!(p256::ecdsa::VerifyingKey::from_sec1_bytes(&k).is_ok());
    }

    // meme calcul que examples/sign.rs
    #[test]
    fn signature_roundtrip() {
        let b64 = base64::engine::general_purpose::STANDARD;
        let k = SigningKey::random(&mut rand::rngs::OsRng);
        let key = b64.encode(k.verifying_key().to_encoded_point(true).as_bytes());
        let mut zip = Sha256::new();
        zip.update(b"archive");
        let mut h = zip.clone();
        h.update(b"\nilot 1.2.3");
        let sig: Signature = k.sign_digest(h);
        let sig = b64.encode(sig.to_bytes());
        assert!(verify_with(&key, signed_message(&zip, "1.2.3"), &sig).is_ok());
        // autre version, autre archive, autre cle
        assert!(verify_with(&key, signed_message(&zip, "1.2.4"), &sig).is_err());
        let mut other = Sha256::new();
        other.update(b"archivf");
        assert!(verify_with(&key, signed_message(&other, "1.2.3"), &sig).is_err());
        assert!(verify(signed_message(&zip, "1.2.3"), &sig).is_err());
    }
}
