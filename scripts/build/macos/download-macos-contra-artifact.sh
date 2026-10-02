#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
REPO="${GX_GITHUB_REPO:-dvorovrus/Generals-Mac-iOS-iPad}"
BRANCH="${GX_GITHUB_BRANCH:-main}"
WORKFLOW="build-macos-contra-dev.yml"
ARTIFACT="GeneralsZH-ContraX-macos-arm64"
DEST="${1:-${ROOT}/build/macos-stable}"

if ! command -v gh >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI (gh) is required."
  echo "Install it with: brew install gh"
  exit 2
fi

if ! gh auth status >/dev/null 2>&1; then
  echo "ERROR: GitHub CLI is not authenticated."
  echo "Run: gh auth login"
  exit 3
fi

echo "==> Finding latest successful macOS Contra build"
RUN_ID="$(gh run list \
  --repo "${REPO}" \
  --workflow "${WORKFLOW}" \
  --branch "${BRANCH}" \
  --status success \
  --limit 1 \
  --json databaseId \
  --jq '.[0].databaseId')"

if [[ -z "${RUN_ID}" || "${RUN_ID}" == "null" ]]; then
  echo "ERROR: no successful ${WORKFLOW} run found on ${BRANCH}"
  exit 4
fi

TMP="$(mktemp -d)"
trap 'rm -rf "${TMP}"' EXIT

echo "==> Downloading artifact from run #${RUN_ID}"
gh run download "${RUN_ID}" \
  --repo "${REPO}" \
  --name "${ARTIFACT}" \
  --dir "${TMP}"

TAR="$(find "${TMP}" -type f -name "GeneralsZH-ContraX-macos-arm64.tar" -print -quit)"
if [[ -z "${TAR}" ]]; then
  echo "ERROR: artifact archive not found after download"
  exit 5
fi

rm -rf "${DEST}"
mkdir -p "${DEST}"
tar -xf "${TAR}" -C "${DEST}"

echo
echo "READY"
echo "Stable run: #${RUN_ID}"
echo "Folder: ${DEST}"
echo "App: ${DEST}/GeneralsZH-ContraX-Dev.app"
echo
echo "Run Install Contra Data.command once if ~/GeneralsX is not initialized."
