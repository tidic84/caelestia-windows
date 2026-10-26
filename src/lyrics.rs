//! Paroles synchronisees du morceau en cours : base libre LRCLIB (lrclib.net,
//! sans cle), puis NetEase Cloud Music en secours (LRCLIB est souvent surcharge :
//! erreur 503). Les paroles trouvees sont gardees dans %LOCALAPPDATA%\Ilot\lyrics.
//! Format LRC : « [01:23.45] ligne », cale sur la position du lecteur cote JS.

use serde::{Deserialize, Serialize};
use serde_json::Value;

#[derive(Serialize, Deserialize, Default, Clone)]
pub struct Lyrics {
    /// paroles horodatees (LRC), vide si LRCLIB n'a que le texte brut
    synced: String,
    plain: String,
    instrumental: bool,
}

const UA: &str = "Ilot (https://github.com/caelestia-dots)";

fn call(path: &str, q: &[(&str, &str)]) -> Result<Value, String> {
    // LRCLIB repond souvent « serveur occupe » (5xx) : nouveaux essais espaces
    let mut r = call_once(path, q);
    for wait in [1200, 3000] {
        match &r {
            Err(e) if e.contains("(5") || e.contains("Connexion") => {
                std::thread::sleep(std::time::Duration::from_millis(wait));
                r = call_once(path, q);
            }
            _ => break,
        }
    }
    r
}

fn call_once(path: &str, q: &[(&str, &str)]) -> Result<Value, String> {
    let mut r = crate::http().get(&format!("https://lrclib.net/api/{path}"))
        .set("User-Agent", UA)
        .timeout(std::time::Duration::from_secs(10));
    for (k, v) in q {
        r = r.query(k, v);
    }
    match r.call() {
        Ok(res) => res.into_json().map_err(|e| e.to_string()),
        Err(ureq::Error::Status(404, _)) => Ok(Value::Null),
        Err(ureq::Error::Status(c, _)) => Err(format!("Service indisponible ({c})")),
        Err(ureq::Error::Transport(e)) => Err(format!("Connexion impossible : {e}")),
    }
}

fn from_json(v: &Value) -> Lyrics {
    Lyrics {
        synced: v["syncedLyrics"].as_str().unwrap_or_default().to_string(),
        plain: v["plainLyrics"].as_str().unwrap_or_default().to_string(),
        instrumental: v["instrumental"].as_bool().unwrap_or(false),
    }
}

/// « Titre (feat. X) - Remastered 2011 » -> « Titre »
fn clean_title(t: &str) -> String {
    let mut s = t.to_string();
    for sep in [" (", " [", " - "] {
        if let Some(i) = s.find(sep) {
            if i > 0 {
                s.truncate(i);
            }
        }
    }
    s.trim().to_string()
}

// ------------------------------------------------------------- cache disque

fn cache_path(artist: &str, title: &str) -> std::path::PathBuf {
    // FNV-1a : nom de fichier stable a partir de « artiste|titre »
    let mut h: u64 = 0xcbf29ce484222325;
    for b in format!("{}|{}", artist.trim().to_lowercase(), title.trim().to_lowercase()).bytes() {
        h = (h ^ b as u64).wrapping_mul(0x100000001b3);
    }
    let dir = crate::store::data_dir().join("lyrics");
    let _ = std::fs::create_dir_all(&dir);
    dir.join(format!("{h:016x}.json"))
}

fn found(l: &Lyrics) -> bool {
    !l.synced.is_empty() || !l.plain.is_empty() || l.instrumental
}

// ----------------------------------------------------- NetEase (secours)

const NE: &str = "https://music.163.com/api";

fn ne_get(url: &str) -> Option<Value> {
    crate::http()
        .get(url)
        .set("Referer", "https://music.163.com")
        .set("User-Agent", "Mozilla/5.0")
        .timeout(std::time::Duration::from_secs(8))
        .call()
        .ok()?
        .into_json()
        .ok()
}

/// minuscules, sans accents ni ponctuation : comparaison souple des titres
fn norm(s: &str) -> String {
    s.to_lowercase()
        .chars()
        .map(|c| match c {
            'à' | 'â' | 'ä' => 'a',
            'é' | 'è' | 'ê' | 'ë' => 'e',
            'î' | 'ï' => 'i',
            'ô' | 'ö' => 'o',
            'ù' | 'û' | 'ü' => 'u',
            'ç' => 'c',
            c => c,
        })
        .filter(|c| c.is_alphanumeric())
        .collect()
}

/// Lignes de credits ajoutees par NetEase (« 作词 : ... », « 作曲 : ... »).
fn strip_credits(lrc: &str) -> String {
    const CREDITS: &[&str] = &["作词", "作曲", "编曲", "制作", "混音", "母带", "和声", "录音", "监制", "出品", "原唱", "本作品", "吉他", "贝斯", "鼓"];
    lrc.lines()
        .filter(|l| {
            let text = l.rsplit(']').next().unwrap_or("").trim();
            !CREDITS.iter().any(|c| text.starts_with(c))
        })
        .collect::<Vec<_>>()
        .join("\n")
}

fn netease(artist: &str, title: &str, duration: f64) -> Option<Lyrics> {
    let q = format!("{artist} {title}");
    let url = format!("{NE}/cloudsearch/pc?type=1&limit=8&s={}", urlencode(&q));
    let v = ne_get(&url)?;
    let songs = v["result"]["songs"].as_array()?;
    let (t, a) = (norm(title), norm(artist));
    let first_artist = a.split(',').next().unwrap_or("").to_string();
    let song = songs
        .iter()
        .filter(|s| {
            let name = norm(s["name"].as_str().unwrap_or(""));
            let artists: Vec<String> = s["ar"].as_array().into_iter().flatten().map(|x| norm(x["name"].as_str().unwrap_or(""))).collect();
            (name == t || name.starts_with(&t) || t.starts_with(&name))
                && !name.is_empty()
                && artists.iter().any(|x| !x.is_empty() && (a.contains(x.as_str()) || x.contains(&first_artist)))
        })
        .min_by_key(|s| {
            let d = s["dt"].as_f64().unwrap_or(0.0) / 1000.0;
            if duration > 0.0 { ((d - duration).abs() * 10.0) as i64 } else { 0 }
        })?;
    // duree trop differente : autre version (live, remix...)
    let d = song["dt"].as_f64().unwrap_or(0.0) / 1000.0;
    if duration > 0.0 && d > 0.0 && (d - duration).abs() > 8.0 {
        return None;
    }
    let id = song["id"].as_i64()?;
    let v = ne_get(&format!("{NE}/song/lyric?id={id}&lv=1"))?;
    let lrc = v["lrc"]["lyric"].as_str().unwrap_or("");
    if !lrc.contains('[') {
        return None;
    }
    let synced = strip_credits(lrc);
    let plain = synced.lines().map(|l| l.rsplit(']').next().unwrap_or("").trim()).collect::<Vec<_>>().join("\n");
    Some(Lyrics { synced, plain, instrumental: false })
}

fn urlencode(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

// ------------------------------------------- videos YouTube (navigateur)

/// Coupe s a la premiere occurrence d'un des motifs (sans tenir compte de la casse).
fn cut_at(s: &str, pats: &[&str]) -> String {
    let low = s.to_ascii_lowercase();
    let i = pats.iter().filter_map(|p| low.find(p)).filter(|&i| i > 0).min().unwrap_or(s.len());
    s[..i].trim().to_string()
}

/// « Titre ft. X | Album » -> « Titre »
fn strip_feat(s: &str) -> String {
    cut_at(s, &[" ft. ", " ft ", " feat. ", " feat ", " featuring ", " | "])
}

/// Mention propre aux videos entre parentheses ou crochets : « (Clip officiel) », « [Lyrics] ».
fn video_tag(title: &str) -> bool {
    const TAGS: &[&str] = &["official", "officiel", "clip", "lyric", "parole", "audio", "video", "vidéo", "visuali", "m/v"];
    let low = title.to_lowercase();
    low.split(['(', '[', '【']).skip(1).any(|part| {
        let inner = part.split([')', ']', '】']).next().unwrap_or("");
        TAGS.iter().any(|t| inner.contains(t))
    })
}

/// Titres japonais : « 【Ado】Raven Sky【MV】 » -> « Raven Sky », « Ado「唱」 » -> « 唱 ».
/// Renvoie le titre et vrai si quelque chose a ete retire.
fn strip_jp(title: &str) -> (String, bool) {
    let mut out = String::new();
    let mut rest = title;
    while let Some(i) = rest.find('【') {
        out.push_str(&rest[..i]);
        match rest[i..].find('】') {
            Some(j) => rest = &rest[i + j + '】'.len_utf8()..],
            None => {
                rest = &rest[i..];
                break;
            }
        }
    }
    out.push_str(rest);
    if let (Some(a), Some(b)) = (out.find('「'), out.find('」')) {
        let inner = if a < b { out[a + '「'.len_utf8()..b].trim() } else { "" };
        if !inner.is_empty() {
            return (inner.to_string(), true);
        }
    }
    let out = out.trim().to_string();
    let changed = out != title.trim() && !out.is_empty();
    (if out.is_empty() { title.trim().to_string() } else { out }, changed)
}

/// Une video YouTube (lue dans un navigateur) donne pour titre « Artiste - Titre
/// (Clip officiel) » et pour artiste le nom de la chaine (« ArtisteVEVO »,
/// « Artiste - Topic »). Renvoie (artiste, titre) remis en ordre, ou None si
/// rien n'indique une video (YouTube Music et les lecteurs donnent un album).
fn youtube(artist: &str, title: &str, album: &str) -> Option<(String, String)> {
    if !album.trim().is_empty() {
        return None;
    }
    let artist = artist.trim();
    let mut channel = artist;
    for suf in [" - Topic", "VEVO", "Vevo", " Official", "Official"] {
        channel = channel.strip_suffix(suf).unwrap_or(channel).trim();
    }
    let is_channel = channel != artist || artist.is_empty();
    let (jp, jp_cut) = strip_jp(title);
    let tagged = video_tag(title) || jp_cut;
    let title = jp.as_str();
    let quotes: &[char] = &['"', '“', '”', '«', '»'];
    let split = [" - ", " – ", " — "].iter().filter_map(|sep| title.find(sep).map(|i| (i, sep.len()))).min();
    if let Some((i, n)) = split {
        let (left, right) = (title[..i].trim(), title[i + n..].trim());
        let (l, c) = (norm(left), norm(channel));
        let same = !l.is_empty() && !c.is_empty() && (l.contains(&c) || c.contains(&l));
        if same || is_channel || tagged {
            let t = clean_title(&strip_feat(right));
            let t = t.trim_matches(quotes).trim();
            if !left.is_empty() && !t.is_empty() {
                return Some((strip_feat(left), t.to_string()));
            }
        }
    }
    if (is_channel && !channel.is_empty()) || tagged {
        let t = clean_title(&strip_feat(title));
        let t = t.trim_matches(quotes).trim();
        return (!t.is_empty()).then(|| (channel.to_string(), t.to_string()));
    }
    None
}

pub fn lyrics_get(artist: String, title: String, album: String, duration: f64) -> Result<Lyrics, String> {
    if title.trim().is_empty() {
        return Ok(Lyrics::default());
    }
    let cache = cache_path(&artist, &title);
    if let Some(l) = std::fs::read_to_string(&cache).ok().and_then(|s| serde_json::from_str::<Lyrics>(&s).ok()) {
        return Ok(l);
    }
    let r = match youtube(&artist, &title, &album) {
        // un clip dure souvent plus que le morceau (intro, fin) : sans la duree
        Some((a, t)) => match lookup(&a, &t, "", duration) {
            Ok(l) if !l.synced.is_empty() || l.instrumental => Ok(l),
            other => match netease(&a, &t, 0.0) {
                Some(l) => Ok(l),
                None => other,
            },
        },
        None => lookup(&artist, &title, &album, duration),
    };
    if let Ok(l) = &r {
        if found(l) {
            let _ = std::fs::write(&cache, serde_json::to_string(l).unwrap_or_default());
        }
    }
    r
}

fn lookup(artist: &str, title: &str, album: &str, duration: f64) -> Result<Lyrics, String> {
    // LRCLIB en panne ou sans paroles horodatees : NetEase
    match lrclib(artist, title, album, duration) {
        Ok(l) if !l.synced.is_empty() || l.instrumental => Ok(l),
        other => match netease(artist, &clean_title(title), duration) {
            Some(l) => Ok(l),
            None => other,
        },
    }
}

fn lrclib(artist: &str, title: &str, album: &str, duration: f64) -> Result<Lyrics, String> {
    let (artist, title, album) = (artist.to_string(), title.to_string(), album.to_string());
    let dur = (duration.round() as i64).to_string();
    // correspondance exacte (titre, artiste, album, duree a 2 s pres)
    if duration > 0.0 {
        let v = call("get", &[("artist_name", &artist), ("track_name", &title), ("album_name", &album), ("duration", &dur)])?;
        if v.is_object() && (v["syncedLyrics"].is_string() || v["instrumental"].as_bool() == Some(true)) {
            return Ok(from_json(&v));
        }
    }
    // sans la duree ni l'album (autre edition du meme morceau)
    let short = clean_title(&title);
    let v = call("get", &[("artist_name", &artist), ("track_name", &short)])?;
    if v["syncedLyrics"].is_string() {
        return Ok(from_json(&v));
    }
    let fallback = v.is_object().then(|| from_json(&v));
    // sinon recherche, en preferant une duree proche et des paroles horodatees
    let v = match call("search", &[("track_name", &short), ("artist_name", &artist)]) {
        Ok(v) => v,
        Err(e) => return fallback.ok_or(e),
    };
    let list = v.as_array().cloned().unwrap_or_default();
    let best = list
        .iter()
        .filter(|x| x["syncedLyrics"].is_string() || x["plainLyrics"].is_string())
        .min_by_key(|x| {
            let d = x["duration"].as_f64().unwrap_or(0.0);
            let off = if duration > 0.0 { ((d - duration).abs() * 10.0) as i64 } else { 0 };
            (x["syncedLyrics"].is_null() as i64, off)
        });
    Ok(best.map(from_json).or(fallback).unwrap_or_default())
}

#[cfg(test)]
mod tests {
    use super::youtube;

    fn yt(a: &str, t: &str) -> Option<(String, String)> {
        youtube(a, t, "")
    }

    #[test]
    fn youtube_titles() {
        let p = |a: &str, t: &str| Some((a.to_string(), t.to_string()));
        assert_eq!(yt("RickAstleyVEVO", "Rick Astley - Never Gonna Give You Up (Official Music Video)"), p("Rick Astley", "Never Gonna Give You Up"));
        assert_eq!(yt("Stromae", "Stromae - papaoutai (Official Video)"), p("Stromae", "papaoutai"));
        assert_eq!(yt("Daft Punk - Topic", "Get Lucky"), p("Daft Punk", "Get Lucky"));
        assert_eq!(yt("Spinnin' Records", "Martin Garrix - Animals [Official Video]"), p("Martin Garrix", "Animals"));
        assert_eq!(yt("Angèle", "Angèle - Balance ton quoi ft. X [Clip Officiel]"), p("Angèle", "Balance ton quoi"));
        assert_eq!(yt("Stromae", "Papaoutai (Clip officiel)"), p("Stromae", "Papaoutai"));
        assert_eq!(yt("Ado", "【Ado】Raven Sky"), p("Ado", "Raven Sky"));
        assert_eq!(yt("Ado", "【Ado】唱"), p("Ado", "唱"));
        assert_eq!(yt("Ado", "Ado「唱」MV"), p("Ado", "唱"));
        assert_eq!(yt("YOASOBI", "YOASOBI「アイドル」 Official Music Video"), p("YOASOBI", "アイドル"));
        assert_eq!(yt("Ado", "うっせぇわ【MV】"), p("Ado", "うっせぇわ"));
        // pas une video : rien ne change
        assert_eq!(yt("Queen", "Bohemian Rhapsody"), None);
        assert_eq!(youtube("The Beatles", "Let It Be - Remastered 2009", "Let It Be"), None);
        assert_eq!(yt("Artiste", "Morceau - Live"), None);
    }
}
