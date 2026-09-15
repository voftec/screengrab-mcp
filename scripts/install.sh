#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

echo "==> Building release binary..."
swift build -c release

BIN=".build/release/screengrab-mcp"
DEST="/usr/local/bin"

if [ ! -w "$DEST" ]; then
  DEST="$HOME/.local/bin"
  mkdir -p "$DEST"
fi

cp "$BIN" "$DEST/screengrab-mcp"
echo "==> Installed to $DEST/screengrab-mcp"
