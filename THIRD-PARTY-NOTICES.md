# Third-party notices

Meet&See itself is licensed under the GNU General Public License, version 3 or later (`GPL-3.0-or-later`). See [`LICENSE`](LICENSE).

This file lists third-party components that are included in the source tree or in the application bundle. The full license text of each component is preserved next to its source.

## lokii-core 0.1.9 (MIT)

- Upstream: <https://github.com/huangy7/lokii>
- Copyright: Copyright (c) 2026 huangy7 / Lokii Contributors
- License: MIT — [`ThirdParty/lokii/LICENSE`](ThirdParty/lokii/LICENSE)
- Vendored path: `ThirdParty/lokii/lokii-core`
- Local version label: `0.1.9-meetsee.1`

The vendored copy is a patched version of the upstream v0.1.9 `lokii-core` crate. The upstream copyright and MIT license are retained. The patch is limited to five source files and is described in [`ThirdParty/lokii/README.md`](ThirdParty/lokii/README.md).

The combined work is distributed under GPL-3.0-or-later. The MIT license continues to apply to the upstream code; it does not disappear because the combined work is GPL.

No official Lokii GUI, CLI, global configuration, Unix socket, or build artifact is included in this repository or application bundle. Meet&See builds a separate headless helper from `lokii-core`.

## toml++ 3.4.0 (MIT)

- Upstream: <https://github.com/marzer/tomlplusplus/tree/v3.4.0>
- Copyright: Copyright (c) Mark Gillard and contributors
- License: MIT — [`ThirdParty/tomlplusplus/LICENSE`](ThirdParty/tomlplusplus/LICENSE)
- Vendored path: `ThirdParty/tomlplusplus/toml.hpp`

Used only by the bundled scope configuration helper (`Tools/LokiiConfigTool.cpp`). The single-header distribution is unmodified.

## Rust dependencies

The bundled engine uses transitive Rust crates. A generated inventory with versions and license identifiers is available in [`ThirdParty/rust-dependencies.md`](ThirdParty/rust-dependencies.md). The license texts shipped with those crates are collected in [`ThirdParty/RUST-LICENSES.txt`](ThirdParty/RUST-LICENSES.txt).

The inventory is generated from `Engine/Cargo.lock`. The licenses are MIT, Apache-2.0, ISC, MPL-2.0, CC0-1.0, Unlicense, Zlib, Unicode-3.0, or dual/triple-license combinations of those. All are compatible with GPL-3.0-or-later.

## Apple frameworks

Meet&See links against system frameworks provided by macOS (AppKit, CoreServices, Carbon, Contacts, Metal, QuartzCore, ServiceManagement). These frameworks are not redistributed with the application.

## Fonts and brand assets

- The application does not bundle font files. The default UI font, Maple Mono NF CN, is used only when it is already installed on the user's Mac; otherwise the system font is used.
- The brand PDFs under `Brand/` contain vector paths converted from system fonts. No font file is distributed.
- The application icon and brand artwork are original assets for this project and are distributed under the same GPL-3.0-or-later terms unless a file states otherwise.

## GPL source availability

Release binaries are built from a tagged commit in this repository. Each release page links to the corresponding source tag so that recipients of the binary can obtain the corresponding source under GPL-3.0 section 6.
