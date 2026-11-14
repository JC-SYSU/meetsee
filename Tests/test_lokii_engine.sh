#!/bin/bash
set -euo pipefail
ROOT="$(cd "$(dirname "$0")/.." && pwd)"
STAGE="$(mktemp -d "${TMPDIR:-/tmp}/meetsee-engine-package-test.XXXXXX")"
bash "$ROOT/Tools/build-lokii-engine.sh" "$STAGE/觅见.app"
python3 "$ROOT/Tests/lokii_engine_tests.py" "$STAGE/觅见.app/Contents/Helpers/meetsee-lokii-engine"
xcrun swiftc -O "$ROOT/SearchCore.swift" "$ROOT/LokiiSearch.swift" "$ROOT/SystemSettingsSearch.swift" "$ROOT/Tests/ManagedSearchTests.swift" -o "$STAGE/managed-search-tests"
"$STAGE/managed-search-tests" "$STAGE/觅见.app/Contents/Helpers/meetsee-lokii-engine"
echo "Independent engine test artifacts: $STAGE"
