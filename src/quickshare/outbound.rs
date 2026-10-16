//! Envoi : l'ilot se connecte a l'appareil trouve par mDNS, presente les
//! fichiers (ou le texte), attend que la personne accepte sur son telephone,
//! puis envoie par morceaux de 512 Ko.

use std::fs::File;
use std::io::Read;
use std::net::{SocketAddr, TcpStream};
use std::path::PathBuf;
use std::sync::mpsc;
use std::time::{Duration, Instant};

use p256::ecdsa::{signature::Signer, Signature, SigningKey};
use prost::Message;

use super::conn::{self, Cmd, Conn, In};
use super::proto::{self, offline, sharing, OfflineFrame, V1Frame};
use super::Qs;

const CHUNK: usize = 512 * 1024;

pub enum Out {
    File { path: PathBuf, name: String, size: i64, payload: i64 },
    Text { text: String, url: bool, payload: i64 },
}

/// Type et type MIME d'apres l'extension (pour l'apercu cote Android).
fn mime_of(name: &str) -> (i32, &'static str) {
    let ext = name.rsplit('.').next().unwrap_or_default().to_ascii_lowercase();
    match ext.as_str() {
        "jpg" | "jpeg" => (sharing::FILE_IMAGE, "image/jpeg"),
        "png" => (sharing::FILE_IMAGE, "image/png"),
        "gif" => (sharing::FILE_IMAGE, "image/gif"),
        "webp" => (sharing::FILE_IMAGE, "image/webp"),
        "heic" => (sharing::FILE_IMAGE, "image/heic"),
        "bmp" => (sharing::FILE_IMAGE, "image/bmp"),
        "mp4" | "m4v" => (sharing::FILE_VIDEO, "video/mp4"),
        "mkv" => (sharing::FILE_VIDEO, "video/x-matroska"),
        "mov" => (sharing::FILE_VIDEO, "video/quicktime"),
        "webm" => (sharing::FILE_VIDEO, "video/webm"),
        "avi" => (sharing::FILE_VIDEO, "video/x-msvideo"),
        "mp3" => (sharing::FILE_AUDIO, "audio/mpeg"),
        "m4a" | "aac" => (sharing::FILE_AUDIO, "audio/mp4"),
        "ogg" | "opus" => (sharing::FILE_AUDIO, "audio/ogg"),
        "flac" => (sharing::FILE_AUDIO, "audio/flac"),
        "wav" => (sharing::FILE_AUDIO, "audio/wav"),
        "apk" => (sharing::FILE_APP, "application/vnd.android.package-archive"),
        "pdf" => (sharing::FILE_DOCUMENT, "application/pdf"),
        "txt" => (sharing::FILE_DOCUMENT, "text/plain"),
        "doc" | "docx" => (sharing::FILE_DOCUMENT, "application/msword"),
        "xls" | "xlsx" => (sharing::FILE_DOCUMENT, "application/vnd.ms-excel"),
        "ppt" | "pptx" => (sharing::FILE_DOCUMENT, "application/vnd.ms-powerpoint"),
        "zip" => (sharing::FILE_UNKNOWN, "application/zip"),
        _ => (sharing::FILE_UNKNOWN, "application/octet-stream"),
    }
}

pub fn send(q: Qs, id: u64, addr: SocketAddr, items: Vec<Out>, qr: Option<SigningKey>, rx: mpsc::Receiver<conn::Ev>, tx: mpsc::Sender<conn::Ev>) {
    let r = TcpStream::connect_timeout(&addr, Duration::from_secs(6))
        .map_err(|e| format!("Connexion impossible : {e}"))
        .and_then(|s| Conn::new(s, tx, rx).map_err(|e| e.to_string()))
        .and_then(|mut c| run(&mut c, &q, id, items, qr));
    q.forget(id);
    if let Err(e) = r {
        q.update(id, |t| {
            if !t.finished() {
                t.status = "failed";
                t.error = e;
            }
        });
    }
}

fn run(c: &mut Conn, q: &Qs, id: u64, items: Vec<Out>, qr: Option<SigningKey>) -> Result<(), String> {
    let short = Duration::from_secs(15);
    let (eid, name, info) = q.identity();
    // 1. demande de connexion
    let req = OfflineFrame::v1(V1Frame {
        r#type: Some(offline::CONNECTION_REQUEST),
        connection_request: Some(proto::ConnectionRequestFrame {
            endpoint_id: Some(eid),
            endpoint_name: Some(name),
            mediums: vec![offline::MEDIUM_WIFI_LAN],
            endpoint_info: Some(info),
        }),
        ..Default::default()
    });
    c.send_raw(&req.encode_to_vec())?;

    // 2. UKEY2 : la cle de ClientFinish est engagee des ClientInit
    let (secret, pubkey) = conn::new_key();
    let cf = proto::Ukey2ClientFinished { public_key: Some(pubkey) };
    let cf_raw = proto::Ukey2Message { message_type: Some(proto::ukey::CLIENT_FINISH), message_data: Some(cf.encode_to_vec()) }.encode_to_vec();
    let ci = proto::Ukey2ClientInit {
        version: Some(1),
        random: Some(conn::random::<32>().to_vec()),
        cipher_commitments: vec![proto::CipherCommitment { handshake_cipher: Some(proto::ukey::P256_SHA512), commitment: Some(conn::sha512(&cf_raw)) }],
        next_protocol: Some(proto::ukey::NEXT_PROTOCOL.into()),
    };
    let ci_raw = proto::Ukey2Message { message_type: Some(proto::ukey::CLIENT_INIT), message_data: Some(ci.encode_to_vec()) }.encode_to_vec();
    c.send_raw(&ci_raw)?;
    let si_raw = c.recv_raw(short)?;
    let msg = proto::Ukey2Message::decode(si_raw.as_slice()).map_err(|e| e.to_string())?;
    if msg.message_type != Some(proto::ukey::SERVER_INIT) {
        c.ukey_alert(proto::ukey::BAD_MESSAGE_TYPE);
        return Err("L'appareil a refusé la connexion".into());
    }
    let si = proto::Ukey2ServerInit::decode(msg.message_data.unwrap_or_default().as_slice()).map_err(|e| e.to_string())?;
    if si.version != Some(1) || si.handshake_cipher != Some(proto::ukey::P256_SHA512) {
        c.ukey_alert(proto::ukey::BAD_HANDSHAKE_CIPHER);
        return Err("UKEY2 : chiffrement non pris en charge".into());
    }
    c.finish_ukey(&secret, &si.public_key.unwrap_or_default(), &ci_raw, &si_raw, false)?;
    c.send_raw(&cf_raw)?;
    c.send_connection_response()?;
    let f = OfflineFrame::decode(c.recv_raw(short)?.as_slice()).map_err(|e| e.to_string())?;
    let accepted = f.v1.and_then(|v| v.connection_response).and_then(|r| r.response) == Some(offline::ACCEPT);
    if !accepted {
        return Err("L'appareil a refusé la connexion".into());
    }
    let pin = conn::pin_code(&c.auth);
    q.update(id, |t| t.pin = pin);

    // 3. cles appairees ; avec le QR code, la signature evite la question
    let sig = qr.map(|k| {
        let s: Signature = k.sign(&c.auth);
        s.to_bytes().to_vec()
    });
    c.send_paired_key_encryption(sig)?;
    let (mut sent_result, mut got_result) = (false, false);
    while !(sent_result && got_result) {
        match c.recv(Duration::from_secs(30))? {
            In::Sharing(sf) => match sf.kind() {
                sharing::PAIRED_KEY_ENCRYPTION if !sent_result => {
                    c.send_paired_key_result()?;
                    sent_result = true;
                }
                sharing::PAIRED_KEY_RESULT => got_result = true,
                sharing::CANCEL => return closed(c, q, id),
                _ => {}
            },
            In::Cmd(Cmd::Cancel) => return cancel(c, q, id),
            In::Closed | In::Idle => return Err("L'appareil ne répond plus".into()),
            _ => {}
        }
    }

    // 4. presentation, puis attente de la reponse
    let mut intro = proto::IntroductionFrame::default();
    for it in &items {
        match it {
            Out::File { name, size, payload, .. } => {
                let (kind, mime) = mime_of(name);
                intro.file_metadata.push(proto::FileMetadata {
                    name: Some(name.clone()),
                    r#type: Some(kind),
                    payload_id: Some(*payload),
                    size: Some(*size),
                    mime_type: Some(mime.into()),
                    id: Some(i64::from_le_bytes(conn::random())),
                });
            }
            Out::Text { text, url, payload } => intro.text_metadata.push(proto::TextMetadata {
                text_title: Some(text.chars().take(40).collect()),
                r#type: Some(if *url { sharing::URL } else { sharing::TEXT }),
                payload_id: Some(*payload),
                size: Some(text.len() as i64),
                id: Some(i64::from_le_bytes(conn::random())),
            }),
        }
    }
    c.send_sharing(proto::SharingV1Frame { r#type: Some(sharing::INTRODUCTION), introduction: Some(intro), ..Default::default() })?;
    q.update(id, |t| t.status = "waiting");
    let asked = Instant::now();
    let status = loop {
        match c.recv(Duration::from_secs(1))? {
            In::Sharing(sf) if sf.kind() == sharing::RESPONSE => {
                break sf.v1.and_then(|v| v.connection_response).and_then(|r| r.status).unwrap_or(0);
            }
            In::Sharing(sf) if sf.kind() == sharing::CANCEL => return closed(c, q, id),
            In::Cmd(Cmd::Cancel) => return cancel(c, q, id),
            In::Closed => return closed(c, q, id),
            _ if asked.elapsed() > Duration::from_secs(150) => {
                c.disconnect();
                return Err("Pas de réponse sur l'appareil".into());
            }
            _ => {}
        }
    };
    if status != sharing::ACCEPT {
        c.disconnect();
        q.update(id, |t| {
            t.status = "rejected";
            t.error = match status {
                sharing::NOT_ENOUGH_SPACE => "Plus assez de place sur l'appareil",
                sharing::UNSUPPORTED_ATTACHMENT_TYPE => "Type non pris en charge par l'appareil",
                sharing::TIMED_OUT => "Délai dépassé",
                _ => "Refusé",
            }
            .into();
        });
        return Ok(());
    }

    // 5. envoi
    q.update(id, |t| t.status = "transfer");
    let mut done: u64 = 0;
    let mut buf = vec![0u8; CHUNK];
    for it in items {
        match it {
            Out::Text { text, payload, .. } => c.send_bytes(payload, text.into_bytes())?,
            Out::File { path, size, payload, .. } => {
                let mut f = File::open(&path).map_err(|e| format!("Lecture impossible : {e}"))?;
                let mut off: i64 = 0;
                while off < size {
                    let n = f.read(&mut buf).map_err(|e| format!("Lecture impossible : {e}"))?;
                    if n == 0 {
                        break;
                    }
                    let n = n.min((size - off) as usize);
                    c.send_file_chunk(payload, size, off, buf[..n].to_vec(), false)?;
                    off += n as i64;
                    done += n as u64;
                    q.progress(id, done);
                    match c.poll()? {
                        Some(In::Cmd(Cmd::Cancel)) => return cancel(c, q, id),
                        Some(In::Closed) => return closed(c, q, id),
                        Some(In::Sharing(sf)) if sf.kind() == sharing::CANCEL => return closed(c, q, id),
                        _ => {}
                    }
                }
                c.send_file_chunk(payload, size, off, Vec::new(), true)?;
            }
        }
    }
    q.progress(id, done);
    // l'appareil coupe quand il a tout recu
    let end = Instant::now() + Duration::from_secs(20);
    while Instant::now() < end {
        if let In::Closed = c.recv(Duration::from_secs(1))? {
            break;
        }
    }
    q.update(id, |t| {
        t.done = t.total;
        t.status = "done";
    });
    c.disconnect();
    Ok(())
}

fn cancel(c: &mut Conn, q: &Qs, id: u64) -> Result<(), String> {
    c.send_cancel().ok();
    c.disconnect();
    q.update(id, |t| t.status = "cancelled");
    Ok(())
}

fn closed(c: &mut Conn, q: &Qs, id: u64) -> Result<(), String> {
    c.disconnect();
    q.update(id, |t| {
        t.status = "cancelled";
        t.error = "Annulé sur l'appareil".into();
    });
    Ok(())
}

/// Prepare l'envoi : fichiers existants et texte (lien si ca en a l'air).
pub fn items_of(paths: &[String], text: Option<String>) -> Vec<Out> {
    let mut v: Vec<Out> = paths
        .iter()
        .map(PathBuf::from)
        .filter_map(|p| {
            let size = std::fs::metadata(&p).ok().filter(|m| m.is_file())?.len() as i64;
            let name = super::safe_name(&p.file_name()?.to_string_lossy());
            Some(Out::File { path: p, name, size, payload: i64::from_le_bytes(conn::random()) })
        })
        .collect();
    if let Some(t) = text.map(|t| t.trim().to_string()).filter(|t| !t.is_empty()) {
        let url = (t.starts_with("https://") || t.starts_with("http://")) && !t.contains(char::is_whitespace);
        v.push(Out::Text { text: t, url, payload: i64::from_le_bytes(conn::random()) });
    }
    v
}

pub fn to_items(items: &[Out]) -> Vec<super::Item> {
    items
        .iter()
        .map(|it| match it {
            Out::File { path, name, size, .. } => super::Item::file(name, *size as u64, &path.to_string_lossy()),
            Out::Text { text, url, .. } => super::Item {
                name: text.chars().take(60).collect(),
                size: text.len() as u64,
                kind: if *url { "url" } else { "text" },
                path: String::new(),
            },
        })
        .collect()
}

