//! Meet&See-owned lokii-core process. No official App, CLI, config, or socket.
use lokii_core::{
    cache,
    config::{AppConfig, ConfigStore},
    filter::CompiledFilter,
    indexer::IndexStore,
    metrics::WatcherMetrics,
    scanner,
    search::{self, SearchMode},
    startup,
    watcher::{self, Resume, WatcherHandle},
};
use serde::Deserialize;
use serde_json::{json, Value};
use std::{
    fs::{File, OpenOptions},
    io::{self, BufRead, Write},
    os::unix::fs::OpenOptionsExt,
    path::{Path, PathBuf},
    sync::{
        atomic::{AtomicBool, AtomicU64, AtomicUsize, Ordering},
        Arc, Mutex,
    },
    time::Duration,
};

const PROTOCOL: u32 = 1;
const MAX_REQUEST: usize = 65536;
const MAX_RESPONSE: usize = 16 * 1024 * 1024;
const MAX_RESULTS: usize = 5000;

#[derive(Deserialize)]
struct Request {
    protocol: u32,
    id: u64,
    #[serde(flatten)]
    command: Command,
}
#[derive(Deserialize)]
#[serde(tag = "op", rename_all = "camelCase", deny_unknown_fields)]
enum Command {
    Hello {},
    Initialize {
        config: Config,
    },
    Status {},
    Search {
        query: String,
        limit: usize,
        #[serde(default = "substring")]
        mode: String,
    },
    Inspect {
        path: String,
    },
    Rebuild {},
    Shutdown {},
}
fn substring() -> String {
    "substring".into()
}
#[derive(Clone, Deserialize)]
#[serde(rename_all = "camelCase", deny_unknown_fields)]
struct Config {
    roots: Vec<String>,
    excluded_paths: Vec<String>,
    include_hidden: bool,
    max_results: usize,
    cache_directory: String,
    #[serde(default = "yes")]
    listen: bool,
    #[serde(default = "network_minutes")]
    network_rescan_minutes: u64,
}
fn yes() -> bool {
    true
}
fn network_minutes() -> u64 {
    5
}

struct State {
    phase: String,
    queryable: bool,
    current: bool,
    startup: String,
    error: Option<String>,
    warnings: Vec<String>,
    generation: u64,
    job: u64,
    listener: bool,
    network: bool,
}
struct Engine {
    index: IndexStore,
    state: Mutex<State>,
    config: Mutex<Option<(Config, AppConfig)>>,
    watcher: Mutex<Option<WatcherHandle>>,
    cache_lock: Mutex<Option<File>>,
    busy: AtomicBool,
    stopping: AtomicBool,
    generation: AtomicU64,
    progress: Arc<AtomicUsize>,
}
static OUTPUT: Mutex<()> = Mutex::new(());
fn emit(value: Value) {
    let mut data = serde_json::to_vec(&value).unwrap();
    if data.len() > MAX_RESPONSE {
        data = serde_json::to_vec(&json!({"protocol":PROTOCOL,"id":value["id"],"ok":false,"error":"response exceeds 16 MiB"})).unwrap();
    }
    data.push(b'\n');
    let _guard = OUTPUT.lock().unwrap();
    let mut out = io::stdout().lock();
    if out.write_all(&data).and_then(|_| out.flush()).is_err() {
        std::process::exit(0);
    }
}
fn reply(id: Option<u64>, result: Result<Value, String>) {
    emit(match result {
        Ok(data) => json!({"protocol":PROTOCOL,"id":id,"ok":true,"data":data}),
        Err(error) => json!({"protocol":PROTOCOL,"id":id,"ok":false,"error":error}),
    });
}
fn directory(raw: &str) -> Result<PathBuf, String> {
    let p = Path::new(raw);
    if !p.is_absolute() {
        return Err("directory must be absolute".into());
    }
    let p = p.canonicalize().map_err(|e| format!("{raw}: {e}"))?;
    if !p.is_dir() {
        return Err(format!("not a directory: {raw}"));
    }
    Ok(p)
}
impl Engine {
    fn new() -> Arc<Self> {
        Arc::new(Self {
            index: IndexStore::new(),
            state: Mutex::new(State {
                phase: "awaitingConfiguration".into(),
                queryable: false,
                current: false,
                startup: "pending".into(),
                error: None,
                warnings: vec![],
                generation: 0,
                job: 0,
                listener: false,
                network: false,
            }),
            config: Mutex::new(None),
            watcher: Mutex::new(None),
            cache_lock: Mutex::new(None),
            busy: AtomicBool::new(false),
            stopping: AtomicBool::new(false),
            generation: AtomicU64::new(0),
            progress: Arc::new(AtomicUsize::new(0)),
        })
    }
    fn snapshot(&self) -> Value {
        let count = self.index.len();
        let s = self.state.lock().unwrap();
        json!({"phase":s.phase,"queryable":s.queryable,"scopeSynchronized":s.current,
            "count":count,"scanned":self.progress.load(Ordering::Relaxed),
            "startup":s.startup,"error":s.error,"warnings":s.warnings,
            "generation":s.generation,"job":s.job,"liveUpdates":s.listener,
            "networkScanning":s.network,"instance":std::process::id(),
            "loadedConfigRevision":if self.config.lock().unwrap().is_some(){1}else{0},
            "indexedConfigRevision":if s.current{Some(1)}else{None}})
    }
    fn notify(&self) {
        emit(json!({"protocol":PROTOCOL,"event":"status","data":self.snapshot()}));
    }
    fn initialize(self: &Arc<Self>, input: Config) -> Result<Value, String> {
        if self.config.lock().unwrap().is_some() {
            return Err("already initialized".into());
        }
        if !(1..=MAX_RESULTS).contains(&input.max_results) {
            return Err("maxResults must be 1..5000".into());
        }
        let cache_dir = directory(&input.cache_directory)?;
        let roots: Vec<_> = input
            .roots
            .iter()
            .map(|r| directory(r))
            .collect::<Result<_, _>>()?;
        if roots.iter().any(|r| r.starts_with(&cache_dir)) {
            return Err("cache directory must not contain a search root".into());
        }
        for name in ["index.cache", "index.tmp", "engine.lock"] {
            if cache_dir
                .join(name)
                .symlink_metadata()
                .is_ok_and(|m| m.file_type().is_symlink())
            {
                return Err("cache destination must not be a symbolic link".into());
            }
        }
        let lock = OpenOptions::new()
            .create(true)
            .truncate(false)
            .read(true)
            .write(true)
            .mode(0o600)
            .custom_flags(libc::O_NOFOLLOW)
            .open(cache_dir.join("engine.lock"))
            .map_err(|e| e.to_string())?;
        use std::os::fd::AsRawFd;
        if unsafe { libc::flock(lock.as_raw_fd(), libc::LOCK_EX | libc::LOCK_NB) } != 0 {
            return Err("private cache is already owned by another engine".into());
        }
        let mut config = AppConfig::default();
        config.index.index_paths = roots
            .iter()
            .map(|r| r.to_string_lossy().into_owned())
            .collect();
        config.index.exclude.clear();
        if input
            .excluded_paths
            .iter()
            .any(|p| !Path::new(p).is_absolute())
        {
            return Err("excluded paths must be absolute".into());
        }
        config.index.exclude_paths = input.excluded_paths.clone();
        config
            .index
            .exclude_paths
            .push(cache_dir.to_string_lossy().into_owned());
        config.index.include_hidden = input.include_hidden;
        config.index.max_results = input.max_results;
        config.index.network_rescan_minutes = if input.listen {
            input.network_rescan_minutes.min(1440)
        } else {
            0
        };
        // TCC remains authoritative. Explicitly approved Documents roots must not
        // disappear just because reading Apple's TCC database was denied.
        config.index.skip_protected_paths = false;
        *self.cache_lock.lock().unwrap() = Some(lock);
        *self.config.lock().unwrap() = Some((input, config));
        self.begin(false)?;
        Ok(json!({"accepted":true,"job":1}))
    }
    fn begin(self: &Arc<Self>, force: bool) -> Result<Value, String> {
        if self.config.lock().unwrap().is_none() {
            return Err("awaiting configuration".into());
        }
        if self.busy.swap(true, Ordering::AcqRel) {
            return Err("index task is already running".into());
        }
        {
            let mut s = self.state.lock().unwrap();
            s.job += 1;
            s.phase = if force { "rebuilding" } else { "initializing" }.into();
            s.current = false;
            s.error = None;
        }
        self.notify();
        let engine = self.clone();
        std::thread::spawn(move || {
            if let Err(error) = engine.boot(force) {
                let mut s = engine.state.lock().unwrap();
                s.phase = "failed".into();
                s.error = Some(error);
            }
            engine.busy.store(false, Ordering::Release);
            engine.notify();
        });
        Ok(json!({"accepted":true}))
    }
    fn boot(self: &Arc<Self>, force: bool) -> Result<(), String> {
        if let Some(old) = self.watcher.lock().unwrap().take() {
            if !old.stop(Duration::from_secs(3)) {
                return Err("previous watcher could not stop".into());
            }
        }
        let (input, config) = self.config.lock().unwrap().clone().unwrap();
        let cache_file = Path::new(&input.cache_directory).join("index.cache");
        let mark = startup::checkpoint(&config);
        let scope_file = Path::new(&input.cache_directory).join("owned-scope.json");
        let mut startup_kind = "hotCache";
        let cached = if force {
            None
        } else {
            cache::load_compact(&cache_file)
                .ok()
                .and_then(|(mut index, saved)| {
                    let mut saved = saved?;
                    if saved.fingerprint != mark.fingerprint {
                        let old: AppConfig =
                            serde_json::from_slice(&std::fs::read(&scope_file).ok()?).ok()?;
                        let narrows = old.resolve_paths() == config.resolve_paths()
                            && old.index.include_hidden == config.index.include_hidden
                            && old.index.skip_protected_paths == config.index.skip_protected_paths
                            && old.index.exclude == config.index.exclude
                            && old
                                .index
                                .exclude_paths
                                .iter()
                                .all(|p| config.index.exclude_paths.contains(p))
                            && saved.fingerprint == startup::scope_fingerprint(&old);
                        if !narrows {
                            return None;
                        }
                        index
                            .apply_event_batch(&[], &config.index.exclude_paths, &[], Vec::new())
                            .ok()?;
                        saved.fingerprint = mark.fingerprint;
                        startup_kind = "narrowedCache";
                    }
                    Some((index, saved))
                })
        };
        let (resume, startup) = if let Some((index, saved)) = cached {
            self.index.replace_compact(index);
            (Resume::From(saved.event_id), startup_kind)
        } else {
            self.progress.store(0, Ordering::Relaxed);
            let fresh = scanner::scan_compact(
                &config.resolve_paths(),
                Arc::new(CompiledFilter::from_config(&config)),
                config.index.include_hidden,
                self.progress.clone(),
            )
            .map_err(|e| e.to_string())?;
            self.index.replace_compact(fresh);
            (Resume::From(mark.event_id), "coldScan")
        };
        if self.stopping.load(Ordering::Acquire) {
            return Ok(());
        }
        let mut warnings = Vec::new();
        for root in &input.roots {
            if let Err(error) = std::fs::read_dir(root) {
                warnings.push(format!("{root}: {error}"));
            }
        }
        self.index.warm_query_index();
        {
            let mut s = self.state.lock().unwrap();
            s.phase = "replaying".into();
            s.queryable = true;
            s.startup = startup.into();
            s.warnings = warnings;
        }
        let weak = Arc::downgrade(self);
        let saving = Arc::downgrade(self);
        let scope_data = serde_json::to_vec(&config).map_err(|e| e.to_string())?;
        let handle = watcher::start_watcher(
            self.index.clone(),
            ConfigStore::new(config.clone()),
            Arc::new(WatcherMetrics::new()),
            resume,
            Arc::new(Mutex::new(())),
            move |_| {
                if let Some(e) = weak.upgrade() {
                    e.generation.fetch_add(1, Ordering::Relaxed);
                }
            },
            move |index, checkpoint| {
                let saved = cache::save_compact(index, Some(checkpoint), &cache_file)
                    .map_err(|e| e.to_string())
                    .and_then(|_| {
                        let temp = scope_file.with_extension("tmp");
                        std::fs::write(&temp, &scope_data)
                            .and_then(|_| std::fs::rename(&temp, &scope_file))
                            .map_err(|e| e.to_string())
                    });
                if let Err(error) = saved {
                    if let Some(e) = saving.upgrade() {
                        e.state.lock().unwrap().error = Some(format!("cache: {error}"));
                    }
                }
            },
        );
        *self.watcher.lock().unwrap() = Some(handle.clone());
        self.notify();
        // One monitor per boot, exits as soon as initial replay settles. Live
        // monitoring thereafter belongs to the single process-wide monitor.
        for _ in 0..600 {
            if self.stopping.load(Ordering::Acquire) {
                return Ok(());
            }
            let ws = handle.status();
            if ws.scope_current {
                if !input.listen {
                    if !handle.stop(Duration::from_secs(3)) {
                        return Err("could not stop one-time recovery watcher".into());
                    }
                    self.watcher.lock().unwrap().take();
                }
                let mut s = self.state.lock().unwrap();
                s.phase = "ready".into();
                s.current = true;
                s.listener = input.listen;
                s.generation = self.generation.fetch_add(1, Ordering::Relaxed) + 1;
                return Ok(());
            }
            if let Some(error) = ws.error {
                return Err(error);
            }
            std::thread::sleep(Duration::from_millis(100));
        }
        Err("initial event recovery timed out; cache is queryable but not synchronized".into())
    }
    fn monitor(self: Arc<Self>) {
        let mut previous = Value::Null;
        while !self.stopping.load(Ordering::Acquire) {
            if !self.busy.load(Ordering::Acquire) {
                let watcher = self.watcher.lock().unwrap().clone();
                if let Some(w) = watcher {
                    let ws = w.status();
                    let mut s = self.state.lock().unwrap();
                    s.phase = match ws.phase {
                        "idle" => "ready",
                        other => other,
                    }
                    .into();
                    s.current = ws.scope_current;
                    s.network = ws.network_scanning;
                    s.generation = self.generation.load(Ordering::Relaxed);
                    if ws.error.is_some() {
                        s.error = ws.error;
                    }
                }
            }
            let current = self.snapshot();
            if current != previous {
                self.notify();
                previous = current;
            }
            std::thread::sleep(Duration::from_millis(500));
        }
    }
    fn close(&self) -> bool {
        self.stopping.store(true, Ordering::Release);
        let w = self.watcher.lock().unwrap().take();
        w.is_none_or(|w| w.stop(Duration::from_secs(3)))
    }
}
fn serve() -> io::Result<()> {
    let engine = Engine::new();
    let monitor = engine.clone();
    std::thread::spawn(move || monitor.monitor());
    type SearchJob = (u64, String, usize, String);
    let search_slot = Arc::new((Mutex::new(None::<SearchJob>), std::sync::Condvar::new()));
    let slot = search_slot.clone();
    let searching = engine.clone();
    std::thread::spawn(move || loop {
        let (lock, available) = &*slot;
        let mut queued = lock.lock().unwrap();
        while queued.is_none() {
            queued = available.wait(queued).unwrap();
        }
        let (id, query, limit, mode) = queued.take().unwrap();
        drop(queued);
        let (hits, error) = search::dispatch(
            &searching.index,
            &query,
            if mode == "regex" {
                SearchMode::Regex
            } else {
                SearchMode::Substring
            },
            limit,
        );
        reply(
            Some(id),
            match error {
                Some(error) => Err(error),
                None => Ok(
                    json!({"results":hits.into_iter().map(|h|h.entry).collect::<Vec<_>>(),"error":null}),
                ),
            },
        );
    });
    let stdin = io::stdin();
    let mut reader = stdin.lock();
    loop {
        let mut frame = Vec::new();
        loop {
            let bytes = reader.fill_buf()?;
            if bytes.is_empty() {
                engine.close();
                return Ok(());
            }
            let n = bytes
                .iter()
                .position(|&b| b == b'\n')
                .map_or(bytes.len(), |p| p + 1);
            if frame.len() + n > MAX_REQUEST {
                reply(None, Err("request exceeds 64 KiB".into()));
                engine.close();
                return Err(io::Error::other("oversized request"));
            }
            frame.extend_from_slice(&bytes[..n]);
            reader.consume(n);
            if frame.last() == Some(&b'\n') {
                break;
            }
        }
        let value: Value = match serde_json::from_slice(&frame) {
            Ok(v) => v,
            Err(e) => {
                reply(None, Err(e.to_string()));
                continue;
            }
        };
        let id = value.get("id").and_then(Value::as_u64);
        let req: Request = match serde_json::from_value(value) {
            Ok(r) => r,
            Err(e) => {
                reply(id, Err(e.to_string()));
                continue;
            }
        };
        if req.protocol != PROTOCOL {
            reply(id, Err("unsupported protocol version".into()));
            continue;
        }
        let result = match req.command {
            Command::Hello {} => Ok(
                json!({"engineVersion":env!("CARGO_PKG_VERSION"),"coreVersion":"0.1.9-meetsee.1",
                "capabilities":{"liveUpdates":true,"cacheRestore":true,"statusEvents":true}}),
            ),
            Command::Initialize { config } => engine.initialize(config),
            Command::Status {} => Ok(engine.snapshot()),
            Command::Inspect { path } => {
                let present = engine
                    .index
                    .read()
                    .iter()
                    .any(|(_, entry)| entry.path_equals(&path));
                Ok(json!({"present":present,"queryable":engine.state.lock().unwrap().queryable}))
            }
            Command::Rebuild {} => engine.begin(true),
            Command::Search { query, limit, mode } => {
                let max = engine
                    .config
                    .lock()
                    .unwrap()
                    .as_ref()
                    .map_or(0, |(c, _)| c.max_results);
                if !engine.state.lock().unwrap().queryable {
                    Err("index is initializing".into())
                } else if limit == 0 || limit > max {
                    Err("invalid search limit".into())
                } else if mode != "substring" && mode != "regex" {
                    Err("unsupported search mode".into())
                } else {
                    let (lock, available) = &*search_slot;
                    if let Some((old, _, _, _)) =
                        lock.lock().unwrap().replace((req.id, query, limit, mode))
                    {
                        reply(Some(old), Err("query superseded".into()));
                    }
                    available.notify_one();
                    continue;
                }
            }
            Command::Shutdown {} => {
                let graceful = engine.close();
                reply(id, Ok(json!({"stopped":true,"graceful":graceful})));
                return Ok(());
            }
        };
        reply(id, result);
    }
}
fn main() {
    let args: Vec<_> = std::env::args().skip(1).collect();
    let result = match args.as_slice() {
        [arg] if arg == "--version" => {
            println!(
                "meetsee-lokii-engine {} (lokii-core 0.1.9-meetsee.1)",
                env!("CARGO_PKG_VERSION")
            );
            Ok(())
        }
        [arg] if arg == "--stdio" => serve(),
        _ => Err(io::Error::other(
            "usage: meetsee-lokii-engine --stdio | --version",
        )),
    };
    if let Err(e) = result {
        eprintln!("MeetSee engine: {e}");
        std::process::exit(1);
    }
}
