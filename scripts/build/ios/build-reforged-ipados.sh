#!/usr/bin/env bash
# GeneralsX @build Codex 27/11/2026 Build the isolated Reforged device runtime.
# Build the optional Reforged ARM64 device app on a Mac with Xcode, CMake and Ninja.
# Usage: bash scripts/build/ios/build-reforged-ipados.sh
set -euo pipefail

if [[ "$(uname -s)" != Darwin ]]; then
  echo "Reforged device builds require macOS and the Xcode iPhoneOS SDK." >&2
  exit 1
fi

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd)"
port="$root/ios/reforged"
upstream=https://github.com/olcayseygan/CnCGeneralsZH-Reforged.git
revision=2b331b2057577e158de724cb3d2b3fe574752bd2
sdk="$(xcrun --sdk iphoneos --show-sdk-path)"
min_ios=16.0

mkdir -p "$root/build/reforged-ipados"
workspace="$(mktemp -d "$root/build/reforged-ipados/run.XXXXXX")"
echo "Reforged build workspace: $workspace"
REPO="$workspace/upstream"
CODE="$REPO/GeneralsMD/Code"
BUILD="$workspace/device"
git init -q "$REPO"
git -C "$REPO" fetch --no-tags --depth 1 "$upstream" "$revision"
git -C "$REPO" -c core.autocrlf=false checkout --detach FETCH_HEAD
[[ "$(git -C "$REPO" rev-parse HEAD)" == "$revision" ]]
git -C "$REPO" apply --check "$port/ipados.patch"
git -C "$REPO" apply "$port/ipados.patch"
mkdir "$workspace/vendor-tmp"
TMPDIR="$workspace/vendor-tmp" ZH_SKIP_ART=1 bash "$CODE/Tools/vendor.sh"

# This generator runs on the build machine even when the game targets a device.
SDKROOT="$(xcrun --sdk macosx --show-sdk-path)" xcrun --sdk macosx clang++ -std=c++17 -O2 \
  "$CODE/Tools/fingerprint/build_fingerprint.cpp" -o "$workspace/build_fingerprint"
cmake -S "$CODE" -B "$BUILD" -G Ninja \
  -DCMAKE_SYSTEM_NAME=iOS -DCMAKE_OSX_SYSROOT="$sdk" \
  -DCMAKE_OSX_ARCHITECTURES=arm64 -DCMAKE_OSX_DEPLOYMENT_TARGET="$min_ios" \
  -DCMAKE_BUILD_TYPE=Release -DCMAKE_EXE_LINKER_FLAGS=-Wl,-no_adhoc_codesign \
  -DZH_HOST_FINGERPRINT="$workspace/build_fingerprint"
cmake --build "$BUILD" --target generals zh_overlay

binary="$BUILD/generals"
[[ "$(xcrun lipo -archs "$binary")" == arm64 ]]
xcrun vtool -show-build "$binary" | awk '$1 == "platform" && $2 == "IOS" { found=1 } END { exit !found }'
if ! xcrun otool -L "$binary" | awk 'NR > 1 && $1 !~ /^\/(System\/Library\/|usr\/lib\/)/ { bad=1 } END { exit bad }'; then
  echo "Unexpected dynamic dependency in the Reforged executable." >&2
  exit 1
fi

# Use upstream's link-line license inventory so every static dependency is covered.
. "$CODE/Tools/package-common.sh"
libraries="$(package_link_libraries "$BUILD/build.ninja" "$workspace/link-libs.txt")"
[[ -n "$libraries" ]]
library_names=()
while IFS= read -r library; do library_names+=("$library"); done <<< "$libraries"
entries="$(package_license_entries "$CODE/Tools/macos-app-licenses.txt" "${library_names[@]}")" || {
  echo "Missing license inventory entries: $entries" >&2
  exit 1
}

app="$workspace/staging/Reforged-iPad.app"
mkdir -p "$app/Licenses"
cp "$binary" "$app/generals"
cp "$port/Info.plist" "$app/Info.plist"
plutil -lint "$app/Info.plist"
cp -R "$BUILD/overlay" "$app/Overlay"
while IFS= read -r entry; do license_entry "$entry" "$app/Licenses"; done <<< "$entries"
cp "$REPO/NOTICE.md" "$app/Licenses/NOTICE.md"
cp "$port/ipados.patch" "$app/Licenses/ipados.patch"
printf 'Upstream source: %s\nRevision: %s\n' "$upstream" "$revision" > "$app/Licenses/Source.txt"
mv "$app" "$workspace/Reforged-iPad.app"
echo "Unsigned device bundle: $workspace/Reforged-iPad.app"
