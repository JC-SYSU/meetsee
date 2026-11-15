#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")/.."
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/meetsee-contacts-tests.XXXXXX")"
xcrun swiftc SearchCore.swift SystemSettingsSearch.swift Tests/ContactsTests.swift -o "$BUILD/core-tests"
"$BUILD/core-tests"
xcrun swiftc SearchCore.swift ContactsSearch.swift Tests/ContactsServiceTests.swift -o "$BUILD/service-tests" -framework AppKit -framework Contacts
"$BUILD/service-tests"
python3 - "$BUILD" <<'PY'
from pathlib import Path
import sys
source = Path('main.swift').read_text().split('\nLaunchEnvironment.sanitize()')[0]
source = source.replace('window.center(); NSApp.activate(ignoringOtherApps: true); window.makeKeyAndOrderFront(nil)', 'window.center()')
source = source.replace('NSApp.setActivationPolicy(.regular)', 'NSApp.setActivationPolicy(.accessory)')
(Path(sys.argv[1])/'main.swift').write_text(source + '\n' + Path('Tests/ContactsIntegration.swift').read_text())
(Path(sys.argv[1])/'files').mkdir()
PY
cp Brand/Signature-light.pdf Brand/Signature-dark.pdf Brand/AboutBrand-light.pdf Brand/AboutBrand-dark.pdf "$BUILD/"
xcrun swiftc ContinuousCorners.swift -swift-version 5 SearchCore.swift ContactsSearch.swift LokiiSearch.swift SystemSettingsSearch.swift SearchDiagnostics.swift IndexWatcher.swift VignetteView.swift HDRSelection.swift SelectionStyle.swift NativeUI.swift MenuBarIcon.swift BrandSignature.swift BrandAboutView.swift PinnedItemsUI.swift LaunchEnvironment.swift "$BUILD/main.swift" -o "$BUILD/app-tests" -framework AppKit -framework Carbon -framework ServiceManagement -framework CoreServices -framework Contacts
QUICKFIND_DATA_DIR="$BUILD/data" "$BUILD/app-tests" "$BUILD/files"
echo "Contacts test artifacts: $BUILD"
