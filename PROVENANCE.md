# Provenance

Meet&See was written for this project and iterated in a recorded development session. No source code from another macOS launcher is known to be included.

## Third-party components

The only third-party code included in the repository is listed in [`THIRD-PARTY-NOTICES.md`](THIRD-PARTY-NOTICES.md):

- `lokii-core` v0.1.9 (MIT), vendored and patched.
- toml++ v3.4.0 (MIT).
- Transitive Rust crates pinned by `Engine/Cargo.lock`.

No official Lokii application code, GUI, CLI, configuration, or build artifact is included.

## If you believe code was derived from your work

Open an issue with the specific file, function, and upstream project. If the claim is valid, the project will do one of the following before the next release:

- Add the copyright notice and license text, and record the change in `THIRD-PARTY-NOTICES.md`.
- Replace the derived code with an independent implementation if the license is incompatible with GPL-3.0-or-later.

Because the project is distributed under GPL-3.0-or-later, the corresponding source is always available in this repository.
