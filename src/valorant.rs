//! Valorant (evenement `valorant`, null quand le jeu est ferme) : file
//! d'attente, partie trouvee et temps restant de la selection des agents.
//!
//! Le client Riot ouvre une API locale (HTTPS sur 127.0.0.1, certificat a lui)
//! dont le port et le mot de passe sont dans son fichier `lockfile`. La
//! presence du joueur (chat/v4/presences) dit ou il en est : menus, file
//! d'attente, partie trouvee, selection des agents, en jeu. Le temps restant
//! de la selection, la carte et les agents choisis viennent des serveurs de
//! Riot (pregame/v1), avec le jeton que donne l'API locale ; adresse des
//! serveurs (glz-<region>-1.<shard>.a.pvp.net) et version du client relevees
//! dans le journal du jeu (ShooterGame.log).

use std::collections::HashMap;
use std::path::PathBuf;
use std::sync::Arc;
use std::time::{Duration, Instant, SystemTime, UNIX_EPOCH};

use base64::Engine;
use serde::Serialize;
use serde_json::Value;
use sysinfo::{ProcessRefreshKind, ProcessesToUpdate, System};

use windows::core::PWSTR;
use windows::Win32::Foundation::CloseHandle;
use windows::Win32::System::Threading::{OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION};
use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId};

use crate::host::AppHandle;

/// Plateforme annoncee aux serveurs de Riot (JSON en base64, comme le client).
const PLATFORM: &str = "ew0KCSJwbGF0Zm9ybVR5cGUiOiAiUEMiLA0KCSJwbGF0Zm9ybU9TIjogIldpbmRvd3MiLA0KCSJwbGF0Zm9ybU9TVmVyc2lvbiI6ICIxMC4wLjE5MDQyLjEuMjU2LjY0Yml0IiwNCgkicGxhdGZvcm1DaGlwc2V0IjogIlVua25vd24iDQp9";
/// Duree habituelle de la selection des agents, si les serveurs ne repondent pas.
const PICK_SECS: u64 = 80;
const EXE: &str = "VALORANT-Win64-Shipping.exe";

#[derive(Serialize, Clone, Default, PartialEq)]
pub struct Valo {
    /// menus, queue (file d'attente), found (partie trouvee), pregame
    /// (selection des agents), ingame
    phase: String,
    /// competitive, unrated, swiftplay... (vide : partie personnalisee)
    queue: String,
    /// nom de la carte (vide : inconnue)
    map: String,
    /// entree dans la file d'attente, ms depuis 1970 (0 = hors file)
    queue_since: u64,
    /// selection des agents : debut et fin, ms depuis 1970 (0 = inconnue)
    start: u64,
    ends: u64,
    /// fin relevee aupres des serveurs de Riot (sinon estimee)
    exact: bool,
    /// selection terminee (tout le monde a verrouille, chargement)
    done: bool,
    /// agent choisi par le joueur, son icone, verrouille ou non
    agent: String,
    agent_icon: String,
    locked: bool,
    /// allies (joueur compris) et allies ayant verrouille
    allies: u32,
    allies_locked: u32,
    /// le joueur est sur une autre fenetre que Valorant
    away: bool,
}

fn now_ms() -> u64 {
    SystemTime::now().duration_since(UNIX_EPOCH).map_or(0, |d| d.as_millis() as u64)
}

fn local_dir() -> PathBuf {
    PathBuf::from(std::env::var_os("LOCALAPPDATA").unwrap_or_default())
}

/// Fenetre au premier plan : celle de Valorant ?
fn in_game() -> bool {
    unsafe {
        let mut pid = 0u32;
        GetWindowThreadProcessId(GetForegroundWindow(), Some(&mut pid));
        let Ok(h) = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid) else { return false };
        let mut buf = [0u16; 512];
        let mut len = buf.len() as u32;
        let ok = QueryFullProcessImageNameW(h, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &mut len).is_ok();
        let _ = CloseHandle(h);
        ok && String::from_utf16_lossy(&buf[..len as usize]).to_lowercase().ends_with(&EXE.to_lowercase())
    }
}

// ------------------------------------------------------ API locale

struct Local {
    port: u16,
    auth: String,
    agent: ureq::Agent,
}

impl Local {
    /// « Riot Client:pid:port:motdepasse:https »
    fn open(lockfile: &str) -> Option<Local> {
        let f: Vec<&str> = lockfile.trim().split(':').collect();
        let port = f.get(2)?.parse().ok()?;
        let pass = f.get(3)?;
        // certificat du client Riot, pour 127.0.0.1 seulement
        let tls = native_tls::TlsConnector::builder()
            .danger_accept_invalid_certs(true)
            .danger_accept_invalid_hostnames(true)
            .build()
            .ok()?;
        let agent = ureq::AgentBuilder::new()
            .tls_connector(Arc::new(tls))
            .timeout_connect(Duration::from_secs(2))
            .timeout(Duration::from_secs(4))
            .build();
        let auth = format!("Basic {}", base64::engine::general_purpose::STANDARD.encode(format!("riot:{pass}")));
        Some(Local { port, auth, agent })
    }

    fn get(&self, path: &str) -> Option<Value> {
        self.agent
            .get(&format!("https://127.0.0.1:{}{path}", self.port))
            .set("Authorization", &self.auth)
            .call()
            .ok()?
            .into_json()
            .ok()
    }
}

/// Jetons du joueur connecte : (puuid, jeton d'acces, jeton des droits)
fn tokens(l: &Local) -> Option<(String, String, String)> {
    let v = l.get("/entitlements/v1/token")?;
    let s = |k: &str| v[k].as_str().filter(|s| !s.is_empty()).map(str::to_string);
    Some((s("subject")?, s("accessToken")?, s("token")?))
}

/// Cherche une cle n'importe ou dans la presence : selon les versions du
/// client, elle est a la racine ou dans matchPresenceData / partyPresenceData.
fn find<'a>(v: &'a Value, key: &str) -> Option<&'a Value> {
    let o = v.as_object()?;
    if let Some(x) = o.get(key) {
        return Some(x);
    }
    o.values().find_map(|x| find(x, key))
}

fn find_str(v: &Value, key: &str) -> String {
    find(v, key).and_then(Value::as_str).unwrap_or("").to_string()
}

/// Presence Valorant du joueur, decodee (champ `private` en base64).
fn presence(l: &Local, puuid: &str) -> Option<Value> {
    let v = l.get("/chat/v4/presences")?;
    let p = v["presences"].as_array()?.iter().find(|p| p["puuid"] == puuid && p["product"] == "valorant")?;
    let raw = base64::engine::general_purpose::STANDARD.decode(p["private"].as_str()?).ok()?;
    serde_json::from_slice(&raw).ok()
}

// --------------------------------------------- serveurs de Riot

struct Glz {
    /// https://glz-eu-1.eu.a.pvp.net
    base: String,
    version: String,
}

/// Adresse des serveurs et version du client, dans le journal du jeu.
fn glz_from_log() -> Option<Glz> {
    let log = std::fs::read(local_dir().join(r"VALORANT\Saved\Logs\ShooterGame.log")).ok()?;
    let log = String::from_utf8_lossy(&log);
    let i = log.rfind("https://glz-")?;
    let end = log[i..].find(".a.pvp.net")?;
    let base = log[i..i + end + 10].to_string();
    // « CI server version: release-09.08-shipping-14-2876436 »
    let version = log
        .rfind("CI server version: ")
        .and_then(|j| log[j + 19..].split_whitespace().next())
        .unwrap_or("")
        .to_string();
    (!base.contains(char::is_whitespace)).then_some(Glz { base, version })
}

/// Noms (francais) et icones des agents, noms des cartes (valorant-api.com).
#[derive(Default)]
struct Names {
    agents: HashMap<String, (String, String)>,
    maps: HashMap<String, String>,
    version: String,
}

fn names() -> Option<Names> {
    let http = crate::http();
    let get = |url: &str| -> Option<Value> { http.get(url).timeout(Duration::from_secs(8)).call().ok()?.into_json().ok() };
    let mut n = Names::default();
    let agents = get("https://valorant-api.com/v1/agents?isPlayableCharacter=true&language=fr-FR")?;
    for a in agents["data"].as_array()? {
        let (Some(id), Some(name)) = (a["uuid"].as_str(), a["displayName"].as_str()) else { continue };
        n.agents.insert(id.to_lowercase(), (name.to_string(), a["displayIcon"].as_str().unwrap_or("").to_string()));
    }
    if let Some(maps) = get("https://valorant-api.com/v1/maps?language=fr-FR") {
        for m in maps["data"].as_array().into_iter().flatten() {
            let (Some(url), Some(name)) = (m["mapUrl"].as_str(), m["displayName"].as_str()) else { continue };
            n.maps.insert(url.to_lowercase(), name.to_string());
        }
    }
    if let Some(v) = get("https://valorant-api.com/v1/version") {
        n.version = v["data"]["riotClientVersion"].as_str().unwrap_or("").to_string();
    }
    Some(n)
}

/// « /Game/Maps/Ascent/Ascent » -> « Ascent » (nom officiel s'il est connu)
fn map_name(names: Option<&Names>, path: &str) -> String {
    if path.is_empty() {
        return String::new();
    }
    if let Some(n) = names.and_then(|n| n.maps.get(&path.to_lowercase())) {
        return n.clone();
    }
    path.rsplit('/').next().unwrap_or(path).to_string()
}

// ------------------------------------------------------------ suivi

#[derive(Default)]
struct Watcher {
    lock: String,
    local: Option<Local>,
    puuid: String,
    glz: Option<Glz>,
    glz_at: Option<Instant>,
    names: Option<Names>,
    names_at: Option<Instant>,
    match_id: String,
    remote_at: Option<Instant>,
    phase: String,
    queue_since: u64,
    /// derniers releves de la selection des agents
    pick: Valo,
}

impl Watcher {
    fn reset(&mut self) {
        *self = Watcher { names: self.names.take(), names_at: self.names_at, ..Default::default() };
    }

    /// Etat actuel et delai avant le prochain releve.
    fn tick(&mut self) -> (Option<Valo>, Duration) {
        let Ok(lock) = std::fs::read_to_string(local_dir().join(r"Riot Games\Riot Client\Config\lockfile")) else {
            self.reset();
            return (None, Duration::from_secs(5));
        };
        if lock != self.lock || self.local.is_none() {
            self.reset();
            self.local = Local::open(&lock);
            self.lock = lock;
        }
        let Some(local) = self.local.as_ref() else { return (None, Duration::from_secs(5)) };
        if self.puuid.is_empty() {
            match tokens(local) {
                Some((p, _, _)) => self.puuid = p,
                None => return (None, Duration::from_secs(5)),
            }
        }
        let Some(p) = presence(local, &self.puuid) else {
            // client Riot ouvert, Valorant ferme
            self.glz = None;
            self.phase.clear();
            return (None, Duration::from_secs(4));
        };
        let loop_state = find_str(&p, "sessionLoopState");
        let party = find_str(&p, "partyState");
        let phase = match loop_state.as_str() {
            "INGAME" => "ingame",
            "PREGAME" => "pregame",
            _ if party == "MATCHMAKING" => "queue",
            _ if party == "MATCHMADE_GAME_STARTING" => "found",
            _ => "menus",
        };
        if phase == "queue" && self.phase != "queue" {
            self.queue_since = now_ms();
        } else if phase != "queue" {
            self.queue_since = 0;
        }
        if phase != "pregame" {
            self.match_id.clear();
            self.remote_at = None;
            self.pick = Valo::default();
        } else if self.phase != "pregame" {
            self.pick.start = now_ms();
        }
        self.phase = phase.to_string();

        // noms des agents et des cartes : une fois, des que la partie approche
        if self.names.is_none()
            && matches!(phase, "queue" | "found" | "pregame")
            && self.names_at.is_none_or(|t| t.elapsed() > Duration::from_secs(60))
        {
            self.names_at = Some(Instant::now());
            self.names = names();
        }
        if phase == "pregame" && self.remote_at.is_none_or(|t| t.elapsed() >= Duration::from_millis(1900)) {
            self.remote_at = Some(Instant::now());
            // serveurs injoignables : fin estimee
            let _ = self.pregame();
        }

        let mut v = if phase == "pregame" { self.pick.clone() } else { Valo::default() };
        v.phase = phase.to_string();
        v.queue = if v.queue.is_empty() { find_str(&p, "queueId") } else { v.queue };
        if v.map.is_empty() {
            v.map = map_name(self.names.as_ref(), &find_str(&p, "matchMap"));
        }
        v.queue_since = self.queue_since;
        v.away = !in_game();
        if phase == "pregame" && !v.exact {
            // fin estimee : duree habituelle de la selection
            v.ends = v.start + PICK_SECS * 1000;
        }
        let wait = match phase {
            "queue" | "found" | "pregame" => 1,
            "ingame" => 5,
            _ => 2,
        };
        (Some(v), Duration::from_secs(wait))
    }

    /// Releve la selection des agents aupres des serveurs de Riot.
    fn pregame(&mut self) -> Option<()> {
        // journal relu de temps en temps tant que l'adresse n'y est pas
        if self.glz.is_none() && self.glz_at.is_none_or(|t| t.elapsed() > Duration::from_secs(15)) {
            self.glz_at = Some(Instant::now());
            self.glz = glz_from_log();
        }
        let glz = self.glz.as_ref()?;
        let (puuid, access, ent) = tokens(self.local.as_ref()?)?;
        let version = if glz.version.is_empty() { self.names.as_ref().map_or("", |n| n.version.as_str()) } else { &glz.version };
        let http = crate::http();
        let get = |path: &str| -> Option<Value> {
            http.get(&format!("{}{path}", glz.base))
                .set("Authorization", &format!("Bearer {access}"))
                .set("X-Riot-Entitlements-JWT", &ent)
                .set("X-Riot-ClientPlatform", PLATFORM)
                .set("X-Riot-ClientVersion", version)
                .timeout(Duration::from_secs(4))
                .call()
                .ok()?
                .into_json()
                .ok()
        };
        if self.match_id.is_empty() {
            let v = get(&format!("/pregame/v1/players/{puuid}"))?;
            self.match_id = v["MatchID"].as_str().filter(|s| !s.is_empty())?.to_string();
        }
        let m = get(&format!("/pregame/v1/matches/{}", self.match_id))?;
        // equipe du joueur : AllyTeam, ou celle qui le contient
        let players = m["AllyTeam"]["Players"].as_array().cloned().or_else(|| {
            m["Teams"].as_array()?.iter().find_map(|t| {
                let pl = t["Players"].as_array()?;
                pl.iter().any(|x| x["Subject"] == puuid).then(|| pl.clone())
            })
        });
        let players = players.unwrap_or_default();
        let me = players.iter().find(|x| x["Subject"] == puuid);
        let pick = &mut self.pick;
        let agent_id = me.and_then(|x| x["CharacterID"].as_str()).unwrap_or("").to_lowercase();
        let (agent, icon) = self
            .names
            .as_ref()
            .and_then(|n| n.agents.get(&agent_id))
            .cloned()
            .unwrap_or_else(|| (if agent_id.is_empty() { String::new() } else { "Agent".into() }, String::new()));
        pick.agent = agent;
        pick.agent_icon = icon;
        pick.locked = me.is_some_and(|x| x["CharacterSelectionState"] == "locked");
        pick.allies = players.len() as u32;
        pick.allies_locked = players.iter().filter(|x| x["CharacterSelectionState"] == "locked").count() as u32;
        pick.done = m["PregameState"].as_str().is_some_and(|s| s != "character_select_active");
        pick.queue = m["QueueID"].as_str().unwrap_or("").to_string();
        pick.map = map_name(self.names.as_ref(), m["MapID"].as_str().unwrap_or(""));
        if let Some(ns) = m["PhaseTimeRemainingNS"].as_i64() {
            let ends = now_ms() + (ns.max(0) / 1_000_000) as u64;
            // fin stable d'un releve a l'autre (pas d'evenement pour quelques ms)
            if !pick.exact || pick.ends.abs_diff(ends) > 1500 {
                pick.ends = ends;
            }
            pick.exact = true;
        }
        Some(())
    }
}

fn enabled(app: &AppHandle) -> bool {
    let st = app.state::<crate::settings::Settings>();
    let cfg = st.0.lock().unwrap();
    cfg.extra.get("valorant").and_then(Value::as_bool).unwrap_or(true)
}

pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        let mut w = Watcher::default();
        let mut last: Option<Option<Valo>> = None;
        loop {
            let (v, wait) = if enabled(&app) { w.tick() } else { (None, Duration::from_secs(10)) };
            if last.as_ref() != Some(&v) {
                let _ = app.emit("valorant", &v);
                last = Some(v);
            }
            std::thread::sleep(wait);
        }
    });
}

/// Ramene la fenetre de Valorant au premier plan (clic sur « Partie trouvee »).
pub fn valorant_focus() -> bool {
    let mut sys = System::new();
    sys.refresh_processes_specifics(ProcessesToUpdate::All, true, ProcessRefreshKind::nothing());
    let pid = sys.processes().values().find(|p| p.name().eq_ignore_ascii_case(EXE)).map(|p| p.pid().as_u32());
    pid.is_some_and(crate::activity::focus_pid)
}
