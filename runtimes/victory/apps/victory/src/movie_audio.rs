//! Windows movie audio for the verified title's console mixer callback.
use std::sync::OnceLock;
use std::sync::atomic::{AtomicBool, Ordering};

use victory_loader::{ImportResolver, LoadedImage, Provenance, Resolution};
use victory_pe::ImportSymbol;

type SetSound = unsafe extern "system" fn(usize, usize) -> i32;
type OpenSound = unsafe extern "system" fn(usize, usize) -> usize;
type SetVolume = unsafe extern "system" fn(usize, u32, i32);

struct Api {
    set: SetSound,
    sound: OpenSound,
    volume: SetVolume,
}

static API: OnceLock<Api> = OnceLock::new();
static HOST_PLAYBACK: AtomicBool = AtomicBool::new(false);

pub(super) struct MovieImports<'a> {
    inner: &'a dyn ImportResolver,
    active: bool,
}

impl<'a> MovieImports<'a> {
    pub(super) fn new(
        inner: &'a dyn ImportResolver,
        dlls: &[(String, LoadedImage)],
        title_hash: &str,
    ) -> Self {
        let active = title_hash == victory_game::SCARLETT_1_0_2_1.blake3
            && std::env::var_os("VICTORY_BINK_XAUDIO2").is_none_or(|v| v != "0")
            && dlls
                .iter()
                .find(|(name, _)| name.eq_ignore_ascii_case("bink2scarlett.dll"))
                .and_then(|(_, dll)| {
                    let set = dll.export("BinkSetSoundSystem")?;
                    let sound = dll.export("BinkOpenXAudio2")?;
                    let volume = dll.export("BinkSetVolume")?;
                    // SAFETY: these named exports use the Bink Scarlett x64 ABI.
                    API.set(unsafe {
                        Api {
                            set: std::mem::transmute::<usize, SetSound>(set),
                            sound: std::mem::transmute::<usize, OpenSound>(sound),
                            volume: std::mem::transmute::<usize, SetVolume>(volume),
                        }
                    })
                    .ok()
                })
                .is_some();
        Self { inner, active }
    }
}

impl ImportResolver for MovieImports<'_> {
    fn resolve(&self, dll: &str, symbol: &ImportSymbol) -> Resolution {
        if self.active
            && dll.eq_ignore_ascii_case("bink2scarlett.dll")
            && let ImportSymbol::Name { name, .. } = symbol
        {
            let address = match name.as_str() {
                "BinkSetSoundSystem" => set_sound as *const () as usize,
                "BinkSetVolume" => set_volume as *const () as usize,
                _ => return self.inner.resolve(dll, symbol),
            };
            return Resolution::Found {
                address,
                provenance: Provenance::Hle,
            };
        }
        self.inner.resolve(dll, symbol)
    }
}

extern "system" fn default_sound(_: usize) -> usize {
    // SAFETY: zero requests the library's own engine and default mastering voice.
    unsafe { (API.get().unwrap().sound)(0, 0) }
}

extern "system" fn set_sound(callback: usize, parameter: usize) -> i32 {
    let api = API.get().unwrap();
    if callback != 0 {
        // SAFETY: Bink calls this factory with its single user parameter.
        let ok = unsafe { (api.set)(default_sound as *const () as usize, 0) };
        eprintln!("Bink movie audio: XAudio2 registration returned {ok}");
        if ok != 0 {
            HOST_PLAYBACK.store(true, Ordering::Release);
            return ok;
        }
    }
    // SAFETY: preserve the title's original registration or shutdown.
    let result = unsafe { (api.set)(callback, parameter) };
    if result != 0 {
        HOST_PLAYBACK.store(false, Ordering::Release);
    }
    result
}

extern "system" fn set_volume(handle: usize, track: u32, volume: i32) {
    if HOST_PLAYBACK.load(Ordering::Acquire) {
        // The verified title uses SetVolume with a no-op volume
        // callback. The same zero gain mutes the Windows backend.
        return;
    }
    // SAFETY: forward the playback handle, track, and raw gain argument unchanged.
    unsafe { (API.get().unwrap().volume)(handle, track, volume) };
}
