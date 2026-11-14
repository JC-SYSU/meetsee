# Contributing

Thanks for taking a look. Meet&See is a small native macOS project; the most useful contributions are bug reports with reproducible search cases, tests, and focused fixes.

## Before you start

- Read `docs/behavior.md` and `docs/architecture.md`.
- For search bugs, include the file name, the query you typed, the expected result, and the actual result. If possible, include whether the native or bundled engine was active.
- For UI changes, include a screenshot or a short recording. Do not include real personal file names; replace them with neutral examples.

## Build

Prerequisites:

- macOS 13 or later.
- Xcode command-line tools with `actool` and Icon Composer support.
- Rust and Cargo for the bundled engine.

```bash
./build.sh
./test.sh
```

`build.sh` writes `build/觅见.app` by default. Signing behavior:

- It prefers the local `CopyLocalDev` identity when present.
- Otherwise it uses ad-hoc signing.
- `SIGNING_IDENTITY=<name>` selects a specific identity.
- `SIGNING_IDENTITY=-` forces ad-hoc.

`test.sh` builds each test target into a temporary directory. Some tests create temporary files and apps; they do not modify your search roots.

## Code layout

See `docs/architecture.md` for the file map. In short:

- `SearchCore.swift` owns settings, scanning, matching, filtering, and ranking.
- `main.swift` owns the AppKit UI and orchestration.
- `Engine/` is the Rust helper; `ThirdParty/lokii/` is the vendored core.
- `Tests/` contains standalone Swift, shell, and Python tests.

The project uses `xcrun swiftc` directly rather than an Xcode project. Keep the build script self-contained.

## Tests

- Add a regression test for every bug fix when practical.
- Core logic tests live in `Tests/main.swift` or a dedicated test executable listed in `test.sh`.
- UI drawing tests should assert geometry or layer properties rather than relying on a screenshot.
- Engine protocol changes require updating both `Tests/lokii_engine_tests.py` and the relevant Swift tests.
- If a test is timing-sensitive (FSEvents, window animations), make it wait on a condition with a timeout instead of a fixed sleep.

## Style

- Match the surrounding Swift style. The codebase uses explicit AppKit layout, no SwiftUI, and no WebView.
- Keep user-facing strings in the existing localization path. English documentation and English release notes are required; the in-app UI can remain bilingual or Chinese.
- Do not add network access, analytics, or a new third-party dependency without discussing it first.
- Do not change the default search roots, blacklist semantics, or ranking order without a test that documents the intended behavior.

## Commits and pull requests

- Keep commits focused. A bug fix and a refactor belong in separate commits.
- Use the repository's noreply identity if you are a maintainer; external contributors can use their own commit identity.
- Do not commit build output, `Engine/target`, app bundles, zips, or `.DS_Store`.
- In the PR description, state what changed, how it was tested, and which permissions or engine mode were exercised.
- By contributing, you agree that your contribution is licensed under GPL-3.0-or-later.

## Security and privacy

- Never include a real API key, token, certificate private key, or personal file path in a commit.
- Test fixtures must be synthetic. Do not attach a real Contacts database, search cache, or transcript.
- If you find a security issue, do not open a public issue with exploit details; contact the maintainer first.
