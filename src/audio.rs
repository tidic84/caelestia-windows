//! Audio : sortie par defaut, melangeur par application, OSD du volume et
//! visualiseur (capture « loopback » de ce que joue le PC + FFT).

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use serde::Serialize;
use crate::host::{AppHandle};
use windows::core::{Interface, PCWSTR};
use windows::Win32::Devices::FunctionDiscovery::PKEY_Device_FriendlyName;
use windows::Win32::Media::Audio::{
    eConsole, eRender, IAudioCaptureClient, IAudioClient, IAudioSessionControl2,
    IAudioSessionManager2, IMMDevice, IMMDeviceEnumerator, ISimpleAudioVolume, MMDeviceEnumerator,
    AUDCLNT_BUFFERFLAGS_SILENT, AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK,
    AudioSessionStateExpired, DEVICE_STATE_ACTIVE, WAVEFORMATEX,
};
use windows::Win32::System::Com::{CoCreateInstance, CoTaskMemFree, CLSCTX_ALL, STGM_READ};

// ------------------------------------------------------------ peripheriques

fn enumerator() -> windows::core::Result<IMMDeviceEnumerator> {
    unsafe { CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL) }
}

fn default_device() -> windows::core::Result<IMMDevice> {
    unsafe { enumerator()?.GetDefaultAudioEndpoint(eRender, eConsole) }
}

pub(crate) fn device_id(d: &IMMDevice) -> String {
    unsafe {
        match d.GetId() {
            Ok(p) => {
                let s = p.to_string().unwrap_or_default();
                CoTaskMemFree(Some(p.0 as _));
                s
            }
            Err(_) => String::new(),
        }
    }
}

pub(crate) fn device_name(d: &IMMDevice) -> String {
    unsafe {
        d.OpenPropertyStore(STGM_READ)
            .and_then(|st| st.GetValue(&PKEY_Device_FriendlyName))
            .map(|v| v.to_string())
            .unwrap_or_default()
    }
}

/// Niveau crete actuel de chaque sortie active (0..1).
fn peaks() -> Vec<(IMMDevice, String, f32)> {
    let mut out = Vec::new();
    let _ = (|| -> windows::core::Result<()> {
        let col = unsafe { enumerator()?.EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE)? };
        for i in 0..unsafe { col.GetCount()? } {
            let d = unsafe { col.Item(i)? };
            let peak = unsafe {
                d.Activate::<windows::Win32::Media::Audio::Endpoints::IAudioMeterInformation>(CLSCTX_ALL, None)
                    .and_then(|m| m.GetPeakValue())
                    .unwrap_or(0.0)
            };
            out.push((d.clone(), device_id(&d), peak));
        }
        Ok(())
    })();
    out
}

/// Diagnostic : niveau de chaque sortie.
pub fn peaks_report() -> String {
    peaks().iter().map(|(d, _, p)| format!("{:.3} {}", p, device_name(d))).collect::<Vec<_>>().join(" | ")
}

/// Sortie a ecouter : celle qui joue le plus fort (la musique peut sortir
/// ailleurs que sur la sortie par defaut, ex. avec Voicemeeter), sinon
/// la sortie par defaut.
fn loudest_device() -> windows::core::Result<IMMDevice> {
    let def = default_device()?;
    Ok(playing_device(&device_id(&def)).unwrap_or(def))
}

/// Sortie qui joue le plus fort, s'il y en a une.
fn playing_device(def_id: &str) -> Option<IMMDevice> {
    let mut best: Option<(IMMDevice, f32)> = None;
    for (d, id, p) in peaks() {
        // a niveau egal, on garde la sortie par defaut
        let p = if id == def_id { p + 0.001 } else { p };
        if p > 0.002 && best.as_ref().is_none_or(|b| p > b.1) {
            best = Some((d, p));
        }
    }
    best.map(|b| b.0)
}

pub fn default_id() -> Option<String> {
    default_device().ok().map(|d| device_id(&d))
}

#[derive(Serialize)]
pub struct Device {
    id: String,
    name: String,
    default: bool,
}

pub fn audio_devices() -> Vec<Device> {
    crate::com_init_mta();
    let mut out = Vec::new();
    let _ = (|| -> windows::core::Result<()> {
        let en = enumerator()?;
        let def = device_id(&default_device()?);
        let col = unsafe { en.EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE)? };
        for i in 0..unsafe { col.GetCount()? } {
            let d = unsafe { col.Item(i)? };
            let id = device_id(&d);
            out.push(Device { name: device_name(&d), default: id == def, id });
        }
        Ok(())
    })();
    out.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    out
}

/// Interface non documentee (mais stable depuis Vista) qu'utilise le panneau
/// Son de Windows pour changer la sortie par defaut.
#[allow(non_snake_case)]
mod policy {
    use std::ffi::c_void;
    use windows::core::{interface, IUnknown, IUnknown_Vtbl, HRESULT, PCWSTR};

    #[interface("f8679f50-850a-41cf-9c72-430f290290c8")]
    unsafe trait IPolicyConfig: IUnknown {
        fn GetMixFormat(&self, id: PCWSTR, fmt: *mut *mut c_void) -> HRESULT;
        fn GetDeviceFormat(&self, id: PCWSTR, default: i32, fmt: *mut *mut c_void) -> HRESULT;
        fn ResetDeviceFormat(&self, id: PCWSTR) -> HRESULT;
        fn SetDeviceFormat(&self, id: PCWSTR, a: *mut c_void, b: *mut c_void) -> HRESULT;
        fn GetProcessingPeriod(&self, id: PCWSTR, default: i32, a: *mut i64, b: *mut i64) -> HRESULT;
        fn SetProcessingPeriod(&self, id: PCWSTR, a: *mut i64) -> HRESULT;
        fn GetShareMode(&self, id: PCWSTR, mode: *mut c_void) -> HRESULT;
        fn SetShareMode(&self, id: PCWSTR, mode: *mut c_void) -> HRESULT;
        fn GetPropertyValue(&self, id: PCWSTR, key: *const c_void, v: *mut c_void) -> HRESULT;
        fn SetPropertyValue(&self, id: PCWSTR, key: *const c_void, v: *mut c_void) -> HRESULT;
        fn SetDefaultEndpoint(&self, id: PCWSTR, role: u32) -> HRESULT;
        fn SetEndpointVisibility(&self, id: PCWSTR, visible: i32) -> HRESULT;
    }

    const CLSID_POLICY_CONFIG: windows::core::GUID =
        windows::core::GUID::from_u128(0x870af99c_171d_4f9e_af0d_e63df40c2bc9);

    /// Sortie par defaut pour les trois roles (console, multimedia, communications).
    pub fn set_default(id: PCWSTR) -> bool {
        use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_ALL};
        unsafe {
            let Ok(pc) = CoCreateInstance::<_, IPolicyConfig>(&CLSID_POLICY_CONFIG, None, CLSCTX_ALL) else {
                return false;
            };
            (0..3).all(|role| pc.SetDefaultEndpoint(id, role).is_ok())
        }
    }
}

pub fn audio_set_default(id: String) -> bool {
    crate::com_init_mta();
    let wide: Vec<u16> = id.encode_utf16().chain([0]).collect();
    policy::set_default(PCWSTR(wide.as_ptr()))
}

// ----------------------------------------------------------------- melangeur

#[derive(Serialize)]
pub struct AppVolume {
    /// une appli peut avoir plusieurs processus (Discord, navigateurs...)
    pids: Vec<u32>,
    name: String,
    icon: String,
    level: f32,
    muted: bool,
}

/// Icones des executables, gardees d'un appel a l'autre.
static ICONS: Mutex<Option<HashMap<String, String>>> = Mutex::new(None);

fn sessions() -> windows::core::Result<Vec<(u32, bool, ISimpleAudioVolume)>> {
    let mut out = Vec::new();
    unsafe {
        let mgr: IAudioSessionManager2 = default_device()?.Activate(CLSCTX_ALL, None)?;
        let en = mgr.GetSessionEnumerator()?;
        for i in 0..en.GetCount()? {
            let c = en.GetSession(i)?;
            if c.GetState()? == AudioSessionStateExpired {
                continue;
            }
            let c2: IAudioSessionControl2 = c.cast()?;
            let system = c2.IsSystemSoundsSession() == windows::Win32::Foundation::S_OK;
            out.push((c2.GetProcessId().unwrap_or(0), system, c.cast()?));
        }
    }
    Ok(out)
}

pub fn mixer_get() -> Vec<AppVolume> {
    // les icones passent par le shell : thread STA dedie
    std::thread::spawn(|| {
        crate::com_init_sta();
        let Ok(list) = sessions() else { return Vec::new() };
        let mut sys = sysinfo::System::new();
        sys.refresh_processes(sysinfo::ProcessesToUpdate::All, false);
        let mut out: Vec<AppVolume> = Vec::new();
        for (pid, system, vol) in list {
            let (level, muted) = unsafe {
                (vol.GetMasterVolume().unwrap_or(0.0), vol.GetMute().map(|m| m.as_bool()).unwrap_or(false))
            };
            let (name, icon) = if system {
                ("Sons système".to_string(), String::new())
            } else {
                let Some(p) = sys.process(sysinfo::Pid::from_u32(pid)) else { continue };
                let exe = p.exe().map(|e| e.to_string_lossy().into_owned()).unwrap_or_default();
                let fallback = p.name().to_string_lossy().trim_end_matches(".exe").to_string();
                let name = crate::apps::file_description(&exe).unwrap_or(fallback);
                let icon = if exe.is_empty() {
                    String::new()
                } else {
                    let mut cache = ICONS.lock().unwrap();
                    let cache = cache.get_or_insert_with(HashMap::new);
                    cache.entry(exe.clone()).or_insert_with(|| crate::apps::file_icon(&exe)).clone()
                };
                (name, icon)
            };
            if let Some(a) = out.iter_mut().find(|a| a.name == name) {
                if !a.pids.contains(&pid) {
                    a.pids.push(pid);
                }
                continue;
            }
            out.push(AppVolume { pids: vec![pid], name, icon, level, muted });
        }
        // les sons systeme a la fin
        out.sort_by_key(|a| (a.icon.is_empty() && a.name == "Sons système", a.name.to_lowercase()));
        out
    })
    .join()
    .unwrap_or_default()
}

pub fn mixer_set(pids: Vec<u32>, level: Option<f32>, muted: Option<bool>) {
    crate::com_init_mta();
    let Ok(list) = sessions() else { return };
    for (p, _, vol) in list {
        if !pids.contains(&p) {
            continue;
        }
        unsafe {
            if let Some(l) = level {
                let _ = vol.SetMasterVolume(l.clamp(0.0, 1.0), std::ptr::null());
            }
            if let Some(m) = muted {
                let _ = vol.SetMute(m, std::ptr::null());
            }
        }
    }
}

// ------------------------------------------------------------------- OSD

#[derive(Serialize, Clone)]
pub struct Osd {
    kind: &'static str,
    value: f32,
    muted: bool,
}

/// Changements signales par Windows au fil de veille du volume.
enum VolEvent {
    /// volume ou sourdine de la sortie suivie
    Level(f32, bool),
    /// nouvelle sortie par defaut
    Device,
}

#[windows::core::implement(windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolumeCallback)]
struct VolumeCb(std::sync::mpsc::Sender<VolEvent>);

impl windows::Win32::Media::Audio::Endpoints::IAudioEndpointVolumeCallback_Impl for VolumeCb_Impl {
    fn OnNotify(&self, data: *mut windows::Win32::Media::Audio::AUDIO_VOLUME_NOTIFICATION_DATA) -> windows::core::Result<()> {
        if let Some(d) = unsafe { data.as_ref() } {
            let _ = self.0.send(VolEvent::Level(d.fMasterVolume, d.bMuted.as_bool()));
        }
        Ok(())
    }
}

#[windows::core::implement(windows::Win32::Media::Audio::IMMNotificationClient)]
struct DeviceCb(std::sync::mpsc::Sender<VolEvent>);

impl windows::Win32::Media::Audio::IMMNotificationClient_Impl for DeviceCb_Impl {
    fn OnDeviceStateChanged(&self, _: &PCWSTR, _: windows::Win32::Media::Audio::DEVICE_STATE) -> windows::core::Result<()> {
        Ok(())
    }
    fn OnDeviceAdded(&self, _: &PCWSTR) -> windows::core::Result<()> {
        Ok(())
    }
    fn OnDeviceRemoved(&self, _: &PCWSTR) -> windows::core::Result<()> {
        Ok(())
    }
    fn OnDefaultDeviceChanged(
        &self,
        flow: windows::Win32::Media::Audio::EDataFlow,
        role: windows::Win32::Media::Audio::ERole,
        _: &PCWSTR,
    ) -> windows::core::Result<()> {
        if flow == eRender && role == eConsole {
            let _ = self.0.send(VolEvent::Device);
        }
        Ok(())
    }
    fn OnPropertyValueChanged(&self, _: &PCWSTR, _: &windows::Win32::Foundation::PROPERTYKEY) -> windows::core::Result<()> {
        Ok(())
    }
}

/// Surveille le volume de la sortie par defaut et emet `osd` quand il
/// change (touches multimedia, autre appli...). Un changement de sortie
/// ne declenche rien. Windows previent a chaque changement (volume et
/// sortie par defaut) : aucun sondage.
pub fn watch_volume(app: AppHandle) {
    use windows::Win32::Media::Audio::Endpoints::{IAudioEndpointVolume, IAudioEndpointVolumeCallback};
    use windows::Win32::Media::Audio::IMMNotificationClient;
    std::thread::spawn(move || {
        crate::com_init_mta();
        let (tx, rx) = std::sync::mpsc::channel();
        let vol_cb: IAudioEndpointVolumeCallback = VolumeCb(tx.clone()).into();
        let dev_cb: IMMNotificationClient = DeviceCb(tx).into();
        // l'enumerateur doit vivre tant que son rappel est enregistre
        let devices = enumerator().ok();
        if let Some(e) = &devices {
            let _ = unsafe { e.RegisterEndpointNotificationCallback(&dev_cb) };
        }
        loop {
            // sortie par defaut : volume actuel (sans OSD), puis ses changements
            let bound = default_device().and_then(|d| unsafe {
                let ep = d.Activate::<IAudioEndpointVolume>(CLSCTX_ALL, None)?;
                let now = (ep.GetMasterVolumeLevelScalar()?, ep.GetMute()?.as_bool());
                ep.RegisterControlChangeNotify(&vol_cb)?;
                Ok((ep, now))
            });
            let (ep, mut last) = match bound {
                Ok((ep, now)) => (Some(ep), now),
                Err(_) => (None, (0.0, false)),
            };
            loop {
                // sans sortie (ou sans rappel de sortie), on reessaie de temps en temps
                let wait = if ep.is_some() && devices.is_some() { Duration::from_secs(3600) } else { Duration::from_secs(2) };
                match rx.recv_timeout(wait) {
                    Ok(VolEvent::Level(l, m)) => {
                        if (last.0 - l).abs() > 0.004 || last.1 != m {
                            let _ = app.emit("osd", Osd { kind: "volume", value: l, muted: m });
                        }
                        last = (l, m);
                    }
                    Ok(VolEvent::Device) => break,
                    Err(std::sync::mpsc::RecvTimeoutError::Timeout) if ep.is_none() || devices.is_none() => break,
                    Err(std::sync::mpsc::RecvTimeoutError::Timeout) => {}
                    Err(std::sync::mpsc::RecvTimeoutError::Disconnected) => return,
                }
            }
            if let Some(ep) = ep {
                let _ = unsafe { ep.UnregisterControlChangeNotify(&vol_cb) };
            }
            // les rappels de l'ancienne sortie encore en file sont ignores
            while rx.try_recv().is_ok() {}
        }
    });
}

// ------------------------------------------------------------ visualiseur

static VIZ_ON: AtomicBool = AtomicBool::new(false);
static VIZ_RUNNING: AtomicBool = AtomicBool::new(false);

const BANDS: usize = 24;
const FFT_N: usize = 1024;
/// Correction de pente sur toute la largeur (~8,4 octaves de 45 Hz a 15 kHz).
const TILT_DB: f32 = 3.0 * 8.4;
/// Dynamique affichee sous le niveau de reference, en dB.
const RANGE_DB: f32 = 42.0;

/// Active ou coupe la capture (l'interface ne la demande que lorsqu'elle
/// affiche le visualiseur et que de la musique joue).
pub fn viz_set(app: AppHandle, on: bool) {
    VIZ_ON.store(on, Ordering::SeqCst);
    if on && !VIZ_RUNNING.swap(true, Ordering::SeqCst) {
        std::thread::spawn(move || {
            crate::com_init_mta();
            // `ILOT_SIM_VIZ=1` : bandes aleatoires a 30 trames/s au lieu du son
            // (mesures de consommation sans musique)
            let mut seed = 0x2545_F491_4F6C_DD1Du64;
            while VIZ_ON.load(Ordering::SeqCst) && std::env::var_os("ILOT_SIM_VIZ").is_some() {
                let b: Vec<u8> = (0..BANDS)
                    .map(|_| {
                        seed ^= seed << 13;
                        seed ^= seed >> 7;
                        seed ^= seed << 17;
                        (seed % 101) as u8
                    })
                    .collect();
                let _ = app.emit("viz", b);
                std::thread::sleep(Duration::from_millis(33));
            }
            while VIZ_ON.load(Ordering::SeqCst) {
                // la sortie a pu changer ou disparaitre : on recommence
                let _ = capture(&|b: Vec<u8>| {
                    let _ = app.emit("viz", b);
                });
                std::thread::sleep(Duration::from_millis(500));
            }
            let _ = app.emit("viz", vec![0u8; BANDS]);
            VIZ_RUNNING.store(false, Ordering::SeqCst);
        });
    }
}

/// Diagnostic : capture `secs` secondes et renvoie le niveau max par bande.
pub fn viz_probe(secs: u64) -> windows::core::Result<Vec<u8>> {
    VIZ_ON.store(true, Ordering::SeqCst);
    std::thread::spawn(move || {
        std::thread::sleep(Duration::from_secs(secs));
        VIZ_ON.store(false, Ordering::SeqCst);
    });
    let max = Mutex::new(vec![0u8; BANDS]);
    capture(&|b: Vec<u8>| {
        let mut m = max.lock().unwrap();
        for (x, y) in m.iter_mut().zip(b) {
            *x = (*x).max(y);
        }
    })?;
    Ok(max.into_inner().unwrap())
}

fn capture(emit: &dyn Fn(Vec<u8>)) -> windows::core::Result<()> {
    unsafe {
        let dev = loudest_device()?;
        let dev_id = device_id(&dev);
        let client: IAudioClient = dev.Activate(CLSCTX_ALL, None)?;
        let fmt = client.GetMixFormat()?;
        let f: WAVEFORMATEX = *fmt;
        let r = client.Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, 2_000_000, 0, fmt, None);
        CoTaskMemFree(Some(fmt as _));
        r?;
        let cap: IAudioCaptureClient = client.GetService()?;
        client.Start()?;

        let channels = f.nChannels.max(1) as usize;
        let bits = f.wBitsPerSample;
        // 3 = IEEE float ; 0xFFFE = extensible, en pratique du float 32 bits
        let float = f.wFormatTag == 3 || (f.wFormatTag == 0xFFFE && bits == 32);
        let rate = f.nSamplesPerSec as f32;
        let edges = band_edges(rate);
        let window: Vec<f32> = (0..FFT_N)
            .map(|i| 0.5 - 0.5 * (2.0 * std::f32::consts::PI * i as f32 / (FFT_N - 1) as f32).cos())
            .collect();

        let mut ring = vec![0f32; FFT_N];
        let mut bands = [0f32; BANDS];
        let mut quiet_frames = 0u32;
        let mut top = -40f32;
        let mut check = Instant::now();
        let result = loop {
            if !VIZ_ON.load(Ordering::SeqCst) {
                break Ok(());
            }
            // le son a pu passer sur une autre sortie : on suit la plus forte
            if check.elapsed() > Duration::from_secs(2) {
                check = Instant::now();
                // (un silence entre deux morceaux ne fait pas changer de sortie)
                let def = default_device().map(|d| device_id(&d)).unwrap_or_default();
                if playing_device(&def).is_some_and(|d| device_id(&d) != dev_id) {
                    break Ok(());
                }
            }
            loop {
                let n = match cap.GetNextPacketSize() {
                    Ok(n) => n,
                    Err(e) => {
                        let _ = client.Stop();
                        return Err(e);
                    }
                };
                if n == 0 {
                    break;
                }
                let mut data = std::ptr::null_mut();
                let mut frames = 0u32;
                let mut flags = 0u32;
                cap.GetBuffer(&mut data, &mut frames, &mut flags, None, None)?;
                let silent = flags & AUDCLNT_BUFFERFLAGS_SILENT.0 as u32 != 0;
                let frames = frames as usize;
                let take = frames.min(FFT_N);
                ring.copy_within(take.., 0);
                let start = FFT_N - take;
                for i in 0..take {
                    let fi = frames - take + i;
                    let mut s = 0f32;
                    if !silent && !data.is_null() {
                        for c in 0..channels {
                            let idx = fi * channels + c;
                            s += if float {
                                *(data as *const f32).add(idx)
                            } else if bits == 16 {
                                *(data as *const i16).add(idx) as f32 / 32768.0
                            } else {
                                0.0
                            };
                        }
                    }
                    ring[start + i] = s / channels as f32;
                }
                cap.ReleaseBuffer(frames as u32)?;
            }

            let mags = spectrum(&ring, &window);
            let dbs: Vec<f32> = edges
                .iter()
                .enumerate()
                .map(|(b, &(lo, hi))| {
                    let peak = mags[lo..hi.max(lo + 1)].iter().cloned().fold(0f32, f32::max);
                    // +3 dB par octave : sinon les graves ecrasent tout (comme cava)
                    20.0 * (peak + 1e-9).log10() + TILT_DB * (b as f32 / BANDS as f32 - 0.35)
                })
                .collect();
            // gain automatique (comme cava) : le plus fort de la trame sert de
            // reference ; elle monte vite et redescend lentement
            let loudest = dbs.iter().cloned().fold(-200f32, f32::max);
            top = if loudest > top { loudest } else { (top - 0.15).max(loudest).max(-70.0) };
            let silent = loudest < -85.0;
            let mut any = false;
            for b in 0..BANDS {
                let target = if silent { 0.0 } else { ((dbs[b] - (top - RANGE_DB)) / RANGE_DB).clamp(0.0, 1.0) };
                // monte vite, retombe doucement
                bands[b] = if target > bands[b] { bands[b] * 0.35 + target * 0.65 } else { bands[b] * 0.82 + target * 0.18 };
                any |= bands[b] > 0.01;
            }
            quiet_frames = if any { 0 } else { quiet_frames + 1 };
            if quiet_frames < 3 {
                let out: Vec<u8> = bands.iter().map(|v| (v * 100.0) as u8).collect();
                emit(out);
            }
            // 30 trames/s panneau ouvert ; replie, l'egaliseur de la pilule
            // (3 barres, lissees) se contente de 15
            std::thread::sleep(Duration::from_millis(if crate::panel_open() { 33 } else { 66 }));
        };
        let _ = client.Stop();
        result
    }
}

/// Bornes (en indices FFT) de bandes reparties logarithmiquement.
fn band_edges(rate: f32) -> Vec<(usize, usize)> {
    let (fmin, fmax) = (45f32, 15000f32.min(rate / 2.0 - 1.0));
    let bin = rate / FFT_N as f32;
    (0..BANDS)
        .map(|b| {
            let f0 = fmin * (fmax / fmin).powf(b as f32 / BANDS as f32);
            let f1 = fmin * (fmax / fmin).powf((b + 1) as f32 / BANDS as f32);
            let lo = ((f0 / bin) as usize).clamp(1, FFT_N / 2 - 1);
            let hi = ((f1 / bin).ceil() as usize).clamp(lo + 1, FFT_N / 2);
            (lo, hi)
        })
        .collect()
}

/// Module du spectre (FFT radix 2 iterative), normalise.
fn spectrum(samples: &[f32], window: &[f32]) -> Vec<f32> {
    let n = samples.len();
    let mut re: Vec<f32> = samples.iter().zip(window).map(|(s, w)| s * w).collect();
    let mut im = vec![0f32; n];
    let mut j = 0;
    for i in 1..n {
        let mut bit = n >> 1;
        while j & bit != 0 {
            j ^= bit;
            bit >>= 1;
        }
        j |= bit;
        if i < j {
            re.swap(i, j);
            im.swap(i, j);
        }
    }
    let mut len = 2;
    while len <= n {
        let ang = -2.0 * std::f32::consts::PI / len as f32;
        let (wr, wi) = (ang.cos(), ang.sin());
        for start in (0..n).step_by(len) {
            let (mut cr, mut ci) = (1f32, 0f32);
            for k in 0..len / 2 {
                let (a, b) = (start + k, start + k + len / 2);
                let tr = re[b] * cr - im[b] * ci;
                let ti = re[b] * ci + im[b] * cr;
                re[b] = re[a] - tr;
                im[b] = im[a] - ti;
                re[a] += tr;
                im[a] += ti;
                let ncr = cr * wr - ci * wi;
                ci = cr * wi + ci * wr;
                cr = ncr;
            }
        }
        len <<= 1;
    }
    (0..n / 2).map(|i| (re[i] * re[i] + im[i] * im[i]).sqrt() * 4.0 / n as f32).collect()
}

// ------------------------------------------- volume d'une appli par son nom
// (Discord en mode simple, sans RPC : sourdine du micro ou du son de Discord)

/// Nom de l'executable d'un processus, en minuscules et sans « .exe ».
fn exe_name_of(pid: u32) -> Option<String> {
    use windows::core::PWSTR;
    use windows::Win32::Foundation::CloseHandle;
    use windows::Win32::System::Threading::{
        OpenProcess, QueryFullProcessImageNameW, PROCESS_NAME_WIN32, PROCESS_QUERY_LIMITED_INFORMATION,
    };
    unsafe {
        let h = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, false, pid).ok()?;
        let mut buf = [0u16; 520];
        let mut len = buf.len() as u32;
        let r = QueryFullProcessImageNameW(h, PROCESS_NAME_WIN32, PWSTR(buf.as_mut_ptr()), &mut len);
        let _ = CloseHandle(h);
        r.ok()?;
        let path = String::from_utf16_lossy(&buf[..len as usize]);
        let file = path.rsplit('\\').next()?.to_lowercase();
        Some(file.trim_end_matches(".exe").to_string())
    }
}

/// Sessions audio (sortie, ou micro si `mic`) des processus dont l'executable contient `app`.
fn named_sessions(app: &str, mic: bool) -> Vec<ISimpleAudioVolume> {
    use windows::Win32::Media::Audio::eCapture;
    crate::com_init_mta();
    let key = app.to_lowercase().trim_end_matches(".exe").to_string();
    let mut out = Vec::new();
    if key.is_empty() {
        return out;
    }
    let flow = if mic { eCapture } else { eRender };
    let _ = (|| -> windows::core::Result<()> {
        unsafe {
            let devs = enumerator()?.EnumAudioEndpoints(flow, DEVICE_STATE_ACTIVE)?;
            for d in 0..devs.GetCount()? {
                let Ok(mgr) = devs.Item(d)?.Activate::<IAudioSessionManager2>(CLSCTX_ALL, None) else { continue };
                let list = mgr.GetSessionEnumerator()?;
                for i in 0..list.GetCount()? {
                    let Ok(ctl) = list.GetSession(i) else { continue };
                    let Ok(ctl2) = ctl.cast::<IAudioSessionControl2>() else { continue };
                    let Ok(pid) = ctl2.GetProcessId() else { continue };
                    if pid == 0 || !exe_name_of(pid).is_some_and(|n| n.contains(&key)) {
                        continue;
                    }
                    if let Ok(v) = ctl.cast::<ISimpleAudioVolume>() {
                        out.push(v);
                    }
                }
            }
            Ok(())
        }
    })();
    out
}

#[derive(Serialize)]
pub struct NamedVolume {
    level: f32,
    muted: bool,
}

/// Volume d'une appli designee par son nom (None si elle n'a pas de session audio).
pub fn app_volume_get(app: String, mic: Option<bool>) -> Option<NamedVolume> {
    let s = named_sessions(&app, mic.unwrap_or(false));
    let first = s.first()?;
    unsafe {
        Some(NamedVolume {
            level: first.GetMasterVolume().ok()?,
            muted: s.iter().any(|v| v.GetMute().is_ok_and(|m| m.as_bool())),
        })
    }
}

pub fn app_volume_set(app: String, mic: Option<bool>, level: Option<f32>, muted: Option<bool>) -> bool {
    let s = named_sessions(&app, mic.unwrap_or(false));
    unsafe {
        for v in &s {
            if let Some(l) = level {
                let _ = v.SetMasterVolume(l.clamp(0.0, 1.0), std::ptr::null());
            }
            if let Some(m) = muted {
                let _ = v.SetMute(m, std::ptr::null());
            }
        }
    }
    !s.is_empty()
}
#[derive(Serialize)]
pub struct FgVolume {
    /// nom affiche (description de l'executable, sinon son nom)
    name: String,
    level: f32,
}

/// Maj + molette sur la pilule : volume de l'appli au premier plan (jeu,
/// navigateur...), par pas de `step`. None si elle ne joue pas de son.
pub fn fg_volume(step: f32) -> Option<FgVolume> {
    use windows::Win32::UI::WindowsAndMessaging::{GetForegroundWindow, GetWindowThreadProcessId};
    crate::com_init_mta();
    let mut pid = 0u32;
    unsafe { GetWindowThreadProcessId(GetForegroundWindow(), Some(&mut pid)) };
    let exe = exe_name_of(pid)?;
    let list: Vec<ISimpleAudioVolume> = sessions()
        .ok()?
        .into_iter()
        .filter(|(p, system, _)| !system && *p != 0 && exe_name_of(*p).as_deref() == Some(exe.as_str()))
        .map(|(_, _, v)| v)
        .collect();
    let first = list.first()?;
    let level = unsafe { first.GetMasterVolume().ok()? };
    // pas de 2 %, comme la molette sur le volume general
    let level = (((level + step) * 50.0).round() / 50.0).clamp(0.0, 1.0);
    unsafe {
        for v in &list {
            let _ = v.SetMasterVolume(level, std::ptr::null());
            if level > 0.0 {
                let _ = v.SetMute(false, std::ptr::null());
            }
        }
    }
    let path = crate::tasks::exe_path(pid).unwrap_or_default();
    let name = crate::apps::file_description(&path).unwrap_or_else(|| {
        let mut c = exe.chars();
        c.next().map(|f| f.to_uppercase().chain(c).collect()).unwrap_or_default()
    });
    Some(FgVolume { name, level })
}
