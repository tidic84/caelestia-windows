//! Claude Code : hooks qui previennent l'ilot au debut et a la fin d'une
//! tache. Chaque hook lance `ilot.exe --claude` (qt/src/main.cpp), qui
//! transmet l'evenement a l'ilot deja lance. Ils sont ajoutes a
//! `%USERPROFILE%\.claude\settings.json` sans toucher au reste du fichier
//! (une copie `settings.json.ilot-bak` est faite avant chaque ecriture).
//! Claude Code lance dans WSL a son propre `~/.claude/settings.json` : on y
//! met les memes hooks, avec le chemin /mnt/<lettre>/... d'ilot.exe (WSL sait
//! lancer un .exe Windows, le JSON passe par stdin de la meme facon).
//! Addon « Claude » : limites de l'abonnement (session de 5 h, semaine), lues
//! avec le jeton OAuth de Claude Code (`usage`).

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

/// Jeton OAuth de Claude Code encore valable : Windows, sinon les WSL demarres.
/// On ne le rafraichit jamais (le jeton de rafraichissement changerait et
/// Claude Code serait deconnecte) : relancer Claude Code suffit.
fn token() -> Result<(String, String), String> {
    let now = now_ms();
    let mut best: Option<(u64, String, String)> = None;
    let mut seen = false;
    let win = windows().map(|t| t.path.with_file_name(".credentials.json")).ok();
    // WSL seulement si le jeton de Windows ne sert pas (wsl.exe a lancer)
    let mut files: Box<dyn Iterator<Item = PathBuf>> = Box::new(win.into_iter());
    let mut tried_wsl = false;
    loop {
        let Some(f) = files.next() else {
            if best.is_some() || tried_wsl {
                break;
            }
            tried_wsl = true;
            files = Box::new(wsl(true).into_iter().map(|t| t.path.with_file_name(".credentials.json")));
            continue;
        };
        let Ok(text) = std::fs::read_to_string(&f) else { continue };
        let Ok(v) = serde_json::from_str::<Value>(text.trim_start_matches('\u{feff}')) else { continue };
        let o = &v["claudeAiOauth"];
        let (Some(tok), exp) = (o["accessToken"].as_str(), o["expiresAt"].as_u64().unwrap_or(0)) else { continue };
        seen = true;
        if exp > now + 60_000 && best.as_ref().is_none_or(|b| exp > b.0) {
            best = Some((exp, tok.to_string(), o["subscriptionType"].as_str().unwrap_or("").to_string()));
        }
    }
    match best {
        Some((_, tok, plan)) => Ok((tok, plan)),
        None if seen => Err("Connexion de Claude Code expirée : relance Claude Code".into()),
        None => Err("Claude Code n'est pas connecté à un abonnement Claude".into()),
    }
}

fn usage_fetch() -> Result<Value, String> {
    let (tok, plan) = token()?;
    let r = crate::http()
        .get("https://api.anthropic.com/api/oauth/usage")
        .set("Authorization", &format!("Bearer {tok}"))
        .set("anthropic-beta", "oauth-2025-04-20")
        .timeout(std::time::Duration::from_secs(10))
        .call();
    let v: Value = match r {
        Ok(r) => r.into_json().map_err(|e| e.to_string())?,
        Err(ureq::Error::Status(401, _)) => return Err("Connexion de Claude Code expirée : relance Claude Code".into()),
        Err(ureq::Error::Status(429, _)) => return Err("Trop de demandes, nouvel essai dans une minute".into()),
        Err(ureq::Error::Status(c, _)) => return Err(format!("Erreur {c} de l'API Claude")),
        Err(_) => return Err("API Claude injoignable".into()),
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

/// Releve toutes les 5 min tant que l'addon « Claude » est active : le
/// graphique a un historique meme quand la page reste fermee.
pub fn watch(app: crate::host::AppHandle) {
    std::thread::spawn(move || {
        std::thread::sleep(std::time::Duration::from_secs(30));
        loop {
            if crate::settings::addon_on(&app, "cusage") {
                let _ = usage(None);
            }
            std::thread::sleep(std::time::Duration::from_secs(300));
        }
    });
}

/// Limites de l'abonnement Claude (session de 5 h, semaine), comme `/usage`
/// dans Claude Code. Gardees 1 min (`fresh` : 10 s) pour menager l'API.
pub fn usage(fresh: Option<bool>) -> Result<Value, String> {
    let keep = std::time::Duration::from_secs(if fresh.unwrap_or(false) { 10 } else { 60 });
    if let Some((at, r)) = USAGE.lock().unwrap().as_ref() {
        if at.elapsed() < keep {
            return r.clone();
        }
    }
    let r = usage_fetch();
    *USAGE.lock().unwrap() = Some((std::time::Instant::now(), r.clone()));
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
