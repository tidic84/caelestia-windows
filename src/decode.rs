//! Decodage des sons de la soundboard (mp3, wav, ogg Vorbis, flac, m4a/aac)
//! avec symphonia, puis conversion en stereo f32 entrelace a la frequence
//! du moteur (48 kHz). Ce que faisait `decodeAudioData` dans l'interface web.

use std::path::Path;

use symphonia::core::audio::SampleBuffer;
use symphonia::core::codecs::{DecoderOptions, CODEC_TYPE_NULL};
use symphonia::core::errors::Error;
use symphonia::core::formats::FormatOptions;
use symphonia::core::io::MediaSourceStream;
use symphonia::core::meta::MetadataOptions;
use symphonia::core::probe::Hint;

/// Echantillons stereo entrelaces (G, D, G, D...) a `rate` Hz, au plus `max_secs` secondes.
pub fn decode_file(path: &Path, rate: u32, max_secs: u32) -> Result<Vec<f32>, String> {
    let file = std::fs::File::open(path).map_err(|e| e.to_string())?;
    let mss = MediaSourceStream::new(Box::new(file), Default::default());
    let mut hint = Hint::new();
    if let Some(ext) = path.extension().and_then(|e| e.to_str()) {
        hint.with_extension(ext);
    }
    let probed = symphonia::default::get_probe()
        .format(&hint, mss, &FormatOptions::default(), &MetadataOptions::default())
        .map_err(|_| "format non reconnu".to_string())?;
    let mut format = probed.format;
    let track = format
        .tracks()
        .iter()
        .find(|t| t.codec_params.codec != CODEC_TYPE_NULL)
        .ok_or("aucune piste audio")?;
    let track_id = track.id;
    let mut src_rate = track.codec_params.sample_rate.unwrap_or(rate);
    let mut decoder = symphonia::default::get_codecs()
        .make(&track.codec_params, &DecoderOptions::default())
        .map_err(|_| "codec non pris en charge".to_string())?;

    // stereo a la frequence d'origine
    let mut stereo: Vec<f32> = Vec::new();
    let limit = |r: u32| r as usize * max_secs as usize * 2 + 2 * 1024;
    let mut buf: Option<SampleBuffer<f32>> = None;
    loop {
        let packet = match format.next_packet() {
            Ok(p) => p,
            Err(Error::IoError(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => break,
            Err(Error::ResetRequired) => break,
            Err(e) => {
                if stereo.is_empty() {
                    return Err(e.to_string());
                }
                break;
            }
        };
        if packet.track_id() != track_id {
            continue;
        }
        let decoded = match decoder.decode(&packet) {
            Ok(d) => d,
            // paquet abime : on passe au suivant
            Err(Error::DecodeError(_)) => continue,
            Err(e) => return Err(e.to_string()),
        };
        let spec = *decoded.spec();
        src_rate = spec.rate;
        let ch = spec.channels.count().max(1);
        let b = match &mut buf {
            Some(b) if b.capacity() >= decoded.capacity() * ch => b,
            _ => buf.insert(SampleBuffer::new(decoded.capacity() as u64, spec)),
        };
        b.copy_interleaved_ref(decoded);
        for frame in b.samples().chunks_exact(ch) {
            let (l, r) = if ch == 1 { (frame[0], frame[0]) } else { (frame[0], frame[1]) };
            stereo.push(l);
            stereo.push(r);
        }
        if stereo.len() >= limit(src_rate) {
            break;
        }
    }
    if stereo.is_empty() {
        return Err("fichier vide".into());
    }
    let mut out = resample(&stereo, src_rate, rate);
    out.truncate(rate as usize * max_secs as usize * 2);
    Ok(out)
}

/// Reechantillonnage stereo par interpolation cubique (Catmull-Rom) : assez
/// fin pour des bruitages, sans dependance de plus.
pub fn resample(src: &[f32], from: u32, to: u32) -> Vec<f32> {
    if from == to || from == 0 {
        return src.to_vec();
    }
    let frames = src.len() / 2;
    let n = (frames as u64 * to as u64 / from as u64) as usize;
    let step = from as f64 / to as f64;
    let at = |i: isize, c: usize| -> f32 {
        let i = i.clamp(0, frames as isize - 1) as usize;
        src[i * 2 + c]
    };
    let mut out = Vec::with_capacity(n * 2);
    for k in 0..n {
        let pos = k as f64 * step;
        let i = pos.floor() as isize;
        let t = (pos - i as f64) as f32;
        for c in 0..2 {
            let (p0, p1, p2, p3) = (at(i - 1, c), at(i, c), at(i + 1, c), at(i + 2, c));
            let v = p1
                + 0.5 * t * (p2 - p0 + t * (2.0 * p0 - 5.0 * p1 + 4.0 * p2 - p3 + t * (3.0 * (p1 - p2) + p3 - p0)));
            out.push(v);
        }
    }
    out
}
