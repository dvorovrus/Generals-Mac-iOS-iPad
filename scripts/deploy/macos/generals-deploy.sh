#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DEPLOY_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"
REPO_ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
WORKSPACE="$(cd "${REPO_ROOT}/.." && pwd)"
CATALOG="${DEPLOY_DIR}/catalog.json"
ARTIFACT_ROOT="${WORKSPACE}/artifacts"
REPO_SLUG="$(python3 - "${CATALOG}" <<'PY'
import json,sys
print(json.load(open(sys.argv[1], encoding="utf-8"))["repository"])
PY
)"

usage() {
  cat <<'EOF'
Generals Apple deployment CLI (macOS)

Usage:
  ./scripts/deploy/macos/generals-deploy.sh init
  ./scripts/deploy/macos/generals-deploy.sh list
  ./scripts/deploy/macos/generals-deploy.sh status   macos contra
  ./scripts/deploy/macos/generals-deploy.sh update   macos contra
  ./scripts/deploy/macos/generals-deploy.sh build    macos contra
  ./scripts/deploy/macos/generals-deploy.sh download macos contra
  ./scripts/deploy/macos/generals-deploy.sh install  macos contra --ipa /path/Contra.ipa
  ./scripts/deploy/macos/generals-deploy.sh full     macos contra --ipa /path/Contra.ipa
  ./scripts/deploy/macos/generals-deploy.sh logs     macos contra

Options:
  --ipa PATH       Full iPad IPA used as the user's local source of retail GameData.
                   Profile variants require a matching full IPA (Contra or Enhanced).
  --run-id ID      Download a specific successful GitHub Actions run.
  --run            Open the installed app after install.
  --no-build       For 'full', use the latest successful artifact instead of triggering a build.
  --wait           Wait when using 'build' (full always waits).
EOF
}

need_gh() {
  command -v gh >/dev/null 2>&1 || { echo "ERROR: GitHub CLI (gh) is required. Install: brew install gh"; exit 2; }
  gh auth status >/dev/null 2>&1 || { echo "ERROR: gh is not authenticated. Run: gh auth login"; exit 3; }
}

catalog_field() {
  local platform="$1" variant="$2" field="$3"
  python3 - "${CATALOG}" "${platform}" "${variant}" "${field}" <<'PY'
import json,sys
data=json.load(open(sys.argv[1], encoding="utf-8"))
platform,variant,field=sys.argv[2:5]
try:
    value=data["variants"][platform][variant]
except KeyError:
    raise SystemExit(4)
for part in field.split("."):
    if value is None:
        break
    value=value.get(part) if isinstance(value,dict) else None
if value is None:
    print("")
elif isinstance(value,bool):
    print("true" if value else "false")
else:
    print(value)
PY
}

variant_exists() {
  python3 - "${CATALOG}" "$1" "$2" <<'PY'
import json,sys
data=json.load(open(sys.argv[1], encoding="utf-8"))
raise SystemExit(0 if sys.argv[3] in data.get("variants",{}).get(sys.argv[2],{}) else 1)
PY
}

show_list() {
  python3 - "${CATALOG}" <<'PY'
import json,sys
data=json.load(open(sys.argv[1], encoding="utf-8"))
print(f"{'PLATFORM':8} {'VARIANT':10} {'STATUS':16} {'BUILD':8} {'INSTALL'}")
for platform, variants in data["variants"].items():
    for key, cfg in variants.items():
        ready="yes" if cfg.get("installReady") else "no"
        print(f"{platform:8} {key:10} {str(cfg.get('status','')):16} {str(cfg.get('buildMode','')):8} {ready}")
PY
}

latest_run_id() {
  local workflow="$1" branch="$2" status="${3:-success}"
  need_gh
  local args=(run list --repo "${REPO_SLUG}" --workflow "${workflow}" --branch "${branch}" --limit 1 --json databaseId)
  if [[ -n "${status}" ]]; then
    args+=(--status "${status}")
  fi
  gh "${args[@]}" --jq '.[0].databaseId'
}

update_variant() {
  local branch="$1"
  [[ -n "${branch}" ]] || { echo "No source branch for this variant."; return 0; }
  echo "==> Fetching origin/${branch}"
  git -C "${REPO_ROOT}" fetch origin "${branch}"

  local current dirty
  current="$(git -C "${REPO_ROOT}" rev-parse --abbrev-ref HEAD)"
  if [[ "${current}" == "${branch}" ]]; then
    dirty="$(git -C "${REPO_ROOT}" status --porcelain)"
    if [[ -z "${dirty}" ]]; then
      git -C "${REPO_ROOT}" pull --ff-only origin "${branch}"
    else
      echo "Working tree has local changes; fetched only."
    fi
  else
    echo "Current branch: ${current}"
    echo "Variant branch: ${branch} (fetched; no automatic branch switch)"
  fi
}

trigger_build() {
  local workflow="$1" branch="$2" wait_flag="$3"
  need_gh
  echo "==> Triggering ${workflow} on ${branch}" >&2
  local output id
  output="$(gh workflow run "${workflow}" --repo "${REPO_SLUG}" --ref "${branch}")"
  if [[ "${output}" =~ /actions/runs/([0-9]+) ]]; then
    id="${BASH_REMATCH[1]}"
  else
    sleep 3
    id="$(latest_run_id "${workflow}" "${branch}" "")"
  fi
  [[ -n "${id}" ]] || { echo "ERROR: unable to resolve workflow run id"; exit 5; }
  echo "Run: ${id}" >&2
  if [[ "${wait_flag}" == "1" ]]; then
    gh run watch "${id}" --repo "${REPO_SLUG}" --exit-status
  fi
  printf '%s\n' "${id}"
}

download_artifact() {
  local platform="$1" variant="$2" workflow="$3" branch="$4" artifact="$5" wanted="$6" selected_run="$7"
  need_gh
  local run_id dest
  run_id="${selected_run}"
  if [[ -z "${run_id}" ]]; then
    run_id="$(latest_run_id "${workflow}" "${branch}" success)"
  fi
  [[ -n "${run_id}" ]] || { echo "ERROR: no successful run found"; exit 6; }

  dest="${ARTIFACT_ROOT}/${platform}/${variant}/${run_id}"
  mkdir -p "${dest}"
  if ! find "${dest}" -type f -print -quit | grep -q .; then
    echo "==> Downloading ${artifact} from run ${run_id}" >&2
    gh run download "${run_id}" \
      --repo "${REPO_SLUG}" \
      --name "${artifact}" \
      --dir "${dest}"
  fi

  local file=""
  if [[ -n "${wanted}" ]]; then
    file="$(find "${dest}" -type f -name "${wanted}" -print -quit)"
  fi
  if [[ -z "${file}" ]]; then
    file="$(find "${dest}" -type f \( -name '*.tar' -o -name '*.zip' -o -name '*.ipa' \) -print -quit)"
  fi
  [[ -n "${file}" ]] || { echo "ERROR: installable file not found in artifact"; exit 7; }
  printf '%s\n' "${file}"
}

install_app() {
  local variant="$1" artifact_file="$2" app_name="$3" data_mode="$4" data_root="$5" profile="$6" profile_root="$7" ipa="$8" run_after="$9"

  local stage app target
  stage="$(mktemp -d)"

  case "${artifact_file}" in
    *.tar) tar -xf "${artifact_file}" -C "${stage}" ;;
    *.zip) ditto -x -k "${artifact_file}" "${stage}" ;;
    *) echo "ERROR: unsupported macOS artifact: ${artifact_file}"; rm -rf "${stage}"; exit 8 ;;
  esac

  app="$(find "${stage}" -type d -name "${app_name}" -print -quit)"
  [[ -n "${app}" ]] || { echo "ERROR: ${app_name} not found after extraction"; rm -rf "${stage}"; exit 9; }

  mkdir -p "${HOME}/Applications"
  target="${HOME}/Applications/${app_name}"
  rm -rf "${target}"
  ditto "${app}" "${target}"
  xattr -dr com.apple.quarantine "${target}" 2>/dev/null || true
  rm -rf "${stage}"

  if [[ "${data_mode}" != "" && "${data_mode}" != "none" ]]; then
    [[ -n "${ipa}" ]] || {
      echo "ERROR: --ipa is required to install GameData for ${variant}."
      echo "The app was copied to ${target}, but data was not installed."
      exit 10
    }
    [[ -f "${ipa}" ]] || { echo "ERROR: IPA not found: ${ipa}"; exit 11; }

    local game_target profile_target
    game_target="${data_root/#\~/$HOME}"
    local args=(--ipa "${ipa}" --game-target "${game_target}" --replace)
    if [[ "${data_mode}" == "gamedata+profile" ]]; then
      profile_target="${profile_root/#\~/$HOME}"
      args+=(--profile "${profile}" --profile-target "${profile_target}")
    fi
    python3 "${DEPLOY_DIR}/extract-ipa-data.py" "${args[@]}"
  fi

  echo
  echo "READY"
  echo "App: ${target}"

  if [[ "${run_after}" == "1" ]]; then
    open "${target}"
  fi
}

COMMAND="${1:-help}"
shift || true

if [[ "${COMMAND}" == "help" ]]; then usage; exit 0; fi
if [[ "${COMMAND}" == "init" ]]; then python3 "${DEPLOY_DIR}/init-workspace.py"; exit $?; fi
if [[ "${COMMAND}" == "list" ]]; then show_list; exit 0; fi

PLATFORM="${1:-}"
VARIANT="${2:-}"
[[ -n "${PLATFORM}" && -n "${VARIANT}" ]] || { usage; exit 2; }
shift 2

variant_exists "${PLATFORM}" "${VARIANT}" || { echo "ERROR: unknown ${PLATFORM}/${VARIANT}"; exit 2; }
[[ "${PLATFORM}" == "macos" ]] || { echo "ERROR: run the Windows deployment CLI for iPad installation."; exit 2; }

IPA=""
RUN_ID=""
RUN_AFTER=0
NO_BUILD=0
WAIT_BUILD=0
while [[ $# -gt 0 ]]; do
  case "$1" in
    --ipa) IPA="$2"; shift 2 ;;
    --run-id) RUN_ID="$2"; shift 2 ;;
    --run) RUN_AFTER=1; shift ;;
    --no-build) NO_BUILD=1; shift ;;
    --wait) WAIT_BUILD=1; shift ;;
    *) echo "ERROR: unknown option: $1"; usage; exit 2 ;;
  esac
done

TITLE="$(catalog_field "${PLATFORM}" "${VARIANT}" title)"
STATUS="$(catalog_field "${PLATFORM}" "${VARIANT}" status)"
BRANCH="$(catalog_field "${PLATFORM}" "${VARIANT}" branch)"
MODE="$(catalog_field "${PLATFORM}" "${VARIANT}" buildMode)"
WORKFLOW="$(catalog_field "${PLATFORM}" "${VARIANT}" workflow)"
ARTIFACT="$(catalog_field "${PLATFORM}" "${VARIANT}" artifact)"
ARTIFACT_FILE="$(catalog_field "${PLATFORM}" "${VARIANT}" artifactFile)"
APP_NAME="$(catalog_field "${PLATFORM}" "${VARIANT}" appName)"
INSTALL_READY="$(catalog_field "${PLATFORM}" "${VARIANT}" installReady)"
DATA_MODE="$(catalog_field "${PLATFORM}" "${VARIANT}" dataMode)"
DATA_ROOT="$(catalog_field "${PLATFORM}" "${VARIANT}" dataRoot)"
PROFILE="$(catalog_field "${PLATFORM}" "${VARIANT}" profile)"
PROFILE_ROOT="$(catalog_field "${PLATFORM}" "${VARIANT}" profileRoot)"
LOG_PATH="$(catalog_field "${PLATFORM}" "${VARIANT}" logPath)"
NOTE="$(catalog_field "${PLATFORM}" "${VARIANT}" note)"

case "${COMMAND}" in
  status)
    echo "${PLATFORM}/${VARIANT} — ${TITLE}"
    echo "Status: ${STATUS}"
    echo "Branch: ${BRANCH}"
    echo "Build: ${MODE}"
    if [[ "${MODE}" == "github" ]]; then
      need_gh
      gh run list --repo "${REPO_SLUG}" --workflow "${WORKFLOW}" --branch "${BRANCH}" --limit 5
    else
      echo "${NOTE}"
    fi
    ;;
  update)
    update_variant "${BRANCH}"
    ;;
  build)
    [[ "${MODE}" == "github" ]] || { echo "ERROR: no macOS cloud build for this variant. ${NOTE}"; exit 4; }
    trigger_build "${WORKFLOW}" "${BRANCH}" "${WAIT_BUILD}"
    ;;
  download)
    [[ "${MODE}" == "github" ]] || { echo "ERROR: no downloadable macOS artifact. ${NOTE}"; exit 4; }
    download_artifact "${PLATFORM}" "${VARIANT}" "${WORKFLOW}" "${BRANCH}" "${ARTIFACT}" "${ARTIFACT_FILE}" "${RUN_ID}"
    ;;
  install)
    [[ "${INSTALL_READY}" == "true" ]] || { echo "ERROR: variant is not install-ready. ${NOTE}"; exit 4; }
    FILE="$(download_artifact "${PLATFORM}" "${VARIANT}" "${WORKFLOW}" "${BRANCH}" "${ARTIFACT}" "${ARTIFACT_FILE}" "${RUN_ID}")"
    install_app "${VARIANT}" "${FILE}" "${APP_NAME}" "${DATA_MODE}" "${DATA_ROOT}" "${PROFILE}" "${PROFILE_ROOT}" "${IPA}" "${RUN_AFTER}"
    ;;
  logs)
    echo "Runtime log: ${LOG_PATH/#\~/$HOME}"
    ;;
  full)
    [[ "${INSTALL_READY}" == "true" ]] || { echo "ERROR: variant is not install-ready. ${NOTE}"; exit 4; }
    [[ "${MODE}" == "github" ]] || { echo "ERROR: no full macOS build flow for this variant. ${NOTE}"; exit 4; }
    update_variant "${BRANCH}"
    if [[ "${NO_BUILD}" != "1" ]]; then
      RUN_ID="$(trigger_build "${WORKFLOW}" "${BRANCH}" 1 | tail -n1)"
    fi
    FILE="$(download_artifact "${PLATFORM}" "${VARIANT}" "${WORKFLOW}" "${BRANCH}" "${ARTIFACT}" "${ARTIFACT_FILE}" "${RUN_ID}")"
    install_app "${VARIANT}" "${FILE}" "${APP_NAME}" "${DATA_MODE}" "${DATA_ROOT}" "${PROFILE}" "${PROFILE_ROOT}" "${IPA}" "${RUN_AFTER}"
    ;;
  *)
    usage
    exit 2
    ;;
esac
