#!/usr/bin/env bash
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT="$(cd "${SCRIPT_DIR}/../../.." && pwd)"
BUILD="${ROOT}/build/macos-vulkan"
PACKAGE_DIR="${ROOT}/build/macos-package"
APP="${PACKAGE_DIR}/GeneralsZH-ContraX-Dev.app"
GAME_BIN="${BUILD}/GeneralsMD/GeneralsXZH"
RUN_APP=0
FORCE_CONFIGURE=0
CLEAN=0

usage() {
  cat <<'EOF'
Usage:
  ./scripts/build/macos/build-macos-contra-local.sh [options]

Options:
  --run        Run Contra immediately after a successful incremental build.
  --configure  Re-run CMake configure before building.
  --clean      Remove build/macos-vulkan and build/macos-package first.
  -h, --help   Show this help.

First build needs VCPKG_ROOT and VULKAN_SDK.
Later builds reuse build/macos-vulkan and only rebuild changed targets.
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

if [[ "${CLEAN}" == "1" ]]; then
  echo "==> Cleaning local macOS build"
  rm -rf "${BUILD}" "${PACKAGE_DIR}"
fi

if [[ ! -f "${BUILD}/build.ninja" || "${FORCE_CONFIGURE}" == "1" ]]; then
  echo "==> Configuring macOS arm64 build"

  detect_vcpkg_root || {
    echo "ERROR: VCPKG_ROOT is not set and vcpkg was not found."
    echo "Example: export VCPKG_ROOT=$HOME/vcpkg"
    exit 3
  }

  detect_vulkan_sdk || {
    echo "ERROR: VULKAN_SDK is not set and ~/VulkanSDK/*/macOS was not found."
    echo "Example: export VULKAN_SDK=$HOME/VulkanSDK/1.4.341.1/macOS"
    exit 4
  }

  git -C "${ROOT}" submodule update --init --recursive --depth 1 references/fbraz3-dxvk

  export VCPKG_DEFAULT_TRIPLET=arm64-osx
  export CC="${CC:-clang}"
  export CXX="${CXX:-clang++}"
  cmake --preset macos-vulkan
fi

echo "==> Incremental engine build"
JOBS="$(sysctl -n hw.ncpu 2>/dev/null || echo 4)"
cmake --build "${BUILD}" --target z_generals -j "${JOBS}"

test -f "${GAME_BIN}" || {
  echo "ERROR: build succeeded but binary is missing: ${GAME_BIN}"
  exit 5
}

if [[ ! -d "${APP}" ]]; then
  echo "==> First local package"
  detect_vulkan_sdk || {
    echo "ERROR: VULKAN_SDK is required for the first local package."
    exit 6
  }
  bash "${ROOT}/scripts/build/macos/package-macos-contra-dev.sh"
else
  echo "==> Refreshing existing app bundle"
  cp "${GAME_BIN}" "${APP}/Contents/Resources/bin/GeneralsXZH"
  chmod +x "${APP}/Contents/Resources/bin/GeneralsXZH"
  codesign --force --deep --sign - "${APP}"
fi

echo
echo "READY"
echo "App: ${APP}"
echo "Log: ${HOME}/Library/Logs/GeneralsXZH/contra-dev.log"
echo "Retail/Contra data stay in ~/GeneralsX and are not recopied on incremental builds."

if [[ "${RUN_APP}" == "1" ]]; then
  echo
  echo "==> Running Contra X"
  exec "${APP}/Contents/MacOS/run.sh"
fi
