#!/usr/bin/env bash
set -euo pipefail

# Build Inkwell desktop app
# Usage: ./scripts/build-desktop.sh [--release]
# Compatible with bash 3.2+ (stock macOS)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TAURI_DIR="$PROJECT_DIR/src-tauri"
BINARIES_DIR="$TAURI_DIR/binaries"

default_burrito_target() {
  local os="$(uname -s)"
  local arch="$(uname -m)"

  case "$os:$arch" in
    Darwin:arm64|Darwin:aarch64)
      echo "darwin_arm64"
      ;;
    Darwin:x86_64)
      echo "darwin_amd64"
      ;;
    Linux:x86_64)
      echo "linux_amd64"
      ;;
    MINGW*:x86_64|MSYS*:x86_64|CYGWIN*:x86_64)
      echo "windows_amd64"
      ;;
    *)
      echo ""
      ;;
  esac
}

BURRITO_TARGET_NAME="${BURRITO_TARGET:-$(default_burrito_target)}"

if [ -z "$BURRITO_TARGET_NAME" ]; then
  echo "Unsupported host platform for automatic Burrito target selection." >&2
  echo "Set BURRITO_TARGET explicitly (for example: darwin_arm64)." >&2
  exit 1
fi

echo "==> Building Burrito release..."
cd "$PROJECT_DIR"
BURRITO_TARGET="$BURRITO_TARGET_NAME" MIX_ENV=prod mix release --overwrite

echo "==> Copying sidecar binaries..."
mkdir -p "$BINARIES_DIR"

copy_if_exists() {
  local src="$PROJECT_DIR/burrito_out/$1"
  local dst="$BINARIES_DIR/$2"

  if [ -f "$src" ]; then
    cp "$src" "$dst"
    chmod +x "$dst"
    echo "  Copied $1 -> $2"
  fi
}

copy_if_exists "inkwell_darwin_arm64" "inkwell-aarch64-apple-darwin"
copy_if_exists "inkwell_darwin_amd64" "inkwell-x86_64-apple-darwin"
copy_if_exists "inkwell_linux_amd64" "inkwell-x86_64-unknown-linux-gnu"
copy_if_exists "inkwell_windows_amd64" "inkwell-x86_64-pc-windows-msvc.exe"

echo "==> Building Tauri app..."
cd "$TAURI_DIR"

if [ "${1:-}" = "--release" ]; then
  RUSTUP_TOOLCHAIN=stable cargo tauri build
else
  RUSTUP_TOOLCHAIN=stable cargo tauri build --debug
fi

# Ad-hoc sign the .app bundle on macOS.
# Tauri's build only linker-signs individual binaries but doesn't sign the
# bundle itself, leaving it without a _CodeSignature directory.  macOS
# Gatekeeper then reports the app as "damaged and can't be opened."
if [ "$(uname -s)" = "Darwin" ]; then
  echo "==> Signing .app bundle..."
  app=$(find "$TAURI_DIR/target" -maxdepth 5 -name '*.app' -type d | head -n 1)
  if [ -n "$app" ]; then
    codesign --force --deep -s - "$app"
    echo "  Signed $app"
  fi
fi

echo "==> Done!"
