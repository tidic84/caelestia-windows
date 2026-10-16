//! Sortie audio : liste des peripheriques de lecture actifs et choix de celui
//! par defaut (casque, haut-parleurs...), comme le menu son de Windows.
//!
//! Windows n'offre pas d'API publique pour changer la sortie par defaut : on
//! passe par IPolicyConfig (interface non documentee de Parametres, la meme
//! qu'utilisent EarTrumpet ou SoundSwitch).

use std::ffi::c_void;

use serde::Serialize;
use windows::core::{Interface, GUID, HRESULT, HSTRING, IUnknown, PCWSTR};
use windows::Win32::Foundation::PROPERTYKEY;
use windows::Win32::Media::Audio::{
    eCommunications, eConsole, eMultimedia, eRender, ERole, IMMDevice, IMMDeviceEnumerator, MMDeviceEnumerator,
    DEVICE_STATE_ACTIVE,
};
use windows::Win32::System::Com::{CoCreateInstance, CoTaskMemFree, CLSCTX_ALL, STGM_READ};

/// PKEY_Device_FriendlyName
const FRIENDLY_NAME: PROPERTYKEY = PROPERTYKEY { fmtid: GUID::from_u128(0xa45c254e_df1c_4efd_8020_67d146a850e0), pid: 14 };
const CLSID_POLICY_CONFIG: GUID = GUID::from_u128(0x870af99c_171d_4f9e_af0d_e63df40c2bc9);
const IID_POLICY_CONFIG: GUID = GUID::from_u128(0xf8679f50_850a_41cf_9c72_430f290290c8);
/// rang de SetDefaultEndpoint dans la table d'IPolicyConfig (3 d'IUnknown + 10)
const SET_DEFAULT_ENDPOINT: usize = 13;

#[derive(Serialize)]
pub struct Output {
    id: String,
    name: String,
    default: bool,
}

pub(crate) unsafe fn dev_id(d: &IMMDevice) -> windows::core::Result<String> {
    let p = d.GetId()?;
    let s = p.to_string().unwrap_or_default();
    CoTaskMemFree(Some(p.0 as _));
    Ok(s)
}

pub(crate) unsafe fn dev_name(d: &IMMDevice) -> String {
    d.OpenPropertyStore(STGM_READ)
        .and_then(|st| st.GetValue(&FRIENDLY_NAME))
        .map(|v| v.to_string())
        .unwrap_or_default()
}

#[tauri::command(async)]
pub fn audio_outputs() -> Vec<Output> {
    crate::com_init_mta();
    let r: windows::core::Result<Vec<Output>> = unsafe {
        (|| {
            let en: IMMDeviceEnumerator = CoCreateInstance(&MMDeviceEnumerator, None, CLSCTX_ALL)?;
            let def = en.GetDefaultAudioEndpoint(eRender, eConsole).and_then(|d| dev_id(&d)).unwrap_or_default();
            let devs = en.EnumAudioEndpoints(eRender, DEVICE_STATE_ACTIVE)?;
            let mut out = Vec::new();
            for i in 0..devs.GetCount()? {
                let d = devs.Item(i)?;
                let id = dev_id(&d)?;
                out.push(Output { name: dev_name(&d), default: id == def, id });
            }
            Ok(out)
        })()
    };
    r.unwrap_or_default()
}

#[tauri::command(async)]
pub fn audio_output_set(id: String) -> bool {
    crate::com_init_mta();
    unsafe {
        let Ok(unk) = CoCreateInstance::<_, IUnknown>(&CLSID_POLICY_CONFIG, None, CLSCTX_ALL) else { return false };
        let mut p: *mut c_void = std::ptr::null_mut();
        if unk.query(&IID_POLICY_CONFIG, &mut p).is_err() || p.is_null() {
            return false;
        }
        // l'interface obtenue est liberee a la fin du bloc
        let policy = IUnknown::from_raw(p);
        let vtable = *(policy.as_raw() as *const *const usize);
        let set: unsafe extern "system" fn(*mut c_void, PCWSTR, ERole) -> HRESULT =
            std::mem::transmute(*vtable.add(SET_DEFAULT_ENDPOINT));
        let id = HSTRING::from(id);
        // jeux, musique et appels : les trois roles, comme le menu son de Windows
        [eConsole, eMultimedia, eCommunications]
            .into_iter()
            .all(|role| set(policy.as_raw(), PCWSTR(id.as_ptr()), role).is_ok())
    }
}
