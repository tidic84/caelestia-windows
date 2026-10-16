//! Connexion Google par le navigateur (OAuth 2, application de bureau) pour
//! lire Gmail en IMAP sans mot de passe d'application.
//!
//! Le navigateur ouvre la page de consentement de Google, qui renvoie sur un
//! petit serveur local (http://127.0.0.1:<port>) ; le code recu est echange
//! (avec PKCE) contre un jeton d'actualisation, chiffre DPAPI dans mail.json.
//!
//! Il faut un client OAuth « Application de bureau » de Google Cloud : soit
//! integre a la compilation (variables ILOT_GOOGLE_CLIENT_ID et
//! ILOT_GOOGLE_CLIENT_SECRET), soit saisi dans l'onglet Mail (google.json).

use std::collections::HashMap;
use std::io::{Read, Write};
use std::net::TcpListener;
use std::sync::atomic::{AtomicU64, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use base64::Engine;
use serde::{Deserialize, Serialize};
use windows::Win32::Security::Cryptography::{
    BCryptGenRandom, BCryptHash, BCRYPT_SHA256_ALG_HANDLE, BCRYPT_USE_SYSTEM_PREFERRED_RNG,
};

const AUTH: &str = "https://accounts.google.com/o/oauth2/v2/auth";
const TOKEN: &str = "https://oauth2.googleapis.com/token";
const SCOPE: &str = "https://mail.google.com/ openid email";
/// Temps laisse pour se connecter dans le navigateur.
const WAIT: Duration = Duration::from_secs(300);

/// Client OAuth saisi par l'utilisateur (%LOCALAPPDATA%\Ilot\google.json).
#[derive(Serialize, Deserialize)]
struct Client {
    client_id: String,
    /// secret chiffre DPAPI, en base64
    secret: String,
}

fn client() -> Option<(String, String)> {
    if let (Some(id), Some(secret)) = (option_env!("ILOT_GOOGLE_CLIENT_ID"), option_env!("ILOT_GOOGLE_CLIENT_SECRET")) {
        return Some((id.into(), secret.into()));
    }
    let c: Client = crate::store::read("google")?;
    Some((c.client_id, crate::mail::unprotect(&c.secret)?))
}

/// Un client OAuth est disponible.
pub fn ready() -> bool {
    client().is_some()
}

pub fn setup(client_id: String, secret: String) -> Result<(), String> {
    let client_id = client_id.trim().to_string();
    let secret = secret.trim().to_string();
    if !client_id.ends_with(".apps.googleusercontent.com") {
        return Err("le Client ID se termine par .apps.googleusercontent.com".into());
    }
    if secret.is_empty() {
        return Err("Client Secret manquant".into());
    }
    let secret = crate::mail::protect(&secret).ok_or("chiffrement impossible")?;
    if !crate::store::write("google", &Client { client_id, secret }) {
        return Err("impossible d'enregistrer le client".into());
    }
    Ok(())
}

pub fn forget() {
    let _ = std::fs::remove_file(crate::store::data_dir().join("google.json"));
}

// ------------------------------------------------------------------ outils

fn b64url(data: &[u8]) -> String {
    base64::engine::general_purpose::URL_SAFE_NO_PAD.encode(data)
}

fn random(n: usize) -> String {
    let mut buf = vec![0u8; n];
    unsafe {
        let _ = BCryptGenRandom(None, &mut buf, BCRYPT_USE_SYSTEM_PREFERRED_RNG);
    }
    b64url(&buf)
}

fn sha256(data: &[u8]) -> [u8; 32] {
    let mut out = [0u8; 32];
    unsafe {
        let _ = BCryptHash(BCRYPT_SHA256_ALG_HANDLE, None, data, &mut out);
    }
    out
}

fn enc(s: &str) -> String {
    s.bytes()
        .map(|b| match b {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => (b as char).to_string(),
            _ => format!("%{b:02X}"),
        })
        .collect()
}

fn dec(s: &str) -> String {
    let b = s.as_bytes();
    let mut out = Vec::with_capacity(b.len());
    let mut i = 0;
    while i < b.len() {
        match b[i] {
            b'+' => out.push(b' '),
            b'%' if i + 2 < b.len() => {
                match std::str::from_utf8(&b[i + 1..i + 3]).ok().and_then(|h| u8::from_str_radix(h, 16).ok()).ok_or(()) {
                    Ok(v) => {
                        out.push(v);
                        i += 2;
                    }
                    Err(_) => out.push(b'%'),
                }
            }
            c => out.push(c),
        }
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

#[derive(Deserialize)]
struct TokenReply {
    access_token: String,
    expires_in: u64,
    refresh_token: Option<String>,
    id_token: Option<String>,
}

fn post_token(form: &[(&str, &str)]) -> Result<TokenReply, String> {
    match ureq::post(TOKEN).timeout(Duration::from_secs(20)).send_form(form) {
        Ok(r) => r.into_json().map_err(|e| e.to_string()),
        Err(ureq::Error::Status(_, r)) => {
            let body: serde_json::Value = r.into_json().unwrap_or_default();
            Err(match body["error"].as_str() {
                Some("invalid_grant") => "acces Google revoque ou expire : reconnectez le compte".into(),
                Some("invalid_client") => "client OAuth Google refuse : verifiez le Client ID et le Secret".into(),
                Some(e) => format!("Google : {e} {}", body["error_description"].as_str().unwrap_or("")).trim().to_string(),
                None => "Google : reponse inattendue".into(),
            })
        }
        Err(e) => Err(format!("Google injoignable : {e}")),
    }
}

// --------------------------------------------------------- jetons d'acces

/// Jetons d'acces en memoire : jeton d'actualisation -> (jeton, expiration).
static ACCESS: Mutex<Option<HashMap<String, (String, Instant)>>> = Mutex::new(None);

/// Jeton d'acces valide pour ce jeton d'actualisation (renouvele au besoin).
pub fn access_token(refresh: &str) -> Result<String, String> {
    if let Some((tok, exp)) = ACCESS.lock().unwrap().as_ref().and_then(|m| m.get(refresh)) {
        if *exp > Instant::now() + Duration::from_secs(60) {
            return Ok(tok.clone());
        }
    }
    let (id, secret) = client().ok_or("client OAuth Google absent : reconfigurez-le dans Comptes")?;
    let r = post_token(&[
        ("client_id", &id),
        ("client_secret", &secret),
        ("refresh_token", refresh),
        ("grant_type", "refresh_token"),
    ])?;
    let exp = Instant::now() + Duration::from_secs(r.expires_in);
    ACCESS.lock().unwrap().get_or_insert_with(HashMap::new).insert(refresh.into(), (r.access_token.clone(), exp));
    Ok(r.access_token)
}

/// Authentification IMAP XOAUTH2.
pub struct XOAuth2 {
    pub user: String,
    pub token: String,
}

impl imap::Authenticator for XOAuth2 {
    type Response = String;
    fn process(&self, challenge: &[u8]) -> String {
        // une seconde invite contient l'erreur en JSON : reponse vide, le serveur conclut par NO
        if challenge.is_empty() {
            format!("user={}\x01auth=Bearer {}\x01\x01", self.user, self.token)
        } else {
            String::new()
        }
    }
}

// --------------------------------------------------------------- connexion

/// Numero de la tentative en cours : une nouvelle (ou une annulation) arrete la precedente.
static FLOW: AtomicU64 = AtomicU64::new(0);

pub fn cancel() {
    FLOW.fetch_add(1, Ordering::SeqCst);
}

/// Page renvoyee au navigateur apres la redirection.
fn reply(stream: &mut std::net::TcpStream, ok: bool) {
    let (title, text) = if ok {
        ("Compte connecté", "Vous pouvez fermer cet onglet et revenir à Ilot.")
    } else {
        ("Connexion annulée", "Aucun compte n'a été ajouté. Vous pouvez fermer cet onglet.")
    };
    let html = format!(
        "<!doctype html><meta charset=utf-8><title>Ilot</title>\
         <body style=\"font-family:Segoe UI,sans-serif;background:#1d1b20;color:#e6e0e9;display:grid;place-items:center;height:100vh;margin:0\">\
         <div style=\"text-align:center\"><h2>{title}</h2><p>{text}</p></div>"
    );
    let _ = write!(
        stream,
        "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nContent-Length: {}\r\nConnection: close\r\n\r\n{html}",
        html.len()
    );
}

/// Attend la redirection de Google ; renvoie le code d'autorisation.
fn wait_code(listener: &TcpListener, state: &str, flow: u64) -> Result<String, String> {
    listener.set_nonblocking(true).map_err(|e| e.to_string())?;
    let deadline = Instant::now() + WAIT;
    loop {
        if FLOW.load(Ordering::SeqCst) != flow {
            return Err("connexion annulee".into());
        }
        if Instant::now() > deadline {
            return Err("delai depasse : connexion Google non terminee".into());
        }
        let mut stream = match listener.accept() {
            Ok((s, _)) => s,
            Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => {
                std::thread::sleep(Duration::from_millis(150));
                continue;
            }
            Err(e) => return Err(e.to_string()),
        };
        let _ = stream.set_nonblocking(false);
        let _ = stream.set_read_timeout(Some(Duration::from_secs(5)));
        let mut buf = [0u8; 4096];
        let n = stream.read(&mut buf).unwrap_or(0);
        let req = String::from_utf8_lossy(&buf[..n]);
        // « GET /?state=...&code=... HTTP/1.1 »
        let path = req.split_whitespace().nth(1).unwrap_or("");
        let Some(query) = path.strip_prefix("/?") else {
            let _ = stream.write_all(b"HTTP/1.1 404 Not Found\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
            continue;
        };
        let params: HashMap<String, String> = query
            .split('&')
            .filter_map(|kv| kv.split_once('='))
            .map(|(k, v)| (k.to_string(), dec(v)))
            .collect();
        if params.get("state").map(String::as_str) != Some(state) {
            let _ = stream.write_all(b"HTTP/1.1 400 Bad Request\r\nContent-Length: 0\r\nConnection: close\r\n\r\n");
            continue;
        }
        if let Some(code) = params.get("code") {
            reply(&mut stream, true);
            return Ok(code.clone());
        }
        reply(&mut stream, false);
        return Err(match params.get("error").map(String::as_str) {
            Some("access_denied") => "connexion refusee dans le navigateur".into(),
            Some(e) => format!("Google : {e}"),
            None => "reponse de Google incomplete".into(),
        });
    }
}

/// Adresse mail contenue dans le jeton d'identite (JWT recu directement de Google).
fn email_of(id_token: &str) -> Option<String> {
    let payload = id_token.split('.').nth(1)?;
    let raw = base64::engine::general_purpose::URL_SAFE_NO_PAD.decode(payload.trim_end_matches('=')).ok()?;
    let v: serde_json::Value = serde_json::from_slice(&raw).ok()?;
    v["email"].as_str().map(str::to_string)
}

/// Ouvre la connexion Google dans le navigateur et attend la fin ; renvoie
/// (adresse, jeton d'actualisation, jeton d'acces).
pub fn sign_in() -> Result<(String, String, String), String> {
    let (id, secret) = client().ok_or("client OAuth Google absent")?;
    let flow = FLOW.fetch_add(1, Ordering::SeqCst) + 1;
    let listener = TcpListener::bind("127.0.0.1:0").map_err(|e| format!("serveur local impossible : {e}"))?;
    let port = listener.local_addr().map_err(|e| e.to_string())?.port();
    let redirect = format!("http://127.0.0.1:{port}");
    let verifier = random(48);
    let challenge = b64url(&sha256(verifier.as_bytes()));
    let state = random(16);
    let url = format!(
        "{AUTH}?client_id={}&redirect_uri={}&response_type=code&scope={}&access_type=offline&prompt=consent\
         &code_challenge={challenge}&code_challenge_method=S256&state={state}",
        enc(&id),
        enc(&redirect),
        enc(SCOPE)
    );
    crate::system::open_url(url);
    let code = wait_code(&listener, &state, flow)?;
    let r = post_token(&[
        ("client_id", &id),
        ("client_secret", &secret),
        ("code", &code),
        ("code_verifier", &verifier),
        ("redirect_uri", &redirect),
        ("grant_type", "authorization_code"),
    ])?;
    let refresh = r.refresh_token.ok_or("Google n'a pas donne d'acces durable : retirez Ilot des applis tierces du compte puis recommencez")?;
    let email = r.id_token.as_deref().and_then(email_of).ok_or("adresse du compte Google introuvable")?;
    let exp = Instant::now() + Duration::from_secs(r.expires_in);
    ACCESS.lock().unwrap().get_or_insert_with(HashMap::new).insert(refresh.clone(), (r.access_token.clone(), exp));
    Ok((email, refresh, r.access_token))
}
