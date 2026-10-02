#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BUILD="${ROOT}/build/macos-vulkan-online"
PACKAGE_DIR="${ROOT}/build/macos-online-package"
APP="${PACKAGE_DIR}/GeneralsZH-Online-Dev.app"
GAME_BIN="${BUILD}/GeneralsMD/GeneralsXZH"
GAME_ROOT="${GX_GAME_ROOT:-${HOME}/GeneralsX/Online/GeneralsZH}"
RUN_APP=0
FORCE_CONFIGURE=0
CLEAN=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/build/macos/build-macos-online-local.sh [options]

Options:
  --run        Run Generals Online immediately after a successful incremental build.
  --configure  Re-run CMake configure before building.
  --clean      Remove Online build/package outputs before rebuilding.
  -h, --help   Show this help.

First build needs VCPKG_ROOT and VULKAN_SDK.
Retail Zero Hour data must already exist in ~/GeneralsX/Online/GeneralsZH.
Later builds reuse build/macos-vulkan-online and only rebuild changed targets.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --run) RUN_APP=1 ;;
    --configure) FORCE_CONFIGURE=1 ;;
    --clean) CLEAN=1; FORCE_CONFIGURE=1 ;;
    -h|--help) usage; exit 0 ;;
    *) echo "ERROR: unknown option: $1"; usage; exit 2 ;;
  esac
  shift
done

detect_vulkan_sdk() {
  if [[ -n "${VULKAN_SDK:-}" && -d "${VULKAN_SDK}" ]]; then
    return 0
  fi

  local candidate
  candidate="$(find "${HOME}/VulkanSDK" -maxdepth 2 -type d -name macOS 2>/dev/null | sort -V | tail -n1 || true)"
  if [[ -n "${candidate}" ]]; then
    export VULKAN_SDK="${candidate}"
    return 0
  fi

  return 1
}

detect_vcpkg_root() {
  if [[ -n "${VCPKG_ROOT:-}" && -f "${VCPKG_ROOT}/scripts/buildsystems/vcpkg.cmake" ]]; then
    return 0
  fi

  local candidate
  for candidate in \
    "${ROOT}/vcpkg" \
    "${HOME}/vcpkg" \
    "/opt/homebrew/share/vcpkg"; do
    if [[ -f "${candidate}/scripts/buildsystems/vcpkg.cmake" ]]; then
      export VCPKG_ROOT="${candidate}"
      return 0
    fi
  done

  if command -v vcpkg >/dev/null 2>&1; then
    candidate="$(cd "$(dirname "$(command -v vcpkg)")/.." 2>/dev/null && pwd || true)"
    if [[ -f "${candidate}/scripts/buildsystems/vcpkg.cmake" ]]; then
      export VCPKG_ROOT="${candidate}"
      return 0
    fi
  fi

  return 1
}

if [[ ! -d "${GAME_ROOT}" || -z "$(find "${GAME_ROOT}" -maxdepth 1 -type f -iname '*.big' -print -quit 2>/dev/null)" ]]; then
  echo "ERROR: Generals Online GameData is not installed: ${GAME_ROOT}"
  echo "Install it once with:"
  echo "  bash scripts/build/macos/install-macos-online-data.sh /path/to/GeneralsZH-FULL-unsigned.ipa"
  echo "or copy your existing clean Zero Hour data into ${GAME_ROOT}."
  exit 3
fi

if [[ "${CLEAN}" == "1" ]]; then
  echo "==> Cleaning local macOS Online build"
  rm -rf "${BUILD}" "${PACKAGE_DIR}"
  rm -f "${ROOT}/GeneralsZH-Online-macos-arm64.tar"
fi

if [[ ! -f "${BUILD}/build.ninja" || "${FORCE_CONFIGURE}" == "1" ]]; then
  echo "==> Configuring macOS Online arm64 build"

  detect_vcpkg_root || {
    echo "ERROR: VCPKG_ROOT is not set and vcpkg was not found."
    echo "Example: export VCPKG_ROOT=$HOME/vcpkg"
    exit 4
  }

  detect_vulkan_sdk || {
    echo "ERROR: VULKAN_SDK is not set and ~/VulkanSDK/*/macOS was not found."
    echo "Example: export VULKAN_SDK=$HOME/VulkanSDK/1.4.341.1/macOS"
    exit 5
  }

  git -C "${ROOT}" submodule update --init --recursive --depth 1 references/fbraz3-dxvk

  export VCPKG_DEFAULT_TRIPLET=arm64-osx
  export CC="${CC:-clang}"
  export CXX="${CXX:-clang++}"
  cmake --preset macos-vulkan-online
fi

echo "==> Incremental Online engine build"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
cmake --build "${BUILD}" --target z_generals -j "${JOBS}"

test -f "${GAME_BIN}" || {
  echo "ERROR: build succeeded but binary is missing: ${GAME_BIN}"
  exit 6
}

if [[ ! -d "${APP}" ]]; then
  echo "==> First local Online package"
else
  echo "==> Refreshing Online app bundle"
fi

detect_vulkan_sdk || {
  echo "ERROR: VULKAN_SDK is required to package the macOS app."
  exit 7
}
GX_MAC_ONLINE=1 bash "${ROOT}/scripts/build/macos/package-macos-contra-dev.sh"

echo
echo "READY"
echo "App: ${APP}"
echo "GameData: ${GAME_ROOT}"
echo "Log: ${HOME}/Library/Logs/GeneralsXZH/online-dev.log"
echo "Retail GameData stays in ~/GeneralsX/Online and is not recopied on incremental builds."

if [[ "${RUN_APP}" == "1" ]]; then
  echo
  echo "==> Running Generals Online"
  exec "${APP}/Contents/MacOS/run.sh"
fi
