//! Luminosite : ecran interne des portables via WMI, ecrans externes via
//! DDC/CI (si l'ecran le permet). Emet aussi l'OSD de luminosite.

use std::mem::ManuallyDrop;
use std::time::Duration;

use serde::Serialize;
use crate::host::{AppHandle, WebviewWindow};
use windows::core::{w, BSTR};
use windows::core::BOOL;
use windows::Win32::Devices::Display::{
    DestroyPhysicalMonitors, DisplayConfigGetDeviceInfo, GetDisplayConfigBufferSizes, GetMonitorBrightness,
    GetNumberOfPhysicalMonitorsFromHMONITOR, GetPhysicalMonitorsFromHMONITOR, QueryDisplayConfig,
    SetMonitorBrightness, DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME, DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME,
    DISPLAYCONFIG_MODE_INFO, DISPLAYCONFIG_OUTPUT_TECHNOLOGY_DISPLAYPORT_EMBEDDED,
    DISPLAYCONFIG_OUTPUT_TECHNOLOGY_INTERNAL, DISPLAYCONFIG_OUTPUT_TECHNOLOGY_LVDS,
    DISPLAYCONFIG_OUTPUT_TECHNOLOGY_UDI_EMBEDDED, DISPLAYCONFIG_PATH_INFO, DISPLAYCONFIG_SOURCE_DEVICE_NAME,
    DISPLAYCONFIG_TARGET_DEVICE_NAME, PHYSICAL_MONITOR, QDC_ONLY_ACTIVE_PATHS,
};
use windows::Win32::Foundation::{ERROR_INSUFFICIENT_BUFFER, ERROR_SUCCESS, LPARAM, RECT};
use windows::Win32::Graphics::Gdi::{
    EnumDisplayMonitors, GetMonitorInfoW, MonitorFromWindow, HDC, HMONITOR, MONITORINFO, MONITORINFOEXW,
    MONITOR_DEFAULTTONEAREST,
};
use windows::Win32::UI::WindowsAndMessaging::MONITORINFOF_PRIMARY;
use windows::Win32::System::Com::{
    CoCreateInstance, CoSetProxyBlanket, CLSCTX_INPROC_SERVER, EOAC_NONE, RPC_C_AUTHN_LEVEL_CALL,
    RPC_C_IMP_LEVEL_IMPERSONATE,
};
use windows::Win32::System::Rpc::{RPC_C_AUTHN_WINNT, RPC_C_AUTHZ_NONE};
use windows::Win32::System::Variant::{VARIANT, VARIANT_0, VARIANT_0_0, VARIANT_0_0_0, VT_UI1};
use windows::Win32::System::Wmi::{
    IWbemClassObject, IWbemLocator, IWbemServices, WbemLocator, WBEM_FLAG_FORWARD_ONLY,
    WBEM_FLAG_RETURN_IMMEDIATELY, WBEM_GENERIC_FLAG_TYPE, WBEM_INFINITE,
};

// --------------------------------------------------------------------- WMI

fn wmi() -> windows::core::Result<IWbemServices> {
    unsafe {
        let loc: IWbemLocator = CoCreateInstance(&WbemLocator, None, CLSCTX_INPROC_SERVER)?;
        let svc = loc.ConnectServer(
            &BSTR::from(r"root\WMI"),
            &BSTR::new(),
            &BSTR::new(),
            &BSTR::new(),
            0,
            &BSTR::new(),
            None,
        )?;
        CoSetProxyBlanket(
            &svc,
            RPC_C_AUTHN_WINNT,
            RPC_C_AUTHZ_NONE,
            None,
            RPC_C_AUTHN_LEVEL_CALL,
            RPC_C_IMP_LEVEL_IMPERSONATE,
            None,
            EOAC_NONE,
        )?;
        Ok(svc)
    }
}

fn first(svc: &IWbemServices, query: &str) -> Option<IWbemClassObject> {
    unsafe {
        let en = svc
            .ExecQuery(
                &BSTR::from("WQL"),
                &BSTR::from(query),
                WBEM_GENERIC_FLAG_TYPE(WBEM_FLAG_FORWARD_ONLY.0 | WBEM_FLAG_RETURN_IMMEDIATELY.0),
                None,
            )
            .ok()?;
        let mut objs = [None];
        let mut n = 0u32;
        let _ = en.Next(WBEM_INFINITE, &mut objs, &mut n);
        if n == 0 {
            return None;
        }
        objs[0].take()
    }
}

fn wmi_get(svc: &IWbemServices) -> Option<u32> {
    let obj = first(svc, "SELECT CurrentBrightness FROM WmiMonitorBrightness")?;
    let mut v = VARIANT::default();
    unsafe { obj.Get(w!("CurrentBrightness"), 0, &mut v, None, None).ok()? };
    u32::try_from(&v).ok()
}

fn variant_u8(b: u8) -> VARIANT {
    VARIANT {
        Anonymous: VARIANT_0 {
            Anonymous: ManuallyDrop::new(VARIANT_0_0 {
                vt: VT_UI1,
                wReserved1: 0,
                wReserved2: 0,
                wReserved3: 0,
                Anonymous: VARIANT_0_0_0 { bVal: b },
            }),
        },
    }
}

fn wmi_set(svc: &IWbemServices, level: u8) -> Option<()> {
    let inst = first(svc, "SELECT * FROM WmiMonitorBrightnessMethods")?;
    unsafe {
        let mut path = VARIANT::default();
        inst.Get(w!("__PATH"), 0, &mut path, None, None).ok()?;
        let path = BSTR::try_from(&path).ok()?;
        let mut class = None;
        svc.GetObject(&BSTR::from("WmiMonitorBrightnessMethods"), WBEM_GENERIC_FLAG_TYPE(0), None, Some(&mut class), None)
            .ok()?;
        let mut sig = None;
        class?.GetMethod(w!("WmiSetBrightness"), 0, &mut sig, std::ptr::null_mut()).ok()?;
        let params = sig?.SpawnInstance(0).ok()?;
        params.Put(w!("Timeout"), 0, &VARIANT::from(0i32), 0).ok()?;
        params.Put(w!("Brightness"), 0, &variant_u8(level), 0).ok()?;
        svc.ExecMethod(&path, &BSTR::from("WmiSetBrightness"), WBEM_GENERIC_FLAG_TYPE(0), None, &params, None, None)
            .ok()
    }
}

// ----------------------------------------------------------------- DDC/CI

fn with_physical<T>(win: &WebviewWindow, f: impl Fn(&PHYSICAL_MONITOR) -> Option<T>) -> Option<T> {
    let hwnd = win.hwnd().ok()?;
    with_physical_mon(unsafe { MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST) }, f)
}

fn with_physical_mon<T>(mon: HMONITOR, f: impl Fn(&PHYSICAL_MONITOR) -> Option<T>) -> Option<T> {
    unsafe {
        let mut n = 0u32;
        GetNumberOfPhysicalMonitorsFromHMONITOR(mon, &mut n).ok()?;
        if n == 0 {
            return None;
        }
        let mut list = vec![PHYSICAL_MONITOR::default(); n as usize];
        GetPhysicalMonitorsFromHMONITOR(mon, &mut list).ok()?;
        let r = list.iter().find_map(&f);
        let _ = DestroyPhysicalMonitors(&list);
        r
    }
}

fn ddc_get_pm(pm: &PHYSICAL_MONITOR) -> Option<f32> {
    unsafe {
        let (mut min, mut cur, mut max) = (0u32, 0u32, 0u32);
        if GetMonitorBrightness(pm.hPhysicalMonitor, &mut min, &mut cur, &mut max) == 0 || max <= min {
            return None;
        }
        Some((cur.clamp(min, max) - min) as f32 / (max - min) as f32)
    }
}

fn ddc_set_pm(pm: &PHYSICAL_MONITOR, level: f32) -> Option<()> {
    unsafe {
        let (mut min, mut cur, mut max) = (0u32, 0u32, 0u32);
        if GetMonitorBrightness(pm.hPhysicalMonitor, &mut min, &mut cur, &mut max) == 0 || max <= min {
            return None;
        }
        let v = min + ((max - min) as f32 * level).round() as u32;
        (SetMonitorBrightness(pm.hPhysicalMonitor, v) != 0).then_some(())
    }
}

fn ddc_get(win: &WebviewWindow) -> Option<f32> {
    with_physical(win, ddc_get_pm)
}

fn ddc_set(win: &WebviewWindow, level: f32) -> Option<()> {
    with_physical(win, |pm| ddc_set_pm(pm, level))
}

// ------------------------------------------------------------ par ecran

/// Un ecran branche : `\\.\DISPLAYn`, son HMONITOR, principal ou non
struct Mon {
    id: String,
    handle: HMONITOR,
    primary: bool,
}

unsafe extern "system" fn add_mon(m: HMONITOR, _: HDC, _: *mut RECT, lp: LPARAM) -> BOOL {
    let v = &mut *(lp.0 as *mut Vec<Mon>);
    let mut mi = MONITORINFOEXW::default();
    mi.monitorInfo.cbSize = std::mem::size_of::<MONITORINFOEXW>() as u32;
    if GetMonitorInfoW(m, &mut mi as *mut MONITORINFOEXW as *mut MONITORINFO).as_bool() {
        let n = mi.szDevice.iter().position(|&c| c == 0).unwrap_or(mi.szDevice.len());
        v.push(Mon {
            id: String::from_utf16_lossy(&mi.szDevice[..n]),
            handle: m,
            primary: mi.monitorInfo.dwFlags & MONITORINFOF_PRIMARY != 0,
        });
    }
    true.into()
}

fn monitors() -> Vec<Mon> {
    let mut v: Vec<Mon> = Vec::new();
    unsafe {
        let _ = EnumDisplayMonitors(None, None, Some(add_mon), LPARAM(&mut v as *mut _ as isize));
    }
    v
}

fn wide(s: &[u16]) -> String {
    let n = s.iter().position(|&c| c == 0).unwrap_or(s.len());
    String::from_utf16_lossy(&s[..n])
}

/// Nom EDID (« MSI G2412F ») et ecran interne de portable, par `\\.\DISPLAYn`
fn outputs() -> Vec<(String, String, bool)> {
    let mut out = Vec::new();
    unsafe {
        // la config peut changer entre les deux appels (ecran branche) :
        // on recommence, comme le prevoit la doc Microsoft
        let mut paths = Vec::new();
        for _ in 0..3 {
            let (mut np, mut nm) = (0u32, 0u32);
            if GetDisplayConfigBufferSizes(QDC_ONLY_ACTIVE_PATHS, &mut np, &mut nm) != ERROR_SUCCESS {
                return out;
            }
            paths = vec![DISPLAYCONFIG_PATH_INFO::default(); np as usize];
            let mut modes = vec![DISPLAYCONFIG_MODE_INFO::default(); nm as usize];
            let r = QueryDisplayConfig(QDC_ONLY_ACTIVE_PATHS, &mut np, paths.as_mut_ptr(), &mut nm, modes.as_mut_ptr(), None);
            if r == ERROR_SUCCESS {
                paths.truncate(np as usize);
                break;
            }
            paths.clear();
            if r != ERROR_INSUFFICIENT_BUFFER {
                return out;
            }
        }
        for p in &paths {
            let mut src = DISPLAYCONFIG_SOURCE_DEVICE_NAME::default();
            src.header.r#type = DISPLAYCONFIG_DEVICE_INFO_GET_SOURCE_NAME;
            src.header.size = std::mem::size_of::<DISPLAYCONFIG_SOURCE_DEVICE_NAME>() as u32;
            src.header.adapterId = p.sourceInfo.adapterId;
            src.header.id = p.sourceInfo.id;
            if DisplayConfigGetDeviceInfo(&mut src.header) != 0 {
                continue;
            }
            let mut tgt = DISPLAYCONFIG_TARGET_DEVICE_NAME::default();
            tgt.header.r#type = DISPLAYCONFIG_DEVICE_INFO_GET_TARGET_NAME;
            tgt.header.size = std::mem::size_of::<DISPLAYCONFIG_TARGET_DEVICE_NAME>() as u32;
            tgt.header.adapterId = p.targetInfo.adapterId;
            tgt.header.id = p.targetInfo.id;
            let name = if DisplayConfigGetDeviceInfo(&mut tgt.header) == 0 {
                wide(&tgt.monitorFriendlyDeviceName)
            } else {
                String::new()
            };
            let t = p.targetInfo.outputTechnology;
            let internal = t == DISPLAYCONFIG_OUTPUT_TECHNOLOGY_INTERNAL
                || t == DISPLAYCONFIG_OUTPUT_TECHNOLOGY_DISPLAYPORT_EMBEDDED
                || t == DISPLAYCONFIG_OUTPUT_TECHNOLOGY_UDI_EMBEDDED
                || t == DISPLAYCONFIG_OUTPUT_TECHNOLOGY_LVDS;
            out.push((wide(&src.viewGdiDeviceName), name, internal));
        }
    }
    out
}

/// Numero de `\\.\DISPLAYn` (meme regle que le choix d'ecran des Reglages)
fn screen_num(id: &str, i: usize) -> u32 {
    let n: String = id.chars().rev().take_while(char::is_ascii_digit).collect();
    n.chars().rev().collect::<String>().parse().unwrap_or(i as u32 + 1)
}

#[derive(Serialize)]
pub struct ScreenBright {
    /// `\\.\DISPLAYn`
    id: String,
    num: u32,
    name: String,
    /// l'ilot est sur cet ecran
    here: bool,
    primary: bool,
    /// None : pas reglable (DDC/CI coupe ou absent)
    level: Option<f32>,
    source: Option<&'static str>,
}

/// Tous les ecrans, avec leur luminosite. Lent (DDC/CI) : a l'ouverture de
/// la page seulement.
pub fn brightness_list(win: WebviewWindow) -> Vec<ScreenBright> {
    crate::com_init_mta();
    let here = win.hwnd().ok().map(|h| unsafe { MonitorFromWindow(h, MONITOR_DEFAULTTONEAREST) });
    let outs = outputs();
    let mut wmi_level = None;
    let mut v: Vec<ScreenBright> = monitors()
        .into_iter()
        .enumerate()
        .map(|(i, m)| {
            let num = screen_num(&m.id, i);
            let (name, internal) = outs
                .iter()
                .find(|o| o.0 == m.id)
                .map(|o| (o.1.clone(), o.2))
                .unwrap_or_default();
            let mut level = None;
            let mut source = None;
            if internal {
                if wmi_level.is_none() {
                    wmi_level = Some(wmi().ok().and_then(|s| wmi_get(&s)));
                }
                if let Some(Some(l)) = wmi_level {
                    level = Some(l as f32 / 100.0);
                    source = Some("wmi");
                }
            }
            if level.is_none() {
                level = with_physical_mon(m.handle, ddc_get_pm);
                source = level.map(|_| "ddc");
            }
            ScreenBright {
                name: if name.is_empty() { format!("Écran {num}") } else { name },
                num,
                here: here == Some(m.handle),
                primary: m.primary,
                level,
                source,
                id: m.id,
            }
        })
        .collect();
    v.sort_by_key(|s| s.num);
    v
}

/// Regle un ecran precis (`\\.\DISPLAYn`) : WMI si c'est l'ecran interne
/// d'un portable, sinon DDC/CI.
fn set_screen(id: &str, level: f32) -> bool {
    let Some(m) = monitors().into_iter().find(|m| m.id == id) else { return false };
    if outputs().iter().any(|o| o.0 == id && o.2) {
        if let Ok(s) = wmi() {
            if wmi_get(&s).is_some() {
                return wmi_set(&s, (level * 100.0).round() as u8).is_some();
            }
        }
    }
    with_physical_mon(m.handle, |pm| ddc_set_pm(pm, level)).is_some()
}

// -------------------------------------------------------------- commandes

#[derive(Serialize)]
pub struct Brightness {
    level: f32,
    /// « wmi » (portable) ou « ddc » (ecran externe)
    source: &'static str,
}

pub fn brightness_get(win: WebviewWindow) -> Option<Brightness> {
    crate::com_init_mta();
    if let Some(v) = wmi().ok().and_then(|s| wmi_get(&s)) {
        return Some(Brightness { level: v as f32 / 100.0, source: "wmi" });
    }
    ddc_get(&win).map(|level| Brightness { level, source: "ddc" })
}

/// `screen` absent : ecran de l'ilot (comportement d'origine).
pub fn brightness_set(win: WebviewWindow, level: f32, screen: Option<String>) -> bool {
    crate::com_init_mta();
    let level = if level.is_finite() { level.clamp(0.0, 1.0) } else { return false };
    if let Some(id) = screen {
        return set_screen(&id, level);
    }
    if let Ok(s) = wmi() {
        if wmi_get(&s).is_some() {
            return wmi_set(&s, (level * 100.0).round() as u8).is_some();
        }
    }
    ddc_set(&win, level).is_some()
}

/// Sur un portable, emet `osd` quand la luminosite change (touches Fn...).
pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        crate::com_init_mta();
        let Ok(svc) = wmi() else { return };
        let Some(mut last) = wmi_get(&svc) else { return };
        // evenements WMI : reveille seulement quand la luminosite change
        let events = unsafe {
            svc.ExecNotificationQuery(
                &BSTR::from("WQL"),
                &BSTR::from("SELECT * FROM WmiMonitorBrightnessEvent"),
                WBEM_GENERIC_FLAG_TYPE(WBEM_FLAG_FORWARD_ONLY.0 | WBEM_FLAG_RETURN_IMMEDIATELY.0),
                None,
            )
        };
        if let Ok(en) = events {
            loop {
                let mut objs = [None];
                let mut n = 0u32;
                if unsafe { en.Next(WBEM_INFINITE, &mut objs, &mut n) }.is_err() {
                    break;
                }
                let Some(obj) = objs[0].take().filter(|_| n > 0) else { continue };
                let mut v = VARIANT::default();
                if unsafe { obj.Get(w!("Brightness"), 0, &mut v, None, None) }.is_err() {
                    continue;
                }
                let Ok(v) = u32::try_from(&v) else { continue };
                if v != last {
                    last = v;
                    let _ = app.emit("osd", serde_json::json!({ "kind": "brightness", "value": v as f32 / 100.0, "muted": false }));
                }
            }
        }
        // repli (service WMI arrete, evenement indisponible) : releve sonde
        loop {
            std::thread::sleep(Duration::from_millis(250));
            if let Some(v) = wmi_get(&svc) {
                if v != last {
                    last = v;
                    let _ = app.emit("osd", serde_json::json!({ "kind": "brightness", "value": v as f32 / 100.0, "muted": false }));
                }
            }
        }
    });
}
