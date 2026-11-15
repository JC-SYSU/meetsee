#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/meetsee-mode-integration.XXXXXX")"
bash Tools/build-lokii-engine.sh "$BUILD/觅见.app"
python3 - "$BUILD" <<'PY'
from pathlib import Path
import sys
build = Path(sys.argv[1])
source = Path('main.swift').read_text().split('\nLaunchEnvironment.sanitize()')[0]
source = source.replace('window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)', 'window.center()')
source = source.replace('NSApp.setActivationPolicy(.regular)', 'NSApp.setActivationPolicy(.accessory)')
(build/'main.swift').write_text(source + '\n' + Path('Tests/AppModeIntegration.swift').read_text())
(build/'files').mkdir(); (build/'files/ONLY_NATIVE.txt').touch()
PY
cp Brand/Signature-light.pdf Brand/Signature-dark.pdf Brand/AboutBrand-light.pdf Brand/AboutBrand-dark.pdf "$BUILD/"
xcrun swiftc ContinuousCorners.swift -g -swift-version 5 SearchCore.swift ContactsSearch.swift LokiiSearch.swift SystemSettingsSearch.swift SearchDiagnostics.swift IndexWatcher.swift VignetteView.swift HDRSelection.swift SelectionStyle.swift NativeUI.swift MenuBarIcon.swift BrandSignature.swift BrandAboutView.swift PinnedItemsUI.swift LaunchEnvironment.swift "$BUILD/main.swift" -o "$BUILD/mode-tests" -framework AppKit -framework Carbon -framework ServiceManagement -framework CoreServices -framework Contacts
QUICKFIND_DATA_DIR="$BUILD/data" QUICKFIND_ROOTS="$BUILD/files" "$BUILD/mode-tests" "$BUILD/files" "$BUILD/觅见.app/Contents/Helpers/meetsee-lokii-engine"
echo "Mode integration artifacts: $BUILD"
