#!/bin/bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
OUT="${ROOT}/build/ios-launcher-smoke"
APP="${OUT}/Payload/GeneralsXZH.app"
IPA="${OUT}/GeneralsXZH-launcher-smoke-unsigned.ipa"
SDK="$(xcrun --sdk iphoneos --show-sdk-path)"

rm -rf "${OUT}"
mkdir -p "${APP}"

echo "==> Compiling native launcher smoke app"
xcrun --sdk iphoneos clang++ \
  -std=c++17 \
  -fobjc-arc \
  -fmodules \
  -arch arm64 \
  -miphoneos-version-min=16.0 \
  -isysroot "${SDK}" \
  -I "${ROOT}/GeneralsMD/Code/Main" \
  "${ROOT}/scripts/build/ios/launcher-smoke-main.mm" \
  "${ROOT}/GeneralsMD/Code/Main/IOSProfileLauncher.mm" \
  -framework Foundation \
  -framework UIKit \
  -o "${APP}/GeneralsXZH"

cat > "${APP}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>CFBundleDisplayName</key>
    <string>ZH Launcher Test</string>
    <key>CFBundleExecutable</key>
    <string>GeneralsXZH</string>
    <key>CFBundleIdentifier</key>
    <string>com.dvorov.generalszh.launcher</string>
    <key>CFBundleInfoDictionaryVersion</key>
    <string>6.0</string>
    <key>CFBundleName</key>
    <string>GeneralsXZH</string>
    <key>CFBundlePackageType</key>
    <string>APPL</string>
    <key>CFBundleShortVersionString</key>
    <string>0.1</string>
    <key>CFBundleVersion</key>
    <string>1</string>
    <key>LSRequiresIPhoneOS</key>
    <true/>
    <key>MinimumOSVersion</key>
    <string>16.0</string>
    <key>UIDeviceFamily</key>
    <array>
        <integer>2</integer>
    </array>
    <key>UIFileSharingEnabled</key>
    <true/>
    <key>LSSupportsOpeningDocumentsInPlace</key>
    <true/>
    <key>UIRequiresFullScreen</key>
    <true/>
    <key>UISupportedInterfaceOrientations~ipad</key>
    <array>
        <string>UIInterfaceOrientationLandscapeLeft</string>
        <string>UIInterfaceOrientationLandscapeRight</string>
    </array>
</dict>
</plist>
PLIST

plutil -lint "${APP}/Info.plist"
file "${APP}/GeneralsXZH"
file "${APP}/GeneralsXZH" | grep -q "Mach-O"
lipo -info "${APP}/GeneralsXZH" | grep -q arm64

(
  cd "${OUT}"
  /usr/bin/zip -qry "$(basename "${IPA}")" Payload
)

test -f "${IPA}"
echo "IPA=${IPA}"
du -h "${IPA}"
