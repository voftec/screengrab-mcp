#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Building release binary..."
swift build -c release

BIN=".build/release/mac-screenshot-mcp"
DEST="/usr/local/bin"

if [ ! -w "$DEST" ]; then
  DEST="$HOME/.local/bin"
  mkdir -p "$DEST"
fi

cp "$BIN" "$DEST/mac-screenshot-mcp"
echo "==> Installed to $DEST/mac-screenshot-mcp"
