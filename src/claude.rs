//! Claude Code : hooks qui previennent l'ilot au debut et a la fin d'une
//! tache. Chaque hook lance `ilot.exe --claude` (qt/src/main.cpp), qui
//! transmet l'evenement a l'ilot deja lance. Ils sont ajoutes a
//! `%USERPROFILE%\.claude\settings.json` sans toucher au reste du fichier
//! (une copie `settings.json.ilot-bak` est faite avant chaque ecriture).
//! Claude Code lance dans WSL a son propre `~/.claude/settings.json` : on y
//! met les memes hooks, avec le chemin /mnt/<lettre>/... d'ilot.exe (WSL sait
//! lancer un .exe Windows, le JSON passe par stdin de la meme facon).

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
}
