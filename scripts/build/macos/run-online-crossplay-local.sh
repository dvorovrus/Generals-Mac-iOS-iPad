#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
APP="${ROOT}/build/macos-online-package/GeneralsZH-Online-Dev.app"
RUN="${APP}/Contents/MacOS/run.sh"
RESULT_DIR="${ROOT}/build/online-crossplay-results"
GAME_ROOT="${GX_GAME_ROOT:-${HOME}/GeneralsX/Online/GeneralsZH}"
AUTH_PROFILE="${GX_ONLINE_AUTH_PROFILE:-crossplay-mac}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/build/macos/run-online-crossplay-local.sh --prepare
  ./scripts/build/macos/run-online-crossplay-local.sh --role guest --room "ROOM NAME"
  ./scripts/build/macos/run-online-crossplay-local.sh --role host  --room "ROOM NAME"

This runs ONE automated macOS Generals Online client against a real external
peer, normally the official Windows GeneralsOnlineZH_60.exe client.

guest:
  Windows creates a public 2-player room with the exact --room name.
  The Mac client finds it, validates Windows-parity CRC, joins, marks ready,
  waits for Windows to start the match, loads the map and validates gameplay.

host:
  The Mac client creates the public 2-player room. Join it from Windows.
  When the Windows player is ready and full-mesh connectivity succeeds,
  the Mac client requests START_GAME and validates gameplay.

Options:
  --frames N        Gameplay frames required for PASS (default 600)
  --timeout SEC     Global timeout (default 300)
  --map PATH        Map path used when Mac is host
  --profile NAME    macOS Keychain auth profile (default crossplay-mac)
EOF
}

prepare=0
role=""
room=""
frames="${GX_ONLINE_SMOKE_FRAMES:-600}"
timeout="${GX_ONLINE_SMOKE_TIMEOUT_SEC:-300}"
map="${GX_ONLINE_SMOKE_MAP:-Maps\\Alpine Assault\\Alpine Assault.map}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prepare)
      prepare=1
      shift
      ;;
    --role)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      role="$2"
      shift 2
      ;;
    --room)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      room="$2"
      shift 2
      ;;
    --frames)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      frames="$2"
      shift 2
      ;;
    --timeout)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      timeout="$2"
      shift 2
      ;;
    --map)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      map="$2"
      shift 2
      ;;
    --profile)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      AUTH_PROFILE="$2"
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "ERROR: unknown argument: $1" >&2
      usage
      exit 2
      ;;
  esac
done

[[ -x "${RUN}" ]] || {
  echo "ERROR: Online app is not built: ${APP}" >&2
  echo "Build it first with: ./scripts/build/macos/build-macos-online-local.sh" >&2
  exit 3
}

[[ -d "${GAME_ROOT}" && -n "$(find "${GAME_ROOT}" -maxdepth 1 -type f -iname '*.big' -print -quit 2>/dev/null)" ]] || {
  echo "ERROR: Zero Hour Online GameData is missing: ${GAME_ROOT}" >&2
  exit 4
}

if [[ "${prepare}" == "1" ]]; then
  echo "Opening normal Online client for Keychain profile '${AUTH_PROFILE}'."
  echo "Enter Online, complete browser sign-in, then close the game."
  GX_ONLINE_AUTH_PROFILE="${AUTH_PROFILE}" \
  GX_MAC_ONLINE_LOG="${HOME}/Library/Logs/GeneralsXZH/online-crossplay-prepare.log" \
    "${RUN}"
  exit $?
fi

case "${role}" in
  host|guest) ;;
  *) echo "ERROR: --role must be host or guest" >&2; usage; exit 2 ;;
esac

[[ -n "${room}" ]] || {
  echo "ERROR: --room is required" >&2
  usage
  exit 2
}

mkdir -p "${RESULT_DIR}"
run_id="$(date +%Y%m%d-%H%M%S)-$$"
result="${RESULT_DIR}/${run_id}-${role}.result"
log="${RESULT_DIR}/${run_id}-${role}.log"
rm -f "${result}" "${log}"

echo "Cross-play role: ${role}"
echo "Room:            ${room}"
echo "Auth profile:    ${AUTH_PROFILE}"
echo "Result:          ${result}"
echo "Log:             ${log}"
echo
if [[ "${role}" == "guest" ]]; then
  echo "Create a PUBLIC room on Windows with the exact name above, then wait."
else
  echo "Join the room above from the official Windows client and mark Ready."
fi
echo

set +e
GX_ONLINE_AUTH_PROFILE="${AUTH_PROFILE}" \
GX_ONLINE_SMOKE_ROLE="${role}" \
GX_ONLINE_SMOKE_ROOM="${room}" \
GX_ONLINE_SMOKE_RESULT="${result}" \
GX_ONLINE_SMOKE_FRAMES="${frames}" \
GX_ONLINE_SMOKE_TIMEOUT_SEC="${timeout}" \
GX_ONLINE_SMOKE_MAP="${map}" \
GX_MAC_ONLINE_LOG="${log}" \
  "${RUN}" -headless
exit_code=$?
set -e

status="$(sed -n 's/^status=//p' "${result}" 2>/dev/null | head -n1 || true)"

echo
echo "Cross-play result: status=${status:-MISSING} exit=${exit_code}"
[[ -f "${result}" ]] && cat "${result}"
echo

if [[ "${status}" == "PASS" ]]; then
  echo "PASS: macOS completed a Generals Online match against the external peer."
  exit 0
fi

echo "FAIL: cross-play run did not reach the gameplay frame target." >&2
echo "Inspect: ${log}" >&2
exit 1
