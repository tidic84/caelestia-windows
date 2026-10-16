//! Petits fichiers JSON dans %LOCALAPPDATA%\Ilot (dossiers d'applis, reglages...).

use std::path::{Path, PathBuf};

/// Dossier de donnees d'Ilot (cree au besoin).
pub fn data_dir() -> PathBuf {
    let base = std::env::var("LOCALAPPDATA").unwrap_or_else(|_| ".".into());
    let d = Path::new(&base).join("Ilot");
    let _ = std::fs::create_dir_all(&d);
    d
}

/// Chemin du fichier `<cle>.json` ; la cle ne contient que [a-z0-9_-].
fn file_of(key: &str) -> Option<PathBuf> {
    let ok = !key.is_empty()
        && key.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-');
    ok.then(|| data_dir().join(format!("{key}.json")))
}

pub fn read<T: serde::de::DeserializeOwned>(key: &str) -> Option<T> {
    let s = std::fs::read_to_string(file_of(key)?).ok()?;
    serde_json::from_str(&s).ok()
}

pub fn write<T: serde::Serialize>(key: &str, value: &T) -> bool {
    let (Some(p), Ok(s)) = (file_of(key), serde_json::to_string_pretty(value)) else {
        return false;
    };
    // ecriture atomique : fichier temporaire puis renommage
    let tmp = p.with_extension("json.tmp");
    std::fs::write(&tmp, s).is_ok() && std::fs::rename(&tmp, &p).is_ok()
}

pub fn store_get(key: String) -> Option<serde_json::Value> {
    read(&key)
}

pub fn store_set(key: String, value: serde_json::Value) -> bool {
    key != "mail" && write(&key, &value)
}
