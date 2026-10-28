//! Quick Share (ex-Nearby Share de Google) : echange de fichiers avec les
//! telephones Android et les PC sur le meme reseau, sans application a part.
//!
//! Le protocole n'est pas documente par Google : cette implementation suit la
//! description de NearDrop (github.com/grishka/NearDrop, domaine public) et
//! les .proto de google/nearby (Apache 2.0). Seul le Wi-Fi local est gere
//! (pas de Bluetooth classique ni de Wi-Fi Direct) :
//! - reception : l'ilot ecoute sur un port TCP et s'annonce en mDNS
//!   (`_FC9F5ED42C8A._tcp`) ; il repond aux annonces Bluetooth des
//!   telephones qui cherchent a qui envoyer en se re-annoncant ;
//! - envoi : recherche des appareils en mDNS ; une annonce Bluetooth
//!   (service 0xFE2C) reveille les telephones Android, qui se rendent alors
//!   visibles. A defaut, le telephone scanne le QR code affiche par l'ilot.

mod conn;
mod inbound;
mod outbound;
mod proto;

use std::collections::{HashMap, HashSet};
use std::net::{IpAddr, Ipv4Addr, SocketAddr, TcpListener};
use std::path::{Path, PathBuf};
use std::sync::mpsc::Sender;
use std::sync::{Arc, Mutex};
use std::time::{Duration, Instant};

use aes_gcm::aead::{Aead, KeyInit, Payload};
use base64::engine::general_purpose::URL_SAFE_NO_PAD;
use base64::Engine;
use mdns_sd::{ServiceDaemon, ServiceEvent, ServiceInfo};
use p256::ecdsa::SigningKey;
use serde::{Deserialize, Serialize};
use windows::Devices::Bluetooth::Advertisement::{
    BluetoothLEAdvertisementDataSection, BluetoothLEAdvertisementPublisher, BluetoothLEAdvertisementReceivedEventArgs,
    BluetoothLEAdvertisementWatcher,
};
use windows::Foundation::TypedEventHandler;
use windows::Storage::Streams::{DataReader, DataWriter};
use windows::Win32::NetworkManagement::IpHelper::{GetAdaptersAddresses, GAA_FLAG_INCLUDE_GATEWAYS, IP_ADAPTER_ADDRESSES_LH};
use windows::Win32::Networking::WinSock::{AF_INET, SOCKADDR_IN};

use crate::host::{AppHandle, State};
use conn::{Cmd, Ev};

const SERVICE: &str = "_FC9F5ED42C8A._tcp.local.";
/// « Visible pendant 10 minutes »
const TEMP_VISIBLE: Duration = Duration::from_secs(600);
/// la recherche s'arrete d'elle-meme si l'interface oublie de la couper
const DISCOVER_MAX: Duration = Duration::from_secs(600);
/// donnees de service Bluetooth qui font s'annoncer les telephones Android
/// (prefixe fixe puis 10 octets au hasard)
const BLE_PREFIX: [u8; 14] = [0xFC, 0x12, 0x8E, 0x01, 0x42, 0, 0, 0, 0, 0, 0, 0, 0, 0];

// ----------------------------------------------------------------- etat

#[derive(Serialize, Deserialize, Clone)]
struct Cfg {
    name: String,
    /// "on" (visible par tous), "temp" (10 minutes), "off" (masque)
    visibility: String,
}

impl Default for Cfg {
    fn default() -> Self {
        let name = std::env::var("COMPUTERNAME").unwrap_or_else(|_| "PC".into());
        Cfg { name, visibility: "on".into() }
    }
}

/// Un element d'un transfert : fichier, texte, lien ou reseau Wi-Fi.
#[derive(Serialize, Clone, Default)]
pub struct Item {
    pub name: String,
    pub size: u64,
    pub kind: &'static str,
    /// fichier envoye ou recu
    pub path: String,
}

impl Item {
    pub fn file(name: &str, size: u64, path: &str) -> Self {
        Item { name: name.into(), size, kind: "file", path: path.into() }
    }
}

/// Un envoi ou une reception, tel que l'interface l'affiche.
#[derive(Serialize, Clone, Default)]
pub struct Transfer {
    pub id: u64,
    pub out: bool,
    pub peer: String,
    /// type d'appareil : 1 telephone, 2 tablette, 3 ordinateur
    pub kind: u8,
    /// connecting, ask (a accepter), waiting (attend l'autre), transfer,
    /// done, rejected, cancelled, failed
    pub status: &'static str,
    pub pin: String,
    pub items: Vec<Item>,
    pub done: u64,
    pub total: u64,
    /// texte ou lien recu, mot de passe Wi-Fi
    pub text: String,
    pub error: String,
    pub qr: bool,
}

impl Transfer {
    pub fn finished(&self) -> bool {
        matches!(self.status, "done" | "rejected" | "cancelled" | "failed")
    }
}

#[derive(Serialize, Clone)]
struct Device {
    id: String,
    name: String,
    kind: u8,
    #[serde(skip)]
    addr: SocketAddr,
    #[serde(skip)]
    fullname: String,
}

struct QrKey {
    key: SigningKey,
    token: Vec<u8>,
    name_key: Vec<u8>,
    url: String,
    png: String,
}

struct Inner {
    cfg: Cfg,
    /// identifiant de l'ilot (4 caracteres) et « endpoint info » annoncee
    eid: String,
    info: Vec<u8>,
    port: u16,
    ip: Option<Ipv4Addr>,
    daemon: Option<ServiceDaemon>,
    registered: Option<String>,
    temp_until: Option<Instant>,
    devices: Vec<Device>,
    discovering: bool,
    discover_gen: u64,
    discover_until: Instant,
    transfers: Vec<Transfer>,
    ctrls: HashMap<u64, Sender<Ev>>,
    next_id: u64,
    qr: Option<QrKey>,
    /// fichiers a envoyer au telephone qui scanne le QR code
    pending: Vec<String>,
    qr_started: HashSet<String>,
    publisher: Option<BluetoothLEAdvertisementPublisher>,
    watcher: Option<BluetoothLEAdvertisementWatcher>,
    ble: &'static str,
    last_progress: Instant,
    last_announce: Instant,
    error: String,
}

#[derive(Clone)]
pub struct Qs(Arc<Mutex<Inner>>);

#[derive(Serialize)]
struct QrView<'a> {
    url: &'a str,
    png: &'a str,
}

#[derive(Serialize)]
struct Snapshot<'a> {
    name: &'a str,
    visibility: &'a str,
    temp_left: u64,
    ready: bool,
    ip: String,
    devices: &'a [Device],
    discovering: bool,
    ble: &'a str,
    transfers: &'a [Transfer],
    qr: Option<QrView<'a>>,
    error: &'a str,
}

fn snapshot(g: &Inner) -> serde_json::Value {
    serde_json::to_value(Snapshot {
        name: &g.cfg.name,
        visibility: &g.cfg.visibility,
        temp_left: g.temp_until.map_or(0, |t| t.saturating_duration_since(Instant::now()).as_secs()),
        ready: g.port != 0 && (g.registered.is_some() || g.cfg.visibility == "off"),
        ip: g.ip.map(|i| i.to_string()).unwrap_or_default(),
        devices: &g.devices,
        discovering: g.discovering,
        ble: g.ble,
        transfers: &g.transfers,
        qr: g.qr.as_ref().map(|q| QrView { url: &q.url, png: &q.png }),
        error: &g.error,
    })
    .unwrap_or_default()
}

impl Default for Qs {
    fn default() -> Self {
        let cfg: Cfg = crate::store::read("quickshare").unwrap_or_default();
        const ALPHA: &[u8] = b"0123456789abcdefghijklmnopqrstuvwxyzABCDEFGHIJKLMNOPQRSTUVWXYZ";
        let eid: String = conn::random::<4>().iter().map(|b| ALPHA[*b as usize % ALPHA.len()] as char).collect();
        let info = endpoint_info(&cfg.name);
        let past = Instant::now() - Duration::from_secs(60);
        Qs(Arc::new(Mutex::new(Inner {
            cfg,
            eid,
            info,
            port: 0,
            ip: None,
            daemon: None,
            registered: None,
            temp_until: None,
            devices: Vec::new(),
            discovering: false,
            discover_gen: 0,
            discover_until: Instant::now(),
            transfers: Vec::new(),
            ctrls: HashMap::new(),
            next_id: 1,
            qr: None,
            pending: Vec::new(),
            qr_started: HashSet::new(),
            publisher: None,
            watcher: None,
            ble: "",
            last_progress: past,
            last_announce: past,
            error: String::new(),
        })))
    }
}

impl Qs {
    fn lock(&self) -> std::sync::MutexGuard<'_, Inner> {
        self.0.lock().unwrap_or_else(|e| e.into_inner())
    }

    /// Modifie l'etat puis previent l'interface (hors du verrou).
    fn with<R>(&self, f: impl FnOnce(&mut Inner) -> R) -> R {
        let (r, snap) = {
            let mut g = self.lock();
            let r = f(&mut g);
            (r, snapshot(&g))
        };
        let _ = AppHandle.emit("qs", snap);
        r
    }

    pub fn add(&self, mut t: Transfer, tx: Sender<Ev>) -> u64 {
        self.with(|g| {
            t.id = g.next_id;
            g.next_id += 1;
            g.ctrls.insert(t.id, tx);
            g.transfers.insert(0, t);
            // garde les 30 derniers
            let mut n = 0;
            g.transfers.retain(|t| {
                n += 1;
                n <= 30 || !t.finished()
            });
            g.next_id - 1
        })
    }

    pub fn update(&self, id: u64, f: impl FnOnce(&mut Transfer)) {
        self.with(|g| {
            if let Some(t) = g.transfers.iter_mut().find(|t| t.id == id) {
                f(t);
            }
        });
    }

    /// Avancement ; l'interface n'est prevenue que quelques fois par seconde.
    pub fn progress(&self, id: u64, done: u64) {
        let snap = {
            let mut g = self.lock();
            if let Some(t) = g.transfers.iter_mut().find(|t| t.id == id) {
                t.done = done;
            }
            if g.last_progress.elapsed() < Duration::from_millis(150) {
                return;
            }
            g.last_progress = Instant::now();
            snapshot(&g)
        };
        let _ = AppHandle.emit("qs", snap);
    }

    pub fn forget(&self, id: u64) {
        self.lock().ctrls.remove(&id);
    }

    /// (identifiant, nom, endpoint info) de l'ilot pour une demande de connexion.
    pub fn identity(&self) -> (String, String, Vec<u8>) {
        let g = self.lock();
        (g.eid.clone(), g.cfg.name.clone(), g.info.clone())
    }
}

/// Octet 0 : type d'appareil (3 = ordinateur) decale d'un bit, visible ;
/// 16 octets au hasard (sans compte Google) ; nom precede de sa longueur.
fn endpoint_info(name: &str) -> Vec<u8> {
    let mut n = name.trim();
    while n.len() > 60 {
        let mut cut = 60;
        while !n.is_char_boundary(cut) {
            cut -= 1;
        }
        n = &n[..cut];
    }
    let mut v = vec![3 << 1];
    v.extend_from_slice(&conn::random::<16>());
    v.push(n.len() as u8);
    v.extend_from_slice(n.as_bytes());
    v
}

fn b64_decode(s: &str) -> Option<Vec<u8>> {
    URL_SAFE_NO_PAD.decode(s.trim_end_matches('=')).ok()
}

// ------------------------------------------------------------- mDNS

fn daemon(g: &mut Inner) -> Option<ServiceDaemon> {
    if g.daemon.is_none() {
        match ServiceDaemon::new() {
            Ok(d) => g.daemon = Some(d),
            Err(e) => g.error = format!("mDNS indisponible : {e}"),
        }
    }
    g.daemon.clone()
}

/// (Re)annonce l'ilot sur le reseau, ou retire l'annonce s'il est masque.
fn advertise(g: &mut Inner) {
    let Some(d) = daemon(g) else { return };
    g.ip = lan_ip();
    if g.cfg.visibility == "off" || g.port == 0 || g.ip.is_none() {
        if let Some(f) = g.registered.take() {
            let _ = d.unregister(&f);
        }
        if g.ip.is_none() {
            g.error = "PC non connecté au réseau local".into();
        }
        return;
    }
    // nom du service : 0x23, identifiant, 3 octets de SHA256("NearbySharing"), 2 zeros
    let mut raw = vec![0x23];
    raw.extend_from_slice(g.eid.as_bytes());
    raw.extend_from_slice(&[0xFC, 0x9F, 0x5E, 0, 0]);
    let instance = URL_SAFE_NO_PAD.encode(raw);
    let txt = HashMap::from([("n".to_string(), URL_SAFE_NO_PAD.encode(&g.info))]);
    let host = format!("ilot-{}.local.", g.eid.to_lowercase());
    let ip = IpAddr::V4(g.ip.unwrap_or(Ipv4Addr::UNSPECIFIED));
    match ServiceInfo::new(SERVICE, &instance, &host, ip, g.port, txt) {
        Ok(si) => {
            let full = si.get_fullname().to_string();
            match d.register(si) {
                Ok(()) => {
                    g.registered = Some(full);
                    g.error.clear();
                    g.last_announce = Instant::now();
                }
                Err(e) => g.error = format!("Annonce impossible : {e}"),
            }
        }
        Err(e) => g.error = format!("Annonce impossible : {e}"),
    }
}

/// Appareil trouve : nom (en clair ou chiffre pour le QR code) et adresse.
fn on_resolved(q: &Qs, info: &ServiceInfo) {
    let full = info.get_fullname().to_string();
    let Some(raw) = full.strip_suffix(&format!(".{SERVICE}")).and_then(b64_decode) else { return };
    if raw.len() < 10 || raw[0] != 0x23 || raw[5..8] != [0xFC, 0x9F, 0x5E] {
        return;
    }
    let eid = String::from_utf8_lossy(&raw[1..5]).to_string();
    let Some((name, kind, tlv)) = info.get_property_val_str("n").and_then(b64_decode).and_then(|i| inbound::parse_endpoint_info(&i)) else {
        return;
    };
    let Some(ip) = info.get_addresses_v4().into_iter().next().copied() else { return };
    let addr = SocketAddr::new(IpAddr::V4(ip), info.get_port());
    let start = q.with(|g| {
        if eid == g.eid {
            return None;
        }
        // QR code scanne : jeton en clair (appareil visible) ou nom chiffre
        let mut name = name;
        let mut via_qr = false;
        if let (Some(qr), Some((_, v))) = (&g.qr, tlv.iter().find(|(t, _)| *t == 1)) {
            if *v == qr.token {
                via_qr = true;
            } else if v.len() > 28 {
                let cipher = aes_gcm::Aes128Gcm::new_from_slice(&qr.name_key).ok()?;
                let plain = cipher.decrypt(v[..12].into(), Payload { msg: &v[12..], aad: &qr.token }).ok();
                if let Some(p) = plain {
                    name = Some(String::from_utf8_lossy(&p).to_string());
                    via_qr = true;
                }
            }
        }
        let mut name = name?;
        // visible mais sans nom : nom d'hote mDNS
        if name.is_empty() {
            name = info.get_hostname().trim_end_matches('.').trim_end_matches(".local").to_string();
            if name.is_empty() {
                name = "Appareil Android".into();
            }
        }
        g.devices.retain(|d| d.id != eid);
        g.devices.push(Device { id: eid.clone(), name, kind, addr, fullname: full });
        (via_qr && !g.pending.is_empty() && g.qr_started.insert(eid.clone())).then(|| (eid.clone(), g.pending.clone()))
    });
    // le telephone qui a scanne le QR code recoit tout de suite les fichiers
    if let Some((eid, paths)) = start {
        let _ = send_to(q, &eid, &paths, None);
    }
}

fn discover(q: &Qs, on: bool) {
    let rx = q.with(|g| {
        if !on {
            g.discover_gen += 1;
            if g.discovering {
                if let Some(d) = &g.daemon {
                    let _ = d.stop_browse(SERVICE);
                }
            }
            g.discovering = false;
            g.devices.clear();
            g.qr = None;
            g.qr_started.clear();
            ble_publish(g, false);
            return None;
        }
        g.discover_until = Instant::now() + DISCOVER_MAX;
        if g.discovering {
            return None;
        }
        let d = daemon(g)?;
        let rx = d.browse(SERVICE).ok()?;
        g.discovering = true;
        g.discover_gen += 1;
        ble_publish(g, true);
        Some((rx, g.discover_gen))
    });
    let Some((rx, gen)) = rx else { return };
    let q = q.clone();
    std::thread::spawn(move || {
        while let Ok(ev) = rx.recv() {
            if q.lock().discover_gen != gen {
                break;
            }
            match ev {
                ServiceEvent::ServiceResolved(info) => on_resolved(&q, &info),
                ServiceEvent::ServiceRemoved(_, full) => q.with(|g| g.devices.retain(|d| d.fullname != full)),
                ServiceEvent::SearchStopped(_) => break,
                _ => {}
            }
        }
    });
}

// ------------------------------------------------------------ Bluetooth

/// Annonce Bluetooth « quelqu'un veut partager » : les telephones Android
/// a proximite se mettent alors a s'annoncer en mDNS.
fn ble_publish(g: &mut Inner, on: bool) {
    if let Some(p) = g.publisher.take() {
        let _ = p.Stop();
    }
    if !on {
        return;
    }
    crate::com_init_mta();
    let start = || -> windows::core::Result<BluetoothLEAdvertisementPublisher> {
        let mut data = vec![0x2C, 0xFE];
        data.extend_from_slice(&BLE_PREFIX);
        data.extend_from_slice(&conn::random::<10>());
        let w = DataWriter::new()?;
        w.WriteBytes(&data)?;
        // 0x16 : donnees de service, UUID sur 16 bits
        let section = BluetoothLEAdvertisementDataSection::Create(0x16, &w.DetachBuffer()?)?;
        let p = BluetoothLEAdvertisementPublisher::new()?;
        p.Advertisement()?.DataSections()?.Append(&section)?;
        p.Start()?;
        Ok(p)
    };
    match start() {
        Ok(p) => {
            g.publisher = Some(p);
            g.ble = "on";
        }
        Err(_) => g.ble = "off",
    }
}

/// Ecoute les annonces Bluetooth des appareils qui partagent : l'ilot se
/// re-annonce aussitot en mDNS pour apparaitre plus vite sur le telephone.
fn ble_watch(q: &Qs) {
    let qc = q.clone();
    let handler = TypedEventHandler::<BluetoothLEAdvertisementWatcher, BluetoothLEAdvertisementReceivedEventArgs>::new(
        move |_, args| {
            let Some(args) = args.as_ref() else { return Ok(()) };
            let sections = args.Advertisement()?.GetSectionsByType(0x16)?;
            let mut sharing = false;
            for s in sections {
                let buf = s.Data()?;
                let mut b = vec![0u8; buf.Length()? as usize];
                DataReader::FromBuffer(&buf)?.ReadBytes(&mut b)?;
                sharing |= b.starts_with(&[0x2C, 0xFE]);
            }
            if sharing {
                nearby(&qc);
            }
            Ok(())
        },
    );
    let start = || -> windows::core::Result<BluetoothLEAdvertisementWatcher> {
        let w = BluetoothLEAdvertisementWatcher::new()?;
        w.Received(&handler)?;
        w.Start()?;
        Ok(w)
    };
    if let Ok(w) = start() {
        q.lock().watcher = Some(w);
    }
}

fn nearby(q: &Qs) {
    let mut g = q.lock();
    if g.cfg.visibility != "off" && g.last_announce.elapsed() > Duration::from_secs(8) {
        advertise(&mut g);
    }
}

// ------------------------------------------------------------- demarrage

/// Ecoute les connexions entrantes, s'annonce et surveille le Bluetooth.
pub fn init(st: State<Qs>) {
    let q: Qs = (*st).clone();
    std::thread::spawn(move || {
        crate::com_init_mta();
        match TcpListener::bind(("0.0.0.0", 0)) {
            Ok(l) => {
                q.lock().port = l.local_addr().map_or(0, |a| a.port());
                let qc = q.clone();
                std::thread::spawn(move || {
                    for s in l.incoming().flatten() {
                        // masque : personne ne peut envoyer
                        if qc.lock().cfg.visibility == "off" {
                            continue;
                        }
                        let qc = qc.clone();
                        std::thread::spawn(move || inbound::handle(s, qc));
                    }
                });
            }
            Err(e) => q.lock().error = format!("Port indisponible : {e}"),
        }
        q.with(advertise);
        ble_watch(&q);
        // horloge : fin de la visibilite temporaire, changement de reseau,
        // recherche oubliee
        let mut tick = 0u32;
        loop {
            std::thread::sleep(Duration::from_secs(2));
            tick += 1;
            let (expired, stale) = {
                let g = q.lock();
                (g.temp_until.is_some_and(|t| Instant::now() >= t), g.discovering && Instant::now() >= g.discover_until)
            };
            if expired {
                q.with(|g| {
                    g.temp_until = None;
                    g.cfg.visibility = "off".into();
                    crate::store::write("quickshare", &g.cfg);
                    advertise(g);
                });
            }
            if stale {
                discover(&q, false);
            }
            if tick.is_multiple_of(15) {
                let changed = q.lock().ip != lan_ip();
                if changed {
                    q.with(advertise);
                }
            }
        }
    });
}

// ------------------------------------------------------------- commandes

pub fn qs_get(st: State<Qs>) -> serde_json::Value {
    snapshot(&st.lock())
}

pub fn qs_config(st: State<Qs>, name: Option<String>, visibility: Option<String>) {
    st.with(|g| {
        if let Some(n) = name.map(|n| n.trim().to_string()).filter(|n| !n.is_empty()) {
            g.cfg.name = n;
            g.info = endpoint_info(&g.cfg.name);
        }
        if let Some(v) = visibility.filter(|v| ["on", "temp", "off"].contains(&v.as_str())) {
            g.temp_until = (v == "temp").then(|| Instant::now() + TEMP_VISIBLE);
            g.cfg.visibility = v;
        }
        crate::store::write("quickshare", &g.cfg);
        advertise(g);
    });
}

/// Recherche des appareils (onglet Quick Share ouvert).
pub fn qs_discover(st: State<Qs>, on: bool) {
    discover(&st, on);
}

fn send_to(q: &Qs, device: &str, paths: &[String], text: Option<String>) -> Result<u64, String> {
    let items = outbound::items_of(paths, text);
    if items.is_empty() {
        return Err("Rien à envoyer".into());
    }
    let (dev, qr) = {
        let g = q.lock();
        let dev = g.devices.iter().find(|d| d.id == device).cloned().ok_or("Appareil introuvable")?;
        let qr = g.qr_started.contains(device).then(|| g.qr.as_ref().map(|k| k.key.clone())).flatten();
        (dev, qr)
    };
    let (tx, rx) = std::sync::mpsc::channel();
    let t = Transfer {
        out: true,
        peer: dev.name.clone(),
        kind: dev.kind,
        status: "connecting",
        total: items.iter().map(|i| if let outbound::Out::File { size, .. } = i { *size as u64 } else { 0 }).sum(),
        items: outbound::to_items(&items),
        qr: qr.is_some(),
        ..Default::default()
    };
    let id = q.add(t, tx.clone());
    let qc = q.clone();
    std::thread::spawn(move || outbound::send(qc, id, dev.addr, items, qr, rx, tx));
    Ok(id)
}

pub fn qs_send(st: State<Qs>, device: String, paths: Vec<String>, text: Option<String>) -> Result<u64, String> {
    send_to(&st, &device, &paths, text)
}

/// Accepter ou refuser une reception.
pub fn qs_answer(st: State<Qs>, id: u64, accept: bool) {
    if let Some(tx) = st.lock().ctrls.get(&id) {
        let _ = tx.send(Ev::Cmd(if accept { Cmd::Accept } else { Cmd::Reject }));
    }
}

pub fn qs_cancel(st: State<Qs>, id: u64) {
    if let Some(tx) = st.lock().ctrls.get(&id) {
        let _ = tx.send(Ev::Cmd(Cmd::Cancel));
    }
}

/// Oublie les transferts termines (ou un seul).
pub fn qs_clear(st: State<Qs>, id: Option<u64>) {
    st.with(|g| g.transfers.retain(|t| !t.finished() || id.is_some_and(|i| i != t.id)));
}

/// Fichiers en attente d'un appareil : envoyes au telephone qui scanne le
/// QR code.
pub fn qs_pending(st: State<Qs>, paths: Vec<String>) {
    st.lock().pending = paths;
}

/// QR code a scanner avec l'appareil photo du telephone : il s'annonce alors
/// avec un jeton derive de la cle, et l'ilot lui envoie les fichiers sans
/// qu'il ait a accepter.
pub fn qs_qr(st: State<Qs>, on: bool) {
    if on {
        discover(&st, true);
    }
    st.with(|g| {
        if !on {
            g.qr = None;
            return;
        }
        if g.qr.is_some() {
            return;
        }
        let key = SigningKey::random(&mut rand::rngs::OsRng);
        // versions (0, 0) puis cle publique compressee (02/03 + X)
        let mut kb = vec![0u8, 0];
        kb.extend_from_slice(key.verifying_key().to_encoded_point(true).as_bytes());
        let url = format!("https://quickshare.google/qrcode#key={}", URL_SAFE_NO_PAD.encode(&kb));
        g.qr = Some(QrKey {
            token: conn::hkdf(&kb, &[], b"advertisingContext", 16),
            name_key: conn::hkdf(&kb, &[], b"encryptionKey", 16),
            png: qr_png(&url),
            url,
            key,
        });
    });
}

// ---------------------------------------------------------------- outils

/// Adresse IPv4 du PC sur le reseau local (carte avec passerelle, hors VPN).
fn lan_ip() -> Option<Ipv4Addr> {
    unsafe {
        let mut size = 16 * 1024u32;
        let mut buf = vec![0u64; size as usize / 8];
        let mut r = GetAdaptersAddresses(AF_INET.0 as u32, GAA_FLAG_INCLUDE_GATEWAYS, None, Some(buf.as_mut_ptr() as _), &mut size);
        if r == 111 {
            // ERROR_BUFFER_OVERFLOW
            buf = vec![0u64; size as usize / 8 + 1];
            r = GetAdaptersAddresses(AF_INET.0 as u32, GAA_FLAG_INCLUDE_GATEWAYS, None, Some(buf.as_mut_ptr() as _), &mut size);
        }
        if r != 0 {
            return None;
        }
        let mut best: Option<(u8, Ipv4Addr)> = None;
        let mut a = buf.as_ptr() as *const IP_ADAPTER_ADDRESSES_LH;
        while !a.is_null() {
            let ad = &*a;
            a = ad.Next;
            // 1 = IfOperStatusUp ; 24 = boucle locale
            if ad.OperStatus.0 != 1 || ad.IfType == 24 || ad.FirstGatewayAddress.is_null() {
                continue;
            }
            let desc = ad.Description.to_string().unwrap_or_default().to_lowercase();
            if ["warp", "vpn", "virtual", "hyper-v", "vmware", "virtualbox", "wsl", "tap-", "wireguard", "tailscale"].iter().any(|k| desc.contains(k)) {
                continue;
            }
            let mut u = ad.FirstUnicastAddress;
            while !u.is_null() {
                let sa = (*u).Address.lpSockaddr;
                u = (*u).Next;
                if sa.is_null() || (*sa).sa_family != AF_INET {
                    continue;
                }
                let sin = &*(sa as *const SOCKADDR_IN);
                let ip = Ipv4Addr::from(u32::from_be(sin.sin_addr.S_un.S_addr));
                // reseau prive classique en premier (192.168.x.x puis 10.x, 172.16-31)
                let rank = match ip.octets() {
                    [192, 168, ..] => 0,
                    [10, ..] => 1,
                    [172, b, ..] if (16..32).contains(&b) => 2,
                    _ => 9,
                };
                if ip.is_link_local() || ip.is_loopback() {
                    continue;
                }
                if best.is_none_or(|(r, _)| rank < r) {
                    best = Some((rank, ip));
                }
            }
        }
        best.map(|(_, ip)| ip)
    }
}

/// QR code en PNG (noir sur blanc, marge de 4 modules), servi par `image://ilot/`.
fn qr_png(text: &str) -> String {
    let Ok(code) = qrcode::QrCode::new(text.as_bytes()) else { return String::new() };
    let n = code.width();
    let colors = code.to_colors();
    let (quiet, scale) = (4usize, 8usize);
    let side = (n + quiet * 2) * scale;
    let img = image::GrayImage::from_fn(side as u32, side as u32, |x, y| {
        let (mx, my) = ((x as usize / scale) as isize - quiet as isize, (y as usize / scale) as isize - quiet as isize);
        let dark = mx >= 0 && my >= 0 && (mx as usize) < n && (my as usize) < n
            && colors[my as usize * n + mx as usize] == qrcode::Color::Dark;
        image::Luma([if dark { 0 } else { 255 }])
    });
    let mut out = std::io::Cursor::new(Vec::new());
    if img.write_to(&mut out, image::ImageFormat::Png).is_err() {
        return String::new();
    }
    crate::img::ART.url("image/png", out.into_inner())
}

/// Nom de fichier sans chemin ni caracteres interdits par Windows.
pub fn safe_name(n: &str) -> String {
    let n: String = n
        .rsplit(['/', '\\'])
        .next()
        .unwrap_or_default()
        .chars()
        .map(|c| if "<>:\"|?*".contains(c) || c.is_control() { '_' } else { c })
        .collect();
    let n = n.trim().trim_matches('.').to_string();
    if n.is_empty() { "fichier".into() } else { n }
}

pub fn downloads_dir() -> PathBuf {
    let home = std::env::var("USERPROFILE").unwrap_or_else(|_| ".".into());
    let d = Path::new(&home).join("Downloads");
    let _ = std::fs::create_dir_all(&d);
    d
}

/// « photo.jpg » -> « photo (2).jpg » si le nom est deja pris.
pub fn free_path(dir: &Path, name: &str) -> PathBuf {
    let p = dir.join(name);
    if !p.exists() {
        return p;
    }
    let (stem, ext) = match name.rfind('.') {
        Some(i) if i > 0 => (&name[..i], &name[i..]),
        _ => (name, ""),
    };
    (2..1000).map(|k| dir.join(format!("{stem} ({k}){ext}"))).find(|p| !p.exists()).unwrap_or(p)
}
