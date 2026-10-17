//! Lecteur multimedia via GSMTC (GlobalSystemMediaTransportControls) :
//! le meme service que le panneau media de Windows (Spotify, navigateurs...).

use std::sync::{mpsc, Mutex};
use std::time::{Duration, Instant};

use serde::Serialize;
use crate::host::{AppHandle};
use windows::Media::Control::{
    GlobalSystemMediaTransportControlsSession as Session,
    GlobalSystemMediaTransportControlsSessionManager as Manager,
    GlobalSystemMediaTransportControlsSessionPlaybackStatus as Status,
};
use windows::Foundation::TypedEventHandler;
use windows::Storage::Streams::DataReader;
use windows_core::Interface;

#[derive(Serialize, Clone, Default, PartialEq)]
pub struct MediaInfo {
    pub has: bool,
    pub title: String,
    pub artist: String,
    pub album: String,
    pub app: String,
    pub playing: bool,
    /// secondes
    pub position: f64,
    pub duration: f64,
}

/// Unites WinRT : 100 ns.
const TICKS: f64 = 10_000_000.0;
/// Ecart entre l'epoque WinRT (1601) et l'epoque Unix, en ticks.
const EPOCH_DIFF: i64 = 116_444_736_000_000_000;

/// Delai maximal d'un appel au service media (NPSMSvc) ou a l'appli qui joue
const WAIT_MS: u64 = 3000;

/// Le gestionnaire GSMTC, cree une fois : le redemander a chaque releve
/// coutait un appel inter-processus asynchrone toutes les 500 ms.
static MANAGER: Mutex<Option<(Manager, Instant)>> = Mutex::new(None);

/// Sans session, un gestionnaire dont le service a redemarre ne renvoie
/// aucune erreur (il repond depuis son etat local) : on le renouvelle au
/// plus toutes les 30 s tant que rien ne joue.
const RENEW_IDLE: Duration = Duration::from_secs(30);

fn manager() -> windows::core::Result<Manager> {
    let mut m = MANAGER.lock().unwrap();
    if let Some((m, _)) = m.as_ref() {
        return Ok(m.clone());
    }
    let got = crate::wait(Manager::RequestAsync()?, WAIT_MS)?;
    *m = Some((got.clone(), Instant::now()));
    Ok(got)
}

/// Oublie le gestionnaire si le service media a redemarre (connexion
/// perdue), ne repond plus, ou si rien ne joue depuis `RENEW_IDLE` : le
/// prochain appel se reconnecte.
fn lost(e: &windows::core::Error) {
    const DEAD: [u32; 4] = [
        0x8001_0108, // RPC_E_DISCONNECTED
        0x8007_06BA, // RPC_S_SERVER_UNAVAILABLE
        0x8007_06BE, // RPC_S_CALL_FAILED
        0x8007_05B4, // delai depasse (crate::wait)
    ];
    let mut m = MANAGER.lock().unwrap();
    let dead = DEAD.contains(&(e.code().0 as u32));
    // erreur vide : pas de session en cours
    let idle = e.code().is_ok() && m.as_ref().is_some_and(|(_, at)| at.elapsed() > RENEW_IDLE);
    if dead || idle {
        *m = None;
    }
}

fn session() -> windows::core::Result<Session> {
    manager()?.GetCurrentSession().inspect_err(lost)
}

fn now_ticks() -> i64 {
    let d = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    (d.as_nanos() / 100) as i64 + EPOCH_DIFF
}

fn read(s: &Session) -> windows::core::Result<MediaInfo> {
    read_props(s).inspect_err(lost)
}

fn read_props(s: &Session) -> windows::core::Result<MediaInfo> {
    let props = crate::wait(s.TryGetMediaPropertiesAsync()?, WAIT_MS)?;
    let playing = s.GetPlaybackInfo()?.PlaybackStatus()? == Status::Playing;
    let tl = s.GetTimelineProperties()?;
    let duration = (tl.EndTime()?.Duration - tl.StartTime()?.Duration) as f64 / TICKS;
    let mut position = tl.Position()?.Duration as f64 / TICKS;
    // La position n'est mise a jour que ponctuellement par l'application :
    // on extrapole depuis le dernier releve.
    if playing {
        let since = (now_ticks() - tl.LastUpdatedTime()?.UniversalTime) as f64 / TICKS;
        if since > 0.0 && since < 3600.0 {
            position += since;
        }
    }
    if duration > 0.0 {
        position = position.clamp(0.0, duration);
    }
    let app = s.SourceAppUserModelId()?.to_string();
    let app = app
        .rsplit(['\\', '!'])
        .next()
        .unwrap_or(&app)
        .trim_end_matches(".exe")
        .to_string();
    Ok(MediaInfo {
        has: true,
        title: props.Title()?.to_string(),
        artist: props.Artist()?.to_string(),
        album: props.AlbumTitle()?.to_string(),
        app,
        playing,
        position,
        duration,
    })
}

fn art(s: &Session) -> windows::core::Result<String> {
    art_bytes(s).inspect_err(lost)
}

fn art_bytes(s: &Session) -> windows::core::Result<String> {
    let props = crate::wait(s.TryGetMediaPropertiesAsync()?, WAIT_MS)?;
    let stream = crate::wait(props.Thumbnail()?.OpenReadAsync()?, WAIT_MS)?;
    let size = stream.Size()? as u32;
    let ctype = stream.ContentType()?.to_string();
    let reader = DataReader::CreateDataReader(&stream)?;
    crate::wait(reader.LoadAsync(size)?.cast::<windows_future::IAsyncOperation<u32>>()?, WAIT_MS)?;
    let mut buf = vec![0u8; size as usize];
    reader.ReadBytes(&mut buf)?;
    Ok(crate::img::ART.url(crate::img::mime(&ctype), buf))
}

/// Meme piece, meme etat : seule la position differe (elle avance toute seule
/// et l'interface l'extrapole).
fn same_but_position(a: &MediaInfo, b: &MediaInfo) -> bool {
    MediaInfo { position: 0.0, ..a.clone() } == MediaInfo { position: 0.0, ..b.clone() }
}

/// Gestionnaire d'evenement qui reveille la boucle de `watch`
fn ping<A: windows::core::RuntimeType + 'static>(tx: mpsc::Sender<()>) -> TypedEventHandler<Session, A> {
    TypedEventHandler::new(move |_, _| {
        let _ = tx.send(());
        Ok(())
    })
}

/// Abonnements aux evenements de la session suivie
struct Subs {
    session: Session,
    tokens: [i64; 3],
}

impl Subs {
    fn new(session: Session, tx: &mpsc::Sender<()>) -> Self {
        let tokens = [
            session.PlaybackInfoChanged(&ping(tx.clone())).unwrap_or_default(),
            session.MediaPropertiesChanged(&ping(tx.clone())).unwrap_or_default(),
            session.TimelinePropertiesChanged(&ping(tx.clone())).unwrap_or_default(),
        ];
        Subs { session, tokens }
    }
}

impl Drop for Subs {
    fn drop(&mut self) {
        let _ = self.session.RemovePlaybackInfoChanged(self.tokens[0]);
        let _ = self.session.RemoveMediaPropertiesChanged(self.tokens[1]);
        let _ = self.session.RemoveTimelinePropertiesChanged(self.tokens[2]);
    }
}

/// Boucle de surveillance : emet `media` a chaque changement et `media-art`
/// quand la piece change (la pochette n'est relue qu'a ce moment-la). Elle
/// est reveillee par les evenements GSMTC ; un releve toutes les 1 s en
/// lecture (5 s sinon) rattrape les applis qui ne les envoient pas.
pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        crate::com_init_mta();
        let (tx, rx) = mpsc::channel::<()>();
        // gestionnaire suivi (il change si le service media redemarre)
        let mut watched: Option<Manager> = None;
        let mut subs: Option<Subs> = None;
        let mut last = MediaInfo::default();
        let mut last_at = Instant::now();
        let mut last_key = String::new();
        let mut first = true;
        loop {
            if let Ok(m) = manager() {
                if watched.as_ref() != Some(&m) {
                    let tx = tx.clone();
                    let _ = m.CurrentSessionChanged(&TypedEventHandler::new(move |_, _| {
                        let _ = tx.send(());
                        Ok(())
                    }));
                    watched = Some(m);
                }
            }
            let cur = session().ok();
            if cur.as_ref() != subs.as_ref().map(|s| &s.session) {
                subs = cur.clone().map(|s| Subs::new(s, &tx));
            }
            let info = cur.as_ref().map(|s| read(s).map(|i| (s, i)));
            let info = match info {
                Some(Ok((s, i))) => {
                    let key = format!("{}\u{1}{}\u{1}{}", i.title, i.artist, i.album);
                    if key != last_key {
                        // certaines applis publient la pochette avec un temps de retard
                        std::thread::sleep(Duration::from_millis(300));
                        let _ = app.emit("media-art", art(s).unwrap_or_default());
                        last_key = key;
                    }
                    i
                }
                _ => {
                    if !last_key.is_empty() {
                        let _ = app.emit("media-art", String::new());
                        last_key.clear();
                    }
                    MediaInfo::default()
                }
            };
            // position attendue si la lecture a simplement continue
            let expected = last.position + if last.playing { last_at.elapsed().as_secs_f64() } else { 0.0 };
            if first || !same_but_position(&info, &last) || (info.position - expected).abs() > 1.5 {
                let _ = app.emit("media", &info);
                last = info;
                last_at = Instant::now();
                first = false;
            }
            let wait = Duration::from_secs(if last.playing { 1 } else { 5 });
            if rx.recv_timeout(wait).is_ok() {
                // plusieurs evenements arrivent souvent ensemble
                std::thread::sleep(Duration::from_millis(50));
                while rx.try_recv().is_ok() {}
            }
        }
    });
}

/// Diagnostic (`--check-media`) : `ok` ou l'erreur de la session / lecture.
pub fn diag() -> String {
    match session() {
        Ok(s) => match read(&s) {
            Ok(_) => "ok".into(),
            Err(e) => format!("read {:?}", e.code()),
        },
        Err(e) => format!("session {:?}", e.code()),
    }
}

pub fn media_get() -> MediaInfo {
    crate::com_init_mta();
    session().and_then(|s| read(&s)).unwrap_or_default()
}

pub fn media_art() -> String {
    crate::com_init_mta();
    session().and_then(|s| art(&s)).unwrap_or_default()
}

pub fn media_action(action: String, value: Option<f64>) {
    crate::com_init_mta();
    let Ok(s) = session() else { return };
    let r = match action.as_str() {
        "toggle" => s.TryTogglePlayPauseAsync().and_then(|o| crate::wait(o, WAIT_MS)),
        "next" => s.TrySkipNextAsync().and_then(|o| crate::wait(o, WAIT_MS)),
        "prev" => s.TrySkipPreviousAsync().and_then(|o| crate::wait(o, WAIT_MS)),
        "seek" => s
            .TryChangePlaybackPositionAsync((value.unwrap_or(0.0) * TICKS) as i64)
            .and_then(|o| crate::wait(o, WAIT_MS)),
        _ => return,
    };
    if let Err(e) = r {
        lost(&e);
    }
}
