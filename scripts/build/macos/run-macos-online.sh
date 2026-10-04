#!/usr/bin/env bash
set -euo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
RES="$(cd "${HERE}/../Resources" && pwd)"
LIB="${RES}/lib"
GAME_ROOT="${GX_GAME_ROOT:-${HOME}/GeneralsX/Online/GeneralsZH}"
LOG_DIR="${HOME}/Library/Logs/GeneralsXZH"
mkdir -p "${LOG_DIR}"
LOG="${LOG_DIR}/online-dev.log"
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
if [[ ! -d "${GAME_ROOT}" || -z "$(find "${GAME_ROOT}" -iname '*.big' -print -quit)" ]]; then
  osascript -e 'display alert "Zero Hour data not installed" message "Run Install Online Data.command and select your Original or Online IPA." as critical' || true
  exit 2
fi
cd "${GAME_ROOT}"
{
  echo "===== $(date) ====="
  echo "GameRoot=${GAME_ROOT}"
  cat "${RES}/build-info.txt"
} >> "${LOG}"
ARGS=()
[[ "${GX_MAC_FULLSCREEN:-0}" != "1" ]] && ARGS+=(-win)
exec "${RES}/bin/GeneralsXZH" "${ARGS[@]}" "$@" >> "${LOG}" 2>&1
