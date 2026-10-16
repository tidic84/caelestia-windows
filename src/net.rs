//! Reglages rapides reseau : radios Wi-Fi / Bluetooth (activer, couper),
//! reseaux Wi-Fi visibles (WLAN API) et appareils Bluetooth connectes.

use std::time::Duration;

use serde::Serialize;
use crate::host::{AppHandle};
use windows::core::{GUID, HSTRING, PCWSTR};
use windows::Devices::Bluetooth::{BluetoothConnectionStatus, BluetoothDevice, BluetoothLEDevice};
use windows::Devices::Enumeration::DeviceInformation;
use windows::Devices::Radios::{Radio, RadioKind, RadioState};
use windows::Win32::Foundation::HANDLE;
use windows::Win32::NetworkManagement::WiFi::{
    dot11_BSS_type_infrastructure, wlan_connection_mode_profile, WlanCloseHandle, WlanConnect,
    WlanDisconnect, WlanEnumInterfaces, WlanFreeMemory, WlanGetAvailableNetworkList, WlanOpenHandle,
    WlanScan, WlanSetProfile, DOT11_AUTH_ALGO_RSNA_PSK, DOT11_AUTH_ALGO_WPA3_SAE,
    DOT11_AUTH_ALGO_WPA_PSK, DOT11_CIPHER_ALGO_CCMP, DOT11_CIPHER_ALGO_TKIP,
    WLAN_AVAILABLE_NETWORK, WLAN_AVAILABLE_NETWORK_CONNECTED, WLAN_AVAILABLE_NETWORK_HAS_PROFILE,
    WLAN_CONNECTION_PARAMETERS, WLAN_INTERFACE_INFO_LIST, WLAN_AVAILABLE_NETWORK_LIST,
};

// ------------------------------------------------------------------ radios

fn radio(kind: RadioKind) -> Option<Radio> {
    let _ = Radio::RequestAccessAsync().ok()?.get();
    let list = Radio::GetRadiosAsync().ok()?.get().ok()?;
    list.into_iter().find(|r| r.Kind().ok() == Some(kind))
}

#[derive(Serialize, Clone, PartialEq)]
pub struct Radios {
    /// `None` = pas de carte
    wifi: Option<bool>,
    bluetooth: Option<bool>,
}

pub fn radios_get() -> Radios {
    let on = |k| radio(k).and_then(|r| r.State().ok()).map(|s| s == RadioState::On);
    Radios { wifi: on(RadioKind::WiFi), bluetooth: on(RadioKind::Bluetooth) }
}

pub fn radio_set(kind: String, on: bool) -> bool {
    let k = if kind == "wifi" { RadioKind::WiFi } else { RadioKind::Bluetooth };
    let Some(r) = radio(k) else { return false };
    let st = if on { RadioState::On } else { RadioState::Off };
    r.SetStateAsync(st).and_then(|op| op.get()).is_ok() && r.State().ok() == Some(st)
}

// -------------------------------------------------------------------- Wi-Fi

/// Session WLAN + premiere carte Wi-Fi.
struct Wlan {
    h: HANDLE,
    guid: GUID,
}

impl Wlan {
    fn open() -> Option<Self> {
        unsafe {
            let (mut ver, mut h) = (0u32, HANDLE::default());
            if WlanOpenHandle(2, None, &mut ver, &mut h) != 0 {
                return None;
            }
            let mut list: *mut WLAN_INTERFACE_INFO_LIST = std::ptr::null_mut();
            if WlanEnumInterfaces(h, None, &mut list) != 0 || list.is_null() {
                WlanCloseHandle(h, None);
                return None;
            }
            let n = (*list).dwNumberOfItems;
            let guid = (n > 0).then(|| (*list).InterfaceInfo[0].InterfaceGuid);
            WlanFreeMemory(list as _);
            match guid {
                Some(guid) => Some(Wlan { h, guid }),
                None => {
                    WlanCloseHandle(h, None);
                    None
                }
            }
        }
    }

    fn networks(&self) -> Vec<WLAN_AVAILABLE_NETWORK> {
        unsafe {
            let mut list: *mut WLAN_AVAILABLE_NETWORK_LIST = std::ptr::null_mut();
            if WlanGetAvailableNetworkList(self.h, &self.guid, 0, None, &mut list) != 0 || list.is_null() {
                return Vec::new();
            }
            let n = (*list).dwNumberOfItems as usize;
            let items = std::slice::from_raw_parts((*list).Network.as_ptr(), n).to_vec();
            WlanFreeMemory(list as _);
            items
        }
    }
}

impl Drop for Wlan {
    fn drop(&mut self) {
        unsafe {
            WlanCloseHandle(self.h, None);
        }
    }
}

fn ssid(n: &WLAN_AVAILABLE_NETWORK) -> String {
    let len = (n.dot11Ssid.uSSIDLength as usize).min(32);
    String::from_utf8_lossy(&n.dot11Ssid.ucSSID[..len]).into_owned()
}

fn wide(s: &[u16]) -> String {
    let end = s.iter().position(|&c| c == 0).unwrap_or(s.len());
    String::from_utf16_lossy(&s[..end])
}

#[derive(Serialize)]
pub struct Network {
    ssid: String,
    signal: u32,
    secure: bool,
    connected: bool,
    known: bool,
}

pub fn wifi_list(scan: bool) -> Vec<Network> {
    let Some(w) = Wlan::open() else { return Vec::new() };
    if scan {
        unsafe { WlanScan(w.h, &w.guid, None, None, None) };
        // le scan est asynchrone : on laisse le temps aux reponses d'arriver
        std::thread::sleep(Duration::from_millis(2500));
    }
    let mut out: Vec<Network> = Vec::new();
    for n in w.networks() {
        let name = ssid(&n);
        if name.is_empty() {
            continue;
        }
        let net = Network {
            signal: n.wlanSignalQuality,
            secure: n.bSecurityEnabled.as_bool(),
            connected: n.dwFlags & WLAN_AVAILABLE_NETWORK_CONNECTED != 0,
            known: n.dwFlags & WLAN_AVAILABLE_NETWORK_HAS_PROFILE != 0,
            ssid: name,
        };
        // un meme reseau apparait une fois par profil + une fois sans
        if let Some(o) = out.iter_mut().find(|o| o.ssid == net.ssid) {
            o.connected |= net.connected;
            o.known |= net.known;
            o.signal = o.signal.max(net.signal);
        } else {
            out.push(net);
        }
    }
    out.sort_by(|a, b| b.connected.cmp(&a.connected).then(b.signal.cmp(&a.signal)));
    out
}

fn xml_escape(s: &str) -> String {
    s.replace('&', "&amp;").replace('<', "&lt;").replace('>', "&gt;").replace('"', "&quot;").replace('\'', "&apos;")
}

/// Se connecte a `ssid`. Pour un reseau inconnu, cree le profil (avec le
/// mot de passe s'il est protege). Renvoie un message d'erreur, ou rien.
pub fn wifi_connect(ssid_name: String, password: Option<String>) -> Result<(), String> {
    let w = Wlan::open().ok_or("Pas de carte Wi-Fi")?;
    let nets = w.networks();
    let entries: Vec<_> = nets.iter().filter(|n| ssid(n) == ssid_name).collect();
    let first = entries.first().ok_or("Réseau introuvable")?;
    let mut profile = entries
        .iter()
        .find(|n| n.dwFlags & WLAN_AVAILABLE_NETWORK_HAS_PROFILE != 0)
        .map(|n| wide(&n.strProfileName));
    if profile.is_none() || password.is_some() {
        let secure = first.bSecurityEnabled.as_bool();
        let auth = match first.dot11DefaultAuthAlgorithm {
            a if a == DOT11_AUTH_ALGO_WPA3_SAE => "WPA3SAE",
            a if a == DOT11_AUTH_ALGO_RSNA_PSK => "WPA2PSK",
            a if a == DOT11_AUTH_ALGO_WPA_PSK => "WPAPSK",
            _ if !secure => "open",
            _ => return Err("Ce type de réseau (entreprise) n'est pas pris en charge".into()),
        };
        let enc = match first.dot11DefaultCipherAlgorithm {
            c if c == DOT11_CIPHER_ALGO_CCMP => "AES",
            c if c == DOT11_CIPHER_ALGO_TKIP => "TKIP",
            _ if !secure => "none",
            _ => "AES",
        };
        let key = match (&password, secure) {
            (Some(p), true) => format!(
                "<sharedKey><keyType>passPhrase</keyType><protected>false</protected><keyMaterial>{}</keyMaterial></sharedKey>",
                xml_escape(p)
            ),
            (None, true) => return Err("password".into()),
            _ => String::new(),
        };
        let name = xml_escape(&ssid_name);
        let xml = format!(
            r#"<?xml version="1.0"?><WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1"><name>{name}</name><SSIDConfig><SSID><name>{name}</name></SSID></SSIDConfig><connectionType>ESS</connectionType><connectionMode>auto</connectionMode><MSM><security><authEncryption><authentication>{auth}</authentication><encryption>{enc}</encryption><useOneX>false</useOneX></authEncryption>{key}</security></MSM></WLANProfile>"#
        );
        let mut reason = 0u32;
        let r = unsafe {
            WlanSetProfile(w.h, &w.guid, 0, &HSTRING::from(xml), PCWSTR::null(), true, None, &mut reason)
        };
        if r != 0 {
            return Err(format!("Profil refusé ({r})"));
        }
        profile = Some(ssid_name.clone());
    }
    let prof = HSTRING::from(profile.unwrap_or_default());
    let params = WLAN_CONNECTION_PARAMETERS {
        wlanConnectionMode: wlan_connection_mode_profile,
        strProfile: PCWSTR(prof.as_ptr()),
        pDot11Ssid: std::ptr::null_mut(),
        pDesiredBssidList: std::ptr::null_mut(),
        dot11BssType: dot11_BSS_type_infrastructure,
        dwFlags: 0,
    };
    match unsafe { WlanConnect(w.h, &w.guid, &params, None) } {
        0 => Ok(()),
        e => Err(format!("Connexion impossible ({e})")),
    }
}

pub fn wifi_disconnect() {
    if let Some(w) = Wlan::open() {
        unsafe { WlanDisconnect(w.h, &w.guid, None) };
    }
}

// ---------------------------------------------------------------- Bluetooth

fn connected_bt() -> Vec<String> {
    let mut names = Vec::new();
    let sels = [
        BluetoothDevice::GetDeviceSelectorFromConnectionStatus(BluetoothConnectionStatus::Connected),
        BluetoothLEDevice::GetDeviceSelectorFromConnectionStatus(BluetoothConnectionStatus::Connected),
    ];
    for sel in sels.into_iter().flatten() {
        let Ok(list) = DeviceInformation::FindAllAsyncAqsFilter(&sel).and_then(|op| op.get()) else { continue };
        for d in list {
            if let Ok(n) = d.Name() {
                let n = n.to_string();
                if !n.is_empty() && !names.contains(&n) {
                    names.push(n);
                }
            }
        }
    }
    names.sort();
    names
}

#[derive(Serialize, Clone, PartialEq)]
pub struct NetState {
    radios: Radios,
    ssid: String,
    bt_devices: Vec<String>,
}

/// Emet `net` quand l'etat change, et une activite `bt` quand un appareil
/// Bluetooth se connecte.
pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        crate::com_init_mta();
        let mut last: Option<NetState> = None;
        loop {
            let radios = radios_get();
            let ssid = if radios.wifi == Some(true) {
                Wlan::open()
                    .map(|w| w.networks().iter().find(|n| n.dwFlags & WLAN_AVAILABLE_NETWORK_CONNECTED != 0).map(ssid).unwrap_or_default())
                    .unwrap_or_default()
            } else {
                String::new()
            };
            let bt_devices = if radios.bluetooth == Some(true) { connected_bt() } else { Vec::new() };
            let now = NetState { radios, ssid, bt_devices };
            if last.as_ref() != Some(&now) {
                if let Some(prev) = &last {
                    for d in &now.bt_devices {
                        if !prev.bt_devices.contains(d) {
                            let _ = app.emit("activity", serde_json::json!({ "kind": "bt", "name": d, "on": true }));
                        }
                    }
                    for d in &prev.bt_devices {
                        if !now.bt_devices.contains(d) {
                            let _ = app.emit("activity", serde_json::json!({ "kind": "bt", "name": d, "on": false }));
                        }
                    }
                }
                let _ = app.emit("net", &now);
                last = Some(now);
            }
            std::thread::sleep(Duration::from_secs(3));
        }
    });
}

pub fn net_get() -> NetState {
    crate::com_init_mta();
    let radios = radios_get();
    let ssid = Wlan::open()
        .map(|w| w.networks().iter().find(|n| n.dwFlags & WLAN_AVAILABLE_NETWORK_CONNECTED != 0).map(ssid).unwrap_or_default())
        .unwrap_or_default();
    let bt_devices = if radios.bluetooth == Some(true) { connected_bt() } else { Vec::new() };
    NetState { radios, ssid, bt_devices }
}
