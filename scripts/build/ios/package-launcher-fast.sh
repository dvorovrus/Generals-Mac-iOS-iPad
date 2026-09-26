#!/bin/bash
# Rebuild only the native iOS launcher dylib and inject it into an existing
# unsigned GeneralsXZH shell IPA. No engine/DXVK/SDL rebuild is performed.
set -euo pipefail

if [[ $# -ne 2 ]]; then
  echo "Usage: $0 <base-shell.ipa> <output.ipa>" >&2
  exit 2
fi

BASE_IPA="$1"
OUTPUT_IPA="$2"
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
LAUNCHER_SRC="${PROJECT_ROOT}/GeneralsMD/Code/Main/IOSProfileLauncher.mm"
LAUNCHER_HEADER="${PROJECT_ROOT}/GeneralsMD/Code/Main/IOSProfileLauncher.h"

test -f "${BASE_IPA}" || { echo "ERROR: base shell IPA not found: ${BASE_IPA}" >&2; exit 1; }
test -f "${LAUNCHER_SRC}" || { echo "ERROR: launcher source not found: ${LAUNCHER_SRC}" >&2; exit 1; }
test -f "${LAUNCHER_HEADER}" || { echo "ERROR: launcher header not found: ${LAUNCHER_HEADER}" >&2; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "$TMP"' EXIT
EXTRACTED="${TMP}/ipa"
LAUNCHER_LIB="${TMP}/libGeneralsXLauncher.dylib"
mkdir -p "${EXTRACTED}"

echo "==> Compiling native launcher only"
xcrun --sdk iphoneos clang++ \
  -target arm64-apple-ios16.0 \
  -std=c++17 \
  -fobjc-arc \
  -fblocks \
  -dynamiclib \
  -Wl,-install_name,@rpath/libGeneralsXLauncher.dylib \
  -framework Foundation \
  -framework UIKit \
  -lobjc \
  "${LAUNCHER_SRC}" \
  -o "${LAUNCHER_LIB}"

file "${LAUNCHER_LIB}" | grep -q "Mach-O"
lipo -info "${LAUNCHER_LIB}" | grep -q "arm64"
otool -D "${LAUNCHER_LIB}" | grep -q "@rpath/libGeneralsXLauncher.dylib"

echo "==> Opening base shell IPA"
ditto -x -k "${BASE_IPA}" "${EXTRACTED}"
APP="$(find "${EXTRACTED}/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
test -n "${APP}" && test -d "${APP}" || {
  echo "ERROR: no .app bundle found in base shell IPA" >&2
  exit 1
}

ENGINE="${APP}/GeneralsXZH"
TARGET_LIB="${APP}/Frameworks/libGeneralsXLauncher.dylib"
test -f "${ENGINE}" || { echo "ERROR: GeneralsXZH executable missing from base shell" >&2; exit 1; }
test -d "${APP}/Frameworks" || { echo "ERROR: Frameworks directory missing from base shell" >&2; exit 1; }
otool -L "${ENGINE}" | grep -q "@rpath/libGeneralsXLauncher.dylib" || {
  echo "ERROR: base engine is not linked to @rpath/libGeneralsXLauncher.dylib" >&2
  exit 1
}

echo "==> Replacing libGeneralsXLauncher.dylib"
cp "${LAUNCHER_LIB}" "${TARGET_LIB}"

# The artifact must remain unsigned. Sideloadly/AltStore/etc. signs the final IPA.
find "${APP}" -name "_CodeSignature" -type d -prune -exec rm -rf {} + 2>/dev/null || true
rm -f "${APP}/embedded.mobileprovision"

echo "==> Auditing launcher runtime"
while IFS= read -r dependency; do
  [[ -n "${dependency}" ]] || continue
  if [[ "${dependency}" == @rpath/* ]]; then
    relative="${dependency#@rpath/}"
    candidate="${APP}/Frameworks/${relative}"
    [[ -e "${candidate}" ]] || {
      echo "ERROR: launcher dependency is not embedded: ${dependency}" >&2
      exit 1
    }
  fi
done < <(otool -L "${TARGET_LIB}" | tail -n +2 | awk '{ print $1 }')

mkdir -p "$(dirname "${OUTPUT_IPA}")"
rm -f "${OUTPUT_IPA}"
(
  cd "${EXTRACTED}"
  /usr/bin/zip -qry "${OUTPUT_IPA}" Payload
)

test -f "${OUTPUT_IPA}"
echo "==> Fast launcher IPA ready: ${OUTPUT_IPA}"
du -h "${OUTPUT_IPA}"
