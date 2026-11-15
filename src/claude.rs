//! Claude Code : hooks qui previennent l'ilot au debut et a la fin d'une
//! tache. Chaque hook lance `ilot.exe --claude` (qt/src/main.cpp), qui
//! transmet l'evenement a l'ilot deja lance. Ils sont ajoutes a
//! `%USERPROFILE%\.claude\settings.json` sans toucher au reste du fichier
//! (une copie `settings.json.ilot-bak` est faite avant chaque ecriture).
//! Claude Code lance dans WSL a son propre `~/.claude/settings.json` : on y
//! met les memes hooks, avec le chemin /mnt/<lettre>/... d'ilot.exe (WSL sait
//! lancer un .exe Windows, le JSON passe par stdin de la meme facon).
//! Addon « Claude » : limites de l'abonnement (session de 5 h, semaine), lues
//! avec le jeton OAuth de Claude Code ou de Claude Desktop (`usage`).

use serde_json::{json, Value};
use std::os::windows::process::CommandExt;
use std::path::{Path, PathBuf};
use std::process::Command;

// Notification « idle_prompt » : Claude attend une saisie. C'est le seul
// signal apres une interruption (Echap ne declenche pas Stop).
const EVENTS: [&str; 4] = ["UserPromptSubmit", "Stop", "SessionEnd", "Notification"];
const FLAG: &str = "--claude";

const CREATE_NO_WINDOW: u32 = 0x0800_0000;

/// Un settings.json de Claude Code et la commande qui y lance ilot.exe
struct Target {
    path: PathBuf,
    cmd: String,
}

fn windows() -> Result<Target, String> {
    let home = std::env::var("USERPROFILE").map_err(|_| "dossier utilisateur introuvable".to_string())?;
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    Ok(Target {
        path: PathBuf::from(home).join(".claude").join("settings.json"),
        cmd: format!("\"{}\" {FLAG}", exe.display()),
    })
}

/// C:\Users\x\ilot.exe -> /mnt/c/Users/x/ilot.exe (montage par defaut de WSL)
fn wsl_path(p: &Path) -> Option<String> {
    let s = p.to_str()?.strip_prefix(r"\\?\").unwrap_or(p.to_str()?);
    let (drive, rest) = s.split_once(":\\")?;
    if drive.len() != 1 || !drive.chars().all(|c| c.is_ascii_alphabetic()) {
        return None;
    }
    Some(format!("/mnt/{}/{}", drive.to_ascii_lowercase(), rest.replace('\\', "/")))
}

/// Distributions WSL (`running` : seulement celles deja demarrees, pour ne
/// pas reveiller WSL en ouvrant les reglages). Pas de WSL : liste vide.
fn distros(running: bool) -> Vec<String> {
    let mut cmd = Command::new("wsl.exe");
    cmd.args(["--list", "--quiet"]);
    if running {
        cmd.arg("--running");
    }
    let Ok(out) = cmd.creation_flags(CREATE_NO_WINDOW).output() else {
        return Vec::new();
    };
    if !out.status.success() {
        return Vec::new();
    }
    // wsl.exe ecrit en UTF-16LE
    let wide: Vec<u16> = out.stdout.chunks_exact(2).map(|b| u16::from_le_bytes([b[0], b[1]])).collect();
    String::from_utf16_lossy(&wide)
        .lines()
        .map(|l| l.trim_matches(|c: char| c.is_whitespace() || c == '\u{feff}' || c == '\0').to_string())
        // docker-desktop : distribution interne de Docker, sans Claude Code
        .filter(|l| !l.is_empty() && !l.starts_with("docker-desktop"))
        .collect()
}

/// settings.json des comptes WSL ou Claude Code a deja servi (dossier ~/.claude)
fn wsl(running: bool) -> Vec<Target> {
    let Some(cmd) = std::env::current_exe().ok().as_deref().and_then(wsl_path) else {
        return Vec::new();
    };
    let cmd = format!("'{}' {FLAG}", cmd.replace('\'', r"'\''"));
    let mut out = Vec::new();
    for d in distros(running) {
        let root = PathBuf::from(format!(r"\\wsl.localhost\{d}"));
        let mut homes = vec![root.join("root")];
        if let Ok(rd) = std::fs::read_dir(root.join("home")) {
            homes.extend(rd.flatten().map(|e| e.path()));
        }
        for h in homes {
            let dir = h.join(".claude");
            if dir.is_dir() {
                out.push(Target { path: dir.join("settings.json"), cmd: cmd.clone() });
            }
        }
    }
    out
}

/// Entree d'un evenement ajoutee par l'ilot : sa commande lance ilot.exe --claude
fn ours(entry: &Value) -> bool {
    entry.get("hooks").and_then(Value::as_array).is_some_and(|hooks| {
        hooks.iter().any(|h| {
            h.get("command").and_then(Value::as_str).is_some_and(|c| {
                let c = c.to_ascii_lowercase();
                c.contains("ilot.exe") && c.contains(FLAG)
            })
        })
    })
}

fn load(p: &Path) -> Result<Value, String> {
    let text = match std::fs::read_to_string(p) {
        Ok(s) => s,
        Err(e) if e.kind() == std::io::ErrorKind::NotFound => return Ok(json!({})),
        Err(e) => return Err(format!("{} : {e}", p.display())),
    };
    // UTF-8 avec BOM (Bloc-notes, PowerShell 5)
    let text = text.trim_start_matches('\u{feff}');
    if text.trim().is_empty() {
        return Ok(json!({}));
    }
    // fichier illisible : on n'y touche pas
    let v: Value = serde_json::from_str(text).map_err(|e| format!("{} illisible : {e}", p.display()))?;
    if v.is_object() {
        Ok(v)
    } else {
        Err(format!("{} n'est pas un objet JSON", p.display()))
    }
}

fn save(p: &Path, v: &Value) -> Result<(), String> {
    if let Some(dir) = p.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    // la premiere sauvegarde seulement : c'est le fichier d'avant l'ilot
    let bak = p.with_file_name("settings.json.ilot-bak");
    if p.exists() && !bak.exists() {
        std::fs::copy(p, &bak).map_err(|e| format!("sauvegarde impossible : {e}"))?;
    }
    let text = serde_json::to_string_pretty(v).map_err(|e| e.to_string())?;
    // ecrit a cote puis remplace : jamais de fichier a moitie ecrit
    let tmp = p.with_file_name("settings.json.ilot-tmp");
    std::fs::write(&tmp, text).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, p).map_err(|e| {
        let _ = std::fs::remove_file(&tmp);
        format!("{} : {e}", p.display())
    })
}

fn installed(v: &Value) -> bool {
    EVENTS.iter().all(|e| {
        v.get("hooks").and_then(|h| h.get(e)).and_then(Value::as_array).is_some_and(|list| list.iter().any(ours))
    })
}

/// Les hooks sont-ils en place, sous Windows et dans les WSL demarres ?
pub fn hooks_status() -> Result<bool, String> {
    if !installed(&load(&windows()?.path)?) {
        return Ok(false);
    }
    for t in wsl(true) {
        if !installed(&load(&t.path)?) {
            return Ok(false);
        }
    }
    Ok(true)
}

/// Ajoute (ou remet a jour, si l'ilot a change de dossier) les hooks de l'ilot
pub fn hooks_install() -> Result<bool, String> {
    install(&windows()?)?;
    for t in wsl(false) {
        install(&t)?;
    }
    Ok(true)
}

/// Retire seulement les hooks de l'ilot
pub fn hooks_remove() -> Result<bool, String> {
    remove(&windows()?.path)?;
    for t in wsl(false) {
        remove(&t.path)?;
    }
    Ok(false)
}

fn install(t: &Target) -> Result<(), String> {
    let mut v = load(&t.path)?;
    let cmd = &t.cmd;
    let root = v.as_object_mut().ok_or("settings.json n'est pas un objet JSON")?;
    let hooks = root.entry("hooks").or_insert_with(|| json!({}));
    let hooks = hooks.as_object_mut().ok_or("« hooks » n'est pas un objet dans settings.json")?;
    for e in EVENTS {
        let list = hooks.entry(e).or_insert_with(|| json!([]));
        let list = list.as_array_mut().ok_or_else(|| format!("« hooks.{e} » n'est pas une liste dans settings.json"))?;
        list.retain(|x| !ours(x));
        let mut entry = json!({ "hooks": [{ "type": "command", "command": cmd, "timeout": 5 }] });
        if e == "Notification" {
            entry["matcher"] = json!("idle_prompt");
        }
        list.push(entry);
    }
    save(&t.path, &v)
}

fn remove(p: &Path) -> Result<(), String> {
    let mut v = load(p)?;
    let mut changed = false;
    if let Some(hooks) = v.get_mut("hooks").and_then(Value::as_object_mut) {
        for e in EVENTS {
            let empty = match hooks.get_mut(e).and_then(Value::as_array_mut) {
                Some(list) => {
                    let n = list.len();
                    list.retain(|x| !ours(x));
                    changed |= list.len() != n;
                    list.is_empty()
                }
                None => false,
            };
            if empty {
                hooks.remove(e);
            }
        }
        if hooks.is_empty() {
            v.as_object_mut().map(|o| o.remove("hooks"));
        }
    }
    if changed {
        save(p, &v)?;
    }
    Ok(())
}

// ------------------------------------------- utilisation (addon « Claude »)

/// Derniere reponse (ou erreur) de l'API d'utilisation, et quand
static USAGE: std::sync::Mutex<Option<(std::time::Instant, Result<Value, String>)>> = std::sync::Mutex::new(None);

fn now_ms() -> u64 {
    std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_millis() as u64)
}

const EXPIRED: &str = "Connexion expirée : relance Claude Code ou Claude Desktop";

/// (expiration, jeton, abonnement) : garde le jeton valable qui dure le plus
fn keep(best: &mut Option<(u64, String, String)>, now: u64, exp: u64, tok: &str, plan: &str) {
    if exp > now + 60_000 && best.as_ref().is_none_or(|b| exp > b.0) {
        *best = Some((exp, tok.to_string(), plan.to_string()));
    }
}

/// Jetons de Claude Code (fichiers .credentials.json)
fn cli(files: impl Iterator<Item = PathBuf>, now: u64, seen: &mut bool) -> Option<(u64, String, String)> {
    let mut best = None;
    for f in files {
        let Ok(text) = std::fs::read_to_string(&f) else { continue };
        let Ok(v) = serde_json::from_str::<Value>(text.trim_start_matches('\u{feff}')) else { continue };
        let o = &v["claudeAiOauth"];
        let Some(tok) = o["accessToken"].as_str() else { continue };
        *seen = true;
        keep(&mut best, now, o["expiresAt"].as_u64().unwrap_or(0), tok, o["subscriptionType"].as_str().unwrap_or(""));
    }
    best
}

/// Jetons de Claude Desktop, qui n'ecrit pas .credentials.json. Ils sont dans
/// %APPDATA%\Claude\config.json (oauth:tokenCacheV2, oauth:tokenCache),
/// chiffres par Electron (safeStorage) : « v10 » + nonce (12) + AES-256-GCM.
/// La cle est os_crypt.encrypted_key de « Local State » : « DPAPI » + DPAPI.
/// Chaque entree est « acct:<compte>|<client>:...:https://api.anthropic.com:<scopes> » ;
/// l'API d'utilisation veut le scope user:profile (les autres : 403).
/// Lecture seule : Desktop rafraichit lui-meme ses jetons.
fn desktop(now: u64, seen: &mut bool) -> Option<(u64, String, String)> {
    use aes_gcm::aead::{Aead, KeyInit};
    use base64::{engine::general_purpose::STANDARD, Engine};
    let dir = PathBuf::from(std::env::var("APPDATA").ok()?).join("Claude");
    let read = |f: &str| -> Option<Value> {
        serde_json::from_str(std::fs::read_to_string(dir.join(f)).ok()?.trim_start_matches('\u{feff}')).ok()
    };
    let cfg = read("config.json")?;
    let state = read("Local State")?;
    let ek = STANDARD.decode(state["os_crypt"]["encrypted_key"].as_str()?).ok()?;
    let key = crate::mail::unprotect_raw(ek.strip_prefix(b"DPAPI")?)?;
    let cipher = aes_gcm::Aes256Gcm::new_from_slice(&key).ok()?;
    // compte connecte dans Desktop (d'anciens comptes peuvent rester en cache)
    let acct = cfg["lastKnownAccountUuid"].as_str().map(|a| format!("acct:{a}|"));
    let mut best = None;
    for k in ["oauth:tokenCacheV2", "oauth:tokenCache"] {
        let Some(b) = cfg[k].as_str().and_then(|s| STANDARD.decode(s).ok()) else { continue };
        let Some(b) = b.strip_prefix(b"v10").filter(|b| b.len() > 12 + 16) else { continue };
        let Ok(plain) = cipher.decrypt(b[..12].into(), &b[12..]) else { continue };
        let Ok(Value::Object(m)) = serde_json::from_slice::<Value>(&plain) else { continue };
        for (id, v) in &m {
            if acct.as_ref().is_some_and(|a| !id.starts_with(a.as_str())) {
                continue;
            }
            let profile = id
                .split_once("https://api.anthropic.com:")
                .is_some_and(|(_, scopes)| scopes.split_whitespace().any(|s| s == "user:profile"));
            let Some(tok) = v["token"].as_str().filter(|_| profile) else { continue };
            *seen = true;
            keep(&mut best, now, v["expiresAt"].as_u64().unwrap_or(0), tok, v["subscriptionType"].as_str().unwrap_or(""));
        }
    }
    best
}

/// Jeton OAuth encore valable : Claude Code sous Windows, sinon Claude
/// Desktop, sinon Claude Code dans les WSL demarres (wsl.exe a lancer).
/// On ne le rafraichit jamais (le jeton de rafraichissement changerait et
/// Claude serait deconnecte) : relancer Claude Code ou Desktop suffit.
fn token() -> Result<(String, String), String> {
    let now = now_ms();
    let mut seen = false;
    let win = windows().map(|t| t.path.with_file_name(".credentials.json")).ok();
    let best = cli(win.into_iter(), now, &mut seen)
        .or_else(|| desktop(now, &mut seen))
        .or_else(|| cli(wsl(true).into_iter().map(|t| t.path.with_file_name(".credentials.json")), now, &mut seen));
    match best {
        Some((_, tok, plan)) => Ok((tok, plan)),
        None if seen => Err(EXPIRED.into()),
        None => Err("Ni Claude Code ni Claude Desktop ne sont connectés à un abonnement Claude".into()),
    }
}

/// Releve rate. `Busy` (429, avec l'attente du Retry-After en s) et `Net`
/// laissent afficher la derniere valeur connue ; `Auth` (pas connecte,
/// connexion expiree) reste une erreur.
enum Fail {
    Auth(String),
    Busy(Option<u64>),
    Net(String),
}

fn usage_fetch() -> Result<Value, Fail> {
    let (tok, plan) = token().map_err(Fail::Auth)?;
    let r = crate::http()
        .get("https://api.anthropic.com/api/oauth/usage")
        .set("Authorization", &format!("Bearer {tok}"))
        .set("anthropic-beta", "oauth-2025-04-20")
        .timeout(std::time::Duration::from_secs(10))
        .call();
    let v: Value = match r {
        Ok(r) => r.into_json().map_err(|e| Fail::Net(e.to_string()))?,
        Err(ureq::Error::Status(401, _)) => return Err(Fail::Auth(EXPIRED.into())),
        Err(ureq::Error::Status(429, r)) => {
            return Err(Fail::Busy(r.header("retry-after").and_then(|s| s.trim().parse().ok())))
        }
        Err(ureq::Error::Status(c, _)) => return Err(Fail::Net(format!("Erreur {c} de l'API Claude"))),
        Err(_) => return Err(Fail::Net("API Claude injoignable".into())),
    };
    // pourcentage (0..100) et remise a zero (ISO 8601), null si absent
    let lim = |k: &str| match v.get(k) {
        Some(l) if l.is_object() => json!({ "pct": l["utilization"], "resets": l["resets_at"] }),
        _ => Value::Null,
    };
    let mut out = json!({
        "plan": plan,
        "session": lim("five_hour"),
        "week": lim("seven_day"),
        "week_opus": lim("seven_day_opus"),
        "week_sonnet": lim("seven_day_sonnet"),
        "at": now_ms(),
    });
    out["hist"] = record(&out);
    Ok(out)
}

/// Fenetre de chaque limite, en ms
fn window_ms(key: &str) -> u64 {
    if key == "session" {
        5 * 3600 * 1000
    } else {
        7 * 86400 * 1000
    }
}

/// Historique des releves pour le graphique : { cle: [[ms, pct], ...] },
/// garde dans %LOCALAPPDATA%\Ilot\claude-usage.json, limite a la fenetre en
/// cours de chaque limite. Un point par changement, ou toutes les 15 min.
fn record(u: &Value) -> Value {
    let mut h: serde_json::Map<String, Value> = crate::store::read("claude-usage").unwrap_or_default();
    let now = now_ms();
    for key in ["session", "week", "week_opus", "week_sonnet"] {
        let l = &u[key];
        let (Some(pct), Some(resets)) = (l["pct"].as_f64(), l["resets"].as_str()) else {
            h.remove(key);
            continue;
        };
        let Some(end) = iso_ms(resets) else { continue };
        let start = end.saturating_sub(window_ms(key));
        let mut pts: Vec<(u64, f64)> = h.get(key).and_then(|v| serde_json::from_value(v.clone()).ok()).unwrap_or_default();
        pts.retain(|p| p.0 >= start && p.0 <= now);
        let keep = pts.last().is_none_or(|p| p.1 != pct || now - p.0 >= 15 * 60 * 1000);
        if keep {
            pts.push((now, pct));
        }
        h.insert(key.into(), json!(pts));
    }
    let h = Value::Object(h);
    crate::store::write("claude-usage", &h);
    h
}

/// « 2026-10-27T10:00:00.013275+00:00 » -> ms depuis 1970 (UTC ou decalage)
fn iso_ms(s: &str) -> Option<u64> {
    let n = |a: usize, b: usize| s.get(a..b)?.parse::<i64>().ok();
    let (y, mo, d, hh, mi, ss) = (n(0, 4)?, n(5, 7)?, n(8, 10)?, n(11, 13)?, n(14, 16)?, n(17, 19)?);
    // jours depuis 1970 (algorithme de Howard Hinnant)
    let (y2, m2) = if mo <= 2 { (y - 1, mo + 9) } else { (y, mo - 3) };
    let era = y2.div_euclid(400);
    let yoe = y2 - era * 400;
    let doy = (153 * m2 + 2) / 5 + d - 1;
    let days = era * 146097 + yoe * 365 + yoe / 4 - yoe / 100 + doy - 719468;
    let mut secs = days * 86400 + hh * 3600 + mi * 60 + ss;
    // decalage horaire en fin de chaine : Z, +hh:mm ou -hh:mm
    let tail = &s[19..];
    if let Some(i) = tail.rfind(['+', '-']) {
        let o = &tail[i..];
        let sign = if o.starts_with('-') { -1 } else { 1 };
        let oh = o.get(1..3)?.parse::<i64>().ok()?;
        let om = o.get(4..6).and_then(|x| x.parse::<i64>().ok()).unwrap_or(0);
        secs -= sign * (oh * 3600 + om * 60);
    }
    u64::try_from(secs).ok().map(|x| x * 1000)
}

/// Releve toutes les 10 min tant que l'addon « Claude » est active : le
/// graphique a un historique meme quand la page reste fermee.
pub fn watch(app: crate::host::AppHandle) {
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_secs(30));
        loop {
            if crate::settings::addon_on(&app, "cusage") {
                let _ = usage(None);
            }
            std::thread::sleep(std::time::Duration::from_secs(600));
        }
    });
}

/// Apres un 429 : aucune demande avant cet instant, et l'attente suivante
/// quand l'API ne donne pas de Retry-After (doublee a chaque 429)
static WAIT: std::sync::Mutex<Option<(std::time::Instant, u64)>> = std::sync::Mutex::new(None);

/// Derniere valeur bonne (sans l'historique), gardee sur disque pour
/// s'afficher aussi apres un redemarrage
const LAST: &str = "claude-usage-last";

/// Derniere valeur connue, marquee `stale` : { why: "busy" | "net", retry: ms
/// (busy), msg (net) }. Rien de connu : l'erreur `none`.
fn stale(why: Value, none: String) -> Result<Value, String> {
    let Some(mut v) = crate::store::read::<Value>(LAST).filter(Value::is_object) else {
        return Err(none);
    };
    v["hist"] = crate::store::read::<Value>("claude-usage").unwrap_or_else(|| json!({}));
    v["stale"] = why;
    Ok(v)
}

/// Attente avant le prochain essai, en ms depuis 1970 et en minutes arrondies
fn retry_at(t: std::time::Instant) -> (u64, u64) {
    let left = t.saturating_duration_since(std::time::Instant::now());
    (now_ms() + left.as_millis() as u64, left.as_secs().div_ceil(60).max(1))
}

/// Limites de l'abonnement Claude (session de 5 h, semaine), comme `/usage`
/// dans Claude Code. Gardees 1 min (`fresh` : 10 s) pour menager l'API.
/// Apres un 429, plus aucune demande avant la fin du delai (Retry-After,
/// sinon 5 min doublees jusqu'a 1 h) : la derniere valeur connue est rendue.
pub fn usage(fresh: Option<bool>) -> Result<Value, String> {
    use std::time::{Duration, Instant};
    let keep = Duration::from_secs(if fresh.unwrap_or(false) { 10 } else { 60 });
    if let Some((at, r)) = USAGE.lock().unwrap().as_ref() {
        if at.elapsed() < keep {
            return r.clone();
        }
    }
    let busy = |t: Instant| {
        let (ms, min) = retry_at(t);
        stale(json!({ "why": "busy", "retry": ms }), format!("Trop de demandes : nouvel essai dans {min} min"))
    };
    let wait = *WAIT.lock().unwrap();
    let r = match wait {
        Some((t, _)) if Instant::now() < t => busy(t),
        _ => match usage_fetch() {
            Ok(v) => {
                *WAIT.lock().unwrap() = None;
                let mut last = v.clone();
                if let Some(o) = last.as_object_mut() {
                    o.remove("hist");
                }
                crate::store::write(LAST, &last);
                Ok(v)
            }
            Err(Fail::Auth(e)) => Err(e),
            Err(Fail::Busy(after)) => {
                let backoff = wait.map_or(300, |(_, b)| (b * 2).min(3600));
                // Retry-After borne (1 min - 1 jour) : jamais de debordement d'Instant
                let t = Instant::now() + Duration::from_secs(after.map_or(backoff, |a| a.clamp(60, 86_400)));
                *WAIT.lock().unwrap() = Some((t, backoff));
                busy(t)
            }
            Err(Fail::Net(e)) => stale(json!({ "why": "net", "msg": e.clone() }), e),
        },
    };
    *USAGE.lock().unwrap() = Some((Instant::now(), r.clone()));
    r
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn reconnait_seulement_nos_hooks() {
        let mine = json!({ "hooks": [{ "type": "command", "command": "\"C:\\Programs\\Ilot\\ilot.exe\" --claude" }] });
        let other = json!({ "hooks": [{ "type": "command", "command": "notify-send fini" }] });
        assert!(ours(&mine));
        assert!(!ours(&other));
        let v = json!({ "hooks": { "UserPromptSubmit": [mine.clone()], "Stop": [other, mine.clone()], "SessionEnd": [mine.clone()], "Notification": [mine] } });
        assert!(installed(&v));
        assert!(!installed(&json!({ "hooks": { "Stop": [] } })));
        assert!(ours(&json!({ "hooks": [{ "type": "command", "command": "'/mnt/c/Programs/Ilot/ilot.exe' --claude" }] })));
    }

    #[test]
    fn chemin_wsl() {
        assert_eq!(wsl_path(Path::new(r"C:\Users\x\Ilot\ilot.exe")).as_deref(), Some("/mnt/c/Users/x/Ilot/ilot.exe"));
        assert_eq!(wsl_path(Path::new(r"\\?\D:\a b\ilot.exe")).as_deref(), Some("/mnt/d/a b/ilot.exe"));
        assert_eq!(wsl_path(Path::new(r"\\serveur\partage\ilot.exe")), None);
    }

    #[test]
    fn date_iso() {
        assert_eq!(iso_ms("1970-01-01T00:00:00Z"), Some(0));
        assert_eq!(iso_ms("2026-10-27T10:00:00.013275+00:00"), Some(1_793_095_200_000));
        assert_eq!(iso_ms("2026-10-27T12:00:00+02:00"), Some(1_793_095_200_000));
    }
}
