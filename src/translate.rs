//! Page Traduction : service de traduction de Google (point d'acces public
//! « gtx », sans cle), appele cote Rust pour eviter les blocages CORS.

use serde::Serialize;
use serde_json::Value;

/// au-dela, l'adresse de la requete devient trop longue
const MAX_CHARS: usize = 4500;

#[derive(Serialize)]
pub struct Translation {
    text: String,
    /// langue detectee (code ISO, ex. « en »)
    detected: String,
}

#[tauri::command(async)]
pub fn translate(text: String, from: String, to: String) -> Result<Translation, String> {
    let text: String = text.chars().take(MAX_CHARS).collect();
    if text.trim().is_empty() {
        return Ok(Translation { text: String::new(), detected: String::new() });
    }
    let v: Value = crate::http().get("https://translate.googleapis.com/translate_a/single")
        .query("client", "gtx")
        .query("sl", if from.is_empty() { "auto" } else { &from })
        .query("tl", &to)
        .query("dt", "t")
        .query("q", &text)
        .timeout(std::time::Duration::from_secs(10))
        .call()
        .map_err(|e| match e {
            ureq::Error::Status(429, _) => "Trop de demandes, réessaie dans un instant".to_string(),
            ureq::Error::Status(c, _) => format!("Service indisponible ({c})"),
            ureq::Error::Transport(_) => "Pas de connexion internet".to_string(),
        })?
        .into_json()
        .map_err(|e| e.to_string())?;
    // [[["traduit", "original", ...], ...], null, "en", ...]
    let text = v[0]
        .as_array()
        .map(|parts| parts.iter().filter_map(|p| p[0].as_str()).collect::<String>())
        .unwrap_or_default();
    let detected = v[2].as_str().unwrap_or_default().to_string();
    Ok(Translation { text, detected })
}
