//! Depot de fichiers sur l'ilot.
//!
//! Avec les WebView2 recents, la fenetre web appartient au processus
//! msedgewebview2.exe : la cible de depot que wry inscrit dans notre processus
//! n'est jamais appelee, et comme wry interdit les depots externes a WebView2,
//! Windows affiche un sens interdit. Le glisser-deposer natif de Tauri est donc
//! coupe (`dragDropEnabled: false`) : WebView2 accepte les fichiers, la page
//! recoit les evenements HTML (dragenter / drop) et renvoie les fichiers deposes
//! avec `chrome.webview.postMessageWithAdditionalObjects("ilot-drop", files)`.
//! On lit ici leur chemin complet (ICoreWebView2File) et on l'envoie a la page
//! (`drop-paths`).

use tauri::{AppHandle, Emitter, Manager};
use webview2_com::Microsoft::Web::WebView2::Win32::{
    ICoreWebView2File, ICoreWebView2WebMessageReceivedEventArgs2,
};
use webview2_com::{take_pwstr, WebMessageReceivedEventHandler};
use windows::core::{Interface, PWSTR};

pub fn start(app: AppHandle) {
    let Some(win) = app.get_webview_window("island") else { return };
    let a = app.clone();
    let _ = win.with_webview(move |w| unsafe {
        let Ok(core) = w.controller().CoreWebView2() else {
            crate::drop_log("webview2 introuvable");
            return;
        };
        let handler = WebMessageReceivedEventHandler::create(Box::new(move |_, args| {
            let Some(args) = args else { return Ok(()) };
            let mut msg = PWSTR::null();
            if args.TryGetWebMessageAsString(&mut msg).is_err() || take_pwstr(msg) != "ilot-drop" {
                return Ok(());
            }
            let mut paths = Vec::new();
            if let Ok(objs) = args.cast::<ICoreWebView2WebMessageReceivedEventArgs2>().and_then(|a| a.AdditionalObjects()) {
                let mut n = 0u32;
                let _ = objs.Count(&mut n);
                for i in 0..n {
                    let Ok(f) = objs.GetValueAtIndex(i).and_then(|o| o.cast::<ICoreWebView2File>()) else { continue };
                    let mut p = PWSTR::null();
                    if f.Path(&mut p).is_ok() {
                        paths.push(take_pwstr(p));
                    }
                }
            }
            crate::drop_log(&format!("drop {paths:?}"));
            let _ = a.emit("drop-paths", paths);
            Ok(())
        }));
        let mut token = 0i64;
        let r = core.add_WebMessageReceived(&handler, &mut token);
        crate::drop_log(&format!("ecoute webview2 {}", if r.is_ok() { "ok" } else { "echec" }));
    });
}
