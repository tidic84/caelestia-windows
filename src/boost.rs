//! Volume au-dela de 100 % : Windows plafonne a 100 %, le gain supplementaire
//! passe par le « Preamp » d'Equalizer APO (module audio systeme, a installer
//! a part). Ilot gere `config.txt` (l'ancien est garde dans
//! `config.ilot-backup.txt`) qui inclut `ilot-boost.txt` : `Preamp: +x dB`.
//! Equalizer APO recharge ces fichiers tout seul.

use std::path::PathBuf;

use windows::core::w;
use windows::Win32::System::Registry::{RegGetValueW, HKEY_LOCAL_MACHINE, RRF_RT_REG_SZ, RRF_SUBKEY_WOW6464KEY};

const MANAGED: &str = "# Configuration geree par Ilot (volume au-dela de 100 %).\r\n\
# L'ancienne configuration est dans config.ilot-backup.txt.\r\n\
Include: ilot-boost.txt\r\n";
/// Gain maximal : x2 (200 %), soit +6 dB.
const MAX: f32 = 2.0;

/// Dossier `config` d'Equalizer APO, s'il est installe.
fn config_dir() -> Option<PathBuf> {
    let mut buf = [0u16; 520];
    let mut len = (buf.len() * 2) as u32;
    let from_reg = unsafe {
        RegGetValueW(
            HKEY_LOCAL_MACHINE,
            w!(r"SOFTWARE\EqualizerAPO"),
            w!("ConfigPath"),
            RRF_RT_REG_SZ | RRF_SUBKEY_WOW6464KEY,
            None,
            Some(buf.as_mut_ptr() as _),
            Some(&mut len),
        )
    }
    .is_ok()
    .then(|| PathBuf::from(String::from_utf16_lossy(&buf[..(len as usize / 2).saturating_sub(1)])));
    from_reg
        .into_iter()
        .chain([PathBuf::from(r"C:\Program Files\EqualizerAPO\config")])
        .find(|d| d.join("config.txt").is_file())
}

/// Gain actuel (1.0 = 100 %), ou None si Equalizer APO n'est pas installe.
pub fn boost_get() -> Option<f32> {
    let dir = config_dir()?;
    let cfg = std::fs::read_to_string(dir.join("config.txt")).unwrap_or_default();
    if !cfg.contains("Include: ilot-boost.txt") {
        // la configuration d'exemple d'Equalizer APO baisse le son de 6 dB :
        // Ilot la remplace tout de suite par un gain neutre
        boost_set(1.0);
        return Some(1.0);
    }
    let txt = std::fs::read_to_string(dir.join("ilot-boost.txt")).unwrap_or_default();
    let db: f32 = txt
        .lines()
        .find_map(|l| l.trim().strip_prefix("Preamp:"))
        .and_then(|v| v.trim().trim_end_matches("dB").trim().parse().ok())
        .unwrap_or(0.0);
    Some(10f32.powf(db / 20.0).clamp(1.0, MAX))
}

/// Regle le gain (1.0 a 2.0). Renvoie faux si Equalizer APO est absent.
pub fn boost_set(gain: f32) -> bool {
    let Some(dir) = config_dir() else { return false };
    let cfg_path = dir.join("config.txt");
    let cfg = std::fs::read_to_string(&cfg_path).unwrap_or_default();
    // premiere fois : on met de cote la configuration existante
    if !cfg.contains("Include: ilot-boost.txt") {
        let backup = dir.join("config.ilot-backup.txt");
        if !backup.exists() && std::fs::write(&backup, &cfg).is_err() {
            return false;
        }
        if std::fs::write(&cfg_path, MANAGED).is_err() {
            return false;
        }
    }
    let db = 20.0 * gain.clamp(1.0, MAX).log10();
    std::fs::write(dir.join("ilot-boost.txt"), format!("Preamp: {db:.2} dB\r\n")).is_ok()
}
