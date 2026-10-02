#!/usr/bin/env bash
set -euo pipefail
IPA="${1:-}"
if [[ -z "${IPA}" ]]; then
  IPA="$(osascript -e 'POSIX path of (choose file with prompt "Select your Zero Hour Original or Online IPA")')"
fi
[[ -f "${IPA}" ]] || { echo "IPA not found: ${IPA}"; exit 1; }
TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT
ditto -x -k "${IPA}" "${TMP}"
APP="$(find "${TMP}/Payload" -maxdepth 1 -type d -name '*.app' -print -quit)"
[[ -n "${APP}" && -d "${APP}/GameData" ]] || { echo "GameData missing in IPA"; exit 1; }
[[ -n "$(find "${APP}/GameData" -iname '*.big' -print -quit)" ]] || { echo "No retail BIG archives in IPA"; exit 1; }
GAME="${HOME}/GeneralsX/Online/GeneralsZH"
mkdir -p "${GAME}"
rsync -a --delete "${APP}/GameData/" "${GAME}/"
echo "READY: ${GAME}"
echo "Open GeneralsZH-Online-Dev.app, then select Online in the game menu."
if [[ -t 0 ]]; then read -r -p "Press Enter to close..."; fi
