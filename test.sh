#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
BUILD="$(mktemp -d "${TMPDIR:-/tmp}/quickfind-tests.XXXXXX")"
xcrun swiftc SearchCore.swift Tests/main.swift -o "$BUILD/tests"
"$BUILD/tests" "$BUILD/fixture"
echo "Test workspace kept at $BUILD"
bash Tests/test_contacts.sh
xcrun swiftc VignetteView.swift Tests/VignetteTests.swift -o "$BUILD/vignette-tests" -framework AppKit
"$BUILD/vignette-tests"
xcrun swiftc SearchCore.swift HDRSelection.swift SelectionStyle.swift Tests/SelectionStyleTests.swift -o "$BUILD/selection-tests" -framework AppKit
"$BUILD/selection-tests"
xcrun swiftc SearchCore.swift NativeUI.swift Tests/NativeUITests.swift -o "$BUILD/native-ui-tests" -framework AppKit -framework QuartzCore
"$BUILD/native-ui-tests"
xcrun swiftc SearchCore.swift NativeUI.swift Tests/SettingsControlsTests.swift -o "$BUILD/settings-controls-tests" -framework AppKit -framework QuartzCore
"$BUILD/settings-controls-tests"
xcrun swiftc BrandSignature.swift Tests/BrandSignatureTests.swift -o "$BUILD/signature-tests" -framework AppKit
"$BUILD/signature-tests" "$PWD/Brand"
xcrun swiftc BrandAboutView.swift Tests/BrandAboutTests.swift -o "$BUILD/about-tests" -framework AppKit
"$BUILD/about-tests" "$PWD/Brand"
xcrun swiftc SearchCore.swift Tests/IndexCacheTests.swift -o "$BUILD/cache-tests"
"$BUILD/cache-tests" "$BUILD/cache-fixture"
xcrun swiftc SearchCore.swift IndexWatcher.swift Tests/IndexWatcherTests.swift -o "$BUILD/watcher-tests" -framework CoreServices
"$BUILD/watcher-tests" "$BUILD/watcher-fixture"
xcrun swiftc -O SearchCore.swift Tests/SearchReference.swift Tests/SearchPerformanceTests.swift -o "$BUILD/search-performance-tests"
"$BUILD/search-performance-tests"
xcrun swiftc SearchCore.swift Tests/SettingsUpdateTests.swift -o "$BUILD/settings-update-tests"
"$BUILD/settings-update-tests"
xcrun swiftc SearchCore.swift SystemSettingsSearch.swift Tests/SystemSettingsTests.swift -o "$BUILD/system-settings-tests"
"$BUILD/system-settings-tests"
xcrun swiftc SearchCore.swift SystemSettingsSearch.swift SearchDiagnostics.swift Tests/SearchDiagnosticsTests.swift -o "$BUILD/diagnostics-tests"
"$BUILD/diagnostics-tests"
xcrun swiftc SearchCore.swift SystemSettingsSearch.swift Tests/PinyinTests.swift -o "$BUILD/pinyin-tests"
"$BUILD/pinyin-tests"
xcrun swiftc SearchCore.swift NativeUI.swift Tests/CandidateShortcutTests.swift -o "$BUILD/candidate-shortcut-tests" -framework AppKit -framework QuartzCore
"$BUILD/candidate-shortcut-tests"

xcrun swiftc SearchCore.swift SystemSettingsSearch.swift Tests/PinnedItemsTests.swift -o "$BUILD/pinned-tests"
"$BUILD/pinned-tests"
xcrun swiftc SearchCore.swift SystemSettingsSearch.swift Tests/SearchReference.swift Tests/ApplicationPriorityTests.swift -o "$BUILD/application-priority-tests"
"$BUILD/application-priority-tests"
xcrun swiftc LaunchEnvironment.swift Tests/LaunchEnvironmentTests.swift -o "$BUILD/launch-environment-tests" -framework AppKit
"$BUILD/launch-environment-tests"
xcrun swiftc SearchCore.swift NativeUI.swift Tests/CandidateTextLayoutTests.swift -o "$BUILD/candidate-text-layout-tests" -framework AppKit -framework QuartzCore
"$BUILD/candidate-text-layout-tests"
xcrun swiftc SearchCore.swift NativeUI.swift Tests/PinnedStatusBadgeTests.swift -o "$BUILD/pinned-status-badge-tests" -framework AppKit -framework QuartzCore
"$BUILD/pinned-status-badge-tests"
xcrun swiftc HDRSelection.swift Tests/HDRSelectionTests.swift -o "$BUILD/hdr-selection-tests" -framework AppKit -framework Metal -framework QuartzCore
"$BUILD/hdr-selection-tests"

xcrun swiftc SearchCore.swift HDRSelection.swift SelectionStyle.swift Tests/HDRRowIntegrationTests.swift -o "$BUILD/hdr-row-tests" -framework AppKit
"$BUILD/hdr-row-tests"
xcrun swiftc SearchCore.swift SystemSettingsSearch.swift Tests/CandidateRefreshTests.swift -o "$BUILD/candidate-refresh-tests"
"$BUILD/candidate-refresh-tests"

xcrun swiftc SearchCore.swift LokiiSearch.swift SystemSettingsSearch.swift SearchDiagnostics.swift Tests/LokiiTests.swift -o "$BUILD/lokii-tests"
python3 Tests/lokii_fixture.py "$BUILD/lokii-tests"

xcrun swiftc SearchCore.swift LokiiSearch.swift LokiiConfig.swift Tests/LokiiConfigTests.swift -o "$BUILD/lokii-config-tests"
"$BUILD/lokii-config-tests"

xcrun clang++ -std=c++17 -O2 -Wno-deprecated-literal-operator Tools/LokiiConfigTool.cpp -o "$BUILD/LokiiConfigTool"
python3 Tests/lokii_scope_tool.py "$BUILD/LokiiConfigTool"
"$BUILD/lokii-config-tests" "$BUILD/LokiiConfigTool"

xcrun swiftc MenuBarIcon.swift Tests/MenuBarIconTests.swift -o "$BUILD/menu-icon-tests" -framework AppKit
"$BUILD/menu-icon-tests" "$BUILD"

# Independent engine contracts; temporary scope only, no official Lokii required.
bash Tests/test_lokii_engine.sh

# Real AppDelegate lifecycle with an artificial scope and package helper.
bash Tests/test_app_modes.sh

# Includes upstream config-creation tests, isolated from the real HOME.
bash Tests/test_lokii_core.sh
