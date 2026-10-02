#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BUILD="${ROOT}/build/macos-vulkan"
OUT="${ROOT}/build/macos-package"
APP_NAME="GeneralsZH-ContraX-Dev.app"
ONLINE="${GX_MAC_ONLINE:-0}"
if [[ "${ONLINE}" == "1" ]]; then
  BUILD="${ROOT}/build/macos-vulkan-online"
  OUT="${ROOT}/build/macos-online-package"
  APP_NAME="GeneralsZH-Online-Dev.app"
fi
APP="${OUT}/${APP_NAME}"
CONTENTS="${APP}/Contents"
MACOS="${CONTENTS}/MacOS"
RES="${CONTENTS}/Resources"
BIN="${RES}/bin"
LIB="${RES}/lib"

rm -rf "${OUT}"
mkdir -p "${MACOS}" "${BIN}" "${LIB}"

GAME_BIN="${BUILD}/GeneralsMD/GeneralsXZH"
test -f "${GAME_BIN}" || { echo "ERROR: missing ${GAME_BIN}"; exit 1; }
cp "${GAME_BIN}" "${BIN}/GeneralsXZH"
chmod +x "${BIN}/GeneralsXZH"

BUILD_COMMIT="${GITHUB_SHA:-}"
if [[ -z "${BUILD_COMMIT}" ]]; then
  BUILD_COMMIT="$(git -C "${ROOT}" rev-parse HEAD 2>/dev/null || echo unknown)"
fi
printf 'commit=%s\n' "${BUILD_COMMIT}" > "${RES}/build-info.txt"

MAC_LAUNCHER_SRC="${ROOT}/scripts/build/macos/MacLauncher.swift"
MAC_LAUNCHER_BIN="${BIN}/GeneralsXMacLauncher"
if [[ "${ONLINE}" != "1" && -f "${MAC_LAUNCHER_SRC}" ]]; then
  command -v xcrun >/dev/null 2>&1 || { echo "ERROR: xcrun is required to build the macOS launcher"; exit 1; }
  echo "==> Building native macOS launcher"
  xcrun swiftc -parse-as-library -O -framework SwiftUI -framework AppKit "${MAC_LAUNCHER_SRC}" -o "${MAC_LAUNCHER_BIN}"
  chmod +x "${MAC_LAUNCHER_BIN}"
fi

cat > "${CONTENTS}/Info.plist" <<'PLIST'
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0"><dict>
<key>CFBundleName</key><string>GeneralsZH Contra X Dev</string>
<key>CFBundleDisplayName</key><string>GeneralsZH Contra X Dev</string>
<key>CFBundleIdentifier</key><string>com.dvorov.generalszh.contrax.dev</string>
<key>CFBundleVersion</key><string>1</string>
<key>CFBundleShortVersionString</key><string>0.1.0</string>
<key>CFBundleExecutable</key><string>run.sh</string>
<key>CFBundlePackageType</key><string>APPL</string>
<key>LSMinimumSystemVersion</key><string>15.0</string>
<key>NSHighResolutionCapable</key><true/>
</dict></plist>
PLIST
if [[ "${ONLINE}" == "1" ]]; then
  /usr/libexec/PlistBuddy -c "Set :CFBundleName GeneralsZH Online Dev" "${CONTENTS}/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleDisplayName GeneralsZH Online Dev" "${CONTENTS}/Info.plist"
  /usr/libexec/PlistBuddy -c "Set :CFBundleIdentifier com.dvorov.generalszh.online.dev" "${CONTENTS}/Info.plist"
fi

copy_first() {
  local dst="$1"; shift
  local candidate
  for candidate in "$@"; do
    if [[ -f "${candidate}" ]]; then
      cp -L "${candidate}" "${dst}"
      return 0
    fi
  done
  return 1
}

copy_first "${LIB}/libSDL3.0.dylib"   "${BUILD}/_deps/sdl3-build/libSDL3.0.dylib"   "${BUILD}/_deps/sdl3-build/libSDL3.dylib" || { echo "ERROR: SDL3 dylib missing"; exit 1; }
ln -sf libSDL3.0.dylib "${LIB}/libSDL3.dylib"

if copy_first "${LIB}/libSDL3_image.dylib"   "${BUILD}/_deps/sdl3_image-build/libSDL3_image.0.4.0.dylib"   "${BUILD}/_deps/sdl3_image-build/libSDL3_image.0.dylib"   "${BUILD}/_deps/sdl3_image-build/libSDL3_image.dylib"; then
  ln -sf libSDL3_image.dylib "${LIB}/libSDL3_image.0.dylib"
fi

copy_first "${LIB}/libgamespy.dylib" "${BUILD}/libgamespy.dylib" || true
copy_first "${LIB}/libdxvk_d3d8.0.dylib"   "${BUILD}/libdxvk_d3d8.0.dylib"   "${BUILD}/_deps/dxvk-build-macos/src/d3d8/libdxvk_d3d8.0.dylib" || { echo "ERROR: DXVK d3d8 missing"; exit 1; }
copy_first "${LIB}/libdxvk_d3d9.0.dylib"   "${BUILD}/libdxvk_d3d9.0.dylib"   "${BUILD}/_deps/dxvk-build-macos/src/d3d9/libdxvk_d3d9.0.dylib" || { echo "ERROR: DXVK d3d9 missing"; exit 1; }
ln -sf libdxvk_d3d8.0.dylib "${LIB}/libdxvk_d3d8.dylib"
ln -sf libdxvk_d3d9.0.dylib "${LIB}/libdxvk_d3d9.dylib"

VSDK="${VULKAN_SDK:-}"
if [[ -d "${VSDK}/macOS" ]]; then VSDK="${VSDK}/macOS"; fi
if [[ -f "${VSDK}/lib/libvulkan.dylib" ]]; then
  cp -L "${VSDK}/lib/libvulkan.dylib" "${LIB}/"
  [[ -f "${VSDK}/lib/libvulkan.1.dylib" ]] && cp -L "${VSDK}/lib/libvulkan.1.dylib" "${LIB}/" || true
  cp -L "${VSDK}/lib/libMoltenVK.dylib" "${LIB}/"
else
  echo "ERROR: Vulkan SDK dylibs not found in VULKAN_SDK=${VULKAN_SDK:-<unset>}"
  exit 1
fi

cat > "${RES}/MoltenVK_icd.json" <<'JSON'
{
  "file_format_version": "1.0.0",
  "ICD": {
    "library_path": "./lib/libMoltenVK.dylib",
    "api_version": "1.4.0",
    "is_portability_driver": true
  }
}
JSON

if [[ -f "${ROOT}/ios/config/dxvk.conf" ]]; then
  cp "${ROOT}/ios/config/dxvk.conf" "${RES}/dxvk.conf"
fi

FONTCONF="${BUILD}/vcpkg_installed/arm64-osx/etc/fonts"
if [[ -f "${FONTCONF}/fonts.conf" ]]; then
  mkdir -p "${RES}/fontconfig"
  cp "${FONTCONF}/fonts.conf" "${RES}/fontconfig/"
  [[ -d "${FONTCONF}/conf.d" ]] && cp -R "${FONTCONF}/conf.d" "${RES}/fontconfig/" || true
fi

# Collect non-system dylibs recursively. DYLD_LIBRARY_PATH in run.sh lets the
# app prefer these bundled copies over Homebrew paths recorded at build time.
pending="${OUT}/.pending"
donefile="${OUT}/.done"
: > "${pending}"; : > "${donefile}"
printf '%s\n' "${BIN}/GeneralsXZH" "${LIB}"/*.dylib >> "${pending}"
while [[ -s "${pending}" ]]; do
  target="$(head -n1 "${pending}")"
  tail -n +2 "${pending}" > "${pending}.next" || true
  mv "${pending}.next" "${pending}"
  [[ -f "${target}" ]] || continue
  grep -Fqx "${target}" "${donefile}" && continue
  echo "${target}" >> "${donefile}"
  while read -r dep; do
    [[ -n "${dep}" ]] || continue
    [[ "${dep}" == /System/Library/* || "${dep}" == /usr/lib/* ]] && continue
    name="$(basename "${dep}")"
    [[ -f "${LIB}/${name}" ]] && continue
    src=""
    if [[ -f "${dep}" ]]; then src="${dep}"; fi
    if [[ -z "${src}" && "${dep}" == @rpath/* ]]; then
      leaf="${dep#@rpath/}"
      for c in "/opt/homebrew/lib/${leaf}" "/usr/local/lib/${leaf}"; do
        [[ -f "${c}" ]] && { src="${c}"; break; }
      done
      if [[ -z "${src}" ]] && command -v brew >/dev/null 2>&1; then
        src="$(find /opt/homebrew/Cellar -name "${leaf}" -type f 2>/dev/null | head -n1 || true)"
      fi
    fi
    if [[ -n "${src}" && -f "${src}" ]]; then
      cp -L "${src}" "${LIB}/${name}"
      echo "${LIB}/${name}" >> "${pending}"
    fi
  done < <(otool -L "${target}" 2>/dev/null | awk 'NR>1 {print $1}')
done
rm -f "${pending}" "${donefile}"

cat > "${MACOS}/run.sh" <<'RUNNER'
#!/usr/bin/env bash
set -u
HERE="$(cd "$(dirname "$0")" && pwd)"
CONTENTS="$(cd "${HERE}/.." && pwd)"
RES="${CONTENTS}/Resources"
BIN="${RES}/bin"
LIB="${RES}/lib"
GAME_ROOT="${GX_GAME_ROOT:-${HOME}/GeneralsX/GeneralsZH}"
SOURCE_MOD_ROOT="${GX_CONTRA_ROOT:-${HOME}/GeneralsX/ContraX}"
RUNTIME_MOD_ROOT="${HOME}/GeneralsX/ContraRuntime"
OPTIONS_FILE="${HOME}/Library/Application Support/GeneralsX/GeneralsZH/Options.ini"
CONTRA_SETTINGS_FILE="${HOME}/Library/Application Support/GeneralsX/GeneralsZH/ContraSettings.ini"
LOG_DIR="${HOME}/Library/Logs/GeneralsXZH"
mkdir -p "${LOG_DIR}"
LOG="${LOG_DIR}/contra-dev.log"

export DYLD_LIBRARY_PATH="${LIB}:${DYLD_LIBRARY_PATH:-}"
export DXVK_WSI_DRIVER=SDL3
export DXVK_HUD="${DXVK_HUD:-0}"
export VK_ICD_FILENAMES="${RES}/MoltenVK_icd.json"
export VK_DRIVER_FILES="${RES}/MoltenVK_icd.json"
[[ -f "${RES}/dxvk.conf" ]] && export DXVK_CONFIG_FILE="${RES}/dxvk.conf"
if [[ -f "${RES}/fontconfig/fonts.conf" ]]; then
  export FONTCONFIG_FILE="${RES}/fontconfig/fonts.conf"
  export FONTCONFIG_PATH="${RES}/fontconfig"
fi
export CNC_GENERALS_ZH_PATH="${GAME_ROOT}"

if [[ ! -d "${GAME_ROOT}" || -z "$(find "${GAME_ROOT}" -name '*.big' -print -quit 2>/dev/null)" ]]; then
  osascript -e 'display alert "Generals ZH data not installed" message "Run Install Contra Data.command once and select your GeneralsZH-ContraX-unsigned.ipa." as critical' >/dev/null 2>&1 || true
  exit 2
fi
if [[ ! -d "${SOURCE_MOD_ROOT}" ]]; then
  osascript -e 'display alert "Contra X profile not installed" message "Run Install Contra Data.command once and select your Contra IPA." as critical' >/dev/null 2>&1 || true
  exit 3
fi

# Native settings launcher. It writes Options.ini/SagePatch.ini and builds the
# selected Contra archive overlay without modifying the installed source profile.
if [[ "${GX_SKIP_MAC_LAUNCHER:-0}" != "1" && -x "${BIN}/GeneralsXMacLauncher" ]]; then
  ACTION_FILE="${TMPDIR:-/tmp}/generalsx-mac-action-$"
  rm -f "${ACTION_FILE}"
  export GX_MAC_LAUNCH_ACTION_FILE="${ACTION_FILE}"
  "${BIN}/GeneralsXMacLauncher"
  if [[ ! -f "${ACTION_FILE}" || "$(tr -d '[:space:]' < "${ACTION_FILE}")" != "play" ]]; then
    rm -f "${ACTION_FILE}"
    exit 0
  fi
  rm -f "${ACTION_FILE}"
fi

MOD_ROOT="${SOURCE_MOD_ROOT}"
if [[ -d "${RUNTIME_MOD_ROOT}" && -n "$(find "${RUNTIME_MOD_ROOT}" -maxdepth 1 -name '*.big' -print -quit 2>/dev/null)" ]]; then
  MOD_ROOT="${RUNTIME_MOD_ROOT}"
fi

cd "${GAME_ROOT}"
{
  echo
  echo "===== $(date) ====="
  echo "GameRoot=${GAME_ROOT}"
  echo "ContraSource=${SOURCE_MOD_ROOT}"
  echo "ContraRoot=${MOD_ROOT}"
  echo "Binary=${BIN}/GeneralsXZH"
  if [[ -f "${RES}/build-info.txt" ]]; then
    echo "BuildInfo=$(tr '\n' ' ' < "${RES}/build-info.txt")"
  fi
  echo "[MAC-LAUNCH] Active ContraRuntime archives:"
  find "${MOD_ROOT}" -maxdepth 1 -type f -name '*.big' -print 2>/dev/null | LC_ALL=C sort | sed 's#^#[MAC-LAUNCH]   #' || true
  find "${MOD_ROOT}" -maxdepth 1 -type l -name '*.big' -print 2>/dev/null | LC_ALL=C sort | sed 's#^#[MAC-LAUNCH]   #' || true
} >> "${LOG}"

ARGS=(-mod "${MOD_ROOT}")
WINDOWED_SETTING=""
CONTROL_BAR_SETTING=""
if [[ -f "${OPTIONS_FILE}" ]]; then
  WINDOWED_SETTING="$(awk -F= 'tolower($1) ~ /^[[:space:]]*windowed[[:space:]]*$/ { gsub(/[[:space:]]/, "", $2); print tolower($2); exit }' "${OPTIONS_FILE}" 2>/dev/null || true)"
fi
if [[ -f "${CONTRA_SETTINGS_FILE}" ]]; then
  CONTROL_BAR_SETTING="$(awk -F= 'tolower($1) ~ /^[[:space:]]*controlbar[[:space:]]*$/ { gsub(/^[[:space:]]+|[[:space:]]+$/, "", $2); print tolower($2); exit }' "${CONTRA_SETTINGS_FILE}" 2>/dev/null || true)"
fi

# Control Bar Pro was designed for GenTool-style full viewport rendering.
# iOS already injects -forcefullviewport for this profile; do the same on macOS
# so the world continues behind the side/bottom UI instead of exposing black
# clear areas around the widescreen control bar.
if [[ "${CONTROL_BAR_SETTING}" == "pro" ]]; then
  ARGS+=(-forcefullviewport)
  echo "[MAC-LAUNCH] ControlBar=Pro -> -forcefullviewport" >> "${LOG}"
fi

if [[ "${GX_MAC_FULLSCREEN:-0}" == "1" ]]; then
  :
elif [[ "${GX_MAC_WINDOWED:-0}" == "1" || "${WINDOWED_SETTING}" == "yes" || "${WINDOWED_SETTING}" == "true" || "${WINDOWED_SETTING}" == "1" ]]; then
  ARGS+=(-win)
fi
exec "${BIN}/GeneralsXZH" "${ARGS[@]}" "$@" >> "${LOG}" 2>&1
RUNNER
chmod +x "${MACOS}/run.sh"

cat > "${OUT}/Install Contra Data.command" <<'INSTALLER'
#!/usr/bin/env bash
set -euo pipefail

IPA="${1:-}"
if [[ -z "${IPA}" ]]; then
  IPA="$(osascript <<'APPLESCRIPT'
set f to choose file with prompt "Select GeneralsZH-ContraX-unsigned.ipa"
POSIX path of f
APPLESCRIPT
)"
fi
IPA="${IPA%$'\n'}"
[[ -f "${IPA}" ]] || { echo "IPA not found: ${IPA}"; read -r; exit 1; }

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
echo "Extracting IPA..."
ditto -x -k "${IPA}" "${TMP}"
APP="$(find "${TMP}/Payload" -maxdepth 1 -type d -name '*.app' | head -n1)"
[[ -n "${APP}" ]] || { echo "No .app found in IPA"; read -r; exit 1; }
[[ -d "${APP}/GameData" ]] || { echo "GameData missing in IPA"; read -r; exit 1; }
[[ -d "${APP}/Profiles/contra-x" ]] || { echo "Contra profile missing in IPA"; read -r; exit 1; }

GAME="${HOME}/GeneralsX/GeneralsZH"
MOD="${HOME}/GeneralsX/ContraX"
mkdir -p "${GAME}" "${MOD}"
echo "Installing retail GameData -> ${GAME}"
rsync -a --delete "${APP}/GameData/" "${GAME}/"
echo "Installing Contra X -> ${MOD}"
rsync -a --delete "${APP}/Profiles/contra-x/" "${MOD}/"
rm -rf "${HOME}/GeneralsX/ContraRuntime"

BIG_COUNT="$(find "${GAME}" -name '*.big' | wc -l | tr -d ' ')"
MOD_BIG_COUNT="$(find "${MOD}" -maxdepth 1 -name '*.big' | wc -l | tr -d ' ')"
echo
echo "READY"
echo "GameData BIG files: ${BIG_COUNT}"
echo "Contra active BIG files: ${MOD_BIG_COUNT}"
echo "You can now open GeneralsZH-ContraX-Dev.app."
echo
read -r -p "Press Enter to close..."
INSTALLER
chmod +x "${OUT}/Install Contra Data.command"

cat > "${OUT}/README-Mac.txt" <<'README'
GeneralsZH Contra X Dev — Apple Silicon test build

1. Run "Install Contra Data.command" once.
2. Select your own GeneralsZH-ContraX-unsigned.ipa.
3. Open GeneralsZH-ContraX-Dev.app.
4. Runtime log:
   ~/Library/Logs/GeneralsXZH/contra-dev.log

Game assets are not included in this build.
The installer only extracts data from the IPA you provide locally.

Environment overrides:
  GX_GAME_ROOT=~/GeneralsX/GeneralsZH
  GX_CONTRA_ROOT=~/GeneralsX/ContraX
  GX_MAC_FULLSCREEN=1
README

INSTALLER_NAME="Install Contra Data.command"
TAR="${ROOT}/GeneralsZH-ContraX-macos-arm64.tar"
if [[ "${ONLINE}" == "1" ]]; then
  cp "${SCRIPT_DIR}/run-macos-online.sh" "${MACOS}/run.sh"
  rm -f "${OUT}/Install Contra Data.command"
  INSTALLER_NAME="Install Online Data.command"
  cp "${SCRIPT_DIR}/install-macos-online-data.sh" "${OUT}/${INSTALLER_NAME}"
  cp "${SCRIPT_DIR}/README-Online-Mac.txt" "${OUT}/README-Mac.txt"
  chmod +x "${MACOS}/run.sh" "${OUT}/${INSTALLER_NAME}"
  TAR="${ROOT}/GeneralsZH-Online-macos-arm64.tar"
fi
codesign --force --deep --sign - "${APP}"

rm -f "${TAR}"
tar -C "${OUT}" -cf "${TAR}" "${APP_NAME}" "${INSTALLER_NAME}" "README-Mac.txt"
echo "READY: ${TAR}"
du -h "${TAR}"
