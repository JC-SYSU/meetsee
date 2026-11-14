# Bundled Lokii engine

Meet&See can use an optional headless search engine built from **lokii-core**, the Rust core of the [Lokii](https://github.com/huangy7/lokii) project. This document explains exactly what is bundled, what was changed, and what is not included.

## What is bundled

- `ThirdParty/lokii/lokii-core` — the `lokii-core` crate at upstream tag **v0.1.9**.
- `ThirdParty/lokii/LICENSE` — the upstream MIT license, unchanged.
- `Engine/` — a small Rust host (`meetsee-lokii-engine`) that links `lokii-core`, owns its own cache, and exposes a private JSONL protocol to the Swift app.
- `Engine/Cargo.lock` — the locked dependency graph used to build the helper.

The helper is copied into `Meet&See.app/Contents/Helpers/meetsee-lokii-engine` and signed with the app.

## What is not bundled

- The official Lokii GUI application.
- The official `lokii` CLI.
- The official global configuration at `~/.config/lokii/config.toml`.
- The official Unix socket at `~/.config/lokii/query.sock`.
- Any upstream build artifact, cache, or release binary.

Meet&See does not install, launch, or communicate with any of those in normal operation. The source tree retains a legacy socket client (`LokiiSearch.swift`) and TOML configuration helpers (`LokiiConfig.swift`) for historical tests. They are not used by production code; `LokiiConfig.swift` is not part of the application build. The bundled engine has its own cache under `~/Library/Application Support/QuickFind/LokiiEngine` and receives its configuration from Meet&See's saved settings.

## Local patch

The vendored core is labelled **0.1.9-meetsee.1**. It is not an unmodified upstream copy. The patch touches five files:

| File | Change |
|---|---|
| `src/config.rs` | Adds a default-on `skip_protected_paths` policy |
| `src/filter.rs` | Applies the same policy during filtering |
| `src/scanner.rs` | Applies the policy during scanning |
| `src/startup.rs` | Includes the policy in cache-scope applicability checks, so an incompatible cache is not reused |
| `src/watcher.rs` | Reports real watcher-thread state; supports explicit stop and flush confirmation; exposes replay, calibration, incremental, and network states; supports an empty scope; reports watcher startup failures |

The protected-path policy exists because the upstream heuristic treats "cannot read the TCC database" as a reason to skip protected locations such as Documents. The standalone host disables that heuristic for roots the user explicitly saved. Actual reads remain governed by macOS TCC; the patch does not bypass permissions.

The patch is intentionally small. It is not a fork with independent product direction. Updating to a newer upstream release requires re-applying or retiring these changes and re-running the engine contract tests.

## Engine host protocol

`Engine/src/main.rs` accepts either `--stdio` or `--version`. Without arguments it does not scan.

The stdio protocol is JSONL:

- Requests contain `protocol: 1`, an unsigned `id`, and an `op`.
- Responses echo the id and return `ok` with `data`, or an `error`.
- Status events use `event: "status"` and have no request id.
- Unknown fields, versions, operations, and oversized lines are rejected.

Operations:

| Operation | Purpose |
|---|---|
| `hello` | Version and capabilities; does not scan |
| `initialize` | Accepts one explicit configuration and starts or restores the index asynchronously |
| `status` | Reports phase, queryability, scope calibration, count, index generation, instance id, errors, and per-root read warnings |
| `search` | Returns raw matches for a query and limit; supports substring and regex modes |
| `inspect` | Checks whether an exact path is present in the engine's index, without the 5,000-result prefetch truncation |
| `rebuild` | Performs a real full rebuild; rejects the request while busy |
| `shutdown` | Stops listening, flushes state, and exits |

The search queue keeps at most one pending request. A superseded request is cancelled.

Example initialization:

```json
{"protocol":1,"id":1,"op":"initialize","config":{"roots":["/absolute/approved/scope"],"excludedPaths":[],"includeHidden":false,"maxResults":5000,"cacheDirectory":"/absolute/cache","listen":true,"networkRescanMinutes":5}}
```

Roots must be existing absolute paths. An empty scope is allowed. The engine does not implicitly fall back to the home directory. The private cache must not contain a search root; if it does, the engine excludes it.

## Behavior differences from the native engine

The native Swift engine remains the reference for matching and filtering. The bundled engine is an alternative file source, not a replacement for the rules implemented in Swift.

- The engine returns at most **5,000 raw matches per query**. Queries with more raw matches can differ from the native engine even after Swift-side filtering.
- File types, Finder aliases, symbolic links, hidden files, blacklist keywords, pinned items, application ranking, Contacts, and System Settings search are applied in Swift code, not by the engine.
- Pinyin for applications and pinned items is generated in Swift.
- The native engine has a different index format and a different cache lifecycle.

## Licensing

- Upstream `lokii-core` is MIT. The upstream copyright and license text are preserved in `ThirdParty/lokii/LICENSE`.
- The vendored copy and the combined work are distributed under GPL-3.0-or-later.
- The full third-party inventory is in [`THIRD-PARTY-NOTICES.md`](../THIRD-PARTY-NOTICES.md).

## Non-affiliation

Meet&See is an independent project. It is not affiliated with, sponsored by, or endorsed by the Lokii project. The name "Lokii" is used only to identify the origin of the bundled engine.
