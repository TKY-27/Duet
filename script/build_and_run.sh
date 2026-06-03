#!/usr/bin/env bash
set -euo pipefail

MODE="${1:-run}"
APP_NAME="Duet"
BUNDLE_ID="dev.duet.Duet"
MIN_SYSTEM_VERSION="14.0"

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
APP_DIR="$ROOT_DIR/app"
DIST_DIR="$ROOT_DIR/dist"
APP_BUNDLE="$DIST_DIR/$APP_NAME.app"
APP_CONTENTS="$APP_BUNDLE/Contents"
APP_MACOS="$APP_CONTENTS/MacOS"
APP_RESOURCES="$APP_CONTENTS/Resources"
APP_BINARY="$APP_MACOS/$APP_NAME"
INFO_PLIST="$APP_CONTENTS/Info.plist"
SOURCE_ICON="$APP_DIR/Sources/Duet/Resources/AppIcon.png"
ICONSET_DIR="$DIST_DIR/AppIcon.iconset"
ICON_FILE="$APP_RESOURCES/AppIcon.icns"
VERIFY_DIR="$DIST_DIR/verify"
VERIFY_REPO="$VERIFY_DIR/repo"
VERIFY_CONFIG="$VERIFY_DIR/duet.config.json"
VERIFY_CONTROL_TOKEN=""
VERIFY_APP_PID=""

process_command() {
  ps -p "$1" -o command= 2>/dev/null || true
}

kill_existing_dev_bundle() {
  local pid command_line
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    command_line="$(process_command "$pid")"
    if [[ "$command_line" == "$APP_BINARY"* || "$command_line" == *"$APP_BUNDLE/Contents/MacOS/$APP_NAME"* ]]; then
      kill "$pid" >/dev/null 2>&1 || true
    fi
  done < <(pgrep -x "$APP_NAME" 2>/dev/null || true)
}

find_dev_bundle_pid() {
  local pid command_line
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    command_line="$(process_command "$pid")"
    if [[ "$command_line" == "$APP_BINARY"* || "$command_line" == *"$APP_BUNDLE/Contents/MacOS/$APP_NAME"* ]]; then
      printf '%s\n' "$pid"
      return 0
    fi
  done < <(pgrep -x "$APP_NAME" 2>/dev/null || true)
  return 1
}

wait_for_pid() {
  local pid="$1"
  for _ in {1..50}; do
    if kill -0 "$pid" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.1
  done
  return 1
}

wait_for_dev_bundle_pid() {
  local pid
  for _ in {1..80}; do
    pid="$(find_dev_bundle_pid || true)"
    if [[ -n "$pid" ]]; then
      printf '%s\n' "$pid"
      return 0
    fi
    sleep 0.1
  done
  return 1
}

kill_pid_and_wait() {
  local pid="$1"
  kill "$pid" >/dev/null 2>&1 || true
  for _ in {1..40}; do
    if ! kill -0 "$pid" >/dev/null 2>&1; then
      return 0
    fi
    sleep 0.05
  done
  kill -9 "$pid" >/dev/null 2>&1 || true
}

kill_hub_for_config() {
  local config_path="$1"
  local pid command_line
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    command_line="$(process_command "$pid")"
    if [[ "$command_line" == *"hub/dist/server.js"* && "$command_line" == *"--config $config_path"* ]]; then
      kill_pid_and_wait "$pid"
    fi
  done < <(pgrep -f "hub/dist/server.js" 2>/dev/null || true)
}

kill_existing_project_hubs() {
  local pid command_line server_script
  server_script="$ROOT_DIR/hub/dist/server.js"
  while IFS= read -r pid; do
    [[ -n "$pid" ]] || continue
    command_line="$(process_command "$pid")"
    if [[ "$command_line" == *"$server_script"* ]]; then
      kill_pid_and_wait "$pid"
    fi
  done < <(pgrep -f "hub/dist/server.js" 2>/dev/null || true)
}

wait_for_health() {
  local url="http://127.0.0.1:8765/health"
  local body
  for _ in {1..80}; do
    body="$(curl -fsS --max-time 1 "$url" 2>/dev/null || true)"
    if [[ "$body" == *'"ok":true'* && "$body" == *'"service":"duet-hub"'* ]]; then
      return 0
    fi
    sleep 0.25
  done
  echo "Hub health check did not pass at $url" >&2
  return 1
}

generate_base64url_token() {
  openssl rand -base64 32 | tr '+/' '-_' | tr -d '='
}

create_verify_config() {
  mkdir -p "$VERIFY_REPO/.git"
  cat >"$VERIFY_CONFIG" <<JSON
{
  "host": "127.0.0.1",
  "port": 8765,
  "repoPath": "$VERIFY_REPO",
  "holdSec": 5,
  "noProgressHoldSec": 2,
  "progressIntervalSec": 1,
  "maxTranscriptMessages": 50,
  "maxQueueMessages": 20,
  "maxWaitersPerAgent": 5,
  "maxTransports": 10,
  "maxControlPayloadBytes": 16384,
  "maxControlConnections": 2,
  "maxRequestsPerMinute": 120,
  "idleTransportTtlSec": 30
}
JSON
}

launch_app_for_verify() {
  VERIFY_CONTROL_TOKEN="$(generate_base64url_token)"
  /usr/bin/open -n \
    --env "DUET_REPO_ROOT=$ROOT_DIR" \
    --env "DUET_CONFIG=$VERIFY_CONFIG" \
    --env "DUET_CONTROL_TOKEN=$VERIFY_CONTROL_TOKEN" \
    "$APP_BUNDLE"
  VERIFY_APP_PID="$(wait_for_dev_bundle_pid)"
}

cleanup_verify() {
  if [[ -n "${VERIFY_APP_PID:-}" ]] && kill -0 "$VERIFY_APP_PID" >/dev/null 2>&1; then
    kill_pid_and_wait "$VERIFY_APP_PID"
  fi
  kill_hub_for_config "$VERIFY_CONFIG"
}

verify_icon_packaging() {
  plutil -lint "$INFO_PLIST" >/dev/null
  [[ -f "$ICON_FILE" ]]
  [[ "$(plutil -extract CFBundleIconFile raw -o - "$INFO_PLIST")" == "AppIcon" ]]
}

verify_control_ws() {
  (
    cd "$ROOT_DIR/hub"
    DUET_CONTROL_TOKEN="$VERIFY_CONTROL_TOKEN" node --input-type=module <<'NODE'
import WebSocket from "ws";

const token = process.env.DUET_CONTROL_TOKEN;
const ws = new WebSocket("ws://127.0.0.1:8765/control", {
  headers: { "X-Duet-Control-Token": token },
});

const timeout = setTimeout(() => {
  console.error("Timed out waiting for control snapshot");
  ws.close();
  process.exit(1);
}, 5000);

ws.on("message", (payload) => {
  const event = JSON.parse(payload.toString());
  if (event.type === "snapshot" && event.snapshot && event.snapshot.repoPath) {
    clearTimeout(timeout);
    ws.close();
    process.exit(0);
  }
});

ws.on("error", (error) => {
  clearTimeout(timeout);
  console.error(error.message);
  process.exit(1);
});
NODE
  )
}

kill_existing_dev_bundle
kill_existing_project_hubs

npm --prefix "$ROOT_DIR/hub" run build
swift build --package-path "$APP_DIR"

BUILD_DIR="$(swift build --package-path "$APP_DIR" --show-bin-path)"
BUILD_BINARY="$BUILD_DIR/$APP_NAME"
RESOURCE_BUNDLE="$BUILD_DIR/${APP_NAME}_${APP_NAME}.bundle"

rm -rf "$APP_BUNDLE" "$ICONSET_DIR"
mkdir -p "$APP_MACOS" "$APP_RESOURCES"
cp "$BUILD_BINARY" "$APP_BINARY"
chmod +x "$APP_BINARY"
if [[ -d "$RESOURCE_BUNDLE" ]]; then
  cp -R "$RESOURCE_BUNDLE" "$APP_RESOURCES/"
fi

if [[ -f "$SOURCE_ICON" ]]; then
  mkdir -p "$ICONSET_DIR"
  sips -z 16 16 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_16x16.png" >/dev/null
  sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_16x16@2x.png" >/dev/null
  sips -z 32 32 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_32x32.png" >/dev/null
  sips -z 64 64 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_32x32@2x.png" >/dev/null
  sips -z 128 128 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_128x128.png" >/dev/null
  sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_128x128@2x.png" >/dev/null
  sips -z 256 256 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_256x256.png" >/dev/null
  sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_256x256@2x.png" >/dev/null
  sips -z 512 512 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_512x512.png" >/dev/null
  sips -z 1024 1024 "$SOURCE_ICON" --out "$ICONSET_DIR/icon_512x512@2x.png" >/dev/null
  iconutil -c icns "$ICONSET_DIR" -o "$ICON_FILE"
fi

cat >"$INFO_PLIST" <<PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleExecutable</key>
  <string>$APP_NAME</string>
  <key>CFBundleIdentifier</key>
  <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>
  <string>$APP_NAME</string>
  <key>CFBundleIconFile</key>
  <string>AppIcon</string>
  <key>CFBundlePackageType</key>
  <string>APPL</string>
  <key>LSMinimumSystemVersion</key>
  <string>$MIN_SYSTEM_VERSION</string>
  <key>NSPrincipalClass</key>
  <string>NSApplication</string>
</dict>
</plist>
PLIST

open_app() {
  /usr/bin/open -n --env "DUET_REPO_ROOT=$ROOT_DIR" "$APP_BUNDLE"
}

case "$MODE" in
  run)
    open_app
    ;;
  --debug|debug)
    DUET_REPO_ROOT="$ROOT_DIR" lldb -- "$APP_BINARY"
    ;;
  --logs|logs)
    open_app
    /usr/bin/log stream --info --style compact --predicate "process == \"$APP_NAME\""
    ;;
  --telemetry|telemetry)
    open_app
    /usr/bin/log stream --info --style compact --predicate "subsystem == \"$BUNDLE_ID\""
    ;;
  --verify|verify)
    create_verify_config
    trap cleanup_verify EXIT
    kill_hub_for_config "$VERIFY_CONFIG"
    verify_icon_packaging
    launch_app_for_verify
    wait_for_health
    verify_control_ws
    echo "Verified $APP_NAME launch, Hub /health, and control WebSocket snapshot."
    ;;
  *)
    echo "usage: $0 [run|--debug|--logs|--telemetry|--verify]" >&2
    exit 2
    ;;
esac
