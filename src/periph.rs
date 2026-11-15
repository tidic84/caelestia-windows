//! Batterie des peripheriques sans fil, relue toutes les minutes :
//! - souris (et autres) Logitech en HID++ 2.0, par recepteur Lightspeed /
//!   Unifying ou en direct (fonctions 0x1004 UNIFIED_BATTERY, sinon 0x1000) ;
//! - casque EPOS H3PRO par son dongle (1395:0303), protocole releve sur le
//!   dongle : trame `01 EB FE 01 00 04 00 <type> 00 <len> 00 <crc8> 00 <donnees>`,
//!   CRC-8 (poly 0x07, init 0xFF) sur les donnees ; demande de type 5
//!   `12 00 03 00`, reponse `12 00 03 00 <pourcentage> 00`.
//!
//! Le resultat est joint a l'evenement `sys` (champ `periph`, voir system.rs).

use crate::host::AppHandle;
use hidapi::{HidApi, HidDevice};
use serde::Serialize;
use std::sync::Mutex;
use std::time::{Duration, Instant};

#[derive(Serialize, Clone)]
pub struct Periph {
    /// « mouse », « keyboard », « headset » ou « other »
    kind: &'static str,
    name: String,
    /// 0-100
    level: u8,
    charging: bool,
}

static LAST: Mutex<Vec<Periph>> = Mutex::new(Vec::new());

/// Derniere lecture (vide tant que rien n'a repondu).
pub fn current() -> Vec<Periph> {
    LAST.lock().map(|v| v.clone()).unwrap_or_default()
}

/// Releve en arriere-plan, seulement si l'addon « batt » (Batteries) est
/// active dans Reglages > Addons.
pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        let mut api = match HidApi::new() {
            Ok(a) => a,
            Err(_) => return,
        };
        // derniere valeur de chaque appareil : une souris en veille ne repond
        // plus, on garde sa valeur une heure plutot que de la faire disparaitre
        let mut seen: Vec<(Periph, Instant)> = Vec::new();
        loop {
            if !crate::settings::addon_on(&app, "batt") {
                seen.clear();
                if let Ok(mut l) = LAST.lock() {
                    l.clear();
                }
                std::thread::sleep(Duration::from_secs(5));
                continue;
            }
            let mut fresh = Vec::new();
            if api.refresh_devices().is_ok() {
                fresh.extend(logitech(&api));
                fresh.extend(epos(&api));
            }
            let now = Instant::now();
            for p in fresh {
                match seen.iter_mut().find(|(q, _)| q.kind == p.kind && q.name == p.name) {
                    Some(e) => *e = (p, now),
                    None => seen.push((p, now)),
                }
            }
            seen.retain(|(_, t)| now.duration_since(*t) < Duration::from_secs(3600));
            if let Ok(mut l) = LAST.lock() {
                *l = seen.iter().map(|(p, _)| p.clone()).collect();
            }
            std::thread::sleep(Duration::from_secs(60));
        }
    });
}

// ---------------------------------------------------------------- Logitech

const LOGI: u16 = 0x046D;
/// identifiant logiciel des requetes HID++ (1-15), pour reconnaitre nos reponses
const SW: u8 = 0x0B;

/// Une requete HID++ 2.0 (rapport court 0x10), reponse lue sur le rapport long
/// 0x11. `None` si erreur ou pas de reponse.
fn hidpp(short: &HidDevice, long: &HidDevice, dev: u8, feat: u8, func: u8, params: &[u8]) -> Option<[u8; 20]> {
    let mut b = [0u8; 7];
    b[0] = 0x10;
    b[1] = dev;
    b[2] = feat;
    b[3] = (func << 4) | SW;
    for (i, p) in params.iter().take(3).enumerate() {
        b[4 + i] = *p;
    }
    short.write(&b).ok()?;
    let end = Instant::now() + Duration::from_millis(600);
    let mut buf = [0u8; 20];
    let mut sbuf = [0u8; 7];
    while Instant::now() < end {
        // erreur HID++ 1.0 (appareil absent sur le recepteur) : rapport court
        if let Ok(n) = short.read_timeout(&mut sbuf, 0) {
            if n >= 4 && sbuf[0] == 0x10 && sbuf[1] == dev && sbuf[2] == 0x8F && sbuf[3] == feat {
                return None;
            }
        }
        let n = long.read_timeout(&mut buf, 50).ok()?;
        if n < 4 || buf[0] != 0x11 || buf[1] != dev {
            continue;
        }
        if buf[2] == feat && buf[3] == b[3] {
            return Some(buf);
        }
        // erreur HID++ 2.0
        if buf[2] == 0xFF && buf[3] == feat {
            return None;
        }
    }
    None
}

fn feature(short: &HidDevice, long: &HidDevice, dev: u8, id: u16) -> Option<u8> {
    let r = hidpp(short, long, dev, 0, 0, &[(id >> 8) as u8, id as u8])?;
    (r[4] != 0).then_some(r[4])
}

fn logi_name(short: &HidDevice, long: &HidDevice, dev: u8) -> Option<(String, u8)> {
    let idx = feature(short, long, dev, 0x0005)?;
    let len = hidpp(short, long, dev, idx, 0, &[])?[4] as usize;
    let mut name = Vec::new();
    while name.len() < len.min(64) {
        let r = hidpp(short, long, dev, idx, 1, &[name.len() as u8])?;
        name.extend(r[4..20].iter().take(len - name.len()));
    }
    let kind = hidpp(short, long, dev, idx, 2, &[]).map_or(0xFF, |r| r[4]);
    Some((String::from_utf8_lossy(&name).trim_end_matches('\0').trim().to_string(), kind))
}

fn logitech(api: &HidApi) -> Vec<Periph> {
    let mut res = Vec::new();
    let list: Vec<_> = api.device_list().collect();
    for s in list.iter().filter(|d| d.vendor_id() == LOGI && d.usage_page() == 0xFF00 && d.usage() == 1) {
        let Some(l) = list.iter().find(|d| {
            d.vendor_id() == LOGI
                && d.product_id() == s.product_id()
                && d.interface_number() == s.interface_number()
                && d.usage_page() == 0xFF00
                && d.usage() == 2
        }) else {
            continue;
        };
        let (Ok(short), Ok(long)) = (s.open_device(api), l.open_device(api)) else {
            continue;
        };
        // recepteur : appareils 1 a 6 ; branche en direct (cable, Bluetooth) : 0xFF
        for dev in (1..=6u8).chain([0xFF]) {
            let Some(ping) = hidpp(&short, &long, dev, 0, 1, &[0, 0, 0xAA]) else {
                continue;
            };
            if ping[4] < 2 {
                continue;
            }
            let (level, charging) = if let Some(i) = feature(&short, &long, dev, 0x1004) {
                match hidpp(&short, &long, dev, i, 1, &[]) {
                    Some(r) => (r[4], matches!(r[6], 1 | 2)),
                    None => continue,
                }
            } else if let Some(i) = feature(&short, &long, dev, 0x1000) {
                match hidpp(&short, &long, dev, i, 0, &[]) {
                    Some(r) => (r[4], matches!(r[6], 1 | 2)),
                    None => continue,
                }
            } else {
                continue;
            };
            if level == 0 || level > 100 {
                continue;
            }
            let (name, t) = logi_name(&short, &long, dev).unwrap_or_else(|| ("Logitech".into(), 0xFF));
            // 0x0005 fonction 2 : 0 clavier, 3 souris, 4 pave tactile, 5 trackball, 8 casque
            let kind = match t {
                0 => "keyboard",
                3..=5 => "mouse",
                8 => "headset",
                _ => "other",
            };
            res.push(Periph { kind, name, level, charging });
        }
    }
    res
}

// -------------------------------------------------------------------- EPOS

const EPOS: u16 = 0x1395;

fn crc8(d: &[u8]) -> u8 {
    let mut c: u8 = 0xFF;
    for b in d {
        c ^= b;
        for _ in 0..8 {
            c = if c & 0x80 != 0 { (c << 1) ^ 0x07 } else { c << 1 };
        }
    }
    c
}

fn epos(api: &HidApi) -> Vec<Periph> {
    let mut res = Vec::new();
    // seul le dongle du H3PRO (0303) a ete verifie
    for d in api.device_list().filter(|d| d.vendor_id() == EPOS && d.product_id() == 0x0303 && d.usage_page() == 0xFFFF) {
        let Ok(dev) = d.open_device(api) else {
            continue;
        };
        let data = [0x12u8, 0x00, 0x03, 0x00];
        let mut f = [0u8; 107];
        f[..13].copy_from_slice(&[0x01, 0xEB, 0xFE, 0x01, 0x00, 0x04, 0x00, 0x05, 0x00, data.len() as u8, 0x00, crc8(&data), 0x00]);
        f[13..13 + data.len()].copy_from_slice(&data);
        if dev.write(&f).is_err() {
            continue;
        }
        let end = Instant::now() + Duration::from_millis(1000);
        let mut buf = [0u8; 107];
        while Instant::now() < end {
            let Ok(n) = dev.read_timeout(&mut buf, 100) else {
                break;
            };
            // 04 20 = erreur (casque eteint, par exemple)
            if n >= 19 && buf[1] == 0xEB && buf[2] == 0xFE && buf[13] == 0x12 && buf[15] == 0x03 {
                if buf[6] != 0x20 && buf[17] > 0 && buf[17] <= 100 {
                    let name = d.product_string().unwrap_or("EPOS").replace(" Dongle", "");
                    res.push(Periph { kind: "headset", name, level: buf[17], charging: false });
                }
                break;
            }
        }
    }
    res
}
