#!/usr/bin/env bash
# Stdio smoke test: pipes JSON-RPC messages into the release binary.
set -euo pipefail

cd "$(dirname "$0")/.."
BIN="${1:-.build/release/mac-screenshot-mcp}"
APP="${APP:-Finder}"

{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"0.1"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_apps","arguments":{}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"check_permissions","arguments":{}}}'
  printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"capture_app\",\"arguments\":{\"app\":\"$APP\",\"return_image\":false}}}"
  sleep 8
} | "$BIN"
