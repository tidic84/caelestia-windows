//! Sous-titres en direct : Live Captions de Windows (LiveCaptions.exe)
//! reconnait la parole de tout le son du PC ; on lit son texte par UI
//! Automation, sa fenetre est rendue invisible, et le texte part vers le
//! bandeau de l'ilot (ui/captions.html, `captions`), qui le traduit.

use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::time::Duration;

use serde::Serialize;
use tauri::{AppHandle, Emitter, Manager};
use windows::core::w;
use windows::Win32::Foundation::{COLORREF, HWND, LPARAM, WPARAM};
use windows::Win32::System::Com::{CoCreateInstance, CLSCTX_INPROC_SERVER};
use windows::Win32::UI::Accessibility::{CUIAutomation, IUIAutomation, IUIAutomationElement, TreeScope_Descendants};
use windows::Win32::UI::WindowsAndMessaging::{
    FindWindowW, GetWindowLongPtrW, GetWindowRect, PostMessageW, SetLayeredWindowAttributes, SetWindowLongPtrW,
    GWL_EXSTYLE, LWA_ALPHA, WM_CLOSE, WS_EX_LAYERED, WS_EX_TOOLWINDOW, WS_EX_TRANSPARENT,
};

static ON: AtomicBool = AtomicBool::new(false);
/// generation de la boucle de lecture : une nouvelle remplace l'ancienne
static GEN: AtomicU64 = AtomicU64::new(0);

#[derive(Serialize, Clone)]
struct Caption {
    /// texte brut de Live Captions (dernieres lignes)
    text: String,
    /// etat : « starting », « ok », « docked » (fenetre ancree : la passer en flottante), « missing »
    status: &'static str,
}

fn lc_window() -> Option<HWND> {
    let h = unsafe { FindWindowW(w!("LiveCaptionsDesktopWindow"), None) }.ok()?;
    (!h.is_invalid()).then_some(h)
}

/// Fenetre de Live Captions invisible et sans clic (elle continue de travailler).
fn hide(h: HWND) {
    unsafe {
        let ex = GetWindowLongPtrW(h, GWL_EXSTYLE);
        let want = ex | (WS_EX_LAYERED.0 | WS_EX_TRANSPARENT.0 | WS_EX_TOOLWINDOW.0) as isize;
        if ex != want {
            SetWindowLongPtrW(h, GWL_EXSTYLE, want);
        }
        let _ = SetLayeredWindowAttributes(h, COLORREF(0), 0, LWA_ALPHA);
    }
}

/// Ancree en haut ou en bas de l'ecran, Live Captions reserve une bande de
/// l'ecran meme invisible : il faut la passer en « Flottante » dans ses reglages.
fn docked(h: HWND) -> bool {
    let mut r = Default::default();
    if unsafe { GetWindowRect(h, &mut r) }.is_err() {
        return false;
    }
    let mi = unsafe {
        use windows::Win32::Graphics::Gdi::{GetMonitorInfoW, MonitorFromWindow, MONITORINFO, MONITOR_DEFAULTTONEAREST};
        let mut mi = MONITORINFO { cbSize: std::mem::size_of::<MONITORINFO>() as u32, ..Default::default() };
        let _ = GetMonitorInfoW(MonitorFromWindow(h, MONITOR_DEFAULTTONEAREST), &mut mi);
        mi
    };
    let full_width = r.right - r.left >= mi.rcMonitor.right - mi.rcMonitor.left - 2;
    full_width && (r.top <= mi.rcMonitor.top + 1 || r.bottom >= mi.rcMonitor.bottom - 1)
}

/// Element texte des sous-titres (AutomationId « CaptionsTextBlock »).
fn find_text(ua: &IUIAutomation, h: HWND) -> Option<IUIAutomationElement> {
    unsafe {
        let root = ua.ElementFromHandle(h).ok()?;
        let all = root.FindAll(TreeScope_Descendants, &ua.CreateTrueCondition().ok()?).ok()?;
        for i in 0..all.Length().ok()? {
            let e = all.GetElement(i).ok()?;
            if e.CurrentAutomationId().map(|s| s.to_string()).unwrap_or_default() == "CaptionsTextBlock" {
                return Some(e);
            }
        }
    }
    None
}

/// Les 2 dernieres lignes non vides.
fn tail(s: &str) -> String {
    let lines: Vec<&str> = s.lines().map(str::trim).filter(|l| !l.is_empty()).collect();
    lines[lines.len().saturating_sub(2)..].join("\n")
}

fn run(app: AppHandle, gen: u64) {
    std::thread::spawn(move || {
        crate::com_init_mta();
        let emit = |text: String, status: &'static str| {
            let _ = app.emit("captions", Caption { text, status });
        };
        // Live Captions : lance au besoin
        if lc_window().is_none() {
            let exe = std::path::Path::new(&std::env::var("SystemRoot").unwrap_or("C:\\Windows".into())).join("System32\\LiveCaptions.exe");
            if std::process::Command::new(exe).spawn().is_err() {
                emit(String::new(), "missing");
                return;
            }
        }
        emit(String::new(), "starting");
        let Ok(ua) = (unsafe { CoCreateInstance::<_, IUIAutomation>(&CUIAutomation, None, CLSCTX_INPROC_SERVER) }) else { return };
        let mut el: Option<IUIAutomationElement> = None;
        let mut last = String::new();
        let mut was_docked = false;
        while ON.load(Ordering::Relaxed) && GEN.load(Ordering::Relaxed) == gen {
            std::thread::sleep(Duration::from_millis(350));
            let Some(h) = lc_window() else { el = None; continue };
            if el.is_none() {
                el = find_text(&ua, h);
            }
            // pas encore pret (1er lancement : telechargement de la langue a accepter) : fenetre visible
            if el.is_none() {
                continue;
            }
            hide(h);
            let d = docked(h);
            if d != was_docked {
                was_docked = d;
                emit(last.clone(), if d { "docked" } else { "ok" });
            }
            let Some(e) = &el else { continue };
            match unsafe { e.CurrentName() } {
                Ok(t) => {
                    let t = tail(&t.to_string());
                    if t != last {
                        last = t.clone();
                        emit(t, if d { "docked" } else { "ok" });
                    }
                }
                Err(_) => el = None,
            }
        }
    });
}

/// Fenetre du bandeau, transparente et sans clic, en bas de l'ecran.
fn overlay(app: &AppHandle, on: bool) {
    let win = match app.get_webview_window("captions") {
        Some(w) => w,
        None if on => match tauri::WebviewWindowBuilder::new(app, "captions", tauri::WebviewUrl::App("captions.html".into()))
            .title("Ilot sous-titres")
            .transparent(true)
            .decorations(false)
            .shadow(false)
            .always_on_top(true)
            .skip_taskbar(true)
            .resizable(false)
            .focused(false)
            .visible(false)
            .disable_drag_drop_handler()
            .build()
        {
            Ok(w) => w,
            Err(_) => return,
        },
        None => return,
    };
    if !on {
        let _ = win.hide();
        return;
    }
    if let Ok(Some(mon)) = win.primary_monitor() {
        let wa = mon.work_area();
        let s = mon.scale_factor();
        let (w, h) = (((wa.size.width as f64) * 0.62) as u32, (170.0 * s) as u32);
        let x = wa.position.x + (wa.size.width as i32 - w as i32) / 2;
        let y = wa.position.y + wa.size.height as i32 - h as i32 - (40.0 * s) as i32;
        let _ = win.set_size(tauri::PhysicalSize::new(w, h));
        let _ = win.set_position(tauri::PhysicalPosition::new(x, y));
    }
    let _ = win.set_ignore_cursor_events(true);
    let _ = win.show();
}

/// Active / coupe les sous-titres ; renvoie l'etat.
#[tauri::command]
pub fn captions_set(app: AppHandle, on: bool) -> bool {
    ON.store(on, Ordering::Relaxed);
    let gen = GEN.fetch_add(1, Ordering::Relaxed) + 1;
    overlay(&app, on);
    if on {
        run(app, gen);
    } else if let Some(h) = lc_window() {
        unsafe {
            let _ = PostMessageW(Some(h), WM_CLOSE, WPARAM(0), LPARAM(0));
        }
    }
    on
}

#[tauri::command]
pub fn captions_on() -> bool {
    ON.load(Ordering::Relaxed)
}
