#!/bin/bash
# Upstream includes a real config-creation test: never run it in the user's HOME.
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/meetsee-core-tests.XXXXXX")"
cargo test --manifest-path "$ROOT/ThirdParty/lokii/Cargo.toml" --locked \
    -p lokii-core --lib --no-run --message-format=json \
    --target-dir "$ROOT/Engine/target" > "$STAGE/build.jsonl"
BINARY="$(/usr/bin/python3 - "$STAGE/build.jsonl" <<'PY'
import json, sys
for line in open(sys.argv[1]):
    message = json.loads(line)
    if (message.get('reason') == 'compiler-artifact'
            and message.get('target', {}).get('name') == 'lokii_core'
            and message.get('profile', {}).get('test')
            and message.get('executable')):
        print(message['executable'])
        break
else:
    raise SystemExit('core test executable not found')
PY
)"
mkdir -p "$STAGE/userdir/.config" "$STAGE/userdir/Documents"
HOME="$STAGE/userdir" XDG_CONFIG_HOME="$STAGE/userdir/.config" PATH=/usr/bin:/bin \
    /usr/bin/sandbox-exec -p "(version 1)(allow default)(deny file-read* file-write* (subpath \"$HOME/.config/lokii\"))" \
    "$BINARY"
echo "Isolated core test artifacts: $STAGE"
