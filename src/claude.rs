//! Claude Code : hooks qui previennent l'ilot au debut et a la fin d'une
//! tache. Chaque hook lance `ilot.exe --claude` (qt/src/main.cpp), qui
//! transmet l'evenement a l'ilot deja lance. Ils sont ajoutes a
//! `%USERPROFILE%\.claude\settings.json` sans toucher au reste du fichier
//! (une copie `settings.json.ilot-bak` est faite avant chaque ecriture).

use serde_json::{json, Value};
use std::path::PathBuf;

// Notification « idle_prompt » : Claude attend une saisie. C'est le seul
// signal apres une interruption (Echap ne declenche pas Stop).
const EVENTS: [&str; 4] = ["UserPromptSubmit", "Stop", "SessionEnd", "Notification"];
const FLAG: &str = "--claude";

fn path() -> Result<PathBuf, String> {
    let home = std::env::var("USERPROFILE").map_err(|_| "dossier utilisateur introuvable".to_string())?;
    Ok(PathBuf::from(home).join(".claude").join("settings.json"))
}

fn command() -> Result<String, String> {
    let exe = std::env::current_exe().map_err(|e| e.to_string())?;
    Ok(format!("\"{}\" {FLAG}", exe.display()))
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

fn load() -> Result<Value, String> {
    let p = path()?;
    let text = match std::fs::read_to_string(&p) {
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

fn save(v: &Value) -> Result<(), String> {
    let p = path()?;
    if let Some(dir) = p.parent() {
        std::fs::create_dir_all(dir).map_err(|e| e.to_string())?;
    }
    // la premiere sauvegarde seulement : c'est le fichier d'avant l'ilot
    let bak = p.with_file_name("settings.json.ilot-bak");
    if p.exists() && !bak.exists() {
        std::fs::copy(&p, &bak).map_err(|e| format!("sauvegarde impossible : {e}"))?;
    }
    let text = serde_json::to_string_pretty(v).map_err(|e| e.to_string())?;
    // ecrit a cote puis remplace : jamais de fichier a moitie ecrit
    let tmp = p.with_file_name("settings.json.ilot-tmp");
    std::fs::write(&tmp, text).map_err(|e| e.to_string())?;
    std::fs::rename(&tmp, &p).map_err(|e| {
        let _ = std::fs::remove_file(&tmp);
        format!("{} : {e}", p.display())
    })
}

fn installed(v: &Value) -> bool {
    EVENTS.iter().all(|e| {
        v.get("hooks").and_then(|h| h.get(e)).and_then(Value::as_array).is_some_and(|list| list.iter().any(ours))
    })
}

/// Les trois hooks sont-ils en place ?
pub fn hooks_status() -> Result<bool, String> {
    Ok(installed(&load()?))
}

/// Ajoute (ou remet a jour, si l'ilot a change de dossier) les hooks de l'ilot
pub fn hooks_install() -> Result<bool, String> {
    let mut v = load()?;
    let cmd = command()?;
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
    save(&v)?;
    Ok(true)
}

/// Retire seulement les hooks de l'ilot
pub fn hooks_remove() -> Result<bool, String> {
    let mut v = load()?;
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
        save(&v)?;
    }
    Ok(false)
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
    }
}
