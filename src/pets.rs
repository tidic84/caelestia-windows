//! Packs de compagnon en sprites (Reglages > Compagnon). Un pack vit hors du
//! depot, dans `%USERPROFILE%\.ilot\pets\<id>\pack.json` (ou dans le dossier
//! de la variable `ILOT_PETS_DIR`, pour les essais). La commande `pet_packs`
//! renvoie `[{ id, name, url, json, meta }]` :
//! - `url` : dossier du pack en `file:///…/` (slash final), pour les images ;
//! - `json` : le `pack.json` tel quel ;
//! - `meta` : les `sprites.json` cites par `json.sprites.meta` et
//!   `json.bust.meta` (`{ sprites: {…}, bust: {…} }`), deja lus, pour que le
//!   QML n'ait pas a lire de fichier local. Avec `json.bust.variants`
//!   (planches par hauteur d'ecran), `meta.bust` est ce fichier
//!   (`{ size, variants: [{ h, dir, meta }] }`), chaque `meta` etant le
//!   `sprites.json` du sous-dossier de la variante.
//!
//! Dossier absent : `[]`. Pack illisible ou JSON invalide : ignore.

use serde_json::{Map, Value};
use std::path::{Component, Path, PathBuf};

/// Taille maximale lue pour un `pack.json` et pour un `sprites.json`.
const MAX_PACK: u64 = 1 << 20;
const MAX_META: u64 = 16 << 20;
/// Total lu par pack (tous ses JSON additionnes).
const BUDGET: u64 = 32 << 20;
/// Variantes de buste gardees au plus.
const MAX_VARIANTS: usize = 32;

fn root() -> Option<PathBuf> {
    if let Some(d) = std::env::var_os("ILOT_PETS_DIR").filter(|d| !d.is_empty()) {
        return Some(PathBuf::from(d));
    }
    Some(Path::new(&std::env::var_os("USERPROFILE")?).join(".ilot").join("pets"))
}

pub fn pet_packs() -> Vec<Value> {
    root().map(|r| scan(&r)).unwrap_or_default()
}

/// Identifiant sur : il sert dans `cfg.pet = "pack:<id>"` et dans l'URL.
fn valid_id(id: &str) -> bool {
    !id.is_empty() && id.len() <= 64 && id.chars().all(|c| c.is_ascii_alphanumeric() || c == '_' || c == '-')
}

/// Chemin relatif simple (pas de `..`, pas de racine ni de lecteur).
fn relative(s: &str) -> Option<&Path> {
    let p = Path::new(s);
    (!s.is_empty() && p.components().all(|c| matches!(c, Component::Normal(_)))).then_some(p)
}

/// Lecteur des JSON d'un pack : chemin reel (jonctions et liens resolus)
/// obligatoirement dans le dossier du pack, fichier ordinaire, taille bornee
/// par fichier et au total.
struct Reader {
    /// dossier du pack, canonique
    base: PathBuf,
    budget: u64,
}

impl Reader {
    fn json(&mut self, rel: &Path, max: u64) -> Option<Value> {
        let p = std::fs::canonicalize(self.base.join(rel)).ok()?;
        if !p.starts_with(&self.base) {
            return None;
        }
        let m = std::fs::metadata(&p).ok()?;
        if !m.is_file() || m.len() > max || m.len() > self.budget {
            return None;
        }
        self.budget -= m.len();
        serde_json::from_slice(&std::fs::read(&p).ok()?).ok()
    }
}

fn file_url(dir: &Path) -> String {
    let mut s = String::from("file:///");
    for c in dir.to_string_lossy().replace('\\', "/").trim_end_matches('/').chars() {
        match c {
            '%' => s.push_str("%25"),
            ' ' => s.push_str("%20"),
            '#' => s.push_str("%23"),
            '?' => s.push_str("%3F"),
            c => s.push(c),
        }
    }
    s.push('/');
    s
}

/// Sous-dossier `dir` d'une section (vide : le pack lui-meme).
fn section_dir(s: &Value) -> Option<PathBuf> {
    match s.get("dir").and_then(Value::as_str).unwrap_or("") {
        "" => Some(PathBuf::new()),
        sub => relative(sub).map(Path::to_path_buf),
    }
}

/// `json.bust.variants` (fichier relatif au dossier du buste) :
/// `{ size, variants: [{ h, dir }] }`, chaque variante recevant `meta`, le
/// `sprites.json` de son sous-dossier. Au plus `MAX_VARIANTS` ; variante
/// illisible : retiree ; aucune : `None` (repli sur `json.bust.meta`).
fn bust_variants(rd: &mut Reader, json: &Value) -> Option<Value> {
    let b = json.get("bust")?;
    let file = relative(b.get("variants")?.as_str()?)?;
    let base = section_dir(b)?;
    let mut v = rd.json(&base.join(file), MAX_PACK).filter(Value::is_object)?;
    let list: Vec<Value> = v
        .get("variants")?
        .as_array()?
        .iter()
        .take(MAX_VARIANTS)
        .filter_map(|x| {
            let sub = relative(x.get("dir")?.as_str()?)?;
            let m = rd.json(&base.join(sub).join("sprites.json"), MAX_META).filter(Value::is_object)?;
            let mut x = x.clone();
            x.as_object_mut()?.insert("meta".to_owned(), m);
            Some(x)
        })
        .collect();
    if list.is_empty() {
        return None;
    }
    v["variants"] = Value::Array(list);
    Some(v)
}

fn scan(root: &Path) -> Vec<Value> {
    let Ok(entries) = std::fs::read_dir(root) else {
        return Vec::new();
    };
    let Ok(croot) = std::fs::canonicalize(root) else {
        return Vec::new();
    };
    let mut out: Vec<Value> = Vec::new();
    for e in entries.flatten() {
        let dir = e.path();
        let Some(id) = dir.file_name().and_then(|n| n.to_str()).map(str::to_owned) else {
            continue;
        };
        if !valid_id(&id) || !dir.is_dir() {
            continue;
        }
        // dossier de pack qui serait une jonction ou un lien : refuse
        let Ok(base) = std::fs::canonicalize(&dir) else {
            continue;
        };
        if base != croot.join(&id) {
            continue;
        }
        let mut rd = Reader { base, budget: BUDGET };
        let Some(json) = rd.json(Path::new("pack.json"), MAX_PACK).filter(Value::is_object) else {
            continue;
        };
        let name = json
            .get("name")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|n| !n.is_empty())
            .unwrap_or(&id)
            .to_owned();
        let mut meta = Map::new();
        for sec in ["sprites", "bust"] {
            let Some(s) = json.get(sec) else { continue };
            let Some(file) = s.get("meta").and_then(Value::as_str).and_then(relative) else {
                continue;
            };
            let Some(base) = section_dir(s) else { continue };
            if let Some(m) = rd.json(&base.join(file), MAX_META).filter(Value::is_object) {
                meta.insert(sec.to_owned(), m);
            }
        }
        // buste en planches par hauteur d'ecran (json.bust.variants), a la
        // place de json.bust.meta
        if let Some(v) = bust_variants(&mut rd, &json) {
            meta.insert("bust".to_owned(), v);
        }
        out.push(serde_json::json!({
            "id": id,
            "name": name,
            "url": file_url(&dir),
            "json": json,
            "meta": meta,
        }));
    }
    out.sort_by(|a, b| a["id"].as_str().cmp(&b["id"].as_str()));
    out
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn scan_packs() {
        let root = std::env::temp_dir().join(format!("ilot-pets-test-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        assert!(scan(&root).is_empty(), "dossier absent");
        let ok = root.join("demo");
        std::fs::create_dir_all(ok.join("bust")).unwrap();
        std::fs::write(
            ok.join("pack.json"),
            r#"{ "name": "Demo", "area": 360, "bust": { "dir": "bust", "meta": "sprites.json", "moods": {} },
                 "sprites": { "dir": "../x", "meta": "sprites.json" } }"#,
        )
        .unwrap();
        std::fs::write(ok.join("bust").join("sprites.json"), r#"{ "w": 10, "h": 12, "anims": { "a": [{}, {}] } }"#).unwrap();
        let bad = root.join("bad");
        std::fs::create_dir_all(&bad).unwrap();
        std::fs::write(bad.join("pack.json"), "{ pas du json").unwrap();
        std::fs::create_dir_all(root.join("vide")).unwrap();
        std::fs::create_dir_all(root.join("a b")).unwrap();
        std::fs::write(root.join("a b").join("pack.json"), "{}").unwrap();

        let packs = scan(&root);
        let _ = std::fs::remove_dir_all(&root);
        assert_eq!(packs.len(), 1, "{packs:?}");
        let p = &packs[0];
        assert_eq!(p["id"], "demo");
        assert_eq!(p["name"], "Demo");
        assert_eq!(p["json"]["area"], 360);
        assert!(p["url"].as_str().unwrap().starts_with("file:///"));
        assert!(p["url"].as_str().unwrap().ends_with("/demo/"));
        assert_eq!(p["meta"]["bust"]["w"], 10);
        // dossier hors du pack : refuse
        assert!(p["meta"].get("sprites").is_none());
    }

    #[test]
    fn bust_variants_lus() {
        let root = std::env::temp_dir().join(format!("ilot-pets-var-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let d = root.join("demo");
        std::fs::create_dir_all(d.join("bust").join("22")).unwrap();
        std::fs::write(d.join("pack.json"), r#"{ "bust": { "dir": "bust", "variants": "variants.json" } }"#).unwrap();
        std::fs::write(
            d.join("bust").join("variants.json"),
            r#"{ "size": 22, "variants": [{ "h": 22, "dir": "22" }, { "h": 28, "dir": "28" }, { "h": 1, "dir": "../x" }] }"#,
        )
        .unwrap();
        std::fs::write(d.join("bust").join("22").join("sprites.json"), r#"{ "w": 24, "h": 22, "anims": {} }"#).unwrap();
        let packs = scan(&root);
        let _ = std::fs::remove_dir_all(&root);
        let b = &packs[0]["meta"]["bust"];
        assert_eq!(b["size"], 22);
        // 28 sans sprites.json et ../x : retirees
        assert_eq!(b["variants"].as_array().unwrap().len(), 1);
        assert_eq!(b["variants"][0]["meta"]["w"], 24);
    }

    /// Jonction (`mklink /J`, sans droits admin) ; faux si impossible.
    fn junction(link: &Path, target: &Path) -> bool {
        std::process::Command::new("cmd")
            .args(["/C", "mklink", "/J"])
            .arg(link)
            .arg(target)
            .output()
            .map(|o| o.status.success())
            .unwrap_or(false)
    }

    #[test]
    fn chemins_hors_du_pack_refuses() {
        let root = std::env::temp_dir().join(format!("ilot-pets-jct-{}", std::process::id()));
        let _ = std::fs::remove_dir_all(&root);
        let pets = root.join("pets");
        let outside = root.join("dehors");
        std::fs::create_dir_all(&outside).unwrap();
        std::fs::write(outside.join("sprites.json"), r#"{ "w": 1, "h": 1, "anims": {} }"#).unwrap();
        std::fs::write(outside.join("pack.json"), r#"{ "name": "Lien" }"#).unwrap();
        // pack normal dont le dossier du buste est une jonction vers dehors,
        // et dont un « fichier » est un dossier
        let d = pets.join("demo");
        std::fs::create_dir_all(d.join("dossier.json")).unwrap();
        std::fs::write(
            d.join("pack.json"),
            r#"{ "bust": { "dir": "bust", "meta": "sprites.json" }, "sprites": { "meta": "dossier.json" } }"#,
        )
        .unwrap();
        let j1 = junction(&d.join("bust"), &outside);
        // dossier de pack qui est lui-meme une jonction
        let j2 = junction(&pets.join("lien"), &outside);
        let packs = scan(&pets);
        // les jonctions d'abord (remove_dir), pour ne pas vider « dehors »
        let _ = std::fs::remove_dir(d.join("bust"));
        let _ = std::fs::remove_dir(pets.join("lien"));
        let _ = std::fs::remove_dir_all(&root);
        assert!(j1 && j2, "mklink /J indisponible");
        assert_eq!(packs.len(), 1, "{packs:?}");
        assert_eq!(packs[0]["id"], "demo");
        assert!(packs[0]["meta"].as_object().unwrap().is_empty(), "{:?}", packs[0]["meta"]);
    }
}
