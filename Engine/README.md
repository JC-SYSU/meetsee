# Bundled Lokii engine host

This crate builds the headless helper used by Meet&See's optional "Lokii engine" file-search mode. It links the vendored `lokii-core` and is managed by the Swift `LokiiProcess` class. The official Lokii app, CLI, global configuration, and socket are not runtime dependencies. Native and Lokii modes are mutually exclusive.

## Build and identity

`bash Tools/build-lokii-engine.sh <app path>` builds the helper. `bash build.sh <app path>` builds the full application. The fixed core source is in `ThirdParty/lokii`; dependencies are pinned by `Engine/Cargo.lock`. Build machines need Rust/Cargo and Xcode; end users need neither.

The helper is installed at `Contents/Helpers/meetsee-lokii-engine` with code identifier `cn.meetsee.app.engine`. The helper is signed first, then the app is signed with the same identity. Local builds default to the `CopyLocalDev` self-signed identity when present; `SIGNING_IDENTITY=-` selects ad-hoc. The upstream license is shipped at `Contents/Resources/Licenses/lokii-MIT.txt`.

The core is based on v0.1.9 with a five-file minimal patch. See `ThirdParty/lokii/README.md`. Do not present the patched build as the official upstream release.

## Private protocol v1

The helper accepts `--stdio` or `--version`. With no arguments it does not scan. stdin/stdout are JSONL; stdout carries no log lines. It does not listen on a port or a global socket. Input lines are limited to 64 KiB and output lines to 16 MiB. The prefetch limit is 5,000.

Requests contain `protocol: 1`, an unsigned `id`, and an `op`. Responses echo the id and return `ok` with `data`, or `error`. Status events use `event: "status"` and have no request id. Unknown fields, versions, operations, and oversized inputs are rejected.

- `hello`: version and capabilities; does not scan.
- `initialize`: accepts one explicit configuration and starts or restores the index asynchronously. Acceptance does not mean completion.
- `status`: real phase, queryability, scope calibration, count, index generation, instance id, errors, and per-root read warnings.
- `search`: `query`, `limit`, and `mode` (`substring` or `regex`). The query queue keeps one pending request; a superseded request is cancelled. Metadata, aliases/Pinyin, filtering, pinned items, and final ranking are handled by Swift.
- `inspect`: checks whether an exact path is in the current core index, without the 5,000-result prefetch truncation. This does not mean the item is visible in the final candidates.
- `rebuild`: accepts a real full rebuild; rejects while busy. It does not delete the cache and call that a refresh.
- `shutdown`: stops the watcher, persists state, and exits. Parent pipe EOF also terminates the process. Swift applies a bounded exit fallback for its own child process.

Example configuration:

```json
{"protocol":1,"id":1,"op":"initialize","config":{"roots":["/absolute/approved/scope"],"excludedPaths":[],"includeHidden":false,"maxResults":5000,"cacheDirectory":"/absolute/cache","listen":true,"networkRescanMinutes":5}}
```

Roots must be existing absolute paths. An empty scope is allowed. The engine does not implicitly use the home directory. The private cache must not contain a search root; if it does, the engine excludes it. The cache target rejects symbolic links, and a file lock rejects a second writer.

## Cache, watching, and status

The app uses `~/Library/Application Support/QuickFind/LokiiEngine/v1`. It does not import the official Lokii cache. A hot restore with the same scope replays offline events. Adding an exclusion under an existing root can reuse and narrow the cache; expanding the scope or using an incompatible cache triggers a new scan. Meet&See's saved settings are the only configuration source; UI drafts are not sent to the helper.

`listen: false` still performs a one-time catch-up for offline changes, then stops watching. When enabled, it keeps an FSEvents incremental watcher. Network directories use a five-minute policy; disabling the watcher stops the recurring network rescan. Native mode continues to use its own index.

Phases distinguish initialization, replay, calibration, rebuild, incremental, ready, and failure. An old index being queryable does not mean a new scope is calibrated. Status is pushed only on change; the helper does not send a fixed heartbeat, and the UI does not poll while hidden. `runtime-state.json` is a recent snapshot and may be stale after exit; use the instance process to determine liveness.

Explicitly saved protected directories are governed by actual macOS TCC. The helper does not use the "cannot read the TCC database, therefore skip Documents" heuristic. An empty root-warning list does not prove every subdirectory is readable; the helper does not modify system TCC or expand the saved scope.

## Tests and boundaries

- `bash Tests/test_lokii_engine.sh`: 13 isolated helper contract tests plus a real Swift candidate-chain comparison.
- `bash Tests/test_app_modes.sh`: AppDelegate draft, save, mode switching, rebuild, silent launch, and exit in a temporary directory.
- `bash test.sh`: full project regression, including the two above. The old socket/TOML tests are retained as historical compatibility fixtures, not a production fallback path.
- `Engine/examples/cache_probe.rs`: read-only acceptance tool; not shipped in the app and not called by production code.

The bundled engine is the default only when the user selects it. The native engine remains the reference behavior. The 5,000-item prefetch has no pagination, so broad queries can differ from native results. Real network volumes, sleep/volume removal, multi-architecture builds, and clean-account behavior still require separate validation; passing on one machine is not a cross-machine guarantee.
