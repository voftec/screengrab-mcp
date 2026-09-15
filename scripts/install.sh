#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

# Neutralize git url.*.insteadOf rewrites (e.g. Devin's git-manager proxy)
# that prevent SPM from fetching dependencies directly from GitHub.
export GIT_CONFIG_GLOBAL=/dev/null
export GIT_CONFIG_SYSTEM=/dev/null

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
