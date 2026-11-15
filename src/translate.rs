//! Page Traduction et sous-titres : DeepL (API) quand une cle est integree
//! au build (build.rs, %USERPROFILE%\.ilot\deepl.key), sinon le service de
//! Google (point d'acces public « gtx », sans cle). Appele cote Rust pour
//! eviter les blocages CORS.

use serde::Serialize;
use serde_json::{json, Value};
use std::sync::Mutex;
use std::time::{Duration, Instant};

/// au-dela, l'adresse de la requete devient trop longue
const MAX_CHARS: usize = 4500;

/// cle de l'API DeepL, integree a la compilation (absente : Google)
const DEEPL_KEY: Option<&str> = option_env!("ILOT_DEEPL_KEY");

#[derive(Serialize)]
pub struct Translation {
    text: String,
    /// langue detectee (code ISO, ex. « en »)
    detected: String,
    /// « deepl » ou « google » (les sous-titres economisent le quota DeepL)
    engine: &'static str,
}

/// Apres un 429 : aucune demande avant cet instant, et l'attente suivante
/// sans Retry-After (1 min, doublee a chaque 429, 10 min au plus). Sans
/// elle, la page et les sous-titres insistaient et prolongeaient le blocage.
type Wait = Mutex<Option<(Instant, u64)>>;
static GOOGLE_WAIT: Wait = Mutex::new(None);
static DEEPL_WAIT: Wait = Mutex::new(None);

fn busy_msg(who: &str, t: Instant) -> String {
    let s = t.saturating_duration_since(Instant::now()).as_secs().max(1);
    if s < 90 {
        format!("{who} limite les demandes : réessaie dans {s} s")
    } else {
        format!("{who} limite les demandes : réessaie dans {} min", s.div_ceil(60))
    }
}

/// Erreur si l'attente apres un 429 n'est pas finie, sinon l'etat precedent
fn check(w: &Wait, who: &str) -> Result<Option<(Instant, u64)>, String> {
    let prev = *w.lock().unwrap();
    match prev {
        Some((t, _)) if Instant::now() < t => Err(busy_msg(who, t)),
        _ => Ok(prev),
    }
}

/// 429 recu : note l'attente (Retry-After, sinon le repli) et rend le message
fn on_429(w: &Wait, who: &str, prev: Option<(Instant, u64)>, r: &ureq::Response) -> String {
    let after: Option<u64> = r.header("retry-after").and_then(|s| s.trim().parse().ok());
    let backoff = prev.map_or(60, |(_, b)| (b * 2).min(600));
    let t = Instant::now() + Duration::from_secs(after.map_or(backoff, |a| a.clamp(10, 3600)));
    *w.lock().unwrap() = Some((t, backoff));
    busy_msg(who, t)
}

pub fn translate(text: String, from: String, to: String) -> Result<Translation, String> {
    let text: String = text.chars().take(MAX_CHARS).collect();
    if text.trim().is_empty() {
        return Ok(Translation { text: String::new(), detected: String::new(), engine: "" });
    }
    if let Some(key) = DEEPL_KEY {
        let auto = from.is_empty() || from == "auto";
        let src = if auto { Some(None) } else { deepl_lang(&from, false).map(Some) };
        // langue que DeepL ne connait pas (hindi...) : Google
        if let (Some(src), Some(tgt)) = (src, deepl_lang(&to, true)) {
            if !blocked(&DEEPL_WAIT) {
                match deepl(key, text.clone(), src, &tgt) {
                    Ok(t) => return Ok(t),
                    // erreur passagere (reseau...) : pas de repli
                    Err(e) if !blocked(&DEEPL_WAIT) => return Err(e),
                    Err(_) => {}
                }
            }
            // DeepL en attente (429, quota du mois, cle refusee) : Google en relais
        }
    }
    google(text, from, to)
}

fn blocked(w: &Wait) -> bool {
    w.lock().unwrap().is_some_and(|(t, _)| Instant::now() < t)
}

// ------------------------------------------------------------------ DeepL

/// Code DeepL d'une langue de la page (AssistPage.langs), None si DeepL ne
/// la connait pas. Cible : l'anglais, le portugais et le chinois veulent une
/// variante.
fn deepl_lang(code: &str, target: bool) -> Option<String> {
    const KNOWN: [&str; 30] = [
        "AR", "BG", "CS", "DA", "DE", "EL", "EN", "ES", "ET", "FI", "FR", "HU", "ID", "IT", "JA", "KO", "LT", "LV",
        "NB", "NL", "PL", "PT", "RO", "RU", "SK", "SL", "SV", "TR", "UK", "ZH",
    ];
    let base = code.split('-').next()?.to_ascii_uppercase();
    if !KNOWN.contains(&base.as_str()) {
        return None;
    }
    Some(match (target, base.as_str()) {
        (true, "EN") => "EN-US".into(),
        // portugais du Bresil, comme Google
        (true, "PT") => "PT-BR".into(),
        (true, "ZH") => "ZH-HANS".into(),
        _ => base,
    })
}

fn deepl(key: &str, text: String, src: Option<String>, tgt: &str) -> Result<Translation, String> {
    // meme langue des deux cotes : rien a traduire (DeepL refuserait)
    if let Some(s) = src.as_deref().filter(|s| tgt.starts_with(s)) {
        return Ok(Translation { detected: s.to_ascii_lowercase(), text, engine: "deepl" });
    }
    let prev = *DEEPL_WAIT.lock().unwrap();
    // quota du mois epuise, cle refusee : DeepL laisse de cote pendant 1 h
    let pause = |msg: &str| {
        *DEEPL_WAIT.lock().unwrap() = Some((Instant::now() + Duration::from_secs(3600), 60));
        msg.to_string()
    };
    // cle de l'offre gratuite : « …:fx »
    let host = if key.ends_with(":fx") { "api-free.deepl.com" } else { "api.deepl.com" };
    let mut body = json!({ "text": [text], "target_lang": tgt });
    if let Some(s) = src {
        body["source_lang"] = json!(s);
    }
    let v: Value = match crate::http()
        .post(&format!("https://{host}/v2/translate"))
        .set("Authorization", &format!("DeepL-Auth-Key {key}"))
        .timeout(Duration::from_secs(10))
        .send_json(body)
    {
        Ok(r) => r.into_json().map_err(|e| e.to_string())?,
        Err(ureq::Error::Status(429, r)) => return Err(on_429(&DEEPL_WAIT, "DeepL", prev, &r)),
        Err(ureq::Error::Status(456, _)) => return Err(pause("Quota DeepL du mois épuisé")),
        Err(ureq::Error::Status(403, _)) => return Err(pause("Clé DeepL refusée")),
        Err(ureq::Error::Status(c, _)) => return Err(format!("DeepL indisponible ({c})")),
        Err(ureq::Error::Transport(_)) => return Err("Pas de connexion internet".into()),
    };
    *DEEPL_WAIT.lock().unwrap() = None;
    // { "translations": [{ "detected_source_language": "EN", "text": "…" }] }
    let t = &v["translations"][0];
    let mut detected = t["detected_source_language"].as_str().unwrap_or_default().to_ascii_lowercase();
    // code de la page (AssistPage.langs, comme Google)
    if detected == "zh" {
        detected = "zh-CN".into();
    }
    Ok(Translation { text: t["text"].as_str().unwrap_or_default().to_string(), detected, engine: "deepl" })
}

// ----------------------------------------------------------------- Google

fn google(text: String, from: String, to: String) -> Result<Translation, String> {
    let prev = check(&GOOGLE_WAIT, "Google")?;
    let v: Value = crate::http().get("https://translate.googleapis.com/translate_a/single")
        .query("client", "gtx")
        .query("sl", if from.is_empty() { "auto" } else { &from })
        .query("tl", &to)
        .query("dt", "t")
        .query("q", &text)
        .timeout(Duration::from_secs(10))
        .call()
        .map_err(|e| match e {
            ureq::Error::Status(429, r) => on_429(&GOOGLE_WAIT, "Google", prev, &r),
            ureq::Error::Status(c, _) => format!("Service indisponible ({c})"),
            ureq::Error::Transport(_) => "Pas de connexion internet".to_string(),
        })?
        .into_json()
        .map_err(|e| e.to_string())?;
    *GOOGLE_WAIT.lock().unwrap() = None;
    // [[["traduit", "original", ...], ...], null, "en", ...]
    let text = v[0]
        .as_array()
        .map(|parts| parts.iter().filter_map(|p| p[0].as_str()).collect::<String>())
        .unwrap_or_default();
    let detected = v[2].as_str().unwrap_or_default().to_string();
    Ok(Translation { text, detected, engine: "google" })
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn langues_deepl() {
        assert_eq!(deepl_lang("en", true).as_deref(), Some("EN-US"));
        assert_eq!(deepl_lang("en", false).as_deref(), Some("EN"));
        assert_eq!(deepl_lang("zh-CN", true).as_deref(), Some("ZH-HANS"));
        assert_eq!(deepl_lang("pt", true).as_deref(), Some("PT-BR"));
        assert_eq!(deepl_lang("fr", true).as_deref(), Some("FR"));
        assert_eq!(deepl_lang("hi", true), None);
    }
}
