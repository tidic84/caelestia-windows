//! Courrier : comptes IMAP (Gmail, Yahoo, iCloud, Orange...), derniers messages
//! de la boite de reception et lecture d'un message.
//!
//! Les comptes sont dans %LOCALAPPDATA%\Ilot\mail.json ; les mots de passe y
//! sont chiffres avec DPAPI (dechiffrables seulement par cette session Windows).

use std::net::{TcpStream, ToSocketAddrs};
use std::os::windows::process::CommandExt;
use std::process::Command;
use std::sync::Mutex;
use std::time::Duration;

use base64::Engine;
use serde::{Deserialize, Serialize};
use tauri::{AppHandle, Emitter, Manager, State};
use windows::Win32::Foundation::{LocalFree, HLOCAL};
use windows::Win32::Security::Cryptography::{
    CryptProtectData, CryptUnprotectData, CRYPTPROTECT_UI_FORBIDDEN, CRYPT_INTEGER_BLOB,
};

const CREATE_NO_WINDOW: u32 = 0x0800_0000;
/// Nombre de messages recuperes par compte.
const PER_ACCOUNT: u32 = 30;
/// Intervalle de verification automatique.
const POLL: Duration = Duration::from_secs(120);

type Session = imap::Session<native_tls::TlsStream<TcpStream>>;

#[derive(Serialize, Deserialize, Clone)]
struct Account {
    email: String,
    host: String,
    port: u16,
    /// mot de passe chiffre DPAPI, en base64
    pass: String,
}

#[derive(Serialize, Clone)]
pub struct AccountInfo {
    email: String,
    host: String,
    unread: u32,
    error: Option<String>,
}

#[derive(Serialize, Clone)]
pub struct Mail {
    account: String,
    uid: u32,
    from: String,
    from_addr: String,
    subject: String,
    /// horodatage unix (s)
    date: i64,
    seen: bool,
    /// lien pour ouvrir le message dans le webmail (vide si inconnu)
    link: String,
}

#[derive(Serialize, Clone, Default)]
pub struct Inbox {
    accounts: Vec<AccountInfo>,
    mails: Vec<Mail>,
}

pub struct MailState(pub Mutex<Inbox>);

// ------------------------------------------------------------------- DPAPI

fn blob(data: &[u8]) -> CRYPT_INTEGER_BLOB {
    CRYPT_INTEGER_BLOB { cbData: data.len() as u32, pbData: data.as_ptr() as *mut u8 }
}

fn take(out: CRYPT_INTEGER_BLOB) -> Vec<u8> {
    unsafe {
        let v = std::slice::from_raw_parts(out.pbData, out.cbData as usize).to_vec();
        let _ = LocalFree(Some(HLOCAL(out.pbData as _)));
        v
    }
}

fn protect(plain: &str) -> Option<String> {
    let mut out = CRYPT_INTEGER_BLOB::default();
    unsafe {
        CryptProtectData(&blob(plain.as_bytes()), None, None, None, None, CRYPTPROTECT_UI_FORBIDDEN, &mut out)
            .ok()?;
    }
    Some(base64::engine::general_purpose::STANDARD.encode(take(out)))
}

fn unprotect(enc: &str) -> Option<String> {
    let data = base64::engine::general_purpose::STANDARD.decode(enc).ok()?;
    let mut out = CRYPT_INTEGER_BLOB::default();
    unsafe {
        CryptUnprotectData(&blob(&data), None, None, None, None, CRYPTPROTECT_UI_FORBIDDEN, &mut out)
            .ok()?;
    }
    String::from_utf8(take(out)).ok()
}

// ------------------------------------------------------------------ comptes

fn load_accounts() -> Vec<Account> {
    crate::store::read("mail").unwrap_or_default()
}

fn save_accounts(list: &[Account]) -> bool {
    crate::store::write("mail", &list)
}

/// Serveur IMAP deduit du domaine de l'adresse.
fn guess_host(email: &str) -> Option<&'static str> {
    let domain = email.rsplit('@').next()?.to_lowercase();
    Some(match domain.as_str() {
        "gmail.com" | "googlemail.com" => "imap.gmail.com",
        "outlook.com" | "outlook.fr" | "hotmail.com" | "hotmail.fr" | "live.com" | "live.fr"
        | "msn.com" => "outlook.office365.com",
        "yahoo.com" | "yahoo.fr" => "imap.mail.yahoo.com",
        "icloud.com" | "me.com" | "mac.com" => "imap.mail.me.com",
        "orange.fr" | "wanadoo.fr" => "imap.orange.fr",
        "free.fr" => "imap.free.fr",
        "sfr.fr" | "neuf.fr" => "imap.sfr.fr",
        "laposte.net" => "imap.laposte.net",
        "bbox.fr" => "imap.bbox.fr",
        "gmx.fr" | "gmx.com" => "imap.gmx.com",
        _ => return None,
    })
}

/// Lien webmail vers un message (par son Message-ID quand c'est possible).
fn web_link(acc: &Account, msgid: &str) -> String {
    let id = msgid.trim().trim_start_matches('<').trim_end_matches('>');
    match acc.host.as_str() {
        "imap.gmail.com" if !id.is_empty() => format!(
            "https://mail.google.com/mail/u/{}/#search/rfc822msgid%3A{}",
            acc.email,
            enc_uri(id)
        ),
        "imap.gmail.com" => format!("https://mail.google.com/mail/u/{}/#inbox", acc.email),
        "outlook.office365.com" => "https://outlook.live.com/mail/0/inbox".into(),
        "imap.mail.yahoo.com" => "https://mail.yahoo.com/".into(),
        "imap.mail.me.com" => "https://www.icloud.com/mail".into(),
        "imap.orange.fr" => "https://messagerie.orange.fr/".into(),
        "imap.free.fr" => "https://webmail.free.fr/".into(),
        "imap.sfr.fr" => "https://webmail.sfr.fr/".into(),
        "imap.laposte.net" => "https://www.laposte.net/accueil".into(),
        _ => String::new(),
    }
}

fn enc_uri(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' | b'@' => {
                (b as char).to_string()
            }
            _ => format!("%{b:02X}"),
        })
        .collect()
}

// --------------------------------------------------------------------- IMAP

fn connect(acc: &Account) -> Result<Session, String> {
    let pass = unprotect(&acc.pass).ok_or("mot de passe illisible, rajoutez le compte")?;
    login(&acc.host, acc.port, &acc.email, &pass)
}

/// Diagnostic `--check-imap <hote>` : connexion + accueil du serveur, sans identifiants.
pub fn check(host: &str) -> String {
    match open(host, 993) {
        Ok(mut c) => match c.read_greeting() {
            Ok(g) => format!("OK {host} : {}", String::from_utf8_lossy(&g).trim()),
            Err(e) => format!("ERREUR accueil {host} : {e}"),
        },
        Err(e) => format!("ERREUR {e}"),
    }
}

fn open(host: &str, port: u16) -> Result<imap::Client<native_tls::TlsStream<TcpStream>>, String> {
    let mut addrs: Vec<_> = (host, port)
        .to_socket_addrs()
        .map_err(|e| format!("serveur introuvable : {host} ({e})"))?
        .collect();
    if addrs.is_empty() {
        return Err(format!("serveur introuvable : {host}"));
    }
    // IPv4 d'abord : sur certaines box 4G/5G l'IPv6 vers le serveur n'aboutit pas
    addrs.sort_by_key(|a| a.is_ipv6());
    let mut last = String::new();
    let tcp = addrs
        .iter()
        .find_map(|a| match TcpStream::connect_timeout(a, Duration::from_secs(6)) {
            Ok(t) => Some(t),
            Err(e) => {
                last = e.to_string();
                None
            }
        })
        .ok_or_else(|| format!("connexion impossible a {host} : {last}"))?;
    let _ = tcp.set_read_timeout(Some(Duration::from_secs(30)));
    let _ = tcp.set_write_timeout(Some(Duration::from_secs(30)));
    let tls = native_tls::TlsConnector::new().map_err(|e| e.to_string())?;
    let stream = tls.connect(host, tcp).map_err(|e| format!("TLS : {e}"))?;
    Ok(imap::Client::new(stream))
}

fn login(host: &str, port: u16, user: &str, pass: &str) -> Result<Session, String> {
    let mut client = open(host, port)?;
    client.read_greeting().map_err(|e| e.to_string())?;
    client.login(user, pass).map_err(|(e, _)| match e {
        imap::error::Error::No(_) | imap::error::Error::Bad(_) => {
            "identifiants refuses (utilisez un mot de passe d'application)".to_string()
        }
        e => e.to_string(),
    })
}

/// Decode un en-tete MIME (=?UTF-8?B?...?=, etc.).
fn header(raw: Option<&[u8]>) -> String {
    let Some(raw) = raw else { return String::new() };
    let mut h = b"X: ".to_vec();
    h.extend_from_slice(raw);
    mailparse::parse_header(&h)
        .map(|(h, _)| h.get_value())
        .unwrap_or_else(|_| String::from_utf8_lossy(raw).into_owned())
        .trim()
        .to_string()
}

fn fetch_account(acc: &Account) -> Result<(u32, Vec<Mail>), String> {
    let mut s = connect(acc)?;
    let mb = s.examine("INBOX").map_err(|e| e.to_string())?;
    let unread = s.search("UNSEEN").map(|r| r.len() as u32).unwrap_or(0);
    let mut mails = Vec::new();
    if mb.exists > 0 {
        let start = mb.exists.saturating_sub(PER_ACCOUNT - 1).max(1);
        let list = s
            .fetch(format!("{start}:{}", mb.exists), "(UID FLAGS ENVELOPE INTERNALDATE)")
            .map_err(|e| e.to_string())?;
        for f in list.iter() {
            let Some(uid) = f.uid else { continue };
            let env = f.envelope();
            let (from, from_addr) = env
                .and_then(|e| e.from.as_ref())
                .and_then(|v| v.first())
                .map(|a| {
                    let addr = format!(
                        "{}@{}",
                        String::from_utf8_lossy(a.mailbox.unwrap_or_default()),
                        String::from_utf8_lossy(a.host.unwrap_or_default())
                    );
                    let name = header(a.name);
                    (if name.is_empty() { addr.clone() } else { name }, addr)
                })
                .unwrap_or_default();
            let msgid = String::from_utf8_lossy(env.and_then(|e| e.message_id).unwrap_or_default()).into_owned();
            mails.push(Mail {
                account: acc.email.clone(),
                uid,
                from,
                from_addr,
                subject: header(env.and_then(|e| e.subject)),
                date: f.internal_date().map(|d| d.timestamp()).unwrap_or(0),
                seen: f.flags().iter().any(|fl| matches!(fl, imap::types::Flag::Seen)),
                link: web_link(acc, &msgid),
            });
        }
    }
    let _ = s.logout();
    Ok((unread, mails))
}

/// Relit tous les comptes, met a jour l'etat et emet `mail`.
fn refresh(app: &AppHandle) -> Inbox {
    let accounts = load_accounts();
    // un thread par compte : un serveur lent ne bloque pas les autres
    let results: Vec<_> = accounts
        .iter()
        .cloned()
        .map(|a| std::thread::spawn(move || fetch_account(&a)))
        .collect::<Vec<_>>()
        .into_iter()
        .map(|h| h.join().unwrap_or_else(|_| Err("erreur interne".into())))
        .collect();
    let mut inbox = Inbox::default();
    for (acc, r) in accounts.iter().zip(results) {
        let (unread, error) = match r {
            Ok((n, mails)) => {
                inbox.mails.extend(mails);
                (n, None)
            }
            Err(e) => (0, Some(e)),
        };
        inbox.accounts.push(AccountInfo { email: acc.email.clone(), host: acc.host.clone(), unread, error });
    }
    inbox.mails.sort_by(|a, b| b.date.cmp(&a.date));
    *app.state::<MailState>().0.lock().unwrap() = inbox.clone();
    let _ = app.emit("mail", inbox.clone());
    inbox
}

/// Verifie les boites toutes les deux minutes.
pub fn watch(app: AppHandle) {
    std::thread::spawn(move || loop {
        if !load_accounts().is_empty() {
            refresh(&app);
        }
        std::thread::sleep(POLL);
    });
}

// ---------------------------------------------------------------- commandes

#[tauri::command]
pub fn mail_get(st: State<MailState>) -> Inbox {
    st.0.lock().unwrap().clone()
}

#[tauri::command(async)]
pub fn mail_refresh(app: AppHandle) -> Inbox {
    refresh(&app)
}

/// Teste la connexion puis enregistre le compte (remplace s'il existe deja).
#[tauri::command(async)]
pub fn mail_add(app: AppHandle, email: String, pass: String, host: Option<String>) -> Result<Inbox, String> {
    let email = email.trim().to_string();
    // Google affiche les mots de passe d'application par groupes de 4 avec des espaces
    let pass = pass.replace(' ', "");
    if !email.contains('@') || pass.is_empty() {
        return Err("adresse ou mot de passe manquant".into());
    }
    // serveur saisi a la main : on tolere « imaps://hote:993/ » et les espaces
    let typed = host
        .map(|h| h.trim().trim_start_matches("imaps://").trim_start_matches("imap://").trim_end_matches('/').replace(' ', ""))
        .filter(|h| !h.is_empty());
    let guessed = guess_host(&email);
    let host = match (typed, guessed) {
        // serveur saisi introuvable mais domaine connu : on prend le serveur connu
        (Some(h), Some(g)) if (h.split(':').next().unwrap_or(&h), 993).to_socket_addrs().is_err() => g.to_string(),
        (Some(h), _) => h,
        (None, Some(g)) => g.to_string(),
        (None, None) => return Err("serveur IMAP inconnu pour ce domaine : indiquez-le".into()),
    };
    let (host, port) = match host.rsplit_once(':') {
        Some((h, p)) if p.parse::<u16>().is_ok() => (h.to_string(), p.parse().unwrap()),
        _ => (host, 993),
    };
    let mut s = login(&host, port, &email, &pass)?;
    let _ = s.logout();
    let enc = protect(&pass).ok_or("chiffrement du mot de passe impossible")?;
    let mut list = load_accounts();
    list.retain(|a| !a.email.eq_ignore_ascii_case(&email));
    list.push(Account { email, host, port, pass: enc });
    if !save_accounts(&list) {
        return Err("impossible d'enregistrer le compte".into());
    }
    Ok(refresh(&app))
}

#[tauri::command(async)]
pub fn mail_remove(app: AppHandle, email: String) -> Inbox {
    let mut list = load_accounts();
    list.retain(|a| a.email != email);
    save_accounts(&list);
    refresh(&app)
}

#[derive(Serialize)]
pub struct Body {
    html: Option<String>,
    text: String,
}

fn find_part<'a>(m: &'a mailparse::ParsedMail<'a>, mime: &str) -> Option<&'a mailparse::ParsedMail<'a>> {
    if m.ctype.mimetype.eq_ignore_ascii_case(mime) && m.get_content_disposition().disposition != mailparse::DispositionType::Attachment {
        return Some(m);
    }
    m.subparts.iter().find_map(|p| find_part(p, mime))
}

/// Contenu d'un message ; le lire le marque comme lu sur le serveur.
#[tauri::command(async)]
pub fn mail_read(app: AppHandle, account: String, uid: u32) -> Result<Body, String> {
    let acc = load_accounts().into_iter().find(|a| a.email == account).ok_or("compte inconnu")?;
    let mut s = connect(&acc)?;
    s.select("INBOX").map_err(|e| e.to_string())?;
    let list = s.uid_fetch(uid.to_string(), "BODY[]").map_err(|e| e.to_string())?;
    let raw = list.iter().find_map(|f| f.body()).ok_or("message introuvable")?.to_vec();
    let _ = s.logout();
    let m = mailparse::parse_mail(&raw).map_err(|e| e.to_string())?;
    let html = find_part(&m, "text/html").and_then(|p| p.get_body().ok());
    let text = find_part(&m, "text/plain").and_then(|p| p.get_body().ok()).unwrap_or_default();

    let st = app.state::<MailState>();
    let mut inbox = st.0.lock().unwrap();
    if let Some(mail) = inbox.mails.iter_mut().find(|x| x.account == account && x.uid == uid) {
        if !mail.seen {
            mail.seen = true;
            if let Some(a) = inbox.accounts.iter_mut().find(|a| a.email == account) {
                a.unread = a.unread.saturating_sub(1);
            }
        }
    }
    let _ = app.emit("mail", inbox.clone());
    Ok(Body { html, text })
}

/// Ouvre un lien http(s) dans le navigateur par defaut.
#[tauri::command(async)]
pub fn open_url(url: String) {
    if url.starts_with("https://") || url.starts_with("http://") {
        let _ = Command::new("explorer.exe").arg(url).creation_flags(CREATE_NO_WINDOW).spawn();
    }
}
