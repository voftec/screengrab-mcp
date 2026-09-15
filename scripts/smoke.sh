#!/usr/bin/env bash
# Stdio smoke test: pipes JSON-RPC messages into the release binary.
set -euo pipefail

cd "$(dirname "$0")/.."
BIN="${1:-.build/release/screengrab-mcp}"
APP="${APP:-Finder}"
COMPARE="${COMPARE:-}"

{
  printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"smoke","version":"0.1"}}}'
  printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":2,"method":"tools/list"}'
  printf '%s\n' '{"jsonrpc":"2.0","id":3,"method":"tools/call","params":{"name":"list_apps","arguments":{}}}'
  printf '%s\n' '{"jsonrpc":"2.0","id":4,"method":"tools/call","params":{"name":"check_permissions","arguments":{}}}'
  printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":5,\"method\":\"tools/call\",\"params\":{\"name\":\"capture_app\",\"arguments\":{\"app\":\"$APP\",\"return_image\":false}}}"
  printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":6,\"method\":\"tools/call\",\"params\":{\"name\":\"capture_app\",\"arguments\":{\"app\":\"$APP\",\"quality\":\"low\",\"return_image\":false}}}"
  printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":7,\"method\":\"tools/call\",\"params\":{\"name\":\"read_ui\",\"arguments\":{\"app\":\"$APP\",\"max_depth\":4,\"max_nodes\":200}}}"
  printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":8,\"method\":\"tools/call\",\"params\":{\"name\":\"event_driven_screengrab\",\"arguments\":{\"app\":\"$APP\",\"timeout_seconds\":5,\"return_image\":false}}}"
  if [ -n "$COMPARE" ]; then
    printf '%s\n' "{\"jsonrpc\":\"2.0\",\"id\":9,\"method\":\"tools/call\",\"params\":{\"name\":\"capture_app\",\"arguments\":{\"app\":\"$APP\",\"return_image\":false,\"compare_with\":\"$COMPARE\"}}}"
  fi
  printf '%s\n' '{"jsonrpc":"2.0","id":10,"method":"resources/list"}'
  sleep 15
} | "$BIN"
