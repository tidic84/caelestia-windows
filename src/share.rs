//! Partage local avec le telephone : un petit serveur web sur le reseau de la
//! maison. Le telephone scanne le QR code, telecharge les fichiers deposes sur
//! l'ilot ou envoie les siens (ranges dans Telechargements). L'adresse contient
//! un jeton aleatoire : sans le QR code, rien n'est accessible.

use std::collections::hash_map::RandomState;
use std::hash::{BuildHasher, Hasher};
use std::io::{BufRead, BufReader, Read, Write};
use std::net::{Ipv4Addr, TcpListener, TcpStream};
use std::path::{Path, PathBuf};
use std::sync::{Arc, Mutex};

use serde::Serialize;
use tauri::{AppHandle, Emitter, State};
use windows::Win32::NetworkManagement::IpHelper::{GetAdaptersAddresses, GAA_FLAG_INCLUDE_GATEWAYS, IP_ADAPTER_ADDRESSES_LH};
use windows::Win32::Networking::WinSock::{AF_INET, SOCKADDR_IN};

const PORT: u16 = 8642;
/// au-dela, l'envoi depuis le telephone est refuse
const MAX_UPLOAD: u64 = 8 * 1024 * 1024 * 1024;

#[derive(Default)]
struct Inner {
    token: String,
    files: Vec<PathBuf>,
    port: u16,
}

#[derive(Default)]
pub struct Share(Arc<Mutex<Inner>>);

#[derive(Serialize)]
pub struct ShareInfo {
    url: String,
    qr: String,
    files: Vec<String>,
    ip: String,
}

#[derive(Serialize, Clone)]
struct ShareEvent {
    kind: &'static str,
    name: String,
    path: String,
}

fn random_token() -> String {
    let mut h = RandomState::new().build_hasher();
    h.write_u128(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_nanos()));
    let a = h.finish();
    let mut h = RandomState::new().build_hasher();
    h.write_u64(a);
    format!("{:016x}{:08x}", a, h.finish() as u32)
}

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

fn qr_svg(text: &str) -> String {
    match qrcode::QrCode::new(text.as_bytes()) {
        Ok(c) => c
            .render::<qrcode::render::svg::Color>()
            .min_dimensions(180, 180)
            .quiet_zone(true)
            .dark_color(qrcode::render::svg::Color("#000000"))
            .light_color(qrcode::render::svg::Color("#ffffff"))
            .build(),
        Err(_) => String::new(),
    }
}

fn file_name(p: &Path) -> String {
    p.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default()
}

/// Pourcent-encodage (noms de fichiers dans les en-tetes et les liens).
fn pct(s: &str) -> String {
    s.bytes()
        .map(|b| if b.is_ascii_alphanumeric() || b"-_.~".contains(&b) { (b as char).to_string() } else { format!("%{b:02X}") })
        .collect()
}

fn unpct(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::new();
    let mut i = 0;
    while i < b.len() {
        if b[i] == b'%' && i + 2 < b.len() {
            if let Ok(v) = u8::from_str_radix(&s[i + 1..i + 3], 16) {
                out.push(v);
                i += 3;
                continue;
            }
        }
        out.push(if b[i] == b'+' { b' ' } else { b[i] });
        i += 1;
    }
    String::from_utf8_lossy(&out).to_string()
}

fn esc(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;")
}

/// Nom de fichier sans chemin ni caracteres interdits par Windows.
fn safe_name(n: &str) -> String {
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

fn downloads_dir() -> PathBuf {
    let home = std::env::var("USERPROFILE").unwrap_or_else(|_| ".".into());
    let d = Path::new(&home).join("Downloads");
    let _ = std::fs::create_dir_all(&d);
    d
}

/// « photo.jpg » -> « photo (2).jpg » si le nom est deja pris.
fn free_path(dir: &Path, name: &str) -> PathBuf {
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

fn respond(s: &mut TcpStream, code: &str, ctype: &str, body: &[u8]) {
    let _ = write!(
        s,
        "HTTP/1.1 {code}\r\nContent-Type: {ctype}\r\nContent-Length: {}\r\nCache-Control: no-store\r\nConnection: close\r\n\r\n",
        body.len()
    );
    let _ = s.write_all(body);
}

fn page(files: &[PathBuf]) -> String {
    let list: String = files
        .iter()
        .enumerate()
        .map(|(i, f)| {
            let size = std::fs::metadata(f).map_or(0, |m| m.len());
            let sz = if size >= 1 << 30 {
                format!("{:.1} Go", size as f64 / (1u64 << 30) as f64)
            } else {
                format!("{:.1} Mo", size as f64 / (1u64 << 20) as f64)
            };
            format!("<a class=f href=\"f/{i}\" download><b>{}</b><small>{sz}</small></a>", esc(&file_name(f)))
        })
        .collect();
    let list = if list.is_empty() { "<p class=e>Aucun fichier partagé pour l'instant.</p>".to_string() } else { list };
    format!(
        r#"<!doctype html><html lang=fr><head><meta charset=utf-8><meta name=viewport content="width=device-width,initial-scale=1">
<title>Ilot · Partage</title><style>
body{{margin:0;font-family:system-ui,sans-serif;background:#141218;color:#e6e0e9;padding:20px}}
h1{{font-size:20px;margin:0 0 4px}}p{{color:#cac4d0;font-size:14px}}
.f{{display:flex;justify-content:space-between;gap:12px;align-items:center;padding:14px 16px;margin:8px 0;border-radius:16px;background:#2b2930;color:#e6e0e9;text-decoration:none}}
.f b{{font-weight:500;word-break:break-all}}.f small{{color:#cac4d0;white-space:nowrap}}
label{{display:block;text-align:center;margin-top:22px;padding:16px;border-radius:99px;background:#d0bcff;color:#381e72;font-weight:600}}
input{{display:none}}#st{{text-align:center;min-height:20px}}.e{{text-align:center}}
progress{{width:100%;height:8px;margin-top:10px}}</style></head><body>
<h1>Ilot · Partage</h1><p>Fichiers du PC :</p>{list}
<label>Envoyer des fichiers au PC<input type=file id=up multiple></label>
<progress id=pr max=1 value=0 hidden></progress><p id=st></p>
<script>
const up=document.getElementById('up'),st=document.getElementById('st'),pr=document.getElementById('pr');
up.onchange=async()=>{{for(const f of up.files){{await new Promise(ok=>{{
const x=new XMLHttpRequest();x.open('POST','up?name='+encodeURIComponent(f.name));
pr.hidden=false;x.upload.onprogress=e=>{{pr.value=e.loaded/e.total;st.textContent=f.name+' : '+Math.round(e.loaded/e.total*100)+' %'}};
x.onloadend=()=>{{st.textContent=x.status==200?'✓ '+f.name+' envoyé (Téléchargements)':'Échec : '+f.name;ok()}};x.send(f)}})}}pr.hidden=true;up.value=''}};
</script></body></html>"#
    )
}

fn handle(mut s: TcpStream, st: Arc<Mutex<Inner>>, app: AppHandle) {
    let _ = s.set_read_timeout(Some(std::time::Duration::from_secs(30)));
    let mut r = BufReader::new(s.try_clone().unwrap());
    let mut line = String::new();
    if r.read_line(&mut line).is_err() {
        return;
    }
    let mut parts = line.split_whitespace();
    let (method, target) = (parts.next().unwrap_or_default().to_string(), parts.next().unwrap_or_default().to_string());
    let mut len: u64 = 0;
    loop {
        let mut h = String::new();
        if r.read_line(&mut h).unwrap_or(0) == 0 || h.trim().is_empty() {
            break;
        }
        if let Some((k, v)) = h.split_once(':') {
            if k.eq_ignore_ascii_case("content-length") {
                len = v.trim().parse().unwrap_or(0);
            }
        }
    }
    let (token, files) = {
        let g = st.lock().unwrap();
        (g.token.clone(), g.files.clone())
    };
    let (path, query) = target.split_once('?').unwrap_or((&target, ""));
    let Some(rest) = (!token.is_empty()).then(|| path.strip_prefix(&format!("/{token}/"))).flatten() else {
        return respond(&mut s, "404 Not Found", "text/plain", b"Lien expire");
    };
    match (method.as_str(), rest) {
        ("GET", "") => respond(&mut s, "200 OK", "text/html; charset=utf-8", page(&files).as_bytes()),
        ("GET", f) if f.starts_with("f/") => {
            let Some(p) = f[2..].parse::<usize>().ok().and_then(|i| files.get(i)) else {
                return respond(&mut s, "404 Not Found", "text/plain", b"?");
            };
            let Ok(mut file) = std::fs::File::open(p) else {
                return respond(&mut s, "404 Not Found", "text/plain", b"?");
            };
            let size = file.metadata().map_or(0, |m| m.len());
            let name = file_name(p);
            let _ = write!(
                s,
                "HTTP/1.1 200 OK\r\nContent-Type: application/octet-stream\r\nContent-Length: {size}\r\nContent-Disposition: attachment; filename*=UTF-8''{}\r\nConnection: close\r\n\r\n",
                pct(&name)
            );
            if std::io::copy(&mut file, &mut s).is_ok() {
                let _ = app.emit("share", ShareEvent { kind: "sent", name, path: p.to_string_lossy().to_string() });
            }
        }
        ("POST", "up") => {
            if len == 0 || len > MAX_UPLOAD {
                return respond(&mut s, "413 Payload Too Large", "text/plain", b"Trop gros");
            }
            let name = query
                .split('&')
                .find_map(|kv| kv.strip_prefix("name="))
                .map(|n| safe_name(&unpct(n)))
                .unwrap_or_else(|| "fichier".into());
            let dest = free_path(&downloads_dir(), &name);
            let tmp = dest.with_extension("ilot-part");
            let ok = std::fs::File::create(&tmp)
                .and_then(|mut f| std::io::copy(&mut (&mut r).take(len), &mut f))
                .is_ok_and(|n| n == len);
            if ok && std::fs::rename(&tmp, &dest).is_ok() {
                let _ = app.emit("share", ShareEvent { kind: "recv", name: file_name(&dest), path: dest.to_string_lossy().to_string() });
                respond(&mut s, "200 OK", "text/plain", b"ok");
            } else {
                let _ = std::fs::remove_file(&tmp);
                respond(&mut s, "500 Internal Server Error", "text/plain", b"echec");
            }
        }
        _ => respond(&mut s, "404 Not Found", "text/plain", b"?"),
    }
}

fn ensure_server(st: &Share, app: &AppHandle) -> Result<u16, String> {
    let mut g = st.0.lock().unwrap();
    if g.port != 0 {
        return Ok(g.port);
    }
    let l = TcpListener::bind(("0.0.0.0", PORT))
        .or_else(|_| TcpListener::bind(("0.0.0.0", 0)))
        .map_err(|e| format!("Serveur impossible : {e}"))?;
    g.port = l.local_addr().map_err(|e| e.to_string())?.port();
    let inner = st.0.clone();
    let app = app.clone();
    std::thread::spawn(move || {
        for c in l.incoming().flatten() {
            let (inner, app) = (inner.clone(), app.clone());
            std::thread::spawn(move || handle(c, inner, app));
        }
    });
    Ok(g.port)
}

/// Partage ces fichiers (liste vide : seulement recevoir depuis le telephone).
#[tauri::command(async)]
pub fn share_start(app: AppHandle, st: State<Share>, paths: Vec<String>) -> Result<ShareInfo, String> {
    let port = ensure_server(&st, &app)?;
    let ip = lan_ip().ok_or("PC non connecté au réseau local")?;
    let mut g = st.0.lock().unwrap();
    if g.token.is_empty() {
        g.token = random_token();
    }
    let mut files = g.files.clone();
    for p in paths.into_iter().map(PathBuf::from).filter(|p| p.is_file()) {
        if !files.contains(&p) {
            files.push(p);
        }
    }
    g.files = files;
    let url = format!("http://{ip}:{port}/{}/", g.token);
    Ok(ShareInfo { qr: qr_svg(&url), files: g.files.iter().map(|p| file_name(p)).collect(), ip: ip.to_string(), url })
}

/// Arrete le partage : l'ancien lien ne marche plus.
#[tauri::command]
pub fn share_stop(st: State<Share>) {
    let mut g = st.0.lock().unwrap();
    g.token.clear();
    g.files.clear();
}
