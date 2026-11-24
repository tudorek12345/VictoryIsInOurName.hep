//! Host copies of title buffers (decision 0007, step 3 and "Copies of title
//! memory"). Title buffers are title memory, which the host GPU cannot
//! read, so a buffer a draw uses gets a persistent host buffer of its size
//! on first use (system memory shaders may also write), and the ranges each
//! submission reads (vertex, index and constant data, buffer views) are
//! brought up to date from title memory before it runs: the 64 KiB pages
//! the title wrote since they were last copied ([`crate::watch`]: write
//! watching, or read-only guards on physical-page views), all of it where
//! neither works. A title GPU address inside the buffer is the same offset
//! in its copy. Ranges shaders write go back to title memory after the
//! submission ([`Shadow::gpu_writes`]).
//!
//! shortcut: only the ranges draws are known to read are brought up to
//! date (vertex and index buffer views, constant buffers in tables, root
//! descriptors, buffer views in tables); buffers read through directly
//! indexed heaps keep what their first use copied.

use std::collections::BTreeMap;
use std::sync::atomic::{AtomicU8, Ordering};
use std::sync::{Arc, Mutex};

use windows::Win32::Graphics::Direct3D12::ID3D12Resource;

use crate::host::{HostList, host};
use crate::watch::PAGE;

/// A title buffer's host copy.
pub(crate) struct Shadow {
    pub(crate) buffer: ID3D12Resource,
    data: *mut u8,
    gpu: u64,
    /// Where the title buffer starts and how long it is.
    start: u64,
    len: u64,
    #[cfg(feature = "diagnostics")]
    _allocation: crate::memstat::Allocation,
    /// Per page of title memory from `start`'s on: the write-watch asking
    /// after which it was last copied (0: never).
    copied: Mutex<Vec<u64>>,
    /// Whether the memory is write-watched: unknown, yes, no.
    watched: AtomicU8,
    /// Ranges shaders of a submission not yet copied back may be writing:
    /// title memory there is older than the copy.
    pending: Mutex<Vec<(usize, usize)>>,
    /// The copy's bytes before the submission ran, from an offset on,
    /// covering the ranges its shaders write: what the GPU wrote differs.
    before: Mutex<Option<(usize, Vec<u8>)>>,
}

/// Snapshot memory kept for reuse (already touched, so no page faults).
static POOL: Mutex<Vec<Vec<u8>>> = Mutex::new(Vec::new());

/// An empty buffer with room for `n` bytes, from the pool if it has one.
fn pooled(n: usize) -> Vec<u8> {
    let mut pool = POOL.lock().unwrap_or_else(|e| e.into_inner());
    let fit = pool
        .iter()
        .enumerate()
        .filter(|(_, v)| v.capacity() >= n)
        .min_by_key(|(_, v)| v.capacity())
        .map(|(i, _)| i);
    let mut v = match fit {
        Some(i) => pool.swap_remove(i),
        None => Vec::with_capacity(n),
    };
    v.clear();
    v
}

/// Returns a snapshot buffer to the pool, with room to reuse two of the
/// roughly 174 MiB snapshots used by world submissions.
fn give_back(v: Vec<u8>) {
    let mut pool = POOL.lock().unwrap_or_else(|e| e.into_inner());
    pool.push(v);
    const MAX_IDLE_BYTES: usize = 384 << 20;
    if pool.len() <= 8 && pool.iter().map(Vec::capacity).sum::<usize>() <= MAX_IDLE_BYTES {
        return;
    }
    pool.sort_unstable_by_key(|v| std::cmp::Reverse(v.capacity()));
    let mut remaining = MAX_IDLE_BYTES;
    pool.retain(|v| {
        let Some(left) = remaining.checked_sub(v.capacity()) else {
            return false;
        };
        remaining = left;
        true
    });
    pool.truncate(8);
}

const NOT_WATCHED: u8 = 2;

// SAFETY: D3D12 resources are free-threaded; `data` is a persistent mapping
// written only on the submitting thread.
unsafe impl Send for Shadow {}
// SAFETY: as above.
unsafe impl Sync for Shadow {}

impl Shadow {
    /// The host GPU address of a title address inside the buffer.
    pub(crate) fn gpu(&self, address: u64) -> u64 {
        self.gpu + (address - self.start)
    }

    /// Bytes from a title address to the buffer's end.
    pub(crate) fn left(&self, address: u64) -> u64 {
        (self.start + self.len).saturating_sub(address)
    }

    /// Offset of a title address from the buffer's start.
    pub(crate) fn offset(&self, address: u64) -> u64 {
        address - self.start
    }

    /// Brings `len` bytes at `address` up to date when `list` is submitted,
    /// and keeps the copy alive until the list is reset.
    pub(crate) fn refresh(self: &Arc<Self>, list: &HostList, address: u64, len: u64) {
        let len = len.min(self.start + self.len - address);
        list.defer_refresh(self, address as usize, len as usize);
    }

    fn new(buffer: ID3D12Resource, data: *mut u8, gpu: u64, start: u64, len: u64) -> Shadow {
        let pages = (start + len).div_ceil(PAGE as u64) - start / PAGE as u64;
        Shadow {
            buffer,
            data,
            gpu,
            start,
            len,
            #[cfg(feature = "diagnostics")]
            _allocation: crate::memstat::Allocation::track(
                crate::memstat::Kind::BufferShadow,
                len,
            ),
            copied: Mutex::new(vec![0; pages as usize]),
            watched: AtomicU8::new(0),
            pending: Mutex::default(),
            before: Mutex::default(),
        }
    }

    /// `[address, address + len)` cut to the buffer, as offsets in the copy.
    fn inside(&self, address: usize, len: usize) -> (usize, usize) {
        let (start, end) = (self.start as usize, (self.start + self.len) as usize);
        let from = address.clamp(start, end);
        (from - start, (address + len).clamp(from, end) - start)
    }

    /// Shaders of `list` may write `[address, address + len)` of the copy
    /// (unordered access): after the list's submission has run, the range
    /// is copied back into title memory, where the title reads it; until
    /// then no refresh copies title memory over it. Call after the
    /// [`Shadow::refresh`] that gives the shaders the title's data.
    ///
    /// shortcut: what shaders wrote is found by keeping the range's bytes
    /// before the submission (a copy per declared range and submission);
    /// a GPU-side dirty mask would save that if big ranges make it slow.
    pub(crate) fn gpu_writes(self: &Arc<Self>, list: &HostList, address: u64, len: u64) {
        let len = len.min(self.left(address));
        list.defer_gpu_write(self, address as usize, len as usize);
    }

    /// At submission, after the range's refresh: a submitted list's shaders
    /// write this range. Its bytes are kept to tell later what the GPU wrote:
    /// one snapshot per copy and submission, grown to cover every range the
    /// submission declares (the world declares overlapping views of its
    /// 174 MB heap dozens of times), in reused memory (fresh snapshots cost
    /// ~2.3 million page faults per world frame).
    pub(crate) fn writing(&self, address: usize, len: usize) {
        self.pending
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .push((address, address + len));
        let (from, to) = self.inside(address, len);
        // SAFETY: inside the mapping.
        let host = |a: usize, b: usize| unsafe { std::slice::from_raw_parts(self.data.add(a), b - a) };
        let mut before = self.before.lock().unwrap_or_else(|e| e.into_inner());
        let (start, end) = match &*before {
            Some((at, bytes)) => ((*at).min(from), (at + bytes.len()).max(to)),
            None => (from, to),
        };
        if let Some((at, bytes)) = &*before
            && (*at, at + bytes.len()) == (start, end)
        {
            return;
        }
        // Parts newly covered from the copy, the rest as it was taken.
        let mut grown = pooled(end - start);
        match before.take() {
            Some((at, bytes)) => {
                grown.extend_from_slice(host(start, at));
                grown.extend_from_slice(&bytes);
                grown.extend_from_slice(host(at + bytes.len(), end));
                give_back(bytes);
            }
            None => grown.extend_from_slice(host(start, end)),
        }
        *before = Some((start, grown));
    }

    /// After the submission ran: copies the bytes its shaders wrote back
    /// into title memory (unmapped pages left alone), and only those: the
    /// title's threads write the same buffers while the GPU runs (its
    /// command memory shares the big GPU heap with what shaders write), and
    /// putting back the copy's older bytes there broke the title's own
    /// records (a fence list read as -1, title+0x4e9b54a). Returns the bytes
    /// written.
    pub(crate) fn copy_back(&self, address: usize, len: usize) -> usize {
        let mut snapshot = self.before.lock().unwrap_or_else(|e| e.into_inner());
        let mut written = 0;
        let (from, to) = self.inside(address, len);
        let start = self.start as usize;
        if let Some((taken, before)) = &*snapshot
            && *taken <= from
            && to <= taken + before.len()
            && from < to
        {
            let before = &before[from - taken..to - taken];
            // By 64 KiB piece: the copy compared with its bytes before the
            // submission, title memory read only where the GPU wrote.
            const PIECE: usize = 64 << 10;
            let mut title = vec![0u8; PIECE];
            let mut synced = Vec::new();
            let mut at = from;
            while at < to {
                let n = (PIECE - (start + at) % PIECE).min(to - at);
                // SAFETY: inside the mapping; only the submitting thread
                // writes it.
                let host = unsafe { std::slice::from_raw_parts_mut(self.data.add(at), n) };
                let old = &before[at - from..at - from + n];
                let title = &mut title[..n];
                if host != old && crate::host::read_into((start + at) as *const u8, title) {
                    let changed = if title == old {
                        // No CPU changes in the sampled title piece. The
                        // GPU's bytes are already the merged result.
                        title.copy_from_slice(host);
                        true
                    } else {
                        // Keep the title's bytes where the GPU made no change.
                        // The shadow also takes the merged result.
                        let mut changed = false;
                        for ((t, h), o) in title.iter_mut().zip(host.iter_mut()).zip(old) {
                            if *h != *o && *t != *h {
                                *t = *h;
                                changed = true;
                            }
                            *h = *t;
                        }
                        changed
                    };
                    if changed {
                        crate::watch::writing(start + at, n);
                        crate::host::write_mapped((start + at) as *mut u8, title.as_ptr(), n);
                        written += n;
                    }
                    synced.push((start + at) / PAGE);
                }
                at += n;
            }
            // Pages made equal to title memory are current in the copy, so
            // our own write is not taken for the title's; others keep what
            // they had (a title write there shows at the next refresh).
            let (first, last) = ((start + from).div_ceil(PAGE), (start + to) / PAGE);
            if first < last
                && !synced.is_empty()
                && self.watched.load(Ordering::Relaxed) != NOT_WATCHED
                && let Some((now, _)) = crate::watch::writes(first * PAGE, last * PAGE, true)
            {
                let base = start / PAGE;
                let mut copied = self.copied.lock().unwrap_or_else(|e| e.into_inner());
                for page in synced.into_iter().filter(|p| (first..last).contains(p)) {
                    copied[page - base] = now;
                }
            }
        }
        // Every submitted step that declared the range is done with it (one
        // submission runs at a time), and the snapshot with the last range.
        let mut pending = self.pending.lock().unwrap_or_else(|e| e.into_inner());
        pending.retain(|&r| r != (address, address + len));
        if pending.is_empty()
            && let Some((_, bytes)) = snapshot.take()
        {
            give_back(bytes);
        }
        written
    }

    /// At submission: copies what changed of `[address, address + len)`
    /// since it was last copied (all of it if the memory is not
    /// write-watched). Returns the bytes copied.
    pub(crate) fn update(&self, address: usize, len: usize) -> usize {
        let (start, end) = (self.start as usize, (self.start + self.len) as usize);
        let (from, to) = (address.max(start), (address + len).min(end));
        if from >= to {
            return 0;
        }
        let mut busy: Vec<(usize, usize)> = self
            .pending
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .iter()
            .copied()
            .filter(|&(a, e)| a < to && e > from)
            .collect();
        if !busy.is_empty() {
            // Around ranges shaders are writing: the gaps, each as below
            // (in the world most submissions have such ranges; copying the
            // gaps whole cost ~1 s per frame).
            busy.sort_unstable();
            let mut at = from;
            let mut gaps = Vec::new();
            for (a, e) in busy {
                if a > at {
                    gaps.push((at, a));
                }
                at = at.max(e);
            }
            if at < to {
                gaps.push((at, to));
            }
            // GetWriteWatch and the view guard both round to whole pages.
            // Gaps touching the same page can use one result from the
            // journal. Only the free bytes are copied into the GPU shadow.
            return gaps
                .chunk_by(|left, right| (left.1 - 1) / PAGE == right.0 / PAGE)
                .map(|ranges| self.update_free(ranges))
                .sum();
        }
        self.update_free(&[(from, to)])
    }

    /// Refreshes nonempty, ordered ranges that don't contain GPU writes.
    /// The range boundaries leave gaps only inside a page.
    fn update_free(&self, ranges: &[(usize, usize)]) -> usize {
        let (from, to) = (ranges[0].0, ranges[ranges.len() - 1].1);
        if self.watched.load(Ordering::Relaxed) != NOT_WATCHED {
            if let Some((now, written)) = crate::watch::writes(from, to, true) {
                self.watched.store(1, Ordering::Relaxed);
                return ranges
                    .iter()
                    .map(|&(from, to)| {
                        let copied = self.copy_stale(from, to, now, &written);
                        #[cfg(feature = "diagnostics")]
                        {
                            use crate::copystat::{C, add};
                            add(C::Checked, (to - from) as u64);
                            add(C::Unchanged, (to - from).saturating_sub(copied) as u64);
                        }
                        copied
                    })
                    .sum();
            }
            if ranges.len() > 1 {
                // A grouped query may cross a reservation boundary.
                // Retry each range by itself before classifying the memory.
                return ranges
                    .iter()
                    .map(|range| self.update_free(std::slice::from_ref(range)))
                    .sum();
            }
            self.watched.store(NOT_WATCHED, Ordering::Relaxed);
        }
        ranges
            .iter()
            .map(|&(from, to)| {
                self.copy(from, to);
                to - from
            })
            .sum()
    }

    /// Copies the pages of `[from, to)` written after their last copy
    /// (`written`: last writes by page, in page order; `now`: this
    /// asking), whole pages within the buffer.
    fn copy_stale(&self, from: usize, to: usize, now: u64, written: &[(usize, u64)]) -> usize {
        // A page only partly in the range would stay stale for the rest and
        // be copied again by every later range in it (directly indexed SRVs
        // ask for many small ranges per page, each submission). Where no
        // shader of a submission may be writing the rest of an edge page,
        // the range takes in the whole page, within the buffer.
        let (from, to) = self.whole_edge_pages(from, to);
        let base = self.start as usize / PAGE;
        let mut copied = self.copied.lock().unwrap_or_else(|e| e.into_inner());
        let first = from / PAGE;
        let i = written.partition_point(|&(page, _)| page < first);
        let mut writes = written[i..].iter().peekable();
        let (mut bytes, mut run) = (0, None);
        let last = (to - 1) / PAGE;
        for page in first..=last {
            let write = match writes.peek() {
                Some(&&(p, w)) if p == page => {
                    writes.next();
                    w
                }
                _ => 0,
            };
            let at = &mut copied[page - base];
            if *at == 0 || write > *at {
                // A page only partly in the range is copied in part: it
                // stays stale for the rest.
                let (start, end) = (self.start as usize, (self.start + self.len) as usize);
                if (page * PAGE).max(start) >= from && ((page + 1) * PAGE).min(end) <= to {
                    *at = now;
                }
                run.get_or_insert(page);
            } else if let Some(first) = run.take() {
                bytes += self.copy((first * PAGE).max(from), (page * PAGE).min(to));
            }
        }
        // Cut to the range: next to it shaders may be writing the copy.
        if let Some(first) = run {
            bytes += self.copy((first * PAGE).max(from), ((last + 1) * PAGE).min(to));
        }
        bytes
    }

    /// `[from, to)` widened to its first and last pages' bounds (cut to the
    /// buffer), each edge only where no pending range lies in what it adds.
    fn whole_edge_pages(&self, from: usize, to: usize) -> (usize, usize) {
        let (start, end) = (self.start as usize, (self.start + self.len) as usize);
        let lo = (from / PAGE * PAGE).max(start);
        let hi = (to.div_ceil(PAGE) * PAGE).min(end);
        if lo == from && hi == to {
            return (from, to);
        }
        let pending = self.pending.lock().unwrap_or_else(|e| e.into_inner());
        let free = |a: usize, e: usize| a >= e || pending.iter().all(|&(p, q)| q <= a || p >= e);
        (
            if free(lo, from) { lo } else { from },
            if free(to, hi) { hi } else { to },
        )
    }

    /// Copies title memory `[from, to)`, cut to the buffer, into the copy.
    fn copy(&self, from: usize, to: usize) -> usize {
        let (start, end) = (self.start as usize, (self.start + self.len) as usize);
        let (from, to) = (from.max(start), to.min(end));
        // SAFETY: inside the mapping (`from` and `to` are within the buffer).
        let at = unsafe { self.data.add(from - start) };
        crate::host::copy_mapped(at, from as *const u8, to - from, false);
        to - from
    }
}

struct Entry {
    end: u64,
    shadow: Option<Arc<Shadow>>,
}

/// Title buffers by (start address, resource), with their copy once made.
static BUFFERS: Mutex<BTreeMap<(u64, usize), Entry>> = Mutex::new(BTreeMap::new());

fn buffers() -> std::sync::MutexGuard<'static, BTreeMap<(u64, usize), Entry>> {
    BUFFERS.lock().unwrap_or_else(|e| e.into_inner())
}

/// A title buffer exists at `start` (`len` bytes).
pub(crate) fn register(resource: usize, start: u64, len: u64) {
    buffers().insert(
        (start, resource),
        Entry {
            end: start + len,
            shadow: None,
        },
    );
}

/// The title released it; lists that still hold its copy keep it alive.
pub(crate) fn unregister(resource: usize, start: u64) {
    buffers().remove(&(start, resource));
}

/// The copy of the innermost title buffer holding `[address, address +
/// len)`, made on first use.
pub(crate) fn find(address: u64, len: u64) -> Option<Arc<Shadow>> {
    find_copy(address, len, true)
}

/// Looks up an already allocated copy for a diagnostic report.
#[cfg(feature = "diagnostics")]
pub(crate) fn existing(address: u64, len: u64) -> Option<Arc<Shadow>> {
    find_copy(address, len, false)
}

fn find_copy(address: u64, len: u64, allocate: bool) -> Option<Arc<Shadow>> {
    let end = address.checked_add(len.max(1))?;
    let mut map = buffers();
    let key = map
        .range(..=(address, usize::MAX))
        .rev()
        .take(64)
        .find(|(_, e)| e.end >= end)
        .map(|(k, _)| *k);
    let Some(key) = key else {
        drop(map);
        return loose(address, end, allocate);
    };
    let entry = map.get_mut(&key)?;
    if entry.shadow.is_none() {
        if !allocate {
            return None;
        }
        let len = entry.end - key.0;
        // Rounded up so that views ending in the buffer's last 256 bytes fit.
        // Shaders write some buffers (unordered access), so not upload memory.
        let (buffer, data) = host()?.shared_buffer(len.next_multiple_of(1 << 16))?;
        crate::host::name(&buffer, || format!("title buffer {:#x}+{len:#x}", key.0));
        // SAFETY: a live buffer.
        let gpu = unsafe { buffer.GetGPUVirtualAddress() };
        if len >= 16 << 20 {
            tracing::info!(
                start = format_args!("{:#x}", key.0),
                len,
                "large buffer copied to the host"
            );
        } else {
            tracing::debug!(
                start = format_args!("{:#x}", key.0),
                len,
                "buffer copied to the host"
            );
        }
        entry.shadow = Some(Arc::new(Shadow::new(buffer, data, gpu, key.0, len)));
    }
    entry.shadow.clone()
}

/// Titles also use memory outside any buffer object as GPU memory (Grand
/// Theft Auto VI's interface vertices, from its own allocator). Such memory
/// gets copies of the aligned windows it touches.
/// shortcut: copies of windows are never freed; key them to the title's
/// allocations if memory use grows.
const WINDOW: u64 = 4 << 20;

/// Copies of title memory outside buffers, by (start, length).
static LOOSE: Mutex<BTreeMap<(u64, u64), Arc<Shadow>>> = Mutex::new(BTreeMap::new());

fn loose(address: u64, end: u64, allocate: bool) -> Option<Arc<Shadow>> {
    let start = address & !(WINDOW - 1);
    let len = end.checked_next_multiple_of(WINDOW)? - start;
    let mut map = LOOSE.lock().unwrap_or_else(|e| e.into_inner());
    if let Some(shadow) = map.get(&(start, len)) {
        return Some(shadow.clone());
    }
    // Keep the same start for structured buffer element offsets, and a
    // stable choice for views already bound to this exact range.
    if let Some((_, shadow)) = map.range((start, len)..=(start, u64::MAX)).next() {
        let shadow = shadow.clone();
        if allocate {
            map.insert((start, len), shadow.clone());
        }
        return Some(shadow);
    }
    if !allocate {
        return None;
    }
    let (buffer, data) = host()?.shared_buffer(len)?;
    crate::host::name(&buffer, || format!("title memory {start:#x}+{len:#x}"));
    // SAFETY: a live buffer.
    let gpu = unsafe { buffer.GetGPUVirtualAddress() };
    tracing::debug!(
        start = format_args!("{start:#x}"),
        len,
        "loose memory copied to the host"
    );
    let shadow = Arc::new(Shadow::new(buffer, data, gpu, start, len));
    map.insert((start, len), shadow.clone());
    Some(shadow)
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn smaller_loose_views_share_existing_storage() {
        if host().is_none() {
            return;
        }
        // Only creating shadows; the guest addresses are never read.
        let start = 0x2_1000_0000;
        let large = loose(start + 48, start + WINDOW + 1, true).unwrap();
        let small = loose(start + 48, start + 256, true).unwrap();
        assert!(Arc::ptr_eq(&large, &small));
        let larger = loose(start + 48, start + 2 * WINDOW + 1, true).unwrap();
        assert!(!Arc::ptr_eq(&large, &larger));
        assert!(Arc::ptr_eq(
            &small,
            &loose(start + 64, start + 512, true).unwrap()
        ));
    }

    #[cfg(feature = "diagnostics")]
    #[test]
    fn diagnostic_lookup_uses_only_existing_shadows() {
        if host().is_none() {
            return;
        }
        let start = 0x2_2000_0000;
        assert!(existing(start, 16).is_none());
        let created = find(start, 16).unwrap();
        assert!(Arc::ptr_eq(&created, &existing(start, 16).unwrap()));
        register(1, start + 16, 16);
        assert!(existing(start + 16, 16).is_none());
        let registered = find(start + 16, 16).unwrap();
        assert!(Arc::ptr_eq(&registered, &existing(start + 16, 16).unwrap()));
        unregister(1, start + 16);
    }
}

/// For device-removed reports: the copy of title memory whose host range
/// starts closest below host GPU address `va`, and where `va` is in it.
pub(crate) fn near(va: u64) -> String {
    let mut all: Vec<(u64, u64, u64)> = buffers()
        .values()
        .filter_map(|e| e.shadow.as_deref().map(|s| (s.gpu, s.start, s.len)))
        .collect();
    all.extend(
        LOOSE
            .lock()
            .unwrap_or_else(|e| e.into_inner())
            .values()
            .map(|s| (s.gpu, s.start, s.len)),
    );
    all.sort_unstable();
    all.dedup();
    let below = all.iter().filter(|c| c.0 <= va).max();
    let above = all.iter().filter(|c| c.0 > va).min();
    let mut text = match below {
        Some(&(gpu, start, len)) => format!(
            "; the nearest title memory copy below it: {start:#x}+{len:#x} at host {gpu:#x}, offset {:#x}",
            va - gpu
        ),
        None => "; no title memory copy below it".into(),
    };
    if let Some(&(gpu, start, len)) = above {
        text.push_str(&format!(
            "; the nearest above: {start:#x}+{len:#x} at host {gpu:#x} ({} copies in all)",
            all.len()
        ));
    }
    text
}

#[cfg(test)]
mod page_tests {
    use super::*;
    use windows_sys::Win32::System::Memory::{
        MEM_COMMIT, MEM_RELEASE, MEM_RESERVE, PAGE_READWRITE, VirtualAlloc, VirtualFree,
    };

    /// A write-watched title allocation of two pages, registered as a
    /// buffer, with its copy.
    struct Watched {
        base: usize,
        shadow: Arc<Shadow>,
    }

    #[test]
    fn snapshots_and_refreshes_respect_writes_on_both_sides_of_a_pending_range() {
        let Some(t) = Watched::new() else { return };
        let page = t.base + PAGE;
        t.shadow.update(page, PAGE);
        t.shadow.writing(page + 1024, 64);
        t.shadow.writing(page + 2048, 64);
        // SAFETY: the title and the shadow each cover this whole page.
        unsafe {
            let title = page as *mut u8;
            let shadow = t.shadow.data.add(PAGE);
            for (at, value) in [(512, 1u8), (1536, 2), (2560, 3)] {
                title.add(at).write(value);
            }
            for (at, value) in [(1024, 4u8), (2048, 5)] {
                shadow.add(at).write(value);
            }
            assert_eq!(t.shadow.update(page, PAGE), PAGE - 128);
            assert_eq!(shadow.add(512).read(), 1);
            assert_eq!(shadow.add(1536).read(), 2);
            assert_eq!(shadow.add(2560).read(), 3);
            assert_eq!(shadow.add(1024).read(), 4);
            assert_eq!(shadow.add(2048).read(), 5);
            t.shadow.copy_back(page + 1024, 64);
            t.shadow.copy_back(page + 2048, 64);
            assert_eq!(title.add(1024).read(), 4);
            assert_eq!(title.add(2048).read(), 5);
        }
    }

    impl Watched {
        fn new() -> Option<Watched> {
            const MEM_WRITE_WATCH: u32 = 0x20_0000;
            crate::host::host()?;
            // SAFETY: a new committed, write-watched allocation the test owns.
            let at = unsafe {
                VirtualAlloc(
                    std::ptr::null(),
                    2 * PAGE,
                    MEM_RESERVE | MEM_COMMIT | MEM_WRITE_WATCH,
                    PAGE_READWRITE,
                )
            };
            assert!(!at.is_null());
            // Fault all the demand-zero pages in before measuring repeated
            // reads. Windows can report their first touch in GetWriteWatch.
            // SAFETY: the fresh allocation is writable for two pages.
            unsafe { at.cast::<u8>().write_bytes(0, 2 * PAGE) };
            let base = at as usize;
            register(base, base as u64, 2 * PAGE as u64);
            let shadow = find(base as u64, 2 * PAGE as u64).unwrap();
            Some(Watched { base, shadow })
        }
    }

    impl Drop for Watched {
        fn drop(&mut self) {
            unregister(self.base, self.base as u64);
            crate::watch::forget_test_allocation(self.base, 2 * PAGE);
            // SAFETY: allocated with VirtualAlloc in `new`.
            unsafe { VirtualFree(self.base as *mut _, 0, MEM_RELEASE) };
        }
    }

    /// Small ranges in one page (as directly indexed SRVs ask for them): the
    /// first copies the page, the others nothing until the title writes it.
    #[test]
    fn small_ranges_in_one_page_copy_it_once() {
        let Some(t) = Watched::new() else {
            return;
        };
        let page = t.base + PAGE;
        // SAFETY: inside the test's allocation.
        unsafe { (page as *mut u32).write(1) };
        assert_eq!(t.shadow.update(page + 16, 16), PAGE);
        for offset in (256..PAGE).step_by(4096) {
            assert_eq!(t.shadow.update(page + offset, 16), 0, "offset {offset}");
        }
        // SAFETY: inside the test's allocation.
        unsafe { ((page + 8192) as *mut u32).write(500) };
        assert_eq!(t.shadow.update(page + 16, 16), PAGE);
        // SAFETY: the copy's mapping covers the allocation.
        let copied = unsafe { t.shadow.data.add(PAGE + 8192).cast::<u32>().read() };
        assert_eq!(copied, 500);
    }

    /// Where shaders of a submission may be writing the rest of the page,
    /// the range is copied as asked and the copy there is left alone.
    #[test]
    fn edge_pages_stay_cut_next_to_pending_writes() {
        let Some(t) = Watched::new() else {
            return;
        };
        let page = t.base + PAGE;
        t.shadow.writing(page + 1024, 64);
        // SAFETY: inside the copy's mapping and the test's allocation.
        unsafe {
            t.shadow.data.add(PAGE + 1024).cast::<u32>().write(7);
            ((page + 1024) as *mut u32).write(13);
        }
        assert_eq!(t.shadow.update(page + 16, 16), 32);
        // SAFETY: inside the copy's mapping.
        let kept = unsafe { t.shadow.data.add(PAGE + 1024).cast::<u32>().read() };
        assert_eq!(kept, 7);
    }
}
