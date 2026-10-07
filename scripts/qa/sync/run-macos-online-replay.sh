#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
APP="${GX_MAC_ONLINE_APP:-${HOME}/Applications/GeneralsZH-Online-Dev.app}"
RUN="${APP}/Contents/MacOS/run.sh"
GAME_ROOT="${GX_GAME_ROOT:-${HOME}/GeneralsX/Online/GeneralsZH}"
OUT_DIR="${ROOT}/build/online-replay-results"

usage() {
  echo "Usage: $0 /absolute/or/relative/path/to/replay.rep"
}

[[ $# -eq 1 ]] || { usage; exit 2; }
REPLAY="$1"
[[ -f "${REPLAY}" ]] || { echo "ERROR: replay not found: ${REPLAY}" >&2; exit 3; }
[[ -x "${RUN}" ]] || { echo "ERROR: Online app is not installed: ${APP}" >&2; exit 4; }
[[ -d "${GAME_ROOT}" ]] || { echo "ERROR: Online GameData is missing: ${GAME_ROOT}" >&2; exit 5; }

REPLAY_DIR="$(cd "$(dirname "${REPLAY}")" && pwd)"
REPLAY_ABS="${REPLAY_DIR}/$(basename "${REPLAY}")"
mkdir -p "${OUT_DIR}"
STAMP="$(date +%Y%m%d-%H%M%S)"
LOG="${OUT_DIR}/${STAMP}-$(basename "${REPLAY_ABS}" .rep).log"

echo "Replay:   ${REPLAY_ABS}"
echo "App:      ${APP}"
echo "GameData: ${GAME_ROOT}"
echo "Log:      ${LOG}"
echo

set +e
GX_GAME_ROOT="${GAME_ROOT}" \
GX_MAC_ONLINE_LOG="${LOG}" \
  "${RUN}" -headless -quickstart -replay "${REPLAY_ABS}"
RC=$?
set -e

echo
echo "=== Replay CRC result ==="
MATCHES="$(grep -E 'REPLAY_CRC_MISMATCH|CRC Mismatch|Replay has gone out of sync|ONLINE-DESYNC|Appended Playback CRC' "${LOG}" || true)"
if [[ -n "${MATCHES}" ]]; then
  printf '%s\n' "${MATCHES}"
fi

if grep -q 'REPLAY_CRC_MISMATCH' "${LOG}"; then
  echo
  echo "RESULT: DESYNC"
  exit 10
fi

if [[ ${RC} -ne 0 ]]; then
  echo
  echo "RESULT: PROCESS_ERROR exit=${RC}"
  exit "${RC}"
fi

echo
echo "RESULT: replay completed without recorded CRC mismatch"
