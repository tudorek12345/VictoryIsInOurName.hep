//! Translated shaders kept on disk (decision 0003): under the configured
//! cache folder, keyed by the container's content and by the VIctory build
//! that translated it (the BLAKE3 of our executable), so a rebuilt
//! translator never serves an old translation. Entries go through
//! `victory-pipeline`'s content-addressed cache, which writes them
//! atomically; an entry that does not read back is translated again.
//!
//! The entry is our own encoding of [`HostShader`]: a field added to it
//! must be added to [`encode`] and [`decode`] too (entries of older builds
//! are ignored anyway).

use std::collections::HashMap;
use std::path::{Path, PathBuf};
use std::sync::atomic::{AtomicBool, AtomicU64, Ordering};
use std::sync::{LazyLock, Mutex, OnceLock, mpsc};

use victory_pipeline::{Cache, CacheKey, Converter};
use victory_shader::emit::{HostShader, StaticSampler, UserData};
use victory_shader::{HwStage, RootType};

static CACHE: OnceLock<Cache> = OnceLock::new();
static HITS: AtomicU64 = AtomicU64::new(0);
static MISSES: AtomicU64 = AtomicU64::new(0);

/// Keeps translated shaders in `dir` from now on.
pub fn use_shader_cache(dir: PathBuf) {
    match Cache::open(dir) {
        Ok(cache) => {
            let _ = CACHE.set(cache);
        }
        Err(e) => tracing::warn!(error = %e, "no shader cache"),
    }
}

/// Disk hits and translations since the start. Callers sharing a fill do not
/// count as additional hits or translations.
pub(crate) fn counts() -> (u64, u64) {
    (HITS.load(Ordering::Relaxed), MISSES.load(Ordering::Relaxed))
}

/// What identifies this build: the BLAKE3 of our executable file and of
/// the translation settings it runs with (the loop limit, which a
/// diagnostics build can change at run time).
fn build() -> &'static [u8; 32] {
    static BUILD: OnceLock<[u8; 32]> = OnceLock::new();
    BUILD.get_or_init(|| {
        let exe = std::env::current_exe().and_then(std::fs::read);
        let limit = victory_shader::emit::loop_limit();
        if limit != victory_shader::emit::DEFAULT_LOOP_LIMIT {
            tracing::warn!(
                limit,
                "VICTORY_SHADER_LOOP_LIMIT: translated loops stop sooner"
            );
        }
        match exe {
            Ok(mut bytes) => {
                bytes.extend_from_slice(&limit.to_le_bytes());
                *blake3::hash(&bytes).as_bytes()
            }
            Err(e) => {
                // Without it no entry can be trusted: a fresh key per run.
                tracing::warn!(error = %e, "cannot read our executable; shader cache unused");
                let now = std::time::SystemTime::now()
                    .duration_since(std::time::UNIX_EPOCH)
                    .unwrap_or_default();
                *blake3::hash(&now.as_nanos().to_le_bytes()).as_bytes()
            }
        }
    })
}

/// The translation of a console shader container, from the cache when
/// there is one.
pub(crate) fn host_shader(container: &[u8]) -> Result<HostShader, String> {
    let translate = |c: &[u8]| victory_shader::emit::translate(c).map_err(|e| e.to_string());
    match CACHE.get() {
        Some(cache) => cached(cache, build(), container, translate),
        None => translate(container),
    }
}

/// The cache entry's converter: the build and the container in, the
/// encoded translation out. `ran` tells a miss from a hit.
struct Translate<F> {
    translate: F,
    ran: AtomicBool,
}

impl<F: Fn(&[u8]) -> Result<HostShader, String> + Send + Sync> Converter for Translate<F> {
    fn id(&self) -> &'static str {
        "shader.dxil"
    }
    fn version(&self) -> u32 {
        // The build fingerprint in the input does the versioning.
        1
    }
    fn convert(&self, input: &[u8]) -> anyhow::Result<Vec<u8>> {
        self.ran.store(true, Ordering::Relaxed);
        let shader = (self.translate)(&input[32..]).map_err(anyhow::Error::msg)?;
        Ok(encode(&shader))
    }
}

fn cached(
    cache: &Cache,
    build: &[u8; 32],
    container: &[u8],
    translate: impl Fn(&[u8]) -> Result<HostShader, String> + Send + Sync,
) -> Result<HostShader, String> {
    let input = [&build[..], container].concat();
    let converter = Translate {
        translate,
        ran: AtomicBool::new(false),
    };
    let key = CacheKey::new(&converter, &input);
    let path = cache.path_for(&key);
    if path.is_file()
        && let Some(shader) = read_shader(&path)
    {
        HITS.fetch_add(1, Ordering::Relaxed);
        tracing::debug!(path = %path.display(), "shader from the cache");
        return Ok(shader);
    }
    fill_once(&path, || fill(cache, &key, &converter, &input))
}

fn read_shader(path: &Path) -> Option<HostShader> {
    std::fs::read(path).ok().and_then(|b| decode(&b))
}

type Translation = Result<HostShader, String>;
type Waiters = Vec<mpsc::Sender<Translation>>;
// The path includes the cache root and the full, versioned on-disk key. Only
// active misses live here; never hold this lock across I/O, translation or wait.
static FILLING: LazyLock<Mutex<HashMap<PathBuf, Waiters>>> = LazyLock::new(Mutex::default);

struct FillGuard<'a>(Option<&'a Path>);

impl FillGuard<'_> {
    fn take_waiters(&mut self) -> Waiters {
        self.0
            .take()
            .and_then(|path| FILLING.lock().unwrap().remove(path))
            .unwrap_or_default()
    }
}

impl Drop for FillGuard<'_> {
    fn drop(&mut self) {
        // On unwind, dropping the senders releases any waiters and the next
        // caller can retry. Never remove a later fill of the same key.
        drop(self.take_waiters());
    }
}

fn fill_once(path: &Path, fill: impl FnOnce() -> Translation) -> Translation {
    let mut active = FILLING.lock().unwrap();
    if let Some(waiters) = active.get_mut(path) {
        let (send, recv) = mpsc::channel();
        waiters.push(send);
        #[cfg(test)]
        tests::JOINED.notify_all();
        drop(active);
        return recv
            .recv()
            .unwrap_or_else(|_| Err("shader cache fill interrupted".into()));
    }
    active.insert(path.to_owned(), Vec::new());
    let mut owner = FillGuard(Some(path));
    drop(active);

    let result = fill();
    for waiter in owner.take_waiters() {
        let _ = waiter.send(result.clone());
    }
    result
}

fn fill<F: Fn(&[u8]) -> Translation + Send + Sync>(
    cache: &Cache,
    key: &CacheKey,
    converter: &Translate<F>,
    input: &[u8],
) -> Translation {
    // Recheck after claiming the key: another fill might have finished since
    // our initial read. Only the owner removes/repairs a damaged entry.
    for _ in 0..2 {
        let path = cache
            .get_or_convert_keyed(key, converter, input)
            .map_err(|e| format!("{e:#}"))?;
        if let Some(shader) = read_shader(&path) {
            let (counter, what) = if converter.ran.load(Ordering::Relaxed) {
                (&MISSES, "translated and cached")
            } else {
                (&HITS, "from the cache")
            };
            counter.fetch_add(1, Ordering::Relaxed);
            tracing::debug!(path = %path.display(), "shader {what}");
            return Ok(shader);
        }
        tracing::debug!(path = %path.display(), "unreadable shader cache entry; translating again");
        let _ = std::fs::remove_file(&path);
    }
    MISSES.fetch_add(1, Ordering::Relaxed);
    (converter.translate)(&input[32..])
}

const MAGIC: &[u8; 4] = b"VSH1";
const STAGES: [HwStage; 8] = [
    HwStage::Ls,
    HwStage::Hs,
    HwStage::Es,
    HwStage::Gs,
    HwStage::Vs,
    HwStage::Ps,
    HwStage::Ms,
    HwStage::Cs,
];

fn root_code(r: RootType) -> u32 {
    match r {
        RootType::Constants => 0,
        RootType::Descriptor => 1,
        RootType::Table => 2,
        RootType::ImmediateSampler => 3,
        RootType::ResourceHeap => 4,
        RootType::SamplerHeap => 5,
        RootType::Other(x) => 6 + x,
    }
}

fn root_type(code: u32) -> RootType {
    match code {
        0 => RootType::Constants,
        1 => RootType::Descriptor,
        2 => RootType::Table,
        3 => RootType::ImmediateSampler,
        4 => RootType::ResourceHeap,
        5 => RootType::SamplerHeap,
        x => RootType::Other(x - 6),
    }
}

/// Little-endian words and length-prefixed lists.
fn encode(s: &HostShader) -> Vec<u8> {
    let mut out = MAGIC.to_vec();
    let word = |out: &mut Vec<u8>, v: u32| out.extend(v.to_le_bytes());
    let stage = STAGES.iter().position(|&x| x == s.stage).unwrap_or(0) as u32;
    word(&mut out, stage);
    word(&mut out, s.dxil.len() as u32);
    out.extend(&s.dxil);
    word(&mut out, s.user_data.len() as u32);
    for u in &s.user_data {
        for v in [u.index, u32::from(u.slot), root_code(u.root), u.dword] {
            word(&mut out, v);
        }
    }
    word(&mut out, s.samplers.len() as u32);
    for sampler in &s.samplers {
        for &v in sampler {
            word(&mut out, v);
        }
    }
    word(&mut out, s.static_samplers.len() as u32);
    for t in &s.static_samplers {
        let [u, v, w] = t.address;
        let words = [
            t.filter,
            u,
            v,
            w,
            t.mip_lod_bias.to_bits(),
            t.max_anisotropy,
            t.comparison,
            t.border,
            t.min_lod.to_bits(),
            t.max_lod.to_bits(),
        ];
        for v in words {
            word(&mut out, v);
        }
    }
    for slots in [&s.root_cbvs, &s.root_srvs] {
        word(&mut out, slots.len() as u32);
        out.extend(slots);
    }
    out
}

fn decode(bytes: &[u8]) -> Option<HostShader> {
    struct Reader<'a>(&'a [u8]);
    impl<'a> Reader<'a> {
        fn take(&mut self, n: usize) -> Option<&'a [u8]> {
            let (head, rest) = self.0.split_at_checked(n)?;
            self.0 = rest;
            Some(head)
        }
        fn word(&mut self) -> Option<u32> {
            Some(u32::from_le_bytes(self.take(4)?.try_into().ok()?))
        }
        fn list(&mut self) -> Option<Vec<u8>> {
            let n = self.word()? as usize;
            Some(self.take(n)?.to_vec())
        }
    }
    let mut r = Reader(bytes);
    if r.take(4)? != MAGIC {
        return None;
    }
    let stage = *STAGES.get(r.word()? as usize)?;
    let dxil = r.list()?;
    let n = r.word()? as usize;
    let mut user_data = Vec::with_capacity(n.min(256));
    for _ in 0..n {
        user_data.push(UserData {
            index: r.word()?,
            slot: u8::try_from(r.word()?).ok()?,
            root: root_type(r.word()?),
            dword: r.word()?,
        });
    }
    let n = r.word()? as usize;
    let mut samplers = Vec::with_capacity(n.min(256));
    for _ in 0..n {
        samplers.push([r.word()?, r.word()?, r.word()?, r.word()?]);
    }
    let n = r.word()? as usize;
    let mut static_samplers = Vec::with_capacity(n.min(256));
    for _ in 0..n {
        static_samplers.push(StaticSampler {
            filter: r.word()?,
            address: [r.word()?, r.word()?, r.word()?],
            mip_lod_bias: f32::from_bits(r.word()?),
            max_anisotropy: r.word()?,
            comparison: r.word()?,
            border: r.word()?,
            min_lod: f32::from_bits(r.word()?),
            max_lod: f32::from_bits(r.word()?),
        });
    }
    let root_cbvs = r.list()?;
    let root_srvs = r.list()?;
    r.0.is_empty().then_some(HostShader {
        stage,
        dxil,
        user_data,
        samplers,
        static_samplers,
        root_cbvs,
        root_srvs,
    })
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::{sync::Condvar, thread, time::Duration};

    pub(super) static JOINED: Condvar = Condvar::new();
    const TIMEOUT: Duration = Duration::from_secs(10);

    fn wait_for_joiners(root: &Path, n: usize) {
        let (active, timeout) = JOINED
            .wait_timeout_while(FILLING.lock().unwrap(), TIMEOUT, |map| {
                !map.iter()
                    .any(|(p, waiters)| p.starts_with(root) && waiters.len() == n)
            })
            .unwrap();
        drop(active);
        assert!(
            !timeout.timed_out(),
            "{n} callers should have joined one fill"
        );
    }

    fn shader() -> HostShader {
        HostShader {
            stage: HwStage::Ps,
            dxil: b"DXBC and the rest".to_vec(),
            user_data: vec![UserData {
                index: 8,
                slot: 1,
                root: RootType::Table,
                dword: 0,
            }],
            samplers: vec![[0x400, 0xc0_0000, 0x18f0_0000, 0]],
            static_samplers: vec![StaticSampler::from_words([
                0x400,
                0xc0_0000,
                0x18f0_0000,
                0,
            ])],
            root_cbvs: vec![2],
            root_srvs: vec![0, 3],
        }
    }

    // Hold a synthetic translator until all three other callers have joined
    // its fill. The timeout only diagnoses a broken handoff; no sleeps/races.
    fn cold_wave(cache: &Cache, root: &Path, answer: Translation) -> Translation {
        let runs = AtomicU64::new(0);
        let (release, gate) = mpsc::channel::<()>();
        let gate = Mutex::new(gate);
        let translate = |_: &[u8]| {
            runs.fetch_add(1, Ordering::Relaxed);
            assert_eq!(
                gate.lock().unwrap().recv_timeout(2 * TIMEOUT),
                Err(mpsc::RecvTimeoutError::Disconnected)
            );
            answer.clone()
        };
        thread::scope(|s| {
            let workers: Vec<_> = (0..4)
                .map(|_| s.spawn(|| cached(cache, &[7; 32], b"same", translate)))
                .collect();
            wait_for_joiners(root, 3);
            drop(release);
            let mut results = workers.into_iter().map(|w| w.join().unwrap());
            let first = results.next().unwrap();
            for result in results {
                assert_eq!(result, first);
            }
            assert_eq!(runs.load(Ordering::Relaxed), 1);
            first
        })
    }

    #[test]
    fn concurrent_misses_and_repairs_translate_once() {
        let dir = tempfile::tempdir().unwrap();
        let cache = Cache::open(dir.path()).unwrap();
        assert_eq!(cold_wave(&cache, dir.path(), Ok(shader())), Ok(shader()));
        let entries = walk(dir.path());
        assert_eq!(entries.len(), 1);
        std::fs::write(&entries[0], b"damaged").unwrap();
        assert_eq!(cold_wave(&cache, dir.path(), Ok(shader())), Ok(shader()));
        assert_eq!(read_shader(&entries[0]), Some(shader()));
    }

    #[test]
    fn concurrent_failure_is_shared_then_retried() {
        let dir = tempfile::tempdir().unwrap();
        let cache = Cache::open(dir.path()).unwrap();
        let err = cold_wave(&cache, dir.path(), Err("synthetic failure".into())).unwrap_err();
        assert!(err.contains("synthetic failure"));
        assert!(walk(dir.path()).is_empty());
        assert_eq!(cold_wave(&cache, dir.path(), Ok(shader())), Ok(shader()));
        assert_eq!(
            cached(&cache, &[7; 32], b"same", |_| panic!("expected disk hit")),
            Ok(shader())
        );
    }

    #[test]
    fn unwinding_owner_releases_waiter_and_key() {
        let dir = tempfile::tempdir().unwrap();
        let path = dir.path().join("panic-test");
        thread::scope(|s| {
            let owner = std::panic::catch_unwind(|| {
                fill_once(&path, || {
                    s.spawn(|| {
                        let result = fill_once(&path, || panic!("expected to join"));
                        assert_eq!(result.unwrap_err(), "shader cache fill interrupted");
                    });
                    wait_for_joiners(&path, 1);
                    panic!("synthetic translator panic");
                })
            });
            assert!(owner.is_err());
        });
        assert_eq!(fill_once(&path, || Ok(shader())), Ok(shader()));
    }

    #[test]
    fn different_containers_and_builds_translate_in_parallel() {
        let dir = tempfile::tempdir().unwrap();
        let cache = &Cache::open(dir.path()).unwrap();
        let (entered, started) = mpsc::channel();
        let (release, gate) = mpsc::channel::<()>();
        let gate = &Mutex::new(gate);
        thread::scope(|s| {
            let mut workers = Vec::new();
            for (tag, build, container) in [(1, 7, b'a'), (2, 7, b'b'), (3, 8, b'a')] {
                let entered = &entered;
                workers.push(s.spawn(move || {
                    cached(cache, &[build; 32], &[container], |_| {
                        entered.send(()).unwrap();
                        let _ = gate.lock().unwrap().recv();
                        Ok(HostShader {
                            dxil: vec![tag],
                            ..shader()
                        })
                    })
                }));
            }
            // No translator may finish until all three distinct keys entered.
            for _ in &workers {
                started.recv_timeout(TIMEOUT).unwrap();
            }
            drop(release);
            for (tag, worker) in (1..).zip(workers) {
                assert_eq!(worker.join().unwrap().unwrap().dxil, [tag]);
            }
        });
    }

    #[test]
    fn translations_come_back_from_the_cache() {
        let dir = tempfile::tempdir().unwrap();
        let cache = Cache::open(dir.path()).unwrap();
        let build = [7u8; 32];
        let container = b"a console container".as_slice();
        let runs = AtomicU64::new(0);
        let translate = |_: &[u8]| {
            runs.fetch_add(1, Ordering::Relaxed);
            Ok(shader())
        };
        assert_eq!(cached(&cache, &build, container, translate), Ok(shader()));
        assert_eq!(cached(&cache, &build, container, translate), Ok(shader()));
        assert_eq!(runs.load(Ordering::Relaxed), 1, "the second came from disk");

        // Another build translates again.
        assert_eq!(cached(&cache, &[8; 32], container, translate), Ok(shader()));
        assert_eq!(runs.load(Ordering::Relaxed), 2);

        // A damaged entry is a miss, translated and stored again.
        for e in walk(dir.path()) {
            std::fs::write(e, b"VSH1 broken").unwrap();
        }
        assert_eq!(cached(&cache, &build, container, translate), Ok(shader()));
        assert_eq!(runs.load(Ordering::Relaxed), 3);
        assert_eq!(cached(&cache, &build, container, translate), Ok(shader()));
        assert_eq!(runs.load(Ordering::Relaxed), 3);

        // Failures are not stored.
        let fail = |_: &[u8]| Err::<HostShader, _>("unsupported".to_owned());
        assert!(cached(&cache, &build, b"other", fail).is_err());
    }

    fn walk(dir: &std::path::Path) -> Vec<PathBuf> {
        let mut files = Vec::new();
        for e in std::fs::read_dir(dir).unwrap().flatten() {
            if e.path().is_dir() {
                files.extend(walk(&e.path()));
            } else {
                files.push(e.path());
            }
        }
        files
    }

    #[test]
    fn entries_round_trip_and_reject_damage() {
        let bytes = encode(&shader());
        assert_eq!(decode(&bytes), Some(shader()));
        assert_eq!(decode(&bytes[..bytes.len() - 1]), None);
        assert_eq!(decode(&[bytes.as_slice(), &[0]].concat()), None);
        assert_eq!(decode(b"VSH0"), None);
    }
}
