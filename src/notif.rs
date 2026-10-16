//! Notifications Windows. L'API officielle (UserNotificationListener) exige
//! une appli empaquetee (MSIX) : on lit donc, en lecture seule, la base ou
//! Windows range le centre de notifications (`wpndatabase.db`).

use std::path::PathBuf;
use std::sync::Mutex;
use std::time::Duration;

use rusqlite::{Connection, OpenFlags};
use serde::Serialize;
use crate::host::{AppHandle, State};

/// Ecart entre l'epoque FILETIME (1601) et l'epoque Unix, en 100 ns.
const EPOCH_DIFF: i64 = 116_444_736_000_000_000;
const MAX: usize = 50;

#[derive(Serialize, Clone, PartialEq)]
pub struct Notif {
    id: i64,
    /// AUMID de l'appli (ou chemin de l'exe)
    app: String,
    title: String,
    body: String,
    /// ms depuis 1970
    time: i64,
    /// image fournie par l'appli (avatar...), en data URL
    image: String,
}

pub struct Notifs(pub Mutex<Vec<Notif>>);

fn db_path() -> PathBuf {
    // diagnostic : lire une copie de la base
    if let Ok(p) = std::env::var("ILOT_WPNDB") {
        return PathBuf::from(p);
    }
    let base = std::env::var("LOCALAPPDATA").unwrap_or_default();
    PathBuf::from(base).join(r"Microsoft\Windows\Notifications\wpndatabase.db")
}

fn open() -> Option<Connection> {
    let c = Connection::open_with_flags(db_path(), OpenFlags::SQLITE_OPEN_READ_ONLY | OpenFlags::SQLITE_OPEN_NO_MUTEX).ok()?;
    let _ = c.busy_timeout(Duration::from_millis(500));
    Some(c)
}

fn unescape(s: &str) -> String {
    s.replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&apos;", "'")
        .replace("&#39;", "'")
        .replace("&amp;", "&")
}

/// Valeur d'un attribut dans une balise ouvrante.
fn attr(tag: &str, name: &str) -> Option<String> {
    let k = format!("{name}=\"");
    let i = tag.find(&k)? + k.len();
    let j = tag[i..].find('"')? + i;
    Some(unescape(&tag[i..j]))
}

/// Textes et image d'un toast XML (`<text>…</text>`, `<image src=…>`).
fn parse(xml: &str) -> (Vec<String>, Option<String>) {
    let mut texts = Vec::new();
    let mut image = None;
    let mut rest = xml;
    while let Some(i) = rest.find('<') {
        rest = &rest[i + 1..];
        let end = rest.find('>').unwrap_or(rest.len());
        let tag = &rest[..end];
        if tag.starts_with("text") && !tag.ends_with('/') {
            let body = &rest[(end + 1).min(rest.len())..];
            if let Some(close) = body.find("</text>") {
                let t = unescape(body[..close].trim());
                if !t.is_empty() {
                    texts.push(t);
                }
            }
        } else if tag.starts_with("image") && image.is_none() {
            let placement = attr(tag, "placement").unwrap_or_default();
            if placement == "appLogoOverride" || placement.is_empty() {
                image = attr(tag, "src");
            }
        }
        rest = &rest[end.min(rest.len())..];
    }
    (texts, image)
}

/// Image locale -> petite miniature ; les images distantes sont ignorees.
fn image_data(src: &str) -> String {
    let path = src
        .strip_prefix("file:///")
        .or_else(|| src.strip_prefix("file://"))
        .unwrap_or(src)
        .replace("%20", " ");
    let p = std::path::Path::new(&path);
    if !p.is_absolute() || !p.is_file() {
        return String::new();
    }
    crate::wall::thumb_sized(p, 96).unwrap_or_default()
}

fn query(c: &Connection, after: i64) -> rusqlite::Result<Vec<Notif>> {
    let mut st = c.prepare(
        "SELECT n.Id, h.PrimaryId, n.Payload, n.ArrivalTime FROM Notification n \
         JOIN NotificationHandler h ON h.RecordId = n.HandlerId \
         WHERE n.Type = 'toast' AND n.Id > ?1 ORDER BY n.Id DESC LIMIT ?2",
    )?;
    let rows = st.query_map(rusqlite::params![after, MAX as i64], |r| {
        let payload: Vec<u8> = r.get::<_, Option<Vec<u8>>>(2)?.unwrap_or_default();
        Ok((r.get::<_, i64>(0)?, r.get::<_, String>(1)?, payload, r.get::<_, Option<i64>>(3)?.unwrap_or(0)))
    })?;
    let mut out = Vec::new();
    for row in rows.flatten() {
        let (id, app, payload, arrival) = row;
        let xml = String::from_utf8_lossy(&payload);
        let (texts, img) = parse(&xml);
        if texts.is_empty() {
            continue;
        }
        out.push(Notif {
            id,
            app,
            title: texts[0].clone(),
            body: texts[1..].join("\n"),
            time: (arrival - EPOCH_DIFF) / 10_000,
            image: img.map(|s| image_data(&s)).unwrap_or_default(),
        });
    }
    Ok(out)
}

/// Diagnostic : les dernieres notifications lues dans la base.
pub fn snapshot() -> Result<Vec<Notif>, String> {
    let c = open().ok_or("base introuvable ou illisible")?;
    query(&c, 0).map_err(|e| e.to_string())
}

fn visible(app: &AppHandle, list: Vec<Notif>) -> Vec<Notif> {
    let st = app.state::<crate::settings::Settings>();
    let cfg = st.0.lock().unwrap();
    list.into_iter()
        .filter(|n| n.id > cfg.notif_cleared && !cfg.notif_hidden.contains(&n.id))
        .collect()
}

/// Emet `notifs` (la liste) quand elle change et `notif` pour chaque
/// nouvelle notification arrivee depuis le lancement.
pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        let mut conn = None;
        let mut seen_max: Option<i64> = None;
        let mut last: Vec<Notif> = Vec::new();
        loop {
            if conn.is_none() {
                conn = open();
            }
            if let Some(c) = &conn {
                match query(c, 0) {
                    Ok(all) => {
                        let max = all.first().map(|n| n.id).unwrap_or(0);
                        if let Some(prev) = seen_max {
                            for n in all.iter().rev().filter(|n| n.id > prev) {
                                let _ = app.emit("notif", n);
                            }
                        }
                        seen_max = Some(seen_max.unwrap_or(0).max(max));
                        let list = visible(&app, all);
                        if list != last {
                            *app.state::<Notifs>().0.lock().unwrap() = list.clone();
                            let _ = app.emit("notifs", &list);
                            last = list;
                        }
                    }
                    Err(_) => conn = None,
                }
            }
            std::thread::sleep(Duration::from_millis(1200));
        }
    });
}

pub fn notifs_get(st: State<Notifs>) -> Vec<Notif> {
    st.0.lock().unwrap().clone()
}

/// Masque une notification (ou toutes avec `id = None`) dans l'ilot. La
/// base de Windows n'est jamais modifiee.
pub fn notifs_dismiss(app: AppHandle, id: Option<i64>) {
    let list = {
        let st = app.state::<Notifs>();
        let mut list = st.0.lock().unwrap();
        crate::settings::update(&app, |cfg| match id {
            Some(id) => cfg.notif_hidden.push(id),
            None => {
                cfg.notif_cleared = cfg.notif_cleared.max(list.iter().map(|n| n.id).max().unwrap_or(0));
                cfg.notif_hidden.clear();
            }
        });
        match id {
            Some(id) => list.retain(|n| n.id != id),
            None => list.clear(),
        }
        list.clone()
    };
    let _ = app.emit("notifs", &list);
}

pub fn notif_open(app_id: String) {
    use std::os::windows::process::CommandExt;
    let _ = std::process::Command::new("explorer.exe")
        .arg(format!("shell:AppsFolder\\{app_id}"))
        .creation_flags(0x0800_0000)
        .spawn();
}
