# Vendored lokii-core

- Upstream: <https://github.com/huangy7/lokii>
- Upstream tag: **v0.1.9**
- Vendored on: 2026-11-09
- Local version label: **0.1.9-meetsee.1**

The `lokii-core/` directory and the upstream MIT `LICENSE` were copied from a clean research checkout of tag v0.1.9. Each copied file was compared byte-for-byte at the time of import. The official GUI and upstream build artifacts are not included. The current tree additionally contains the patch and the publication sanitization described below.

The host lives in `../../Engine/`. Its `Cargo.lock` pins the complete dependency graph. Build paths are relative to this repository; the original research checkout is not required.

Upstream CLI and UniFFI source files are retained because the core is kept close to upstream. Meet&See does not build, install, or invoke the official CLI, and does not use the global configuration or Unix socket.

## Patch

The core is not an unmodified upstream copy. After the initial import, the following minimal patch was applied:

- `src/config.rs`, `src/filter.rs`, `src/scanner.rs`: add a default-on `skip_protected_paths` policy. The standalone host disables this heuristic for roots the user explicitly saved, so "cannot read the TCC database" is not treated as a reason to skip all of Documents. Actual reads remain governed by macOS TCC; the patch does not bypass authorization.
- `src/startup.rs`: include the policy in cache-scope applicability, so an incompatible old scope is not reused.
- `src/watcher.rs`: report the real service-thread state, support explicit stop and flush confirmation, and expose replay, calibration, incremental, and network-task states. An empty scope can complete, and a watcher that cannot start reports an error.

## Publication sanitization

Synthetic user names in upstream tests and comments (for example `/Users/test`, `/Users/me`, `/Users/huangy`) were replaced with `/Users/example`. Comments that referred to `/private/var` were reworded to "the /private prefix". These changes affect test fixtures and comments only; library logic is unchanged.

## Verification

- 276 upstream core unit tests pass.
- 13 isolated host contract tests cover incremental changes, hot restore, disabling the watcher, scope expansion/contraction, cache usage, real rebuild, and shutdown.
- Swift-side mode switching and candidate parity are covered by the project tests and acceptance records.

## License

The upstream code remains MIT. The local patch and the combined work are distributed under GPL-3.0-or-later. The MIT notice is preserved in `LICENSE` in this directory and is shipped in the application bundle.

Meet&See is not affiliated with or endorsed by the Lokii project.
