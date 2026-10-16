//! Notifications Windows (UserNotificationListener) : la liste est relue
//! toutes les 1,5 s et chaque nouvelle notification est envoyee a l'ilot
//! (`notif`), qui s'agrandit quelques secondes pour l'afficher.

use std::collections::HashSet;

use base64::Engine;
use serde::Serialize;
use tauri::{AppHandle, Emitter};
use windows::Foundation::Size;
use windows::Storage::Streams::DataReader;
use windows::UI::Notifications::Management::{UserNotificationListener, UserNotificationListenerAccessStatus};
use windows::UI::Notifications::{KnownNotificationBindings, NotificationKinds, UserNotification};

#[derive(Serialize, Clone)]
pub struct Notif {
    app: String,
    title: String,
    body: String,
    /// logo de l'appli (data URL) ou vide
    icon: String,
}

fn icon(n: &UserNotification) -> windows::core::Result<String> {
    let logo = n.AppInfo()?.DisplayInfo()?.GetLogo(Size { Width: 64.0, Height: 64.0 })?;
    let stream = logo.OpenReadAsync()?.get()?;
    let size = stream.Size()? as u32;
    let ctype = stream.ContentType()?.to_string();
    let reader = DataReader::CreateDataReader(&stream)?;
    reader.LoadAsync(size)?.get()?;
    let mut buf = vec![0u8; size as usize];
    reader.ReadBytes(&mut buf)?;
    let ctype = if ctype.is_empty() { "image/png".into() } else { ctype };
    Ok(format!("data:{ctype};base64,{}", base64::engine::general_purpose::STANDARD.encode(buf)))
}

fn read(n: &UserNotification) -> windows::core::Result<Notif> {
    let app = n.AppInfo()?.DisplayInfo()?.DisplayName()?.to_string();
    let binding = n.Notification()?.Visual()?.GetBinding(&KnownNotificationBindings::ToastGeneric()?)?;
    let elems = binding.GetTextElements()?;
    let mut texts = Vec::new();
    for i in 0..elems.Size()? {
        let t = elems.GetAt(i)?.Text()?.to_string();
        if !t.trim().is_empty() {
            texts.push(t);
        }
    }
    let title = texts.first().cloned().unwrap_or_default();
    let body = texts.get(1..).map(|r| r.join(" · ")).unwrap_or_default();
    Ok(Notif { app, title, body, icon: icon(n).unwrap_or_default() })
}

pub fn watch(app: AppHandle) {
    std::thread::spawn(move || {
        crate::com_init_mta();
        let Ok(l) = UserNotificationListener::Current() else { return };
        // Parametres > Confidentialite > Notifications : acces refuse, rien a faire
        if l.GetAccessStatus().ok() != Some(UserNotificationListenerAccessStatus::Allowed) {
            return;
        }
        let mut seen: HashSet<u32> = HashSet::new();
        let mut first = true;
        loop {
            if let Ok(list) = l.GetNotificationsAsync(NotificationKinds::Toast).and_then(|o| o.get()) {
                let mut now = HashSet::new();
                for i in 0..list.Size().unwrap_or(0) {
                    let Ok(n) = list.GetAt(i) else { continue };
                    let Ok(id) = n.Id() else { continue };
                    now.insert(id);
                    // au demarrage, les notifications deja presentes ne sont pas rejouees
                    if !first && !seen.contains(&id) {
                        if let Ok(x) = read(&n) {
                            if !x.title.is_empty() {
                                let _ = app.emit("notif", x);
                            }
                        }
                    }
                }
                seen = now;
                first = false;
            }
            std::thread::sleep(std::time::Duration::from_millis(1500));
        }
    });
}
