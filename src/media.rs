//! Lecteur multimedia via GSMTC (GlobalSystemMediaTransportControls) :
//! le meme service que le panneau media de Windows (Spotify, navigateurs...).

use std::sync::{mpsc, Mutex};
use std::time::{Duration, Instant};

use serde::Serialize;
use tauri::{AppHandle, Emitter};
use windows::Media::Control::{
    GlobalSystemMediaTransportControlsSession as Session,
    GlobalSystemMediaTransportControlsSessionManager as Manager,
    GlobalSystemMediaTransportControlsSessionPlaybackStatus as Status,
};
use windows::Foundation::TypedEventHandler;
use windows::Storage::Streams::DataReader;

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

/// Le gestionnaire GSMTC, cree une fois : le redemander a chaque releve
/// coutait un appel inter-processus asynchrone toutes les 500 ms.
fn manager() -> windows::core::Result<Manager> {
    static M: Mutex<Option<Manager>> = Mutex::new(None);
    let mut m = M.lock().unwrap();
    if let Some(m) = m.as_ref() {
        return Ok(m.clone());
    }
    let got = Manager::RequestAsync()?.get()?;
    *m = Some(got.clone());
    Ok(got)
}

fn session() -> windows::core::Result<Session> {
    manager()?.GetCurrentSession()
}

fn now_ticks() -> i64 {
    let d = std::time::SystemTime::now()
        .duration_since(std::time::UNIX_EPOCH)
        .unwrap_or_default();
    (d.as_nanos() / 100) as i64 + EPOCH_DIFF
}

fn read(s: &Session) -> windows::core::Result<MediaInfo> {
    let props = s.TryGetMediaPropertiesAsync()?.get()?;
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
    let props = s.TryGetMediaPropertiesAsync()?.get()?;
    let stream = props.Thumbnail()?.OpenReadAsync()?.get()?;
    let size = stream.Size()? as u32;
    let ctype = stream.ContentType()?.to_string();
    let reader = DataReader::CreateDataReader(&stream)?;
    reader.LoadAsync(size)?.get()?;
    let mut buf = vec![0u8; size as usize];
    reader.ReadBytes(&mut buf)?;
    Ok(crate::img::url(crate::img::mime(&ctype), buf))
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
        if let Ok(m) = manager() {
            let tx = tx.clone();
            let _ = m.CurrentSessionChanged(&TypedEventHandler::new(move |_, _| {
                let _ = tx.send(());
                Ok(())
            }));
        }
        let mut subs: Option<Subs> = None;
        let mut last = MediaInfo::default();
        let mut last_at = Instant::now();
        let mut last_key = String::new();
        let mut first = true;
        loop {
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

#[tauri::command(async)]
pub fn media_get() -> MediaInfo {
    crate::com_init_mta();
    session().and_then(|s| read(&s)).unwrap_or_default()
}

#[tauri::command(async)]
pub fn media_art() -> String {
    crate::com_init_mta();
    session().and_then(|s| art(&s)).unwrap_or_default()
}

#[tauri::command(async)]
pub fn media_action(action: String, value: Option<f64>) {
    crate::com_init_mta();
    let Ok(s) = session() else { return };
    let r = match action.as_str() {
        "toggle" => s.TryTogglePlayPauseAsync().and_then(|o| o.get()),
        "next" => s.TrySkipNextAsync().and_then(|o| o.get()),
        "prev" => s.TrySkipPreviousAsync().and_then(|o| o.get()),
        "seek" => s
            .TryChangePlaybackPositionAsync((value.unwrap_or(0.0) * TICKS) as i64)
            .and_then(|o| o.get()),
        _ => return,
    };
    let _ = r;
}
