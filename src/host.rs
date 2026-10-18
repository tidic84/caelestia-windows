//! Hote de l'interface Qt : remplace les quelques services de Tauri dont les
//! modules se servent (evenements vers l'interface, etat partage, fenetres,
//! dossier de configuration). L'application Qt (qt/src) charge cette
//! bibliotheque, lui donne une fonction pour recevoir les evenements et lui
//! declare ses fenetres par label (`island`, `bar-DISPLAY2`...).

use std::any::{Any, TypeId};
use std::collections::HashMap;
use std::ffi::{c_char, CString};
use std::ops::Deref;
use std::path::PathBuf;
use std::sync::{Mutex, OnceLock, RwLock};

use serde::Serialize;
use windows::Win32::Foundation::HWND;

/// Recoit chaque evenement : nom puis charge utile en JSON (C, UTF-8).
pub type EmitFn = unsafe extern "C" fn(name: *const c_char, json: *const c_char);

static EMIT: OnceLock<EmitFn> = OnceLock::new();

pub(crate) fn set_emitter(f: EmitFn) {
    let _ = EMIT.set(f);
}

fn emit_json(name: &str, json: &str) {
    let Some(f) = EMIT.get() else { return };
    let (Ok(n), Ok(j)) = (CString::new(name), CString::new(json)) else { return };
    unsafe { f(n.as_ptr(), j.as_ptr()) }
}

// ------------------------------------------------------------------ etat

type States = HashMap<TypeId, &'static (dyn Any + Send + Sync)>;
static STATES: RwLock<Option<States>> = RwLock::new(None);

/// Etat partage d'un type donne, comme `tauri::State`.
pub struct State<'a, T>(&'a T);

#[cfg(test)]
impl<'a, T> State<'a, T> {
    pub fn of(v: &'a T) -> Self {
        State(v)
    }
}

impl<T> Deref for State<'_, T> {
    type Target = T;
    fn deref(&self) -> &T {
        self.0
    }
}

// --------------------------------------------------------------- fenetres

/// Fenetres declarees par l'application Qt : (label, HWND)
static WINDOWS: Mutex<Vec<(String, isize)>> = Mutex::new(Vec::new());

pub(crate) fn register(label: &str, hwnd: isize) {
    let mut w = WINDOWS.lock().unwrap();
    w.retain(|(l, _)| l != label);
    w.push((label.to_string(), hwnd));
}

pub(crate) fn unregister(label: &str) {
    WINDOWS.lock().unwrap().retain(|(l, _)| l != label);
}

// --------------------------------------------------------------- AppHandle

/// Acces aux services de l'hote (une seule application par processus).
#[derive(Clone, Copy, Default)]
pub struct AppHandle;

static APP: AppHandle = AppHandle;

pub struct PathResolver;

impl PathResolver {
    /// `%APPDATA%\io.github.tidic84.ilot`, comme la version Tauri : les
    /// reglages sont repris tels quels.
    pub fn app_config_dir(&self) -> Result<PathBuf, String> {
        let base = std::env::var_os("APPDATA").ok_or("APPDATA absent")?;
        Ok(PathBuf::from(base).join("io.github.tidic84.ilot"))
    }
}

impl AppHandle {
    /// Envoie un evenement a l'interface.
    pub fn emit<S: Serialize>(&self, event: &str, payload: S) -> Result<(), String> {
        let json = serde_json::to_string(&payload).map_err(|e| e.to_string())?;
        emit_json(event, &json);
        Ok(())
    }

    pub fn manage<T: Send + Sync + 'static>(&self, value: T) -> bool {
        let mut st = STATES.write().unwrap();
        let map = st.get_or_insert_with(HashMap::new);
        if map.contains_key(&TypeId::of::<T>()) {
            return false;
        }
        map.insert(TypeId::of::<T>(), Box::leak(Box::new(value)));
        true
    }

    /// Etat enregistre avec `manage` (panique s'il manque, comme Tauri).
    pub fn state<T: Send + Sync + 'static>(&self) -> State<'static, T> {
        let st = STATES.read().unwrap();
        let any = st.as_ref().and_then(|m| m.get(&TypeId::of::<T>()).copied()).expect("etat non enregistre");
        State(any.downcast_ref::<T>().expect("type d'etat"))
    }

    pub fn path(&self) -> PathResolver {
        PathResolver
    }

    pub fn get_webview_window(&self, label: &str) -> Option<WebviewWindow> {
        WINDOWS
            .lock()
            .unwrap()
            .iter()
            .find(|(l, _)| l == label)
            .map(|(l, h)| WebviewWindow { label: l.clone(), hwnd: *h })
    }

    pub fn webview_windows(&self) -> HashMap<String, WebviewWindow> {
        WINDOWS
            .lock()
            .unwrap()
            .iter()
            .map(|(l, h)| (l.clone(), WebviewWindow { label: l.clone(), hwnd: *h }))
            .collect()
    }
}

/// Une fenetre de l'application Qt.
#[derive(Clone)]
pub struct WebviewWindow {
    label: String,
    hwnd: isize,
}

impl WebviewWindow {
    pub fn hwnd(&self) -> Result<HWND, String> {
        Ok(HWND(self.hwnd as _))
    }

    pub fn app_handle(&self) -> &AppHandle {
        &APP
    }

    /// Demande a Qt de donner le clavier a la fenetre.
    pub fn set_focus(&self) -> Result<(), String> {
        APP.emit("@focus", &self.label)
    }
}
