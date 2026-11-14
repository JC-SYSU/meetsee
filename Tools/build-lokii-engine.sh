#!/bin/bash
# Build-time Rust only; end users need neither Rust nor the official Lokii install.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
APP="${1:?usage: build-lokii-engine.sh STAGED_APP}"
IDENTITY="${SIGNING_IDENTITY:--}"
if [ "$IDENTITY" != "-" ] && ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$IDENTITY\""; then
    echo "No valid signing identity \"$IDENTITY\". Set SIGNING_IDENTITY=- for ad-hoc signing." >&2
    exit 1
fi
# Explicit target directory ignores developer-wide CARGO_TARGET_DIR settings.
cargo build --manifest-path "$ROOT/Engine/Cargo.toml" --locked --release \
    --bin meetsee-lokii-engine --target-dir "$ROOT/Engine/target"
mkdir -p "$APP/Contents/Helpers" "$APP/Contents/Resources/Licenses"
install -m 755 "$ROOT/Engine/target/release/meetsee-lokii-engine" \
    "$APP/Contents/Helpers/meetsee-lokii-engine"
cp "$ROOT/ThirdParty/lokii/LICENSE" "$APP/Contents/Resources/Licenses/lokii-MIT.txt"
codesign --force --sign "$IDENTITY" --identifier cn.meetsee.app.engine \
    "$APP/Contents/Helpers/meetsee-lokii-engine"
codesign --verify --strict "$APP/Contents/Helpers/meetsee-lokii-engine"
