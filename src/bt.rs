//! Selecteur Bluetooth (onglet Controles) : appareils appaires, recherche et
//! appairage des nouveaux, connexion des appareils audio, oubli.

use std::collections::HashMap;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::Mutex;
use std::time::{Duration, Instant};

use serde::Serialize;
use windows::core::{Interface, Ref, HSTRING, PCWSTR};
use windows::Devices::Bluetooth::{BluetoothDevice, BluetoothLEDevice};
use windows::Devices::Enumeration::{
    DeviceInformation, DeviceInformationCustomPairing, DeviceInformationUpdate, DevicePairingKinds,
    DevicePairingRequestedEventArgs, DevicePairingResultStatus, DeviceUnpairingResultStatus, DeviceWatcher,
    DeviceWatcherStatus,
};
use windows::Foundation::{Deferral, IPropertyValue, TypedEventHandler};
use windows::Win32::Media::Audio::{eAll, IDeviceTopology, IMMDeviceEnumerator, MMDeviceEnumerator, DEVICE_STATE, DEVICE_STATEMASK_ALL};
use windows::Win32::Media::KernelStreaming::{
    IKsControl, KSIDENTIFIER, KSIDENTIFIER_0_0, KSPROPERTY_ONESHOT_DISCONNECT, KSPROPERTY_ONESHOT_RECONNECT,
    KSPROPERTY_TYPE_GET, KSPROPSETID_BtAudio,
};
use windows::Win32::System::Com::{CoCreateInstance, CoTaskMemFree, CLSCTX_ALL};
use windows_collections::IIterable;

use crate::host::AppHandle;

const WAIT_MS: u64 = 4000;

const CONNECTED: &str = "System.Devices.Aep.IsConnected";
const COD_MAJOR: &str = "System.Devices.Aep.Bluetooth.Cod.Major";
const COD_MINOR: &str = "System.Devices.Aep.Bluetooth.Cod.Minor";
const LE_CAT: &str = "System.Devices.Aep.Bluetooth.Le.Appearance.Category";
const LE_SUB: &str = "System.Devices.Aep.Bluetooth.Le.Appearance.Subcategory";
const LE_CONNECTABLE: &str = "System.Devices.Aep.Bluetooth.Le.IsConnectable";

fn props() -> IIterable<HSTRING> {
    IIterable::from(
        [CONNECTED, COD_MAJOR, COD_MINOR, LE_CAT, LE_SUB, LE_CONNECTABLE].map(HSTRING::from).to_vec(),
    )
}

fn prop(d: &DeviceInformation, key: &str) -> Option<IPropertyValue> {
    d.Properties().ok()?.Lookup(&HSTRING::from(key)).ok()?.cast().ok()
}

fn prop_bool(d: &DeviceInformation, key: &str) -> Option<bool> {
    prop(d, key)?.GetBoolean().ok()
}

fn prop_u16(d: &DeviceInformation, key: &str) -> u16 {
    prop(d, key).and_then(|v| v.GetUInt16().ok()).unwrap_or(0)
}

fn lock<T>(m: &Mutex<T>) -> std::sync::MutexGuard<'_, T> {
    m.lock().unwrap_or_else(|e| e.into_inner())
}

#[derive(Serialize)]
pub struct BtDevice {
    id: String,
    name: String,
    paired: bool,
    connected: bool,
    /// icone Material Symbols
    icon: &'static str,
    /// casque, enceinte : connexion et deconnexion possibles depuis l'ilot
    audio: bool,
}

fn device(d: &DeviceInformation, paired: bool) -> Option<BtDevice> {
    let name = d.Name().ok()?.to_string();
    if name.trim().is_empty() {
        return None;
    }
    let id = d.Id().ok()?.to_string();
    let le = id.starts_with("BluetoothLE#");
    // classe de l'appareil (Bluetooth classique) ou apparence (BLE)
    let (major, minor) = (prop_u16(d, COD_MAJOR), prop_u16(d, COD_MINOR));
    let (cat, sub) = (prop_u16(d, LE_CAT), prop_u16(d, LE_SUB));
    let icon = match (le, major, cat) {
        (false, 1, _) | (true, _, 2) => "computer",
        (false, 2, _) | (true, _, 1) => "smartphone",
        (false, 4, _) if minor == 5 => "speaker",
        (false, 4, _) => "headphones",
        (false, 5, _) if minor & 0x20 != 0 => "mouse",
        (false, 5, _) if minor & 0x10 != 0 => "keyboard",
        (false, 5, _) => "sports_esports",
        (true, _, 15) if sub == 1 => "keyboard",
        (true, _, 15) if sub == 2 => "mouse",
        (true, _, 15) => "sports_esports",
        _ => "bluetooth",
    };
    Some(BtDevice {
        connected: prop_bool(d, CONNECTED).unwrap_or(false),
        audio: !le && major == 4,
        icon,
        paired,
        name,
        id,
    })
}

// ---------------------------------------------------------------- recherche

/// Appareils trouves par la recherche en cours, par identifiant
static FOUND: Mutex<Option<HashMap<String, DeviceInformation>>> = Mutex::new(None);
/// Recherche en cours et dernier `bt_list` : la feuille fermee sans
/// `bt_scan(false)` (ilot replie, appli rechargee) ne doit pas chercher
/// indefiniment.
static SCAN: Mutex<Option<(Vec<DeviceWatcher>, Instant)>> = Mutex::new(None);

fn scan_stop() {
    if let Some((ws, _)) = lock(&SCAN).take() {
        for w in ws {
            let _ = w.Stop();
        }
    }
    *lock(&FOUND) = None;
}

fn watcher(aqs: HSTRING) -> windows::core::Result<DeviceWatcher> {
    let w = DeviceInformation::CreateWatcherAqsFilterAndAdditionalProperties(&aqs, &props())?;
    w.Added(&TypedEventHandler::new(|_, d: Ref<DeviceInformation>| {
        if let (Some(d), Some(map)) = (d.as_ref(), lock(&FOUND).as_mut()) {
            map.insert(d.Id()?.to_string(), d.clone());
        }
        Ok(())
    }))?;
    w.Updated(&TypedEventHandler::new(|_, u: Ref<DeviceInformationUpdate>| {
        if let (Some(u), Some(map)) = (u.as_ref(), lock(&FOUND).as_mut()) {
            if let Some(d) = map.get(&u.Id()?.to_string()) {
                d.Update(u)?;
            }
        }
        Ok(())
    }))?;
    w.Removed(&TypedEventHandler::new(|_, u: Ref<DeviceInformationUpdate>| {
        if let (Some(u), Some(map)) = (u.as_ref(), lock(&FOUND).as_mut()) {
            map.remove(&u.Id()?.to_string());
        }
        Ok(())
    }))?;
    w.Start()?;
    Ok(w)
}

/// Lance ou arrete la recherche des appareils a proximite (non appaires).
pub fn bt_scan(on: bool) {
    crate::com_init_mta();
    if !on {
        scan_stop();
        return;
    }
    // radio coupee puis rallumee : Windows a interrompu la recherche
    let dead = |w: &DeviceWatcher| {
        matches!(w.Status(), Ok(DeviceWatcherStatus::Aborted | DeviceWatcherStatus::Stopped) | Err(_))
    };
    if lock(&SCAN).as_ref().is_some_and(|(ws, _)| ws.is_empty() || ws.iter().any(dead)) {
        scan_stop();
    }
    let mut scan = lock(&SCAN);
    if let Some((_, last)) = scan.as_mut() {
        *last = Instant::now();
        return;
    }
    *lock(&FOUND) = Some(HashMap::new());
    let sels = [
        BluetoothDevice::GetDeviceSelectorFromPairingState(false),
        BluetoothLEDevice::GetDeviceSelectorFromPairingState(false),
    ];
    let ws: Vec<_> = sels.into_iter().flatten().filter_map(|s| watcher(s).ok()).collect();
    *scan = Some((ws, Instant::now()));
    drop(scan);
    std::thread::spawn(|| loop {
        std::thread::sleep(Duration::from_secs(5));
        let stale = match lock(&SCAN).as_ref() {
            None => return,
            Some((_, last)) => last.elapsed() > Duration::from_secs(20),
        };
        if stale {
            scan_stop();
            return;
        }
    });
}

/// Appareils appaires, puis ceux trouves par la recherche.
pub fn bt_list() -> Vec<BtDevice> {
    crate::com_init_mta();
    if let Some((_, last)) = lock(&SCAN).as_mut() {
        *last = Instant::now();
    }
    let mut paired: Vec<BtDevice> = Vec::new();
    let sels = [
        BluetoothDevice::GetDeviceSelectorFromPairingState(true),
        BluetoothLEDevice::GetDeviceSelectorFromPairingState(true),
    ];
    for sel in sels.into_iter().flatten() {
        let Ok(list) = DeviceInformation::FindAllAsyncAqsFilterAndAdditionalProperties(&sel, &props())
            .and_then(|op| crate::wait(op, WAIT_MS))
        else {
            continue;
        };
        for d in list.into_iter().filter_map(|d| device(&d, true)) {
            // un appareil a la fois classique et BLE n'apparait qu'une fois
            // (le classique d'abord, ou celui qui est connecte)
            match paired.iter_mut().find(|o| o.name == d.name) {
                Some(o) if d.connected && !o.connected => *o = d,
                Some(_) => {}
                None => paired.push(d),
            }
        }
    }
    paired.sort_by(|a, b| b.connected.cmp(&a.connected).then(a.name.to_lowercase().cmp(&b.name.to_lowercase())));
    let mut found: Vec<BtDevice> = lock(&FOUND)
        .as_ref()
        .map(|m| {
            m.values()
                .filter(|d| prop_bool(d, LE_CONNECTABLE) != Some(false))
                .filter_map(|d| device(d, false))
                .filter(|d| !paired.iter().any(|p| p.id == d.id || p.name == d.name))
                .collect()
        })
        .unwrap_or_default();
    found.sort_by(|a, b| a.name.to_lowercase().cmp(&b.name.to_lowercase()));
    found.dedup_by(|a, b| a.name == b.name);
    paired.extend(found);
    paired
}

// --------------------------------------------------------------- appairage

/// Un seul appairage a la fois (une seule demande de code en attente)
static PAIRING: AtomicBool = AtomicBool::new(false);
/// Demande de code en attente d'une reponse de l'utilisateur
static PENDING: Mutex<Option<(DevicePairingRequestedEventArgs, Deferral)>> = Mutex::new(None);

fn info(id: &str) -> Result<DeviceInformation, String> {
    DeviceInformation::CreateFromIdAsync(&HSTRING::from(id))
        .and_then(|op| crate::wait(op, WAIT_MS))
        .map_err(|_| "Appareil introuvable".to_string())
}

/// Appaire l'appareil `id`. Un code a confirmer ou a saisir arrive dans
/// l'evenement `bt_pin` ({ id, kind: display | confirm | provide, pin }) ;
/// la reponse passe par `bt_pair_answer`.
pub fn bt_pair(app: AppHandle, id: String) -> Result<(), String> {
    if PAIRING.swap(true, Ordering::SeqCst) {
        return Err("Un appairage est déjà en cours".into());
    }
    let r = pair(app, id);
    PAIRING.store(false, Ordering::SeqCst);
    r
}

fn pair(app: AppHandle, id: String) -> Result<(), String> {
    crate::com_init_mta();
    let pairing = info(&id)?.Pairing().map_err(|e| e.message())?;
    if pairing.IsPaired().unwrap_or(false) {
        return Ok(());
    }
    let custom: DeviceInformationCustomPairing = pairing.Custom().map_err(|e| e.message())?;
    let idc = id.clone();
    custom
        .PairingRequested(&TypedEventHandler::new(move |_, a: Ref<DevicePairingRequestedEventArgs>| {
            let Some(a) = a.as_ref() else { return Ok(()) };
            let kind = a.PairingKind()?;
            let pin = a.Pin().map(|p| p.to_string()).unwrap_or_default();
            let k = match kind {
                // l'utilisateur vient de cliquer sur « Appairer »
                DevicePairingKinds::ConfirmOnly => return a.Accept(),
                DevicePairingKinds::DisplayPin => {
                    a.Accept()?;
                    "display"
                }
                DevicePairingKinds::ConfirmPinMatch => "confirm",
                DevicePairingKinds::ProvidePin => "provide",
                // non accepte : Windows refuse l'appairage
                _ => return Ok(()),
            };
            if k != "display" {
                *lock(&PENDING) = Some((a.clone(), a.GetDeferral()?));
            }
            let _ = app.emit("bt_pin", serde_json::json!({ "id": idc, "kind": k, "pin": pin }));
            Ok(())
        }))
        .map_err(|e| e.message())?;
    let kinds = DevicePairingKinds(
        DevicePairingKinds::ConfirmOnly.0
            | DevicePairingKinds::DisplayPin.0
            | DevicePairingKinds::ProvidePin.0
            | DevicePairingKinds::ConfirmPinMatch.0,
    );
    // le temps de lire et de taper un code
    let res = custom.PairAsync(kinds).and_then(|op| crate::wait(op, 90_000));
    // demande restee sans reponse : on la refuse
    if let Some((_, d)) = lock(&PENDING).take() {
        let _ = d.Complete();
    }
    let st = res.and_then(|r| r.Status()).map_err(|_| "Délai dépassé".to_string())?;
    match st {
        DevicePairingResultStatus::Paired | DevicePairingResultStatus::AlreadyPaired => Ok(()),
        DevicePairingResultStatus::NotReadyToPair => Err("Mets l’appareil en mode appairage".into()),
        DevicePairingResultStatus::AuthenticationTimeout => Err("Délai dépassé".into()),
        DevicePairingResultStatus::AuthenticationFailure => Err("Code refusé".into()),
        DevicePairingResultStatus::PairingCanceled | DevicePairingResultStatus::RejectedByHandler => {
            Err("Appairage annulé".into())
        }
        s => Err(format!("Échec de l’appairage ({})", s.0)),
    }
}

/// Reponse a la demande de code de `bt_pair` (`pin` : code saisi).
pub fn bt_pair_answer(accept: bool, pin: Option<String>) {
    if let Some((a, d)) = lock(&PENDING).take() {
        if accept {
            let _ = match pin {
                Some(p) => a.AcceptWithPin(&HSTRING::from(p)),
                None => a.Accept(),
            };
        }
        let _ = d.Complete();
    }
}

pub fn bt_unpair(id: String) -> Result<(), String> {
    crate::com_init_mta();
    let st = info(&id)?
        .Pairing()
        .and_then(|p| p.UnpairAsync())
        .and_then(|op| crate::wait(op, 15_000))
        .and_then(|r| r.Status())
        .map_err(|e| e.message())?;
    match st {
        DeviceUnpairingResultStatus::Unpaired | DeviceUnpairingResultStatus::AlreadyUnpaired => Ok(()),
        s => Err(format!("Impossible d’oublier l’appareil ({})", s.0)),
    }
}

// ------------------------------------------------------- connexion (audio)

/// Pilotes audio Bluetooth (A2DP, mains libres) de l'appareil : on les
/// retrouve par les sorties audio, meme debranchees. Le pilote porte
/// l'adresse de l'appareil (A2DP) ; la sortie, son nom (« Casque (Nom) »).
unsafe fn bt_filters(addr: &str, name: &str) -> windows::core::Result<Vec<IKsControl>> {
    let en: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
    let col = en.EnumAudioEndpoints(eAll, DEVICE_STATE(DEVICE_STATEMASK_ALL))?;
    // sans nom, l'adresse seule (sinon « ( » viserait toutes les sorties)
    let tag = if name.is_empty() { String::new() } else { format!("({name}") };
    let mut seen: Vec<String> = Vec::new();
    let mut out = Vec::new();
    for i in 0..col.GetCount()? {
        let Ok(ep) = col.Item(i) else { continue };
        let Ok(topo) = ep.Activate::<IDeviceTopology>(CLSCTX_ALL, None) else { continue };
        let Ok(p) = topo.GetConnector(0).and_then(|c| c.GetDeviceIdConnectedTo()) else { continue };
        let fid = p.to_string().unwrap_or_default();
        CoTaskMemFree(Some(p.0 as _));
        let low = fid.to_lowercase();
        if !low.contains("bth") || seen.contains(&fid) {
            continue;
        }
        if !(low.contains(addr) || (!tag.is_empty() && crate::audio::device_name(&ep).contains(&tag))) {
            continue;
        }
        let wid = HSTRING::from(&fid);
        if let Ok(ks) = en.GetDevice(PCWSTR(wid.as_ptr())).and_then(|d| d.Activate::<IKsControl>(CLSCTX_ALL, None)) {
            out.push(ks);
        }
        seen.push(fid);
    }
    Ok(out)
}

/// Connecte ou deconnecte un casque / une enceinte Bluetooth appaire.
pub fn bt_connect(id: String, on: bool) -> Result<(), String> {
    crate::com_init_mta();
    let name = info(&id)?.Name().map(|n| n.to_string()).unwrap_or_default();
    // « Bluetooth#Bluetooth<adresse du PC>-<adresse de l'appareil> »
    let addr: String = id.rsplit('-').next().unwrap_or("").chars().filter(|c| *c != ':').collect::<String>().to_lowercase();
    let filters = unsafe { bt_filters(&addr, &name) }.map_err(|e| e.message())?;
    if filters.is_empty() {
        return Err("Pas de sortie audio pour cet appareil".into());
    }
    let mut prop = KSIDENTIFIER::default();
    prop.Anonymous.Anonymous = KSIDENTIFIER_0_0 {
        Set: KSPROPSETID_BtAudio,
        Id: (if on { KSPROPERTY_ONESHOT_RECONNECT } else { KSPROPERTY_ONESHOT_DISCONNECT }).0 as u32,
        Flags: KSPROPERTY_TYPE_GET,
    };
    let mut ok = false;
    for ks in filters {
        let mut n = 0u32;
        ok |= unsafe {
            ks.KsProperty(&prop, std::mem::size_of::<KSIDENTIFIER>() as u32, std::ptr::null_mut(), 0, &mut n)
        }
        .is_ok();
    }
    if ok {
        Ok(())
    } else if on {
        Err("Connexion impossible : l’appareil est-il allumé ?".into())
    } else {
        Err("Déconnexion impossible".into())
    }
}
