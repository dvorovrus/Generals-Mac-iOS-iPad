#!/usr/bin/env bash
set -euo pipefail
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
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

# Original Zero Hour IPAs do not contain the Generals Online community data
# pack. Synchronize the exact official QFE6A payload so the INI CRC matches
# the official Windows client before Online is launched.
SYNC="${SCRIPT_DIR}/GeneralsZH-Online-Dev.app/Contents/Resources/tools/sync-generals-online-data.py"
[[ -f "${SYNC}" ]] || { echo "Online data sync helper missing: ${SYNC}"; exit 1; }
command -v python3 >/dev/null 2>&1 || { echo "python3 is required to sync Generals Online data"; exit 1; }
python3 "${SYNC}" \
  --dest "${GAME}" \
  --cache-dir "${HOME}/Library/Caches/GeneralsX/GeneralsOnline" \
  --expected-version 100126_QFE6A \
  --expected-seed 0x808CB29E

PATCH="${GAME}/GeneralsOnlineGameData/500_900_CommunityPatch_CoreINI.big"
[[ -f "${PATCH}" ]] || { echo "Generals Online community patch missing after sync"; exit 1; }

echo "READY: ${GAME}"
echo "Online patch: ${PATCH}"
echo "Open GeneralsZH-Online-Dev.app, then select Online in the game menu."
if [[ -t 0 ]]; then read -r -p "Press Enter to close..."; fi
