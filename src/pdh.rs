//! Compteurs de performance Windows (PDH) : les memes que le Gestionnaire des
//! taches. Le CPU est « % Processor Time » (« % Processor Utility », pondere
//! par le turbo, donne ~12-25 % de plus que le Gestionnaire), le GPU vient de
//! « GPU Engine », l'activite disque de « PhysicalDisk ».

use std::collections::HashMap;

use windows::core::{HSTRING, PWSTR};
use windows::Win32::System::Performance::{
    PdhAddEnglishCounterW, PdhCloseQuery, PdhCollectQueryData, PdhGetFormattedCounterArrayW, PdhOpenQueryW,
    PDH_FMT, PDH_FMT_COUNTERVALUE_ITEM_W, PDH_HCOUNTER, PDH_HQUERY,
};

/// PDH_FMT_DOUBLE | PDH_FMT_NOCAP100
const FMT: PDH_FMT = PDH_FMT(0x0200 | 0x8000);
const PDH_MORE_DATA: u32 = 0x8000_07D2;

pub struct Query {
    q: PDH_HQUERY,
    counters: Vec<PDH_HCOUNTER>,
}

// la requete n'est utilisee que derriere un Mutex
unsafe impl Send for Query {}

impl Query {
    /// Une requete avec ces compteurs (chemins anglais, ex. `\GPU Engine(*)\Utilization Percentage`).
    pub fn new(paths: &[&str]) -> Option<Query> {
        unsafe {
            let mut q = PDH_HQUERY::default();
            if PdhOpenQueryW(None, 0, &mut q) != 0 {
                return None;
            }
            let counters = paths
                .iter()
                .map(|p| {
                    let mut c = PDH_HCOUNTER::default();
                    PdhAddEnglishCounterW(q, &HSTRING::from(*p), 0, &mut c);
                    c
                })
                .collect();
            let me = Query { q, counters };
            // premiere mesure : les taux se calculent entre deux collectes
            PdhCollectQueryData(q);
            Some(me)
        }
    }

    pub fn collect(&self) {
        unsafe {
            PdhCollectQueryData(self.q);
        }
    }

    /// Valeurs du compteur `i`, par instance (« _Total », « pid_1234_luid_... »).
    pub fn values(&self, i: usize) -> Vec<(String, f64)> {
        let Some(&c) = self.counters.get(i) else { return Vec::new() };
        if c.is_invalid() {
            return Vec::new();
        }
        unsafe {
            let (mut size, mut n) = (0u32, 0u32);
            if PdhGetFormattedCounterArrayW(c, FMT, &mut size, &mut n, None) != PDH_MORE_DATA {
                return Vec::new();
            }
            // tampon aligne sur 8 : les items contiennent des f64
            let mut buf = vec![0u64; (size as usize).div_ceil(8) + 1];
            let items = buf.as_mut_ptr() as *mut PDH_FMT_COUNTERVALUE_ITEM_W;
            if PdhGetFormattedCounterArrayW(c, FMT, &mut size, &mut n, Some(items)) != 0 {
                return Vec::new();
            }
            (0..n as usize)
                .filter_map(|k| {
                    let it = &*items.add(k);
                    // 0 = PDH_CSTATUS_VALID_DATA, 1 = PDH_CSTATUS_NEW_DATA
                    if it.FmtValue.CStatus > 1 {
                        return None;
                    }
                    let name = PWSTR(it.szName.0).to_string().unwrap_or_default();
                    Some((name, it.FmtValue.Anonymous.doubleValue))
                })
                .collect()
        }
    }

    /// Valeur de l'instance `inst` (ex. « _Total »).
    pub fn value(&self, i: usize, inst: &str) -> Option<f64> {
        self.values(i).into_iter().find(|(n, _)| n == inst).map(|(_, v)| v)
    }
}

impl Drop for Query {
    fn drop(&mut self) {
        unsafe {
            PdhCloseQuery(self.q);
        }
    }
}

/// GPU par processus, comme la colonne GPU du Gestionnaire des taches : pour
/// chaque processus, le moteur (3D, Copy, Video Decode...) le plus charge.
/// Renvoie aussi la charge globale (moteur le plus charge, tous processus).
pub fn gpu_by_pid(vals: &[(String, f64)]) -> (HashMap<u32, f64>, f64) {
    let mut per: HashMap<(u32, String), f64> = HashMap::new();
    let mut engines: HashMap<String, f64> = HashMap::new();
    for (name, v) in vals {
        // pid_1234_luid_0x00000000_0x0000D1A6_phys_0_eng_0_engtype_3D
        let Some(rest) = name.strip_prefix("pid_") else { continue };
        let Some((pid, rest)) = rest.split_once('_') else { continue };
        let Ok(pid) = pid.parse::<u32>() else { continue };
        let engine = rest.split("_engtype_").next().unwrap_or(rest).to_string();
        *per.entry((pid, engine.clone())).or_default() += v;
        *engines.entry(engine).or_default() += v;
    }
    let mut out: HashMap<u32, f64> = HashMap::new();
    for ((pid, _), v) in per {
        let e = out.entry(pid).or_default();
        *e = e.max(v);
    }
    let total = engines.values().cloned().fold(0.0, f64::max).min(100.0);
    (out, total)
}
