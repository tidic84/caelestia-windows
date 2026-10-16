//! Visualiseur : capture « loopback » de la sortie audio par defaut (ce que
//! le PC joue, Spotify compris), FFT, puis bandes de frequences emises a
//! l'interface (`spectrum`, ~30 fois par seconde). Ne tourne que si
//! l'interface le demande (`viz_set`) : musique en cours, ilot visible.

use std::sync::atomic::{AtomicBool, Ordering};
use std::time::{Duration, Instant};

use tauri::{AppHandle, Emitter};
use windows::Win32::Media::Audio::{
    eConsole, eRender, IAudioCaptureClient, IAudioClient, IMMDevice, IMMDeviceEnumerator, MMDeviceEnumerator,
    AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK,
};
use windows::Win32::System::Com::{CoCreateInstance, CoTaskMemFree, CLSCTX_ALL};

/// Nombre de bandes envoyees a l'interface.
const BANDS: usize = 48;
const N: usize = 2048;
const SILENT: u32 = 2; // AUDCLNT_BUFFERFLAGS_SILENT

static WANT: AtomicBool = AtomicBool::new(false);
static RUNNING: AtomicBool = AtomicBool::new(false);

#[tauri::command]
pub fn viz_set(app: AppHandle, on: bool) {
    WANT.store(on, Ordering::SeqCst);
    if on && !RUNNING.swap(true, Ordering::SeqCst) {
        std::thread::spawn(move || {
            while WANT.load(Ordering::SeqCst) {
                // erreur (peripherique change, debranche...) : on recommence
                if capture(&app).is_err() {
                    std::thread::sleep(Duration::from_secs(1));
                }
            }
            let _ = app.emit("spectrum", vec![0u8; BANDS]);
            RUNNING.store(false, Ordering::SeqCst);
        });
    }
}

fn capture(app: &AppHandle) -> windows::core::Result<()> {
    crate::com_init_mta();
    unsafe {
        let en: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
        let dev = en.GetDefaultAudioEndpoint(eRender, eConsole)?;
        let client: IAudioClient = dev.Activate(CLSCTX_ALL, None)?;
        let fmt = client.GetMixFormat()?;
        let (channels, rate, bits) = ((*fmt).nChannels as usize, (*fmt).nSamplesPerSec as f32, (*fmt).wBitsPerSample);
        let r = client.Initialize(AUDCLNT_SHAREMODE_SHARED, AUDCLNT_STREAMFLAGS_LOOPBACK, 1_000_000, 0, fmt, None);
        CoTaskMemFree(Some(fmt as _));
        r?;
        let cap: IAudioCaptureClient = client.GetService()?;
        client.Start()?;

        let edges = band_edges(rate);
        let window: Vec<f32> = (0..N).map(|i| 0.5 - 0.5 * (2.0 * std::f32::consts::PI * i as f32 / N as f32).cos()).collect();
        let mut ring = vec![0f32; N];
        let mut pos = 0usize;
        let mut last = Instant::now();
        let mut device_check = Instant::now();
        let default_id = dev_id(&dev)?;

        while WANT.load(Ordering::SeqCst) {
            std::thread::sleep(Duration::from_millis(10));
            loop {
                let n = cap.GetNextPacketSize()?;
                if n == 0 {
                    break;
                }
                let mut data = std::ptr::null_mut();
                let mut frames = 0u32;
                let mut flags = 0u32;
                cap.GetBuffer(&mut data, &mut frames, &mut flags, None, None)?;
                for f in 0..frames as usize {
                    // mono : moyenne des canaux
                    let mut s = 0.0;
                    if flags & SILENT == 0 {
                        for c in 0..channels {
                            let i = f * channels + c;
                            s += match bits {
                                32 => *(data as *const f32).add(i),
                                16 => *(data as *const i16).add(i) as f32 / 32768.0,
                                _ => 0.0,
                            };
                        }
                        s /= channels as f32;
                    }
                    ring[pos] = s;
                    pos = (pos + 1) % N;
                }
                cap.ReleaseBuffer(frames)?;
            }
            if last.elapsed() >= Duration::from_millis(33) {
                last = Instant::now();
                let _ = app.emit("spectrum", spectrum(&ring, pos, &window, &edges));
            }
            // sortie par defaut changee (casque branche...) : on se reconnecte
            if device_check.elapsed() >= Duration::from_secs(2) {
                device_check = Instant::now();
                let now = dev_id(&en.GetDefaultAudioEndpoint(eRender, eConsole)?)?;
                if now != default_id {
                    break;
                }
            }
        }
        let _ = client.Stop();
    }
    Ok(())
}

fn dev_id(dev: &IMMDevice) -> windows::core::Result<String> {
    unsafe {
        let p = dev.GetId()?;
        let s = p.to_string().unwrap_or_default();
        CoTaskMemFree(Some(p.0 as _));
        Ok(s)
    }
}

/// Bornes (indices de FFT) de bandes reparties en echelle logarithmique, 40 Hz - 16 kHz.
fn band_edges(rate: f32) -> Vec<usize> {
    let (lo, hi) = (40f32, 16_000f32.min(rate / 2.0));
    (0..=BANDS)
        .map(|b| {
            let f = lo * (hi / lo).powf(b as f32 / BANDS as f32);
            ((f * N as f32 / rate).round() as usize).clamp(1, N / 2)
        })
        .collect()
}

fn spectrum(ring: &[f32], pos: usize, window: &[f32], edges: &[usize]) -> Vec<u8> {
    let mut re: Vec<f32> = (0..N).map(|i| ring[(pos + i) % N] * window[i]).collect();
    let mut im = vec![0f32; N];
    fft(&mut re, &mut im);
    (0..BANDS)
        .map(|b| {
            let (a, z) = (edges[b], edges[b + 1].max(edges[b] + 1));
            let mag = (a..z).map(|k| (re[k] * re[k] + im[k] * im[k]).sqrt()).fold(0f32, f32::max);
            // en dB, ramene a 0-255 (plancher -60 dB) ; les aigus, plus faibles, sont releves
            let tilt = 1.0 + b as f32 / BANDS as f32 * 1.5;
            let db = 20.0 * (mag * tilt / (N as f32 / 4.0) + 1e-9).log10();
            (((db + 60.0) / 60.0).clamp(0.0, 1.0) * 255.0) as u8
        })
        .collect()
}

/// FFT radix-2 en place (N puissance de 2).
fn fft(re: &mut [f32], im: &mut [f32]) {
    let n = re.len();
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
                let nr = cr * wr - ci * wi;
                ci = cr * wi + ci * wr;
                cr = nr;
            }
        }
        len <<= 1;
    }
}
