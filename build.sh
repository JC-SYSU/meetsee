#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"
APP="${1:-build/觅见.app}"
# Keep the Swift binary, Rust helper, resources, and Info.plist on one release floor.
export MACOSX_DEPLOYMENT_TARGET=13.0
# Local builds prefer the stable self-signed identity so TCC grants survive
# rebuilds. Release builds and CI can pass SIGNING_IDENTITY=- for ad-hoc.
SIGNING_IDENTITY="${SIGNING_IDENTITY:-}"
if [ -z "$SIGNING_IDENTITY" ]; then
    if /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq '"CopyLocalDev"'; then
        SIGNING_IDENTITY="CopyLocalDev"
    else
        SIGNING_IDENTITY="-"
    fi
fi
if [ "$SIGNING_IDENTITY" != "-" ] && ! /usr/bin/security find-identity -v -p codesigning | /usr/bin/grep -Fq "\"$SIGNING_IDENTITY\""; then
    echo "No valid signing identity \"$SIGNING_IDENTITY\". Set SIGNING_IDENTITY=- for ad-hoc signing." >&2
    exit 1
fi
export SIGNING_IDENTITY
mkdir -p "$(dirname "$APP")" "$APP/Contents/MacOS" "$APP/Contents/Resources"
# Build and sign the bundled search engine before the app.
bash Tools/build-lokii-engine.sh "$APP"
xcrun swiftc -target "$(uname -m)-apple-macos${MACOSX_DEPLOYMENT_TARGET}" ContinuousCorners.swift -O -swift-version 5 SearchCore.swift ContactsSearch.swift LokiiSearch.swift SystemSettingsSearch.swift SearchDiagnostics.swift IndexWatcher.swift VignetteView.swift HDRSelection.swift SelectionStyle.swift NativeUI.swift MenuBarIcon.swift BrandSignature.swift BrandAboutView.swift PinnedItemsUI.swift LaunchEnvironment.swift main.swift -o "$APP/Contents/MacOS/QuickFind" -framework AppKit -framework Carbon -framework ServiceManagement -framework CoreServices -framework Contacts
cp Brand/Signature-light.pdf Brand/Signature-dark.pdf Brand/AboutBrand-light.pdf Brand/AboutBrand-dark.pdf "$APP/Contents/Resources/"
mkdir -p "$APP/Contents/Resources/Licenses"
cp LICENSE "$APP/Contents/Resources/Licenses/GPL-3.0.txt"
cp ThirdParty/tomlplusplus/LICENSE "$APP/Contents/Resources/Licenses/tomlplusplus-MIT.txt"
cp ThirdParty/RUST-LICENSES.txt "$APP/Contents/Resources/Licenses/RUST-LICENSES.txt"
cp THIRD-PARTY-NOTICES.md "$APP/Contents/Resources/Licenses/THIRD-PARTY-NOTICES.md"
ICON_INFO="$(mktemp "${TMPDIR:-/tmp}/quickfind-icon-info.XXXXXX")"
xcrun actool AppIcon.icon --compile "$APP/Contents/Resources" --platform macosx --minimum-deployment-target "$MACOSX_DEPLOYMENT_TARGET" --app-icon AppIcon --output-partial-info-plist "$ICON_INFO" --output-format human-readable-text
# Static fallback for system surfaces that do not read Icon Composer assets.
ICONSET="$(mktemp -d "${TMPDIR:-/tmp}/quickfind-iconset.XXXXXX")/AppIcon.iconset"
mkdir -p "$ICONSET"
for size in 16 32 128 256 512; do
    sips -z "$size" "$size" Brand/AppIcon-fallback.png --out "$ICONSET/icon_${size}x${size}.png" >/dev/null
    double=$((size * 2))
    sips -z "$double" "$double" Brand/AppIcon-fallback.png --out "$ICONSET/icon_${size}x${size}@2x.png" >/dev/null
done
xcrun iconutil -c icns "$ICONSET" -o "$APP/Contents/Resources/AppIcon.icns"
/usr/bin/python3 - "$APP" "$ICON_INFO" "$MACOSX_DEPLOYMENT_TARGET" <<'PY'
import plistlib,sys
from pathlib import Path
app=Path(sys.argv[1])
info={'CFBundleExecutable':'QuickFind','CFBundleIdentifier':'cn.meetsee.app','CFBundleName':'觅见','CFBundleDisplayName':'觅见','CFBundlePackageType':'APPL','CFBundleShortVersionString':'0.1.0','CFBundleVersion':'1','LSMinimumSystemVersion':sys.argv[3],'LSUIElement':True,'NSHighResolutionCapable':True,'NSPrincipalClass':'NSApplication','NSContactsUsageDescription':'在你启用通讯录检索后，仅在本机按完整姓名或全拼查找联系人，并复制所选电话号码。','NSAppleEventsUsageDescription':'在你按 Command+I 时，请求 Finder 显示所选文件的原生简介窗口。','CFBundleLocalizations':['zh-Hans','en'],'CFBundleDevelopmentRegion':'zh-Hans','CFBundleAllowMixedLocalizations':True}
with open(sys.argv[2], 'rb') as f: info.update(plistlib.load(f))
with (app/'Contents/Info.plist').open('wb') as f: plistlib.dump(info,f)
PY
codesign --force --sign "$SIGNING_IDENTITY" "$APP"
codesign --verify --strict "$APP"
printf '\nBuilt: %s\n' "$APP"
