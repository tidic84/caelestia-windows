//! Images servies a l'interface par `image://ilot/<cle>.<ext>` (icones,
//! pochettes, fonds, apercus) : les evenements ne portent qu'une URL, et Qt
//! decode et met en cache l'image une fois (voir `ilot_image`).

use std::collections::{HashMap, VecDeque};
use std::hash::{Hash, Hasher};
use std::path::PathBuf;
use std::sync::Mutex;

enum Src {
    Bytes(Vec<u8>),
    /// Miniature deja en cache sur le disque : rien a garder en memoire
    File(PathBuf),
}

/// Images gardees tant que l'ilot tourne (icones, fonds, pochettes)
static KEPT: Mutex<Option<HashMap<u64, (&'static str, Src)>>> = Mutex::new(None);

/// Images vite remplacees : seules les dernieres restent.
pub struct Ring(Mutex<VecDeque<(u64, &'static str, Vec<u8>)>>, usize);

/// Apercus de fenetres (barre), renouveles sans cesse
pub static THUMBS: Ring = Ring(Mutex::new(VecDeque::new()), 48);
/// Images du presse-papiers (l'historique n'en garde que quelques-unes)
pub static CLIPS: Ring = Ring(Mutex::new(VecDeque::new()), 16);
/// Pochettes (une par morceau) et QR codes de Quick Share : gardees dans
/// `KEPT`, elles s'accumuleraient tant que l'ilot tourne
pub static ART: Ring = Ring(Mutex::new(VecDeque::new()), 16);

fn key<T: Hash + ?Sized>(v: &T) -> u64 {
    let mut h = std::collections::hash_map::DefaultHasher::new();
    v.hash(&mut h);
    h.finish()
}

/// URL lue par le fournisseur d'images de Qt (qt/src/backend.cpp)
fn url_of(k: u64, mime: &str) -> String {
    format!("image://ilot/{k:016x}.{}", ext_of(mime))
}

/// Garde l'image et renvoie son URL (meme contenu : meme URL).
pub fn url(mime: &'static str, bytes: Vec<u8>) -> String {
    let k = key(bytes.as_slice());
    KEPT.lock().unwrap().get_or_insert_with(HashMap::new).entry(k).or_insert((mime, Src::Bytes(bytes)));
    url_of(k, mime)
}

/// URL d'une image sur le disque, lue a chaque demande.
pub fn file_url(mime: &'static str, path: PathBuf) -> String {
    let k = key(&path);
    KEPT.lock().unwrap().get_or_insert_with(HashMap::new).entry(k).or_insert((mime, Src::File(path)));
    url_of(k, mime)
}

impl Ring {
    pub fn url(&self, mime: &'static str, bytes: Vec<u8>) -> String {
        let k = key(bytes.as_slice());
        let mut q = self.0.lock().unwrap();
        if !q.iter().any(|e| e.0 == k) {
            q.push_back((k, mime, bytes));
            while q.len() > self.1 {
                q.pop_front();
            }
        }
        url_of(k, mime)
    }

    fn get(&self, k: u64) -> Option<(&'static str, Vec<u8>)> {
        self.0.lock().unwrap().iter().find(|e| e.0 == k).map(|e| (e.1, e.2.clone()))
    }
}

/// Type MIME a duree de vie statique, d'apres celui annonce par une source.
pub fn mime(m: &str) -> &'static str {
    match m {
        "image/jpeg" | "image/jpg" => "image/jpeg",
        "image/gif" => "image/gif",
        "image/webp" => "image/webp",
        "image/bmp" => "image/bmp",
        _ => "image/png",
    }
}

fn ext_of(mime: &str) -> &'static str {
    match mime {
        "image/jpeg" => "jpg",
        "image/gif" => "gif",
        "image/webp" => "webp",
        "image/bmp" => "bmp",
        _ => "png",
    }
}

fn find(k: u64) -> Option<(&'static str, Vec<u8>)> {
    let kept = KEPT.lock().unwrap().as_ref().and_then(|m| {
        m.get(&k).map(|(mime, src)| match src {
            Src::Bytes(b) => Some((*mime, b.clone())),
            Src::File(p) => std::fs::read(p).ok().map(|b| (*mime, b)),
        })
    });
    kept.flatten().or_else(|| THUMBS.get(k)).or_else(|| CLIPS.get(k)).or_else(|| ART.get(k))
}

/// Contenu d'une image d'apres son URL (diagnostics).
pub fn bytes(url: &str) -> Option<Vec<u8>> {
    let name = url.rsplit('/').next()?;
    find(u64::from_str_radix(name.split('.').next()?, 16).ok()?).map(|f| f.1)
}

/// Contenu d'une image d'apres son identifiant : `<cle>.<ext>`
pub fn lookup(id: &str) -> Option<Vec<u8>> {
    let name = id.rsplit('/').next()?;
    let hex = name.split('.').next().unwrap_or(name);
    find(u64::from_str_radix(hex, 16).ok()?).map(|f| f.1)
}
