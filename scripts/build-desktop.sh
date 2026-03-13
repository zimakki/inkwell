#!/usr/bin/env bash
set -euo pipefail

# Build Inkwell desktop app
# Usage: ./scripts/build-desktop.sh [--release]
# Compatible with bash 3.2+ (stock macOS)

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
PROJECT_DIR="$(dirname "$SCRIPT_DIR")"
TAURI_DIR="$PROJECT_DIR/src-tauri"
BINARIES_DIR="$TAURI_DIR/binaries"

echo "==> Building Burrito release..."
cd "$PROJECT_DIR"
MIX_ENV=prod mix release

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

echo "==> Done!"
