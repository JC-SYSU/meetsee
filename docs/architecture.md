# Architecture

Meet&See is a single macOS application bundle with an optional headless helper process. There is no network service, database server, or background daemon outside the app.

## Process model

```
Meet&See.app
├── Contents/MacOS/QuickFind          Swift/AppKit application
└── Contents/Helpers/
    └── meetsee-lokii-engine          Optional Rust search engine (child process)
```

- The app runs as an `LSUIElement` menu bar application. It does not show a Dock icon while idle.
- The search panel is a floating `NSPanel`; the dimming layer is a separate non-activating panel placed below it.
- The bundled engine is started only when the user selects "Lokii engine" in Settings. It communicates with the app over stdin/stdout using a private JSONL protocol.
- The engine is a child of the app. When the app exits, the engine receives an EOF on its stdin and shuts down.

## Source layout

| Path | Purpose |
|---|---|
| `main.swift` | Application delegate, panels, menus, settings UI, search orchestration, open/copy actions |
| `SearchCore.swift` | Settings model, scanning, type classification, matching, filtering, ranking, cache |
| `NativeUI.swift` | Native settings controls, scroll-edge veil, scan-motion views, status layout |
| `SelectionStyle.swift` | Shared highlight rendering, settings preview, and material colors |
| `HDRSelection.swift` | Metal/EDR highlight rendering |
| `IndexWatcher.swift` | FSEvents watcher and incremental updates |
| `ContactsSearch.swift` | Contacts authorization, in-memory index, phone-number cleaning |
| `SystemSettingsSearch.swift` | Verified System Settings page catalog and matching |
| `SearchDiagnostics.swift` | "Why is this not found?" analysis |
| `LokiiSearch.swift` | Bundled engine process management and result adaptation |
| `LokiiConfig.swift` | Scope synchronization for the legacy external Lokii mode (kept for migration; not used by the bundled engine) |
| `MenuBarIcon.swift` | Vector menu bar template image |
| `BrandSignature.swift`, `BrandAboutView.swift` | Vector brand assets |
| `LaunchEnvironment.swift` | Removes terminal-only environment variables before launching child apps |
| `Engine/` | Rust host that links `lokii-core` and exposes the JSONL protocol |
| `ThirdParty/lokii/` | Vendored `lokii-core` v0.1.9 with a five-file patch |
| `ThirdParty/tomlplusplus/` | toml++ 3.4.0 for the legacy configuration helper |
| `Tests/` | Standalone Swift, shell, and Python tests |
| `Tools/` | Build helpers and asset generators |
| `Brand/` | Vector PDFs, SVGs, and icon fallbacks |

## Search data flow

### Native engine

1. The scanner walks the configured roots. It applies hidden/alias/symlink filters during enumeration.
2. Each entry is classified into a file kind and stored in an in-memory snapshot with name, path, type, and timestamps.
3. A query normalizes case, width, and diacritics, splits keywords, and matches against the name or full path.
4. The filter layer applies the whitelist/blacklist, type rules, extension rules, and pinned-item rules.
5. The ranking layer places pinned items first, then applications if enabled, then normal matches.
6. The UI receives the first N candidates and the total match count.

The snapshot is persisted as a binary property list under `~/Library/Application Support/QuickFind/IndexCache/`. On launch the cache is loaded before the background calibration completes.

### Bundled engine

1. The app sends an `initialize` request with roots, excluded paths, hidden-file preference, cache directory, and a 5,000-result prefetch limit.
2. The engine scans or restores its own cache and streams status events.
3. A `search` request returns raw matches. The app applies the same Swift-side filters, aliases, Pinyin, pinned items, and ranking.
4. The app never reads or writes `~/.config/lokii` when using the bundled engine.

## Settings and state

| Path | Contents |
|---|---|
| `~/Library/Application Support/QuickFind/settings.json` | All user settings, including roots, rules, pinned items, theme, and hotkey |
| `~/Library/Application Support/QuickFind/IndexCache/names-v1.plist` | Native engine cache |
| `~/Library/Application Support/QuickFind/LokiiEngine/v1/` | Bundled engine cache, runtime state, and instance lock |

The support directory name is historical (`QuickFind`) and is not tied to the bundle identifier. Changing the bundle identifier does not move or reset these files.

## Permissions and identity

- The app is not sandboxed. It reads user-selected folders and relies on macOS TCC for protected locations.
- Full Disk Access is optional. Without it, macOS prompts per protected folder.
- Contacts access is requested only when the user enables Contacts search.
- Finder automation is requested on the first `Command-I`.
- The application bundle identifier is `cn.meetsee.app`; the helper identifier is `cn.meetsee.app.engine`.
- Local development builds prefer a stable self-signed identity so TCC grants survive rebuilds. Public releases use ad-hoc signing; each new build has a new cdhash-based designated requirement, so macOS may ask for permissions again after an update.

## Build pipeline

`build.sh` performs the following steps:

1. Resolve a signing identity (`CopyLocalDev` if present, otherwise ad-hoc).
2. Build and sign the Rust helper with `Tools/build-lokii-engine.sh`.
3. Compile the Swift sources with `xcrun swiftc -O`.
4. Copy brand PDFs and license files into `Contents/Resources`.
5. Compile `AppIcon.icon` with `actool` and generate a fallback `AppIcon.icns`.
6. Write `Info.plist`.
7. Sign the app and verify the signature.

`test.sh` compiles each test target separately and runs it. Some tests create temporary apps, indexes, or files; they do not touch the user's search roots.

## Design constraints

- Native AppKit only. The UI does not embed a WebView.
- The search path stays local. There is no network code in the app or engine.
- The native engine remains the reference behavior. The bundled engine is an optional alternative, not a replacement for the filter and ranking rules implemented in Swift.
- File contents are out of scope. The index stores names, paths, types, and timestamps only.
