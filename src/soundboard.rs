//! Soundboard pour le vocal Discord.
//!
//! Discord ne laisse pas une appli tierce jouer un son dans un salon : on passe
//! donc par un micro virtuel. L'ilot capte le vrai micro, y melange les sons et
//! envoie le tout dans la sortie d'un cable virtuel (Steam Streaming
//! Microphone, Voicemod, VB-CABLE...) ; dans Discord, on choisit le micro
//! correspondant comme peripherique d'entree. Les sons sont aussi joues dans
//! la sortie par defaut (casque) pour qu'on les entende soi-meme.
//!
//! Les sons (mp3, wav, ogg, flac, m4a...) sont decodes ici (symphonia), mis a
//! 48 kHz stereo, normalises, puis enregistres en PCM brut f32
//! (%LOCALAPPDATA%\Ilot\sounds\<id>.pcm).

use std::collections::{HashMap, VecDeque};
use std::path::PathBuf;
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{Arc, Mutex, OnceLock};
use std::time::Duration;

use serde::{Deserialize, Serialize};
use crate::host::AppHandle;
use windows::core::HSTRING;
use windows::Win32::Media::Audio::{
    eCapture, eCommunications, eConsole, eRender, EDataFlow, IAudioCaptureClient, IAudioClient, IAudioRenderClient,
    IMMDevice, IMMDeviceEnumerator, MMDeviceEnumerator, AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM,
    AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY, DEVICE_STATE_ACTIVE, WAVEFORMATEX,
};
use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_ALL};

const RATE: u32 = 48_000;
const CH: usize = 2;
const SILENT: u32 = 2; // AUDCLNT_BUFFERFLAGS_SILENT
/// donnees gardees d'avance dans les sorties (latence ajoutee au micro)
const AHEAD: u32 = RATE / 25; // 40 ms
/// au-dela, le retard du micro est rattrape (horloges des deux cartes son)
const MIC_MAX: usize = RATE as usize / 20 * CH; // 50 ms

#[derive(Serialize, Deserialize, Clone, Default, PartialEq)]
pub struct Config {
    /// actif : le micro passe par l'ilot
    pub on: bool,
    /// sortie du cable virtuel (id de peripherique)
    pub cable: String,
    /// micro reel ; vide = micro par defaut (communications)
    pub mic: String,
    /// sons aussi joues dans la sortie par defaut
    pub monitor: bool,
    /// volume du micro (1 = inchange)
    pub mic_gain: f32,
}

struct Voice {
    id: String,
    pcm: Arc<Vec<f32>>,
    pos: usize,
    vol: f32,
}

#[derive(Default)]
struct Shared {
    cfg: Mutex<Config>,
    voices: Mutex<Vec<Voice>>,
    cache: Mutex<HashMap<String, Arc<Vec<f32>>>>,
    /// change a chaque nouvelle configuration : le moteur redemarre
    gen: AtomicU64,
    running: AtomicBool,
}

fn shared() -> &'static Shared {
    static S: OnceLock<Shared> = OnceLock::new();
    S.get_or_init(Shared::default)
}

fn sounds_dir() -> PathBuf {
    let d = crate::store::data_dir().join("sounds");
    let _ = std::fs::create_dir_all(&d);
    d
}

fn safe_id(id: &str) -> Option<&str> {
    (!id.is_empty() && id.len() < 64 && id.bytes().all(|b| b.is_ascii_alphanumeric() || b == b'-' || b == b'_')).then_some(id)
}

fn load_pcm(id: &str) -> Option<Arc<Vec<f32>>> {
    let id = safe_id(id)?;
    if let Some(p) = shared().cache.lock().ok()?.get(id) {
        return Some(p.clone());
    }
    let bytes = std::fs::read(sounds_dir().join(format!("{id}.pcm"))).ok()?;
    let pcm: Vec<f32> = bytes.chunks_exact(4).map(|b| f32::from_le_bytes([b[0], b[1], b[2], b[3]])).collect();
    let pcm = Arc::new(pcm);
    shared().cache.lock().ok()?.insert(id.to_string(), pcm.clone());
    Some(pcm)
}

// ------------------------------------------------------------ peripheriques

#[derive(Serialize)]
pub struct Device {
    id: String,
    name: String,
}

#[derive(Serialize)]
pub struct Devices {
    outputs: Vec<Device>,
    inputs: Vec<Device>,
}

unsafe fn list(en: &IMMDeviceEnumerator, flow: EDataFlow) -> Vec<Device> {
    let Ok(devs) = en.EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE) else { return Vec::new() };
    let mut out = Vec::new();
    for i in 0..devs.GetCount().unwrap_or(0) {
        let Ok(d) = devs.Item(i) else { continue };
        let id = crate::audio::device_id(&d);
        out.push(Device { name: crate::audio::device_name(&d), id });
    }
    out
}

pub fn sb_devices() -> Devices {
    crate::com_init_mta();
    unsafe {
        match CoCreateInstance::<_, IMMDeviceEnumerator>(&MMDeviceEnumerator, None, CLSCTX_ALL) {
            Ok(en) => Devices { outputs: list(&en, eRender), inputs: list(&en, eCapture) },
            Err(_) => Devices { outputs: Vec::new(), inputs: Vec::new() },
        }
    }
}

// --------------------------------------------------------------- commandes

pub fn sb_config(app: AppHandle, cfg: Config) {
    let s = shared();
    let changed = s.cfg.lock().map(|mut c| std::mem::replace(&mut *c, cfg.clone()) != cfg).unwrap_or(false);
    if changed {
        s.gen.fetch_add(1, Ordering::SeqCst);
    }
    ensure(app);
}

/// Un son importe : identifiant, nom (sans extension), duree en secondes.
#[derive(Serialize)]
pub struct Imported {
    id: String,
    name: String,
    dur: f32,
}

/// Decode, convertit et enregistre un fichier audio (depose sur l'ilot ou
/// choisi avec « Ajouter »).
pub fn sb_import(path: String) -> Result<Imported, String> {
    let p = std::path::Path::new(&path);
    let meta = std::fs::metadata(p).map_err(|e| e.to_string())?;
    if meta.len() > 50 * 1024 * 1024 {
        return Err("Fichier trop gros (50 Mo maxi)".into());
    }
    let pcm = crate::decode::decode_file(p, RATE, MAX_SECS)?;
    let pcm = normalize(pcm);
    let id = new_id();
    let bytes: Vec<u8> = pcm.iter().flat_map(|v| v.to_le_bytes()).collect();
    std::fs::write(sounds_dir().join(format!("{id}.pcm")), bytes).map_err(|e| e.to_string())?;
    let name: String = p
        .file_stem()
        .map(|s| s.to_string_lossy().to_string())
        .unwrap_or_else(|| "Son".into())
        .chars()
        .take(40)
        .collect();
    Ok(Imported { dur: (pcm.len() / CH) as f32 / RATE as f32, id, name })
}

/// duree maximale d'un son, en secondes
const MAX_SECS: u32 = 30;

/// Crete ramenee a -1 dB : niveaux homogenes d'un son a l'autre.
fn normalize(mut pcm: Vec<f32>) -> Vec<f32> {
    let peak = pcm.iter().fold(0f32, |m, v| m.max(v.abs()));
    if peak > 0.001 {
        let k = 0.89 / peak;
        pcm.iter_mut().for_each(|v| *v *= k);
    }
    pcm
}

fn new_id() -> String {
    use std::hash::{BuildHasher, Hasher};
    let mut h = std::collections::hash_map::RandomState::new().build_hasher();
    h.write_u128(std::time::SystemTime::now().duration_since(std::time::UNIX_EPOCH).map_or(0, |d| d.as_nanos()));
    format!("s{:012x}", h.finish() & 0xffff_ffff_ffff)
}

/// Fichiers audio a importer (boite de dialogue de Windows).
pub fn sb_pick(app: AppHandle) -> Vec<String> {
    crate::games::pick_files(app, "Ajouter des sons", "Sons", "*.mp3;*.wav;*.ogg;*.oga;*.flac;*.m4a;*.aac;*.mp4")
}

pub fn sb_delete(id: String) {
    let Some(id) = safe_id(&id) else { return };
    let _ = std::fs::remove_file(sounds_dir().join(format!("{id}.pcm")));
    if let Ok(mut c) = shared().cache.lock() {
        c.remove(id);
    }
}

/// Joue un son (le relance s'il jouait deja) ; `exclusive` coupe les autres.
pub fn sb_play(app: AppHandle, id: String, volume: f32, exclusive: bool) -> bool {
    let Some(pcm) = load_pcm(&id) else { return false };
    if let Ok(mut v) = shared().voices.lock() {
        if exclusive {
            v.clear();
        }
        v.retain(|x| x.id != id);
        v.push(Voice { id, pcm, pos: 0, vol: volume.clamp(0.0, 2.0) });
    }
    ensure(app);
    true
}

pub fn sb_stop(id: Option<String>) {
    if let Ok(mut v) = shared().voices.lock() {
        match id {
            Some(id) => v.retain(|x| x.id != id),
            None => v.clear(),
        }
    }
}

// ------------------------------------------------------------------ moteur

fn ensure(app: AppHandle) {
    let s = shared();
    if s.running.swap(true, Ordering::SeqCst) {
        return;
    }
    std::thread::spawn(move || {
        crate::com_init_mta();
        loop {
            let cfg = s.cfg.lock().map(|c| c.clone()).unwrap_or_default();
            let idle = s.voices.lock().map(|v| v.is_empty()).unwrap_or(true);
            // rien a faire : ni micro a faire passer, ni son en cours
            if !cfg.on && idle {
                break;
            }
            if run(&app, &cfg).is_err() {
                std::thread::sleep(Duration::from_secs(1));
            }
        }
        s.running.store(false, Ordering::SeqCst);
        let _ = app.emit("sb-playing", Vec::<String>::new());
    });
}

struct Out {
    client: IAudioClient,
    render: IAudioRenderClient,
    size: u32,
}

fn format() -> WAVEFORMATEX {
    WAVEFORMATEX {
        wFormatTag: 3, // WAVE_FORMAT_IEEE_FLOAT
        nChannels: CH as u16,
        nSamplesPerSec: RATE,
        nAvgBytesPerSec: RATE * CH as u32 * 4,
        nBlockAlign: CH as u16 * 4,
        wBitsPerSample: 32,
        cbSize: 0,
    }
}

/// Client audio partage au format du moteur (Windows convertit si besoin).
unsafe fn open(dev: &IMMDevice) -> windows::core::Result<IAudioClient> {
    let client: IAudioClient = dev.Activate(CLSCTX_ALL, None)?;
    let fmt = format();
    client.Initialize(
        AUDCLNT_SHAREMODE_SHARED,
        AUDCLNT_STREAMFLAGS_AUTOCONVERTPCM | AUDCLNT_STREAMFLAGS_SRC_DEFAULT_QUALITY,
        1_000_000, // 100 ms
        0,
        &fmt,
        None,
    )?;
    Ok(client)
}

unsafe fn open_out(dev: &IMMDevice) -> windows::core::Result<Out> {
    let client = open(dev)?;
    let render: IAudioRenderClient = client.GetService()?;
    let size = client.GetBufferSize()?;
    client.Start()?;
    Ok(Out { client, render, size })
}

/// Ecrit dans la sortie ce qu'il faut pour garder ~40 ms d'avance, en tirant
/// les echantillons de `src` (silence s'il en manque).
unsafe fn feed(o: &Out, src: &mut VecDeque<f32>) -> windows::core::Result<()> {
    let pad = o.client.GetCurrentPadding()?;
    let n = AHEAD.saturating_sub(pad).min(o.size - pad);
    if n == 0 {
        return Ok(());
    }
    let buf = o.render.GetBuffer(n)? as *mut f32;
    for i in 0..n as usize * CH {
        *buf.add(i) = src.pop_front().unwrap_or(0.0);
    }
    o.render.ReleaseBuffer(n, 0)
}

fn run(app: &AppHandle, cfg: &Config) -> windows::core::Result<()> {
    let s = shared();
    let gen = s.gen.load(Ordering::SeqCst);
    unsafe {
        let en: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
        let speakers = en.GetDefaultAudioEndpoint(eRender, eConsole)?;
        let speakers_id = crate::audio::device_id(&speakers);
        // cable virtuel + micro reel, seulement si la soundboard est active
        let cable = if cfg.on && !cfg.cable.is_empty() { Some(open_out(&en.GetDevice(&HSTRING::from(&cfg.cable))?)?) } else { None };
        let mic = if cable.is_some() {
            let dev = if cfg.mic.is_empty() { en.GetDefaultAudioEndpoint(eCapture, eCommunications)? } else { en.GetDevice(&HSTRING::from(&cfg.mic))? };
            let client = open(&dev)?;
            let cap: IAudioCaptureClient = client.GetService()?;
            client.Start()?;
            Some((client, cap))
        } else {
            None
        };
        // retour dans le casque : pas si le casque est lui-meme le cable
        let monitor = if (cfg.monitor || cable.is_none()) && speakers_id != cfg.cable { Some(open_out(&speakers)?) } else { None };

        let gain = if cfg.mic_gain > 0.0 { cfg.mic_gain } else { 1.0 };
        let mut micq: VecDeque<f32> = VecDeque::new();
        let mut cableq: VecDeque<f32> = VecDeque::new();
        let mut monq: VecDeque<f32> = VecDeque::new();
        let mut playing: Vec<String> = Vec::new();
        let mut idle_ticks = 0u32;
        loop {
            std::thread::sleep(Duration::from_millis(5));
            if s.gen.load(Ordering::SeqCst) != gen {
                break;
            }
            // micro : tout ce qui est arrive ; retard rattrape si on prend du retard
            if let Some((_, cap)) = &mic {
                loop {
                    if cap.GetNextPacketSize()? == 0 {
                        break;
                    }
                    let mut data = std::ptr::null_mut();
                    let (mut frames, mut flags) = (0u32, 0u32);
                    cap.GetBuffer(&mut data, &mut frames, &mut flags, None, None)?;
                    let d = data as *const f32;
                    for i in 0..frames as usize * CH {
                        micq.push_back(if flags & SILENT != 0 { 0.0 } else { *d.add(i) * gain });
                    }
                    cap.ReleaseBuffer(frames)?;
                }
                if micq.len() > MIC_MAX {
                    let extra = micq.len() - MIC_MAX / 2;
                    micq.drain(..extra - extra % CH);
                }
            }
            // sons : on mixe ce que la sortie la plus en avance va reclamer
            let want = cable.as_ref().or(monitor.as_ref()).map_or(0, |o| {
                let pad = o.client.GetCurrentPadding().unwrap_or(o.size);
                AHEAD.saturating_sub(pad) as usize * CH
            });
            let mut sfx = vec![0f32; want];
            if let Ok(mut voices) = s.voices.lock() {
                for v in voices.iter_mut() {
                    let take = (v.pcm.len() - v.pos.min(v.pcm.len())).min(want);
                    for (i, smp) in v.pcm[v.pos..v.pos + take].iter().enumerate() {
                        sfx[i] += smp * v.vol;
                    }
                    v.pos += take;
                }
                voices.retain(|v| v.pos < v.pcm.len());
                let now: Vec<String> = voices.iter().map(|v| v.id.clone()).collect();
                if now != playing {
                    let _ = app.emit("sb-playing", &now);
                    playing = now;
                }
            }
            if let Some(o) = &cable {
                for (i, x) in sfx.iter().enumerate() {
                    let m = if i < micq.len() { micq[i] } else { 0.0 };
                    cableq.push_back((m + x).clamp(-1.0, 1.0));
                }
                micq.drain(..want.min(micq.len()));
                feed(o, &mut cableq)?;
            }
            if let Some(o) = &monitor {
                monq.extend(sfx.iter().copied());
                // la sortie casque a sa propre horloge : on evite que l'ecart grandisse
                if monq.len() > MIC_MAX * 2 {
                    let extra = monq.len() - MIC_MAX;
                    monq.drain(..extra - extra % CH);
                }
                feed(o, &mut monq)?;
            }
            // soundboard coupee et plus aucun son : le moteur s'arrete
            if !cfg.on && playing.is_empty() {
                idle_ticks += 1;
                if idle_ticks > 100 {
                    break;
                }
            } else {
                idle_ticks = 0;
            }
        }
        if let Some(o) = &cable {
            let _ = o.client.Stop();
        }
        if let Some(o) = &monitor {
            let _ = o.client.Stop();
        }
        if let Some((c, _)) = &mic {
            let _ = c.Stop();
        }
    }
    Ok(())
}
