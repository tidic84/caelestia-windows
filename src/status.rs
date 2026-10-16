//! Etat des services (onglet PC) : page d'etat officielle quand elle existe
//! (Statuspage : Discord, Spotify, Epic, Claude) et test de connexion depuis
//! ce PC. On distingue ainsi « panne chez eux » et « probleme de ton cote ».
//! Releve toutes les 3 min (addon PC active), envoye a l'interface (`services`).

use std::sync::Mutex;
use std::time::{Duration, Instant};

use serde::Serialize;
use crate::host::AppHandle;

struct Svc {
    id: &'static str,
    name: &'static str,
    /// page d'etat Statuspage (api/v2/status.json), vide si aucune
    status: &'static str,
    /// adresse testee depuis le PC
    probe: &'static str,
    /// page ouverte au clic
    page: &'static str,
}

const SERVICES: &[Svc] = &[
    Svc { id: "discord", name: "Discord", status: "https://discordstatus.com/api/v2/status.json", probe: "https://discord.com/api/v10/gateway", page: "https://discordstatus.com" },
    Svc { id: "steam", name: "Steam", status: "", probe: "https://api.steampowered.com/ISteamWebAPIUtil/GetServerInfo/v1/", page: "https://steamstat.us" },
    Svc { id: "ea", name: "EA / Apex", status: "", probe: "https://accounts.ea.com/connect/auth", page: "https://apexlegendsstatus.com" },
    Svc { id: "spotify", name: "Spotify", status: "https://spotify.statuspage.io/api/v2/status.json", probe: "https://api.spotify.com/v1", page: "https://spotify.statuspage.io" },
    Svc { id: "epic", name: "Epic Games", status: "https://status.epicgames.com/api/v2/status.json", probe: "https://store.epicgames.com", page: "https://status.epicgames.com" },
    Svc { id: "roblox", name: "Roblox", status: "", probe: "https://www.roblox.com", page: "https://status.roblox.com" },
    Svc { id: "claude", name: "Claude", status: "https://status.claude.com/api/v2/status.json", probe: "https://claude.ai", page: "https://status.claude.com" },
];

#[derive(Serialize, Clone)]
pub struct Service {
    id: &'static str,
    name: &'static str,
    page: &'static str,
    /// indicateur officiel : none / minor / major / critical / maintenance, vide si inconnu
    official: String,
    /// texte officiel (« All Systems Operational »...)
    desc: String,
    /// temps de reponse depuis le PC en ms, None si injoignable
    ms: Option<u32>,
}

/// Le serveur a repondu, meme par une erreur 4xx : il est joignable.
/// Une erreur 5xx ou une coupure compte comme injoignable.
fn probe(url: &str) -> Option<u32> {
    let t = Instant::now();
    let r = crate::http().get(url).timeout(Duration::from_secs(8)).call();
    let ok = match r {
        Ok(_) => true,
        Err(ureq::Error::Status(code, _)) => code < 500,
        Err(_) => false,
    };
    ok.then(|| t.elapsed().as_millis() as u32)
}

fn official(url: &str) -> (String, String) {
    if url.is_empty() {
        return Default::default();
    }
    let v: Option<serde_json::Value> =
        crate::http().get(url).timeout(Duration::from_secs(8)).call().ok().and_then(|r| r.into_json().ok());
    let Some(v) = v else { return Default::default() };
    (
        v["status"]["indicator"].as_str().unwrap_or_default().to_string(),
        v["status"]["description"].as_str().unwrap_or_default().to_string(),
    )
}

fn check_all() -> Vec<Service> {
    std::thread::scope(|s| {
        let hs: Vec<_> = SERVICES
            .iter()
            .map(|svc| {
                s.spawn(move || {
                    let (official, desc) = official(svc.status);
                    // deuxieme essai avant de declarer un service injoignable
                    let ms = probe(svc.probe).or_else(|| probe(svc.probe));
                    Service { id: svc.id, name: svc.name, page: svc.page, official, desc, ms }
                })
            })
            .collect();
        hs.into_iter().filter_map(|h| h.join().ok()).collect()
    })
}

static LAST: Mutex<Option<(Instant, Vec<Service>)>> = Mutex::new(None);

/// Dernier releve ; `fresh` force un nouveau test (bouton Actualiser).
pub fn services_get(app: AppHandle, fresh: Option<bool>) -> Vec<Service> {
    if !fresh.unwrap_or(false) {
        if let Some((t, v)) = &*LAST.lock().unwrap() {
            if t.elapsed() < Duration::from_secs(180) {
                return v.clone();
            }
        }
    }
    let v = check_all();
    *LAST.lock().unwrap() = Some((Instant::now(), v.clone()));
    let _ = app.emit("services", &v);
    v
}

pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(20));
        loop {
            // addon PC desactive : pas de releve
            if crate::settings::addon_on(&app, "pc") {
                let v = check_all();
                *LAST.lock().unwrap() = Some((Instant::now(), v.clone()));
                let _ = app.emit("services", &v);
            }
            std::thread::sleep(Duration::from_secs(180));
        }
    });
}
