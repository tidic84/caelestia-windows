//! Lecteur multimedia via GSMTC (GlobalSystemMediaTransportControls) :
//! le meme service que le panneau media de Windows (Spotify, navigateurs...).

use base64::Engine;
use serde::Serialize;
use tauri::{AppHandle, Emitter};
use windows::Media::Control::{
    GlobalSystemMediaTransportControlsSession as Session,
    GlobalSystemMediaTransportControlsSessionManager as Manager,
    GlobalSystemMediaTransportControlsSessionPlaybackStatus as Status,
};
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

fn session() -> windows::core::Result<Session> {
    Manager::RequestAsync()?.get()?.GetCurrentSession()
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
    let ctype = if ctype.is_empty() { "image/png".into() } else { ctype };
    Ok(format!(
        "data:{ctype};base64,{}",
        base64::engine::general_purpose::STANDARD.encode(buf)
    ))
}

/// Boucle de surveillance : emet `media` a chaque changement et `media-art`
/// quand la piece change (la pochette n'est relue qu'a ce moment-la).
pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        crate::com_init_mta();
        let mut last = MediaInfo::default();
        let mut last_key = String::new();
        let mut tick = 0u32;
        loop {
            let info = session().and_then(|s| read(&s).map(|i| (s, i)));
            let info = match info {
                Ok((s, i)) => {
                    let key = format!("{}\u{1}{}\u{1}{}", i.title, i.artist, i.album);
                    if key != last_key {
                        // certaines applis publient la pochette avec un temps de retard
                        std::thread::sleep(std::time::Duration::from_millis(300));
                        let _ = app.emit("media-art", art(&s).unwrap_or_default());
                        last_key = key;
                    }
                    i
                }
                Err(_) => {
                    if !last_key.is_empty() {
                        let _ = app.emit("media-art", String::new());
                        last_key.clear();
                    }
                    MediaInfo::default()
                }
            };
            // la position avance toute seule : on renvoie quand meme toutes les 2 s
            if info != last || tick % 4 == 0 {
                let _ = app.emit("media", &info);
                last = info;
            }
            tick = tick.wrapping_add(1);
            std::thread::sleep(std::time::Duration::from_millis(500));
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
