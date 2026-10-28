//! Reception : un telephone (ou un PC) se connecte au port annonce par mDNS,
//! presente ce qu'il veut envoyer ; l'ilot demande a l'utilisateur, puis
//! range les fichiers dans Telechargements.

use std::collections::HashMap;
use std::fs::File;
use std::io::Write;
use std::net::TcpStream;
use std::path::PathBuf;
use std::sync::mpsc;
use std::time::{Duration, Instant};

use prost::Message;

use super::conn::{self, Cmd, Conn, In};
use super::proto::{self, offline, sharing, OfflineFrame};
use super::{Item, Qs, Transfer};

/// Nom et type d'appareil dans l'« endpoint info » (voir PROTOCOL.md de
/// NearDrop) ; le nom manque si l'appareil est masque.
pub fn parse_endpoint_info(info: &[u8]) -> Option<(Option<String>, u8, Vec<(u8, Vec<u8>)>)> {
    if info.len() < 17 {
        return None;
    }
    let kind = (info[0] >> 1) & 7;
    let visible = info[0] & 0x10 == 0;
    let mut off = 17;
    let name = if visible {
        // certains telephones (2026) se disent visibles sans envoyer de nom :
        // nom vide, l'appelant prend un nom de repli
        match info.get(17) {
            None => Some(String::new()),
            Some(&n) => {
                let n = n as usize;
                let s = String::from_utf8_lossy(info.get(18..18 + n)?).to_string();
                off = 18 + n;
                Some(s)
            }
        }
    } else {
        None
    };
    // enregistrements TLV (donnees du QR code, fabricant)
    let mut tlv = Vec::new();
    while off + 2 <= info.len() {
        let (t, l) = (info[off], info[off + 1] as usize);
        off += 2;
        let Some(v) = info.get(off..off + l) else { break };
        tlv.push((t, v.to_vec()));
        off += l;
    }
    Some((name, kind, tlv))
}

pub fn handle(stream: TcpStream, q: Qs) {
    let (tx, rx) = mpsc::channel();
    let Ok(mut c) = Conn::new(stream, tx.clone(), rx) else { return };
    let mut id = 0;
    let r = run(&mut c, &q, &mut id, tx);
    if id == 0 {
        return;
    }
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

struct Incoming {
    file: Option<File>,
    name: String,
    path: PathBuf,
    size: i64,
    got: i64,
    idx: usize,
}

fn run(c: &mut Conn, q: &Qs, id: &mut u64, tx: mpsc::Sender<conn::Ev>) -> Result<(), String> {
    let short = Duration::from_secs(15);
    // 1. demande de connexion : qui est-ce ?
    let f = OfflineFrame::decode(c.recv_raw(short)?.as_slice()).map_err(|e| e.to_string())?;
    let req = f.v1.and_then(|v| v.connection_request).ok_or("demande de connexion attendue")?;
    let (name, kind, _) = parse_endpoint_info(&req.endpoint_info.unwrap_or_default()).ok_or("appareil inconnu")?;
    let peer = name.filter(|s| !s.is_empty()).or(req.endpoint_name).unwrap_or_else(|| "Appareil inconnu".into());

    // 2. UKEY2 : ClientInit -> ServerInit -> ClientFinish
    let ci_raw = c.recv_raw(short)?;
    let msg = proto::Ukey2Message::decode(ci_raw.as_slice()).map_err(|e| e.to_string())?;
    if msg.message_type != Some(proto::ukey::CLIENT_INIT) {
        c.ukey_alert(proto::ukey::BAD_MESSAGE_TYPE);
        return Err("UKEY2 : ClientInit attendu".into());
    }
    let Ok(ci) = proto::Ukey2ClientInit::decode(msg.message_data.unwrap_or_default().as_slice()) else {
        c.ukey_alert(proto::ukey::BAD_MESSAGE_DATA);
        return Err("UKEY2 : ClientInit illisible".into());
    };
    if ci.version != Some(1) {
        c.ukey_alert(proto::ukey::BAD_VERSION);
        return Err("UKEY2 : version".into());
    }
    if ci.random.as_ref().map_or(0, |r| r.len()) != 32 {
        c.ukey_alert(proto::ukey::BAD_RANDOM);
        return Err("UKEY2 : alea".into());
    }
    let Some(commitment) = ci
        .cipher_commitments
        .iter()
        .find(|cc| cc.handshake_cipher == Some(proto::ukey::P256_SHA512))
        .and_then(|cc| cc.commitment.clone())
    else {
        c.ukey_alert(proto::ukey::BAD_HANDSHAKE_CIPHER);
        return Err("UKEY2 : chiffrement".into());
    };
    if ci.next_protocol.as_deref() != Some(proto::ukey::NEXT_PROTOCOL) {
        c.ukey_alert(proto::ukey::BAD_NEXT_PROTOCOL);
        return Err("UKEY2 : protocole".into());
    }
    let (secret, pubkey) = conn::new_key();
    let si = proto::Ukey2ServerInit {
        version: Some(1),
        random: Some(conn::random::<32>().to_vec()),
        handshake_cipher: Some(proto::ukey::P256_SHA512),
        public_key: Some(pubkey),
    };
    let si_raw = proto::Ukey2Message { message_type: Some(proto::ukey::SERVER_INIT), message_data: Some(si.encode_to_vec()) }.encode_to_vec();
    c.send_raw(&si_raw)?;
    let cf_raw = c.recv_raw(short)?;
    if conn::sha512(&cf_raw) != commitment {
        return Err("UKEY2 : engagement invalide".into());
    }
    let msg = proto::Ukey2Message::decode(cf_raw.as_slice()).map_err(|e| e.to_string())?;
    if msg.message_type != Some(proto::ukey::CLIENT_FINISH) {
        return Err("UKEY2 : ClientFinish attendu".into());
    }
    let cf = proto::Ukey2ClientFinished::decode(msg.message_data.unwrap_or_default().as_slice()).map_err(|e| e.to_string())?;
    c.finish_ukey(&secret, &cf.public_key.unwrap_or_default(), &ci_raw, &si_raw, true)?;

    // 3. reponses de connexion en clair, puis tout est chiffre
    let f = OfflineFrame::decode(c.recv_raw(short)?.as_slice()).map_err(|e| e.to_string())?;
    if f.kind() != offline::CONNECTION_RESPONSE {
        return Err("reponse de connexion attendue".into());
    }
    c.send_connection_response()?;
    c.send_paired_key_encryption(None)?;

    // 4. cles appairees, puis presentation de ce qui arrive
    let intro = loop {
        match c.recv(Duration::from_secs(30))? {
            In::Sharing(sf) => match sf.kind() {
                sharing::PAIRED_KEY_ENCRYPTION => c.send_paired_key_result()?,
                sharing::INTRODUCTION => break sf.v1.and_then(|v| v.introduction).unwrap_or_default(),
                sharing::CANCEL => {
                    c.disconnect();
                    return Ok(());
                }
                _ => {}
            },
            In::Idle | In::Closed | In::Cmd(_) => return Err("L'appareil a abandonné".into()),
            _ => {}
        }
    };

    let mut items = Vec::new();
    let mut files: HashMap<i64, Incoming> = HashMap::new();
    let mut texts: HashMap<i64, (i32, usize)> = HashMap::new();
    let mut wifi: HashMap<i64, usize> = HashMap::new();
    for m in &intro.file_metadata {
        let size = m.size.unwrap_or(0).max(0);
        let name = super::safe_name(m.name.as_deref().unwrap_or("fichier"));
        items.push(Item::file(&name, size as u64, ""));
        files.insert(m.payload_id.unwrap_or(0), Incoming { file: None, name, path: PathBuf::new(), size, got: 0, idx: items.len() - 1 });
    }
    for t in &intro.text_metadata {
        let kind = t.r#type.unwrap_or(sharing::TEXT);
        texts.insert(t.payload_id.unwrap_or(0), (kind, items.len()));
        let k = if kind == sharing::URL { "url" } else { "text" };
        items.push(Item { name: t.text_title.clone().unwrap_or_default(), size: t.size.unwrap_or(0).max(0) as u64, kind: k, path: String::new() });
    }
    for w in &intro.wifi_credentials_metadata {
        wifi.insert(w.payload_id.unwrap_or(0), items.len());
        items.push(Item { name: w.ssid.clone().unwrap_or_default(), size: 0, kind: "wifi", path: String::new() });
    }
    if items.is_empty() {
        c.send_response(sharing::UNSUPPORTED_ATTACHMENT_TYPE)?;
        c.disconnect();
        return Ok(());
    }
    let total: u64 = files.values().map(|f| f.size as u64).sum();
    *id = q.add(
        Transfer { out: false, peer, kind, status: "ask", pin: conn::pin_code(&c.auth), items, total, ..Default::default() },
        tx,
    );
    let id = *id;

    // 5. l'utilisateur accepte ou refuse (2 minutes, comme Android)
    let asked = Instant::now();
    loop {
        match c.recv(Duration::from_secs(1))? {
            In::Cmd(Cmd::Accept) => break,
            In::Cmd(_) => {
                c.send_response(sharing::REJECT)?;
                c.disconnect();
                q.update(id, |t| t.status = "rejected");
                return Ok(());
            }
            In::Sharing(sf) if sf.kind() == sharing::CANCEL => {
                q.update(id, |t| t.status = "cancelled");
                c.disconnect();
                return Ok(());
            }
            In::Closed => {
                q.update(id, |t| t.status = "cancelled");
                return Ok(());
            }
            _ if asked.elapsed() > Duration::from_secs(120) => {
                c.send_response(sharing::TIMED_OUT)?;
                c.disconnect();
                q.update(id, |t| {
                    t.status = "failed";
                    t.error = "Pas de réponse à temps".into();
                });
                return Ok(());
            }
            _ => {}
        }
    }

    // 6. reception
    let dir = super::downloads_dir();
    let mut paths = Vec::new();
    for f in files.values_mut() {
        f.path = super::free_path(&dir, &f.name);
        f.file = Some(File::create(&f.path).map_err(|e| format!("Écriture impossible : {e}"))?);
        paths.push((f.idx, f.path.to_string_lossy().to_string()));
    }
    q.update(id, |t| {
        for (i, p) in &paths {
            t.items[*i].path = p.clone();
        }
        t.status = "transfer";
    });
    c.expected.extend(texts.keys().chain(wifi.keys()).copied());
    c.send_response(sharing::ACCEPT)?;

    let cleanup = |files: &mut HashMap<i64, Incoming>| {
        for f in files.values_mut() {
            if f.file.take().is_some() || f.got < f.size {
                let _ = std::fs::remove_file(&f.path);
            }
        }
    };
    let mut done: u64 = 0;
    let mut left = files.len() + texts.len() + wifi.len();
    while left > 0 {
        let ev = match c.recv(Duration::from_secs(60)) {
            Ok(ev) => ev,
            Err(e) => {
                cleanup(&mut files);
                return Err(e);
            }
        };
        match ev {
            In::File { id: pid, offset, body, last } => {
                let Some(f) = files.get_mut(&pid) else { continue };
                if offset != f.got || f.got + body.len() as i64 > f.size {
                    cleanup(&mut files);
                    return Err("Données reçues incohérentes".into());
                }
                if let Some(file) = f.file.as_mut() {
                    if let Err(e) = file.write_all(&body) {
                        cleanup(&mut files);
                        c.send_cancel().ok();
                        c.disconnect();
                        return Err(format!("Écriture impossible : {e}"));
                    }
                }
                f.got += body.len() as i64;
                done += body.len() as u64;
                q.progress(id, done);
                if last && f.file.is_some() {
                    f.file.take();
                    left -= 1;
                }
            }
            In::Bytes(pid, data) => {
                if let Some(&(kind, idx)) = texts.get(&pid) {
                    let s = String::from_utf8_lossy(&data).to_string();
                    // texte : directement dans le presse-papiers
                    if kind != sharing::URL {
                        crate::system::clip_text(s.clone());
                    }
                    q.update(id, |t| {
                        t.text = s;
                        if t.items[idx].name.is_empty() {
                            t.items[idx].name = t.text.chars().take(60).collect();
                        }
                    });
                    left -= 1;
                } else if wifi.contains_key(&pid) {
                    let w = proto::WifiCredentials::decode(data.as_slice()).unwrap_or_default();
                    q.update(id, |t| t.text = w.password.unwrap_or_default());
                    left -= 1;
                }
            }
            In::Cmd(Cmd::Cancel) => {
                c.send_cancel().ok();
                c.disconnect();
                cleanup(&mut files);
                q.update(id, |t| t.status = "cancelled");
                return Ok(());
            }
            In::Sharing(sf) if sf.kind() == sharing::CANCEL => {
                cleanup(&mut files);
                q.update(id, |t| t.status = "cancelled");
                c.disconnect();
                return Ok(());
            }
            // certains envoyeurs ne marquent pas la fin d'un fichier vide et
            // coupent directement : complet si tout est arrive
            In::Closed if left == files.values().filter(|f| f.file.is_some()).count() && files.values().all(|f| f.got == f.size) => {
                for f in files.values_mut() {
                    f.file.take();
                }
                break;
            }
            In::Closed | In::Idle => {
                cleanup(&mut files);
                return Err("Transfert interrompu".into());
            }
            _ => {}
        }
    }
    q.progress(id, done);
    q.update(id, |t| {
        t.done = t.total;
        t.status = "done";
    });
    c.disconnect();
    Ok(())
}

#[cfg(test)]
mod tests {
    use super::parse_endpoint_info;

    #[test]
    fn endpoint_info() {
        // visible (bit 0x10 a 0), telephone (type 1), nom "Pixel"
        let mut v = vec![1 << 1];
        v.extend([0u8; 16]);
        v.push(5);
        v.extend(b"Pixel");
        assert_eq!(parse_endpoint_info(&v).map(|r| r.0), Some(Some("Pixel".into())));
        // visible mais sans nom (17 octets) : garde, nom vide
        assert_eq!(parse_endpoint_info(&v[..17]).map(|r| r.0), Some(Some(String::new())));
        // masque : pas de nom
        v[0] |= 0x10;
        assert_eq!(parse_endpoint_info(&v[..17]).map(|r| r.0), Some(None));
        // trop court
        assert!(parse_endpoint_info(&v[..10]).is_none());
    }
}
