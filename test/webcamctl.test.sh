#!/usr/bin/env bash
# Tests for bin/webcamctl against a recorded pw-dump and a fake wpctl.
set -euo pipefail

root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
ctl="$root/bin/webcamctl"
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

export WEBCAMCTL_PW_DUMP="$root/test/fixtures/pw-dump.json"
export WEBCAMCTL_WPCTL="$tmp/wpctl"
export XDG_RUNTIME_DIR="$tmp/run"
printf '#!/bin/sh\necho "$@" >"%s/wpctl.log"\n' "$tmp" >"$WEBCAMCTL_WPCTL"
chmod +x "$WEBCAMCTL_WPCTL"

pass=0
check() {
  local name=$1; shift
  if "$@"; then pass=$((pass + 1)); else echo "FAIL: $name" >&2; exit 1; fi
}

list=$("$ctl" list)
check "lists three cameras" test "$(jq length <<<"$list")" = 3
check "exactly one default" test "$(jq '[.[] | select(.default)] | length' <<<"$list")" = 1
check "default follows metadata" test "$(jq -r '.[] | select(.default) | .device' <<<"$list")" = /dev/video0
check "strips (V4L2) suffix" test "$(jq -r '.[] | select(.device == "/dev/video4") | .name' <<<"$list")" = "NexiGo HD Webcam"
check "unique names keep plain label" test "$(jq -r '.[] | select(.device == "/dev/video4") | .label' <<<"$list")" = "NexiGo HD Webcam"
check "duplicate names get distinct labels" test "$(jq '[.[] | select(.name == "Surface Camera Front") | .label] | unique | length' <<<"$list")" = 2

# A configured default beats priority.
jq '(.[] | select(.type == "PipeWire:Interface:Metadata") | .metadata[]? | select(.key == "default.video.source") | .value.name) = "v4l2_input.pci-0000_00_14.0-usb-0_2_1.0"' "$WEBCAMCTL_PW_DUMP" >"$tmp/usb.json"
check "configured default wins" test "$(WEBCAMCTL_PW_DUMP="$tmp/usb.json" "$ctl" list | jq -r '.[] | select(.default) | .device')" = /dev/video4

# Without a configured default, the highest-priority camera wins.
jq 'map(select(.type != "PipeWire:Interface:Metadata"))' "$WEBCAMCTL_PW_DUMP" >"$tmp/nometa.json"
check "falls back to priority" test "$(WEBCAMCTL_PW_DUMP="$tmp/nometa.json" "$ctl" list | jq -r '.[] | select(.default) | .device')" = /dev/video0

"$ctl" set-default 88
check "set-default calls wpctl" test "$(cat "$tmp/wpctl.log")" = "set-default 88"
check "rejects non-camera node" bash -c "! '$ctl' set-default 1 2>/dev/null"
check "rejects non-numeric id" bash -c "! '$ctl' set-default '88; rm -rf /' 2>/dev/null"
check "rejects non-video device" bash -c "! '$ctl' preview /etc/passwd 2>/dev/null"
check "no preview running" test "$("$ctl" preview-running)" = false

# A stale pid file pointing at an unrelated process must never be signalled.
mkdir -p "$XDG_RUNTIME_DIR/omarchy-webcam"
sleep 30 & bystander=$!
echo "$bystander" >"$XDG_RUNTIME_DIR/omarchy-webcam/preview.pid"
check "ignores foreign pid" test "$("$ctl" preview-running)" = false
"$ctl" stop-preview
check "bystander survives stop-preview" kill -0 "$bystander"
kill "$bystander"

echo "ok - $pass checks passed"
