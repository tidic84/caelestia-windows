//! Connexion Quick Share : trames prefixees de leur longueur sur TCP, echange
//! de cles UKEY2 (P-256, SHA-512), puis messages chiffres « SecureMessage »
//! (AES-256-CBC + HMAC-SHA256) qui transportent les trames de Nearby
//! Connections et, dedans, les charges utiles (octets ou fichiers).

use std::collections::{HashMap, HashSet};
use std::io::{Read, Write};
use std::net::TcpStream;
use std::sync::mpsc::{Receiver, RecvTimeoutError, Sender};
use std::time::{Duration, Instant};

use aes::cipher::{block_padding::Pkcs7, BlockDecryptMut, BlockEncryptMut, KeyIvInit};
use hkdf::Hkdf;
use hmac::{Hmac, Mac};
use p256::ecdh::EphemeralSecret;
use p256::elliptic_curve::sec1::ToEncodedPoint;
use p256::PublicKey;
use prost::Message;
use rand::RngCore;
use sha2::{Digest, Sha256, Sha512};

use super::proto::{self, offline, sharing, OfflineFrame, SharingFrame, V1Frame};

/// au-dela, une trame est refusee (les fichiers arrivent par morceaux de 512 Ko)
const MAX_FRAME: usize = 5 * 1024 * 1024;
/// Android coupe la connexion s'il ne recoit rien pendant un moment
const KEEP_ALIVE: Duration = Duration::from_secs(10);

pub fn random<const N: usize>() -> [u8; N] {
    let mut b = [0u8; N];
    rand::rngs::OsRng.fill_bytes(&mut b);
    b
}

pub fn hkdf(ikm: &[u8], salt: &[u8], info: &[u8], len: usize) -> Vec<u8> {
    let mut out = vec![0u8; len];
    let _ = Hkdf::<Sha256>::new(Some(salt), ikm).expand(info, &mut out);
    out
}

fn hmac(key: &[u8], data: &[u8]) -> Vec<u8> {
    let mut m = Hmac::<Sha256>::new_from_slice(key).expect("cle HMAC");
    m.update(data);
    m.finalize().into_bytes().to_vec()
}

/// Ce qui arrive au fil de la connexion : trames lues par un thread a part,
/// et ordres de l'interface (accepter, refuser, annuler).
pub enum Ev {
    Frame(Vec<u8>),
    Closed,
    Cmd(Cmd),
}

#[derive(Clone, Copy, PartialEq, Debug)]
pub enum Cmd {
    Accept,
    Reject,
    Cancel,
}

/// Ce que `Conn::recv` rend une fois le chiffrement en place.
pub enum In {
    Sharing(SharingFrame),
    /// charge utile d'octets attendue (texte, lien, Wi-Fi)
    Bytes(i64, Vec<u8>),
    File { id: i64, offset: i64, body: Vec<u8>, last: bool },
    Cmd(Cmd),
    /// rien dans le delai
    Idle,
    /// l'autre appareil a coupe ou annule
    Closed,
}

struct Keys {
    enc: Vec<u8>,
    dec: Vec<u8>,
    send_mac: Vec<u8>,
    recv_mac: Vec<u8>,
}

pub struct Conn {
    w: TcpStream,
    rx: Receiver<Ev>,
    keys: Option<Keys>,
    send_seq: i32,
    recv_seq: i32,
    bufs: HashMap<i64, Vec<u8>>,
    /// identifiants des charges d'octets qui ne sont pas des trames de partage
    pub expected: HashSet<i64>,
    last_send: Instant,
    /// cle d'authentification UKEY2 (code PIN, signature du QR code)
    pub auth: Vec<u8>,
}

/// Lit une trame (longueur sur 4 octets, gros-boutiste).
fn read_frame(r: &mut TcpStream) -> std::io::Result<Vec<u8>> {
    let mut len = [0u8; 4];
    r.read_exact(&mut len)?;
    let len = u32::from_be_bytes(len) as usize;
    if len > MAX_FRAME {
        return Err(std::io::Error::other("trame trop grande"));
    }
    let mut buf = vec![0u8; len];
    r.read_exact(&mut buf)?;
    Ok(buf)
}

impl Conn {
    /// Lance la lecture en arriere-plan ; `tx` sert aussi a l'interface pour
    /// envoyer ses ordres a la connexion.
    pub fn new(stream: TcpStream, tx: Sender<Ev>, rx: Receiver<Ev>) -> std::io::Result<Self> {
        let _ = stream.set_nodelay(true);
        let mut r = stream.try_clone()?;
        std::thread::spawn(move || loop {
            match read_frame(&mut r) {
                Ok(f) => {
                    if tx.send(Ev::Frame(f)).is_err() {
                        break;
                    }
                }
                Err(_) => {
                    let _ = tx.send(Ev::Closed);
                    break;
                }
            }
        });
        Ok(Conn {
            w: stream,
            rx,
            keys: None,
            send_seq: 0,
            recv_seq: 0,
            bufs: HashMap::new(),
            expected: HashSet::new(),
            last_send: Instant::now(),
            auth: Vec::new(),
        })
    }

    pub fn send_raw(&mut self, data: &[u8]) -> Result<(), String> {
        let mut b = Vec::with_capacity(data.len() + 4);
        b.extend_from_slice(&(data.len() as u32).to_be_bytes());
        b.extend_from_slice(data);
        self.last_send = Instant::now();
        self.w.write_all(&b).map_err(|e| format!("Connexion perdue : {e}"))
    }

    /// Trame en clair, avant la fin de l'echange de cles.
    pub fn recv_raw(&mut self, timeout: Duration) -> Result<Vec<u8>, String> {
        let end = Instant::now() + timeout;
        loop {
            let left = end.saturating_duration_since(Instant::now());
            match self.rx.recv_timeout(left) {
                Ok(Ev::Frame(f)) => return Ok(f),
                Ok(Ev::Cmd(Cmd::Cancel)) => return Err("Annulé".into()),
                Ok(Ev::Cmd(_)) => {}
                Ok(Ev::Closed) | Err(RecvTimeoutError::Disconnected) => return Err("L'appareil a coupé la connexion".into()),
                Err(RecvTimeoutError::Timeout) => return Err("L'appareil ne répond pas".into()),
            }
        }
    }

    pub fn send_offline(&mut self, f: &OfflineFrame) -> Result<(), String> {
        let Some(k) = &self.keys else { return self.send_raw(&f.encode_to_vec()) };
        self.send_seq += 1;
        let d2d = proto::DeviceToDeviceMessage { message: Some(f.encode_to_vec()), sequence_number: Some(self.send_seq) };
        let iv: [u8; 16] = random();
        let body = cbc::Encryptor::<aes::Aes256>::new(k.enc.as_slice().into(), (&iv).into())
            .encrypt_padded_vec_mut::<Pkcs7>(&d2d.encode_to_vec());
        let meta = proto::GcmMetadata { r#type: proto::DEVICE_TO_DEVICE_MESSAGE, version: Some(1) };
        let hb = proto::HeaderAndBody {
            header: proto::Header {
                signature_scheme: proto::HMAC_SHA256,
                encryption_scheme: proto::AES_256_CBC,
                iv: Some(iv.to_vec()),
                public_metadata: Some(meta.encode_to_vec()),
            },
            body,
        }
        .encode_to_vec();
        let signature = hmac(&k.send_mac, &hb);
        let msg = proto::SecureMessage { header_and_body: hb, signature };
        self.send_raw(&msg.encode_to_vec())
    }

    fn decrypt(&mut self, data: &[u8]) -> Result<OfflineFrame, String> {
        let k = self.keys.as_ref().ok_or("pas de cle")?;
        let msg = proto::SecureMessage::decode(data).map_err(|e| e.to_string())?;
        let mut m = Hmac::<Sha256>::new_from_slice(&k.recv_mac).expect("cle HMAC");
        m.update(&msg.header_and_body);
        m.verify_slice(&msg.signature).map_err(|_| "signature invalide")?;
        let hb = proto::HeaderAndBody::decode(msg.header_and_body.as_slice()).map_err(|e| e.to_string())?;
        let iv = hb.header.iv.unwrap_or_default();
        if iv.len() != 16 {
            return Err("IV invalide".into());
        }
        let plain = cbc::Decryptor::<aes::Aes256>::new(k.dec.as_slice().into(), iv.as_slice().into())
            .decrypt_padded_vec_mut::<Pkcs7>(&hb.body)
            .map_err(|_| "dechiffrement impossible")?;
        let d2d = proto::DeviceToDeviceMessage::decode(plain.as_slice()).map_err(|e| e.to_string())?;
        self.recv_seq += 1;
        if d2d.sequence_number != Some(self.recv_seq) {
            return Err("numero de sequence inattendu".into());
        }
        OfflineFrame::decode(d2d.message.unwrap_or_default().as_slice()).map_err(|e| e.to_string())
    }

    /// Prochain evenement utile (trame de partage, morceau de fichier, ordre
    /// de l'interface) ; repond aux « keep-alive » et en envoie au besoin.
    pub fn recv(&mut self, timeout: Duration) -> Result<In, String> {
        let end = Instant::now() + timeout;
        loop {
            if self.last_send.elapsed() >= KEEP_ALIVE {
                self.keep_alive(false)?;
            }
            let left = end.saturating_duration_since(Instant::now()).min(Duration::from_secs(1));
            let ev = match self.rx.recv_timeout(left) {
                Ok(ev) => ev,
                Err(RecvTimeoutError::Timeout) if Instant::now() >= end => return Ok(In::Idle),
                Err(RecvTimeoutError::Timeout) => continue,
                Err(RecvTimeoutError::Disconnected) => return Ok(In::Closed),
            };
            let data = match ev {
                Ev::Frame(f) => f,
                Ev::Closed => return Ok(In::Closed),
                Ev::Cmd(c) => return Ok(In::Cmd(c)),
            };
            let f = self.decrypt(&data)?;
            let Some(v1) = f.v1 else { continue };
            match v1.r#type.unwrap_or(0) {
                offline::KEEP_ALIVE => {
                    if !v1.keep_alive.and_then(|k| k.ack).unwrap_or(false) {
                        self.keep_alive(true)?;
                    }
                }
                offline::DISCONNECTION => return Ok(In::Closed),
                offline::PAYLOAD_TRANSFER => {
                    let Some(pt) = v1.payload_transfer else { continue };
                    if pt.packet_type == Some(offline::PACKET_CONTROL) {
                        if pt.control_message.and_then(|c| c.event) == Some(offline::PAYLOAD_CANCELED) {
                            return Ok(In::Closed);
                        }
                        continue;
                    }
                    let (Some(h), Some(c)) = (pt.payload_header, pt.payload_chunk) else { continue };
                    let id = h.id.unwrap_or(0);
                    let last = c.flags.unwrap_or(0) & offline::LAST_CHUNK != 0;
                    let offset = c.offset.unwrap_or(0);
                    let body = c.body.unwrap_or_default();
                    if h.r#type == Some(offline::PAYLOAD_FILE) {
                        return Ok(In::File { id, offset, body, last });
                    }
                    let buf = self.bufs.entry(id).or_default();
                    if offset as usize != buf.len() || buf.len() + body.len() > MAX_FRAME {
                        self.bufs.remove(&id);
                        return Err("charge utile incoherente".into());
                    }
                    buf.extend_from_slice(&body);
                    if last {
                        let data = self.bufs.remove(&id).unwrap_or_default();
                        if self.expected.contains(&id) {
                            return Ok(In::Bytes(id, data));
                        }
                        if let Ok(sf) = SharingFrame::decode(data.as_slice()) {
                            return Ok(In::Sharing(sf));
                        }
                    }
                }
                _ => {}
            }
        }
    }

    pub fn keep_alive(&mut self, ack: bool) -> Result<(), String> {
        self.send_offline(&OfflineFrame::v1(V1Frame {
            r#type: Some(offline::KEEP_ALIVE),
            keep_alive: Some(proto::KeepAliveFrame { ack: Some(ack) }),
            ..Default::default()
        }))
    }

    /// Envoie une charge d'octets (comme Android : le tout, puis un morceau
    /// vide marque « dernier »).
    pub fn send_bytes(&mut self, id: i64, data: Vec<u8>) -> Result<(), String> {
        let total = data.len() as i64;
        let header = proto::PayloadHeader { id: Some(id), r#type: Some(offline::PAYLOAD_BYTES), total_size: Some(total), is_sensitive: Some(false) };
        for (flags, offset, body) in [(0, 0, Some(data)), (offline::LAST_CHUNK, total, None)] {
            self.send_offline(&payload_frame(header.clone(), proto::PayloadChunk { flags: Some(flags), offset: Some(offset), body }))?;
        }
        Ok(())
    }

    pub fn send_file_chunk(&mut self, id: i64, total: i64, offset: i64, body: Vec<u8>, last: bool) -> Result<(), String> {
        let header = proto::PayloadHeader { id: Some(id), r#type: Some(offline::PAYLOAD_FILE), total_size: Some(total), is_sensitive: Some(false) };
        let flags = if last { offline::LAST_CHUNK } else { 0 };
        self.send_offline(&payload_frame(header, proto::PayloadChunk { flags: Some(flags), offset: Some(offset), body: Some(body) }))
    }

    pub fn send_sharing(&mut self, f: proto::SharingV1Frame) -> Result<(), String> {
        let id = i64::from_le_bytes(random());
        self.send_bytes(id, SharingFrame::v1(f).encode_to_vec())
    }

    /// Trame « clé appairée » : sans compte Google, des octets au hasard
    /// suffisent (le QR code, lui, signe la cle d'authentification).
    pub fn send_paired_key_encryption(&mut self, qr_signature: Option<Vec<u8>>) -> Result<(), String> {
        self.send_sharing(proto::SharingV1Frame {
            r#type: Some(sharing::PAIRED_KEY_ENCRYPTION),
            paired_key_encryption: Some(proto::PairedKeyEncryptionFrame {
                signed_data: Some(random::<72>().to_vec()),
                secret_id_hash: Some(random::<6>().to_vec()),
                qr_code_handshake_data: qr_signature,
            }),
            ..Default::default()
        })
    }

    pub fn send_paired_key_result(&mut self) -> Result<(), String> {
        self.send_sharing(proto::SharingV1Frame {
            r#type: Some(sharing::PAIRED_KEY_RESULT),
            paired_key_result: Some(proto::PairedKeyResultFrame { status: Some(sharing::UNABLE) }),
            ..Default::default()
        })
    }

    pub fn send_response(&mut self, status: i32) -> Result<(), String> {
        self.send_sharing(proto::SharingV1Frame {
            r#type: Some(sharing::RESPONSE),
            connection_response: Some(proto::SharingResponseFrame { status: Some(status) }),
            ..Default::default()
        })
    }

    pub fn send_cancel(&mut self) -> Result<(), String> {
        self.send_sharing(proto::SharingV1Frame { r#type: Some(sharing::CANCEL), ..Default::default() })
    }

    /// Derniere trame en clair, juste apres l'echange de cles.
    pub fn send_connection_response(&mut self) -> Result<(), String> {
        let f = OfflineFrame::v1(V1Frame {
            r#type: Some(offline::CONNECTION_RESPONSE),
            connection_response: Some(proto::ConnectionResponseFrame {
                status: Some(0),
                response: Some(offline::ACCEPT),
                os_info: Some(proto::OsInfo { r#type: Some(offline::OS_WINDOWS) }),
            }),
            ..Default::default()
        });
        self.send_raw(&f.encode_to_vec())
    }

    /// Fin propre : trame de deconnexion, puis fermeture.
    pub fn disconnect(&mut self) {
        let _ = self.send_offline(&OfflineFrame::v1(V1Frame {
            r#type: Some(offline::DISCONNECTION),
            disconnection: Some(proto::DisconnectionFrame { request_safe_to_disconnect: None }),
            ..Default::default()
        }));
        // laisse le temps a la trame de partir avant de couper
        std::thread::sleep(Duration::from_millis(300));
        let _ = self.w.shutdown(std::net::Shutdown::Both);
    }

    /// Ordre de l'interface en attente, sans bloquer (pendant un envoi).
    pub fn poll(&mut self) -> Result<Option<In>, String> {
        match self.recv(Duration::ZERO)? {
            In::Idle => Ok(None),
            x => Ok(Some(x)),
        }
    }

    // ---------------------------------------------------------- UKEY2

    pub fn ukey_alert(&mut self, kind: i32) {
        let alert = proto::Ukey2Alert { r#type: Some(kind), error_message: None };
        let msg = proto::Ukey2Message { message_type: Some(proto::ukey::ALERT), message_data: Some(alert.encode_to_vec()) };
        let _ = self.send_raw(&msg.encode_to_vec());
    }

    /// Termine l'echange : secret ECDH, cles d'authentification et de session
    /// (HKDF), comme le fait Chromium (d2d_crypto_ops, crypto_ops).
    pub fn finish_ukey(
        &mut self,
        secret: &EphemeralSecret,
        peer_key: &[u8],
        client_init: &[u8],
        server_init: &[u8],
        server: bool,
    ) -> Result<(), String> {
        let peer = parse_public_key(peer_key)?;
        let shared = secret.diffie_hellman(&peer);
        let dhs = Sha256::digest(shared.raw_secret_bytes());
        let info = [client_init, server_init].concat();
        let auth = hkdf(&dhs, b"UKEY2 v1 auth", &info, 32);
        let next = hkdf(&dhs, b"UKEY2 v1 next", &info, 32);
        let d2d_salt = Sha256::digest(b"D2D");
        let client = hkdf(&next, &d2d_salt, b"client", 32);
        let srv = hkdf(&next, &d2d_salt, b"server", 32);
        let salt = Sha256::digest(b"SecureMessage");
        let (c_enc, c_mac) = (hkdf(&client, &salt, b"ENC:2", 32), hkdf(&client, &salt, b"SIG:1", 32));
        let (s_enc, s_mac) = (hkdf(&srv, &salt, b"ENC:2", 32), hkdf(&srv, &salt, b"SIG:1", 32));
        self.keys = Some(if server {
            Keys { enc: s_enc, send_mac: s_mac, dec: c_enc, recv_mac: c_mac }
        } else {
            Keys { enc: c_enc, send_mac: c_mac, dec: s_enc, recv_mac: s_mac }
        });
        self.auth = auth;
        Ok(())
    }
}

fn payload_frame(header: proto::PayloadHeader, chunk: proto::PayloadChunk) -> OfflineFrame {
    OfflineFrame::v1(V1Frame {
        r#type: Some(offline::PAYLOAD_TRANSFER),
        payload_transfer: Some(proto::PayloadTransferFrame {
            packet_type: Some(offline::PACKET_DATA),
            payload_header: Some(header),
            payload_chunk: Some(chunk),
            control_message: None,
        }),
        ..Default::default()
    })
}

/// Nouvelle paire de cles P-256 et sa cle publique serialisee
/// (GenericPublicKey). Les coordonnees sont des entiers signes a la Java :
/// un octet nul devant si le bit de poids fort est a 1.
pub fn new_key() -> (EphemeralSecret, Vec<u8>) {
    let secret = EphemeralSecret::random(&mut rand::rngs::OsRng);
    let point = secret.public_key().to_encoded_point(false);
    let signed = |v: &[u8]| if v[0] & 0x80 != 0 { [&[0u8][..], v].concat() } else { v.to_vec() };
    let key = proto::GenericPublicKey {
        r#type: proto::EC_P256,
        ec_p256_public_key: Some(proto::EcP256PublicKey {
            x: signed(point.x().map(|x| x.as_slice()).unwrap_or_default()),
            y: signed(point.y().map(|y| y.as_slice()).unwrap_or_default()),
        }),
    };
    (secret, key.encode_to_vec())
}

fn parse_public_key(data: &[u8]) -> Result<PublicKey, String> {
    let k = proto::GenericPublicKey::decode(data).map_err(|e| e.to_string())?;
    let ec = k.ec_p256_public_key.ok_or("cle publique absente")?;
    let fit = |v: &[u8]| -> Result<[u8; 32], String> {
        // enleve le zero de tete ou complete a gauche
        let v = if v.len() > 32 { &v[v.len() - 32..] } else { v };
        let mut out = [0u8; 32];
        out[32 - v.len()..].copy_from_slice(v);
        Ok(out)
    };
    let mut sec1 = vec![4u8];
    sec1.extend_from_slice(&fit(&ec.x)?);
    sec1.extend_from_slice(&fit(&ec.y)?);
    PublicKey::from_sec1_bytes(&sec1).map_err(|_| "cle publique invalide".to_string())
}

pub fn sha512(data: &[u8]) -> Vec<u8> {
    Sha512::digest(data).to_vec()
}

/// Code a 4 chiffres affiche des deux cotes (algorithme de Chromium,
/// nearby_sharing_service_impl.cc).
pub fn pin_code(auth: &[u8]) -> String {
    let (mut hash, mut mult) = (0i64, 1i64);
    for &b in auth {
        hash = (hash + (b as i8) as i64 * mult) % 9973;
        mult = (mult * 31) % 9973;
    }
    format!("{:04}", hash.abs())
}
