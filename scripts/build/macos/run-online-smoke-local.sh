#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
APP="${ROOT}/build/macos-online-package/GeneralsZH-Online-Dev.app"
RUN="${APP}/Contents/MacOS/run.sh"
RESULT_DIR="${ROOT}/build/online-smoke-results"
GAME_ROOT="${GX_GAME_ROOT:-${HOME}/GeneralsX/Online/GeneralsZH}"

usage() {
  cat <<'EOF'
Usage:
  ./scripts/build/macos/run-online-smoke-local.sh --prepare host
  ./scripts/build/macos/run-online-smoke-local.sh --prepare guest
  ./scripts/build/macos/run-online-smoke-local.sh [--frames N] [--timeout SEC]

The two one-time --prepare commands open the normal Online UI with separate
Keychain profiles. Sign in to two different Generals Online accounts, then
close each app. After both profiles exist, run the script without --prepare.

The automated run starts two headless clients and validates:
cached auth -> WebSocket -> create/find/join lobby -> P2P/TURN full mesh ->
START_GAME -> map load -> synchronized gameplay frame progress.
EOF
}

prepare_role=""
frames="${GX_ONLINE_SMOKE_FRAMES:-300}"
timeout="${GX_ONLINE_SMOKE_TIMEOUT_SEC:-150}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prepare)
      [[ $# -ge 2 ]] || { usage; exit 2; }
      prepare_role="$2"
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

if [[ -n "${prepare_role}" ]]; then
  case "${prepare_role}" in
    host|guest) ;;
    *) echo "ERROR: --prepare must be host or guest" >&2; exit 2 ;;
  esac

  echo "Opening normal Online client for the '${prepare_role}' smoke profile."
  echo "Enter Online, complete browser sign-in with a dedicated account, then close the game."
  GX_ONLINE_AUTH_PROFILE="smoke-${prepare_role}" \
  GX_MAC_ONLINE_LOG="${HOME}/Library/Logs/GeneralsXZH/online-smoke-prepare-${prepare_role}.log" \
    "${RUN}"
  exit $?
fi

mkdir -p "${RESULT_DIR}"
run_id="$(date +%Y%m%d-%H%M%S)-$$"
room="GX-SMOKE-${run_id}"
host_result="${RESULT_DIR}/${run_id}-host.result"
guest_result="${RESULT_DIR}/${run_id}-guest.result"
host_log="${RESULT_DIR}/${run_id}-host.log"
guest_log="${RESULT_DIR}/${run_id}-guest.log"
rm -f "${host_result}" "${guest_result}" "${host_log}" "${guest_log}"

cleanup() {
  local code=$?
  [[ -n "${host_pid:-}" ]] && kill "${host_pid}" 2>/dev/null || true
  [[ -n "${guest_pid:-}" ]] && kill "${guest_pid}" 2>/dev/null || true
  [[ -n "${host_pid:-}" ]] && wait "${host_pid}" 2>/dev/null || true
  [[ -n "${guest_pid:-}" ]] && wait "${guest_pid}" 2>/dev/null || true
  return "${code}"
}
trap cleanup EXIT INT TERM

echo "Online smoke room: ${room}"
echo "Host log: ${host_log}"
echo "Guest log: ${guest_log}"

GX_ONLINE_AUTH_PROFILE=smoke-host \
GX_ONLINE_SMOKE_ROLE=host \
GX_ONLINE_SMOKE_ROOM="${room}" \
GX_ONLINE_SMOKE_RESULT="${host_result}" \
GX_ONLINE_SMOKE_FRAMES="${frames}" \
GX_ONLINE_SMOKE_TIMEOUT_SEC="${timeout}" \
GX_MAC_ONLINE_LOG="${host_log}" \
  "${RUN}" -headless &
host_pid=$!

sleep 2

GX_ONLINE_AUTH_PROFILE=smoke-guest \
GX_ONLINE_SMOKE_ROLE=guest \
GX_ONLINE_SMOKE_ROOM="${room}" \
GX_ONLINE_SMOKE_RESULT="${guest_result}" \
GX_ONLINE_SMOKE_FRAMES="${frames}" \
GX_ONLINE_SMOKE_TIMEOUT_SEC="${timeout}" \
GX_MAC_ONLINE_LOG="${guest_log}" \
  "${RUN}" -headless &
guest_pid=$!

host_exit=0
guest_exit=0
wait "${host_pid}" || host_exit=$?
host_pid=""
wait "${guest_pid}" || guest_exit=$?
guest_pid=""

host_status="$(sed -n 's/^status=//p' "${host_result}" 2>/dev/null | head -n1 || true)"
guest_status="$(sed -n 's/^status=//p' "${guest_result}" 2>/dev/null | head -n1 || true)"

echo
echo "Host:  status=${host_status:-MISSING} exit=${host_exit}"
[[ -f "${host_result}" ]] && cat "${host_result}"
echo
echo "Guest: status=${guest_status:-MISSING} exit=${guest_exit}"
[[ -f "${guest_result}" ]] && cat "${guest_result}"
echo

if [[ "${host_status}" == "PASS" && "${guest_status}" == "PASS" ]]; then
  echo "PASS: two-client Generals Online E2E smoke test completed."
  trap - EXIT INT TERM
  exit 0
fi

echo "FAIL: Generals Online smoke test did not pass on both clients." >&2
echo "Inspect: ${host_log}" >&2
echo "         ${guest_log}" >&2
trap - EXIT INT TERM
exit 1
