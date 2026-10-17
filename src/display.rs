//! Luminosite : ecran interne des portables via WMI, ecrans externes via
//! DDC/CI (si l'ecran le permet). Emet aussi l'OSD de luminosite.

use std::mem::ManuallyDrop;
use std::time::Duration;

use serde::Serialize;
use crate::host::{AppHandle, WebviewWindow};
use windows::core::{w, BSTR};
use windows::Win32::Devices::Display::{
    DestroyPhysicalMonitors, GetMonitorBrightness, GetNumberOfPhysicalMonitorsFromHMONITOR,
    GetPhysicalMonitorsFromHMONITOR, SetMonitorBrightness, PHYSICAL_MONITOR,
};
use windows::Win32::Graphics::Gdi::{MonitorFromWindow, MONITOR_DEFAULTTONEAREST};
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
    unsafe {
        let hwnd = win.hwnd().ok()?;
        let mon = MonitorFromWindow(hwnd, MONITOR_DEFAULTTONEAREST);
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

fn ddc_get(win: &WebviewWindow) -> Option<f32> {
    with_physical(win, |pm| unsafe {
        let (mut min, mut cur, mut max) = (0u32, 0u32, 0u32);
        if GetMonitorBrightness(pm.hPhysicalMonitor, &mut min, &mut cur, &mut max) == 0 || max <= min {
            return None;
        }
        Some((cur - min) as f32 / (max - min) as f32)
    })
}

fn ddc_set(win: &WebviewWindow, level: f32) -> Option<()> {
    with_physical(win, |pm| unsafe {
        let (mut min, mut cur, mut max) = (0u32, 0u32, 0u32);
        if GetMonitorBrightness(pm.hPhysicalMonitor, &mut min, &mut cur, &mut max) == 0 || max <= min {
            return None;
        }
        let v = min + ((max - min) as f32 * level).round() as u32;
        (SetMonitorBrightness(pm.hPhysicalMonitor, v) != 0).then_some(())
    })
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

pub fn brightness_set(win: WebviewWindow, level: f32) -> bool {
    crate::com_init_mta();
    let level = level.clamp(0.0, 1.0);
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
