//! Discord via son RPC local (tube nomme \\.\pipe\discord-ipc-N) : couper le
//! micro / le son, et regler le volume de chaque personne du salon vocal.
//!
//! Discord n'ouvre ces fonctions qu'a une « application » Discord creee par
//! l'utilisateur (portail developpeurs) : il faut son Client ID et son Client
//! Secret, saisis une fois dans l'onglet PC. Discord demande ensuite
//! l'autorisation dans sa propre fenetre. Tout est stocke chiffre (DPAPI) dans
//! %LOCALAPPDATA%\Ilot\discord.json.

use std::collections::VecDeque;
use std::fs::File;
use std::io::{Read, Write};
use std::os::windows::io::AsRawHandle;
use std::sync::{Arc, Mutex};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use crate::host::{AppHandle, State};
use windows::Win32::Foundation::HANDLE;
use windows::Win32::System::Pipes::PeekNamedPipe;

const SCOPES: &[&str] = &["rpc", "rpc.voice.read", "rpc.voice.write"];

#[derive(Serialize, Deserialize, Default, Clone)]
struct Config {
    client_id: String,
    /// champs chiffres DPAPI (base64)
    secret: String,
    #[serde(default)]
    token: String,
    #[serde(default)]
    refresh: String,
}

#[derive(Serialize, Clone, Default)]
pub struct Person {
    id: String,
    name: String,
    avatar: String,
    /// 0 a 200 (%)
    volume: f64,
    mute: bool,
    speaking: bool,
    self_mute: bool,
    self_deaf: bool,
}

#[derive(Serialize, Clone, Default)]
pub struct DiscordState {
    /// setup | closed | authorizing | ready | error
    status: String,
    error: String,
    me: String,
    /// id de l'utilisateur connecte (sa ligne du salon regle le micro)
    me_id: String,
    /// volume du micro dans Discord (0-100)
    mic_volume: f64,
    mute: bool,
    deaf: bool,
    channel: String,
    people: Vec<Person>,
}

pub struct Discord {
    state: Arc<Mutex<DiscordState>>,
    queue: Arc<Mutex<VecDeque<(String, Value)>>>,
}

impl Default for Discord {
    fn default() -> Self {
        Discord { state: Arc::new(Mutex::new(DiscordState::default())), queue: Arc::new(Mutex::new(VecDeque::new())) }
    }
}

fn load() -> Option<Config> {
    crate::store::read::<Config>("discord").filter(|c| !c.client_id.is_empty())
}

fn save(c: &Config) {
    crate::store::write("discord", c);
}

/// Commande ajoutee a la file (reveille la boucle de la session)
static COMMANDS: crate::events::Wake = crate::events::Wake::new();

// ------------------------------------------------------------------- tube

struct Pipe {
    f: File,
    nonce: u64,
}

impl Pipe {
    fn open() -> Option<Pipe> {
        (0..10).find_map(|i| {
            std::fs::OpenOptions::new()
                .read(true)
                .write(true)
                .open(format!(r"\\.\pipe\discord-ipc-{i}"))
                .ok()
                .map(|f| Pipe { f, nonce: 0 })
        })
    }

    fn send(&mut self, op: u32, v: &Value) -> Result<(), String> {
        let body = v.to_string().into_bytes();
        let mut buf = Vec::with_capacity(8 + body.len());
        buf.extend_from_slice(&op.to_le_bytes());
        buf.extend_from_slice(&(body.len() as u32).to_le_bytes());
        buf.extend_from_slice(&body);
        self.f.write_all(&buf).map_err(|e| e.to_string())
    }

    fn recv(&mut self) -> Result<(u32, Value), String> {
        let mut h = [0u8; 8];
        self.f.read_exact(&mut h).map_err(|e| e.to_string())?;
        let op = u32::from_le_bytes(h[..4].try_into().unwrap());
        let len = u32::from_le_bytes(h[4..].try_into().unwrap()) as usize;
        let mut body = vec![0u8; len];
        self.f.read_exact(&mut body).map_err(|e| e.to_string())?;
        if op == 2 {
            return Err("Discord a ferme la connexion".into());
        }
        Ok((op, serde_json::from_slice(&body).unwrap_or(Value::Null)))
    }

    /// Octets en attente (lecture sans blocage).
    fn pending(&self) -> Result<u32, String> {
        let mut avail = 0u32;
        unsafe {
            PeekNamedPipe(HANDLE(self.f.as_raw_handle() as _), None, 0, None, Some(&mut avail), None)
                .map_err(|_| "Discord a ete ferme".to_string())?;
        }
        Ok(avail)
    }

    fn command(&mut self, cmd: &str, args: Value, evt: Option<&str>) -> Result<String, String> {
        self.nonce += 1;
        let nonce = self.nonce.to_string();
        let mut v = json!({ "cmd": cmd, "args": args, "nonce": nonce });
        if let Some(e) = evt {
            v["evt"] = json!(e);
        }
        self.send(1, &v)?;
        Ok(nonce)
    }

    /// Envoie une commande et attend sa reponse (les evenements recus entre-temps
    /// sont transmis a `on_event`).
    fn call(&mut self, cmd: &str, args: Value, on_event: &mut dyn FnMut(&Value)) -> Result<Value, String> {
        let nonce = self.command(cmd, args, None)?;
        loop {
            let (_, v) = self.recv()?;
            if v["nonce"].as_str() == Some(nonce.as_str()) {
                if v["evt"] == "ERROR" {
                    return Err(v["data"]["message"].as_str().unwrap_or("erreur Discord").to_string());
                }
                return Ok(v["data"].clone());
            }
            on_event(&v);
        }
    }
}

// --------------------------------------------------------------- OAuth2

fn token_request(form: &[(&str, &str)]) -> Result<Value, String> {
    let tls = native_tls::TlsConnector::new().map_err(|e| e.to_string())?;
    let agent = ureq::AgentBuilder::new()
        .tls_connector(Arc::new(tls))
        .timeout_connect(Duration::from_secs(6))
        .timeout(Duration::from_secs(20))
        .build();
    match agent.post("https://discord.com/api/oauth2/token").send_form(form) {
        Ok(r) => r.into_json::<Value>().map_err(|e| e.to_string()),
        Err(ureq::Error::Status(_, r)) => {
            let v: Value = r.into_json().unwrap_or(Value::Null);
            Err(v["error_description"].as_str().or(v["error"].as_str()).unwrap_or("refus de Discord").to_string())
        }
        Err(e) => Err(e.to_string()),
    }
}

/// Echange le code d'autorisation contre des jetons (et les enregistre).
fn exchange(cfg: &mut Config, grant: &str, value: &str) -> Result<String, String> {
    let secret = crate::mail::unprotect(&cfg.secret).ok_or("secret illisible : ressaisissez-le")?;
    let key = if grant == "refresh_token" { "refresh_token" } else { "code" };
    let base = [("client_id", cfg.client_id.as_str()), ("client_secret", secret.as_str()), ("grant_type", grant), (key, value)];
    let v = token_request(&base).or_else(|e| {
        // certaines applis Discord exigent l'URL de redirection enregistree
        if e.to_lowercase().contains("redirect") {
            let mut f = base.to_vec();
            f.push(("redirect_uri", "http://localhost"));
            token_request(&f)
        } else {
            Err(e)
        }
    })?;
    let token = v["access_token"].as_str().ok_or("pas de jeton recu")?.to_string();
    cfg.token = crate::mail::protect(&token).unwrap_or_default();
    if let Some(r) = v["refresh_token"].as_str() {
        cfg.refresh = crate::mail::protect(r).unwrap_or_default();
    }
    save(cfg);
    Ok(token)
}

// ---------------------------------------------------------------- session

fn person(v: &Value) -> Person {
    let u = &v["user"];
    let id = u["id"].as_str().unwrap_or_default().to_string();
    let name = v["nick"]
        .as_str()
        .filter(|s| !s.is_empty())
        .or(u["global_name"].as_str())
        .or(u["username"].as_str())
        .unwrap_or("?")
        .to_string();
    let avatar = u["avatar"]
        .as_str()
        .map(|a| format!("https://cdn.discordapp.com/avatars/{id}/{a}.png?size=64"))
        .unwrap_or_default();
    let vs = &v["voice_state"];
    Person {
        id,
        name,
        avatar,
        volume: v["volume"].as_f64().unwrap_or(100.0),
        mute: v["mute"].as_bool().unwrap_or(false),
        speaking: false,
        self_mute: vs["self_mute"].as_bool().unwrap_or(false) || vs["mute"].as_bool().unwrap_or(false),
        self_deaf: vs["self_deaf"].as_bool().unwrap_or(false) || vs["deaf"].as_bool().unwrap_or(false),
    }
}

struct Session<'a> {
    pipe: Pipe,
    app: &'a AppHandle,
    st: Arc<Mutex<DiscordState>>,
    channel_id: Option<String>,
}

impl Session<'_> {
    fn emit(&self) {
        let s = self.st.lock().unwrap().clone();
        let _ = self.app.emit("discord", s);
    }

    fn set_status(&self, status: &str, error: &str) {
        {
            let mut s = self.st.lock().unwrap();
            s.status = status.into();
            s.error = error.into();
        }
        self.emit();
    }

    fn sub_channel(&mut self, on: bool) -> Result<(), String> {
        let Some(id) = self.channel_id.clone() else { return Ok(()) };
        let cmd = if on { "SUBSCRIBE" } else { "UNSUBSCRIBE" };
        for e in ["VOICE_STATE_CREATE", "VOICE_STATE_UPDATE", "VOICE_STATE_DELETE", "SPEAKING_START", "SPEAKING_STOP"] {
            self.pipe.command(cmd, json!({ "channel_id": id }), Some(e))?;
        }
        Ok(())
    }

    /// Relit le salon vocal actuel.
    fn load_channel(&mut self) -> Result<(), String> {
        self.sub_channel(false)?;
        let data = self.pipe.call("GET_SELECTED_VOICE_CHANNEL", json!({}), &mut |_| {})?;
        self.channel_id = data["id"].as_str().map(String::from);
        {
            let mut s = self.st.lock().unwrap();
            s.channel = data["name"].as_str().unwrap_or_default().to_string();
            s.people = data["voice_states"].as_array().map(|a| a.iter().map(person).collect()).unwrap_or_default();
        }
        self.sub_channel(true)?;
        self.emit();
        Ok(())
    }

    fn on_event(&mut self, v: &Value) -> Result<(), String> {
        let data = &v["data"];
        match v["evt"].as_str().unwrap_or_default() {
            "VOICE_CHANNEL_SELECT" => return self.load_channel(),
            "VOICE_SETTINGS_UPDATE" => {
                let mut s = self.st.lock().unwrap();
                s.mute = data["mute"].as_bool().unwrap_or(s.mute);
                s.deaf = data["deaf"].as_bool().unwrap_or(s.deaf);
                s.mic_volume = data["input"]["volume"].as_f64().unwrap_or(s.mic_volume);
            }
            "VOICE_STATE_CREATE" | "VOICE_STATE_UPDATE" => {
                let p = person(data);
                let mut s = self.st.lock().unwrap();
                match s.people.iter_mut().find(|x| x.id == p.id) {
                    Some(x) => *x = Person { speaking: x.speaking, ..p },
                    None => s.people.push(p),
                }
            }
            "VOICE_STATE_DELETE" => {
                let id = data["user"]["id"].as_str().unwrap_or_default();
                self.st.lock().unwrap().people.retain(|x| x.id != id);
            }
            e @ ("SPEAKING_START" | "SPEAKING_STOP") => {
                let id = data["user_id"].as_str().unwrap_or_default();
                if let Some(x) = self.st.lock().unwrap().people.iter_mut().find(|x| x.id == id) {
                    x.speaking = e == "SPEAKING_START";
                }
            }
            _ => return Ok(()),
        }
        self.emit();
        Ok(())
    }

    fn run(&mut self, cfg: &mut Config, queue: &Mutex<VecDeque<(String, Value)>>) -> Result<(), String> {
        self.pipe.send(0, &json!({ "v": 1, "client_id": cfg.client_id }))?;
        let (_, ready) = self.pipe.recv()?;
        if ready["evt"] != "READY" {
            return Err(ready["data"]["message"].as_str().unwrap_or("Client ID refuse par Discord").to_string());
        }

        // jeton enregistre, rafraichi, ou nouvelle autorisation dans Discord
        let mut auth = None;
        if let Some(t) = crate::mail::unprotect(&cfg.token) {
            auth = self.pipe.call("AUTHENTICATE", json!({ "access_token": t }), &mut |_| {}).ok();
        }
        if auth.is_none() {
            if let Some(r) = crate::mail::unprotect(&cfg.refresh) {
                if let Ok(t) = exchange(cfg, "refresh_token", &r) {
                    auth = self.pipe.call("AUTHENTICATE", json!({ "access_token": t }), &mut |_| {}).ok();
                }
            }
        }
        if auth.is_none() {
            self.set_status("authorizing", "");
            let data = self
                .pipe
                .call("AUTHORIZE", json!({ "client_id": cfg.client_id, "scopes": SCOPES }), &mut |_| {})
                .map_err(|e| format!("autorisation refusee : {e}"))?;
            let code = data["code"].as_str().ok_or("pas de code d'autorisation")?;
            let t = exchange(cfg, "authorization_code", code)?;
            auth = Some(self.pipe.call("AUTHENTICATE", json!({ "access_token": t }), &mut |_| {})?);
        }
        let auth = auth.unwrap();
        {
            let mut s = self.st.lock().unwrap();
            s.me = auth["user"]["global_name"].as_str().or(auth["user"]["username"].as_str()).unwrap_or_default().into();
            s.me_id = auth["user"]["id"].as_str().unwrap_or_default().into();
        }

        let vs = self.pipe.call("GET_VOICE_SETTINGS", json!({}), &mut |_| {})?;
        {
            let mut s = self.st.lock().unwrap();
            s.mute = vs["mute"].as_bool().unwrap_or(false);
            s.deaf = vs["deaf"].as_bool().unwrap_or(false);
            s.mic_volume = vs["input"]["volume"].as_f64().unwrap_or(100.0);
        }
        self.pipe.command("SUBSCRIBE", json!({}), Some("VOICE_SETTINGS_UPDATE"))?;
        self.pipe.command("SUBSCRIBE", json!({}), Some("VOICE_CHANNEL_SELECT"))?;
        self.load_channel()?;
        self.set_status("ready", "");

        let mut seen = COMMANDS.seq();
        loop {
            // commandes de l'interface
            let todo: Vec<_> = queue.lock().unwrap().drain(..).collect();
            for (cmd, args) in todo {
                if cmd == "reset" {
                    return Ok(());
                }
                self.pipe.command(&cmd, args, None)?;
            }
            // messages de Discord
            while self.pipe.pending()? > 0 {
                let (_, v) = self.pipe.recv()?;
                if v["evt"] == "ERROR" {
                    let msg = v["data"]["message"].as_str().unwrap_or_default().to_string();
                    self.set_status("ready", &msg);
                } else if v["cmd"] == "DISPATCH" {
                    self.on_event(&v)?;
                } else if v["cmd"] == "SET_VOICE_SETTINGS" {
                    let mut s = self.st.lock().unwrap();
                    s.mute = v["data"]["mute"].as_bool().unwrap_or(s.mute);
                    s.deaf = v["data"]["deaf"].as_bool().unwrap_or(s.deaf);
                    drop(s);
                    self.emit();
                }
            }
            // en vocal, les evenements (qui parle) arrivent vite ; sinon Discord
            // ecrit rarement, et les commandes de l'interface reveillent la boucle
            if self.channel_id.is_some() {
                std::thread::sleep(Duration::from_millis(60));
            } else {
                seen = COMMANDS.wait(seen, Duration::from_millis(400));
            }
        }
    }
}

/// Boucle de connexion : retente tant que Discord n'est pas lance.
pub fn start(app: AppHandle) {
    std::thread::spawn(move || loop {
        let d = app.state::<Discord>();
        let (st, queue) = (d.state.clone(), d.queue.clone());
        let status = |s: &str, e: &str| {
            let mut x = st.lock().unwrap();
            if x.status != s || x.error != e {
                *x = DiscordState { status: s.into(), error: e.into(), ..Default::default() };
                let _ = app.emit("discord", x.clone());
            }
        };
        // lu avant la configuration : un `discord_setup` juste apres compte
        let seen = COMMANDS.seq();
        let Some(mut cfg) = load() else {
            queue.lock().unwrap().clear();
            status("setup", "");
            // pas encore configure : `discord_setup` reveille la boucle
            COMMANDS.wait(seen, Duration::from_secs(30));
            continue;
        };
        let Some(pipe) = Pipe::open() else {
            queue.lock().unwrap().clear();
            status("closed", "");
            std::thread::sleep(Duration::from_secs(4));
            continue;
        };
        let mut s = Session { pipe, app: &app, st: st.clone(), channel_id: None };
        match s.run(&mut cfg, &queue) {
            Ok(()) => {}
            Err(e) => {
                status("error", &e);
                std::thread::sleep(Duration::from_secs(5));
            }
        }
    });
}

// --------------------------------------------------------------- commandes

pub fn discord_get(st: State<Discord>) -> DiscordState {
    st.state.lock().unwrap().clone()
}

/// Enregistre l'application Discord (Client ID + Secret).
pub fn discord_setup(st: State<Discord>, client_id: String, secret: String) -> Result<(), String> {
    let client_id = client_id.trim().to_string();
    let secret = secret.trim().to_string();
    if client_id.is_empty() || !client_id.chars().all(|c| c.is_ascii_digit()) {
        return Err("le Client ID est un nombre (Application ID)".into());
    }
    if secret.is_empty() {
        return Err("Client Secret manquant".into());
    }
    let secret = crate::mail::protect(&secret).ok_or("chiffrement impossible")?;
    save(&Config { client_id, secret, ..Default::default() });
    st.queue.lock().unwrap().push_back(("reset".into(), Value::Null));
    COMMANDS.notify();
    Ok(())
}

pub fn discord_forget(st: State<Discord>) {
    let _ = std::fs::remove_file(crate::store::data_dir().join("discord.json"));
    st.queue.lock().unwrap().push_back(("reset".into(), Value::Null));
    COMMANDS.notify();
}

/// Son micro / casque (dans Discord).
pub fn discord_self(st: State<Discord>, mute: Option<bool>, deaf: Option<bool>) {
    let mut args = json!({});
    if let Some(m) = mute {
        args["mute"] = json!(m);
    }
    if let Some(d) = deaf {
        args["deaf"] = json!(d);
    }
    st.queue.lock().unwrap().push_back(("SET_VOICE_SETTINGS".into(), args));
    COMMANDS.notify();
}

/// Volume du micro dans Discord (0-100) : Discord ignore le volume
/// « utilisateur » applique a soi-meme, d'ou ce reglage pour sa propre ligne.
pub fn discord_mic(st: State<Discord>, volume: f64) {
    let v = volume.clamp(0.0, 100.0);
    st.state.lock().unwrap().mic_volume = v;
    st.queue.lock().unwrap().push_back(("SET_VOICE_SETTINGS".into(), json!({ "input": { "volume": v } })));
    COMMANDS.notify();
}

/// Volume (0-200) ou sourdine locale d'une personne.
pub fn discord_user(st: State<Discord>, user_id: String, volume: Option<f64>, mute: Option<bool>) {
    {
        let mut s = st.state.lock().unwrap();
        if let Some(p) = s.people.iter_mut().find(|p| p.id == user_id) {
            if let Some(v) = volume {
                p.volume = v;
            }
            if let Some(m) = mute {
                p.mute = m;
            }
        }
    }
    let mut args = json!({ "user_id": user_id });
    if let Some(v) = volume {
        args["volume"] = json!(v.clamp(0.0, 200.0));
    }
    if let Some(m) = mute {
        args["mute"] = json!(m);
    }
    st.queue.lock().unwrap().push_back(("SET_USER_VOICE_SETTINGS".into(), args));
    COMMANDS.notify();
}
