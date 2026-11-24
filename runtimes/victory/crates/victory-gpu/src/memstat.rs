//! Live allocation sizes and Windows memory usage for `VICTORY_MEMORY_STATS=1`.

use std::sync::OnceLock;
use std::sync::atomic::{AtomicU64, Ordering::Relaxed};

use windows::Win32::Graphics::Dxgi::*;
use windows_sys::Win32::System::ProcessStatus::{K32GetProcessMemoryInfo, PROCESS_MEMORY_COUNTERS_EX};
use windows_sys::Win32::System::Threading::GetCurrentProcess;

#[derive(Clone, Copy)]
pub(crate) enum Kind {
    GuestResource,
    HostTexture,
    AddressTexture,
    TextureUpload,
    BufferShadow,
}

struct Totals {
    count: AtomicU64,
    bytes: AtomicU64,
}

static LIVE: [Totals; Kind::BufferShadow as usize + 1] = [const {
    Totals {
        count: AtomicU64::new(0),
        bytes: AtomicU64::new(0),
    }
}; Kind::BufferShadow as usize + 1];

pub(crate) fn enabled() -> bool {
    static ENABLED: OnceLock<bool> = OnceLock::new();
    *ENABLED.get_or_init(|| std::env::var("VICTORY_MEMORY_STATS").as_deref() == Ok("1"))
}

/// Accounts for an allocation until its last owner drops it.
pub(crate) struct Allocation {
    kind: Kind,
    bytes: u64,
}

impl Allocation {
    pub(crate) fn track(kind: Kind, bytes: u64) -> Self {
        let bytes = if enabled() { bytes } else { 0 };
        if bytes != 0 {
            let totals = &LIVE[kind as usize];
            totals.bytes.fetch_add(bytes, Relaxed);
            totals.count.fetch_add(1, Relaxed);
        }
        Self { kind, bytes }
    }
}

impl Drop for Allocation {
    fn drop(&mut self) {
        if self.bytes != 0 {
            let totals = &LIVE[self.kind as usize];
            totals.count.fetch_sub(1, Relaxed);
            totals.bytes.fetch_sub(self.bytes, Relaxed);
        }
    }
}

fn live(kind: Kind) -> (u64, u64) {
    let totals = &LIVE[kind as usize];
    (totals.count.load(Relaxed), totals.bytes.load(Relaxed) >> 20)
}

fn segment(adapter: Option<&IDXGIAdapter3>, group: DXGI_MEMORY_SEGMENT_GROUP) -> Option<(u64, u64)> {
    let mut info = DXGI_QUERY_VIDEO_MEMORY_INFO::default();
    // SAFETY: node zero is the runtime's node and the output is sized.
    unsafe { adapter?.QueryVideoMemoryInfo(0, group, &mut info) }.ok()?;
    Some((info.CurrentUsage >> 20, info.Budget >> 20))
}

pub(crate) fn report(adapter: Option<&IDXGIAdapter3>, event: &str) {
    if !enabled() {
        return;
    }
    let mut process = PROCESS_MEMORY_COUNTERS_EX {
        cb: size_of::<PROCESS_MEMORY_COUNTERS_EX>() as u32,
        ..Default::default()
    };
    // SAFETY: our process and the extended buffer advertised by `cb`.
    let measured = unsafe {
        K32GetProcessMemoryInfo(GetCurrentProcess(), (&raw mut process).cast(), process.cb) != 0
    };
    let (_, guest_mib) = live(Kind::GuestResource);
    let (textures, texture_mib) = live(Kind::HostTexture);
    let (address_textures, address_texture_mib) = live(Kind::AddressTexture);
    let (uploads, upload_mib) = live(Kind::TextureUpload);
    let (shadows, shadow_mib) = live(Kind::BufferShadow);
    // GPU-segment usage can overlap the process and allocation figures.
    tracing::info!(
        event,
        private_mib = ?measured.then_some(process.PrivateUsage >> 20),
        working_set_mib = ?measured.then_some(process.WorkingSetSize >> 20),
        local_usage_budget_mib = ?segment(adapter, DXGI_MEMORY_SEGMENT_GROUP_LOCAL),
        nonlocal_usage_budget_mib = ?segment(adapter, DXGI_MEMORY_SEGMENT_GROUP_NON_LOCAL),
        guest_mib,
        textures,
        texture_mib,
        address_textures,
        address_texture_mib,
        uploads,
        upload_mib,
        shadows,
        shadow_mib,
        "runtime memory"
    );
}
