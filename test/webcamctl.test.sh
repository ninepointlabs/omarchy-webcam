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

# ---------- Image controls ----------
export WEBCAMCTL_V4L2CTL="$root/test/fixtures/fake-v4l2-ctl"
export WEBCAMCTL_V4L_DIR="$tmp/v4l"
export FAKE_V4L2_STATE="$tmp/v4l2"
export XDG_STATE_HOME="$tmp/state"
mkdir -p "$WEBCAMCTL_V4L_DIR/by-id"
ln -s /dev/video4 "$WEBCAMCTL_V4L_DIR/by-id/usb-Test_Cam_SN1-video-index0"
saved="$XDG_STATE_HOME/omarchy-webcam/controls/usb-Test_Cam_SN1-video-index0.json"
ctrl() { "$ctl" controls /dev/video4 | jq -r --arg n "$1" ".[] | select(.name == \$n) | .$2"; }

controls=$("$ctl" controls /dev/video4)
check "parses all int/bool/menu controls" test "$(jq length <<<"$controls")" = 16
check "friendly labels" test "$(ctrl zoom_absolute label)" = Zoom
check "menu options parsed" test "$(jq -c '.[] | select(.name == "power_line_frequency") | [.options[].label]' <<<"$controls")" = '["Disabled","50 Hz","60 Hz"]'
check "auto exposure labels simplified" test "$(jq -c '.[] | select(.name == "auto_exposure") | [.options[].label]' <<<"$controls")" = '["Manual","Auto"]'
check "manual white balance starts inactive" test "$(ctrl white_balance_temperature inactive)" = true

# Turning auto off and setting the manual value in one call must work even
# though the manual value is locked until the auto switch flips.
"$ctl" set-controls /dev/video4 white_balance_temperature=3500 white_balance_automatic=0 brightness=10
check "switch applied" test "$(ctrl white_balance_automatic value)" = 0
check "dependent manual value applied" test "$(ctrl white_balance_temperature value)" = 3500
check "saved under stable by-id key" test -f "$saved"
check "saves only changed values" test "$(jq -c . "$saved")" = '{"brightness":10,"white_balance_automatic":0,"white_balance_temperature":3500}'

check "rejects unknown control" bash -c "! '$ctl' set-controls /dev/video4 bogus=1 2>/dev/null"
check "rejects non-integer value" bash -c "! '$ctl' set-controls /dev/video4 'brightness=1;id' 2>/dev/null"
check "rejects bad device" bash -c "! '$ctl' controls /dev/sda 2>/dev/null"

# Simulate a replug: the driver forgets everything, restore brings it back.
rm -f "$FAKE_V4L2_STATE"/[a-z]*
check "replug resets device" test "$(ctrl brightness value)" = 0
"$ctl" restore /dev/video4
check "restore brings back switch" test "$(ctrl white_balance_automatic value)" = 0
check "restore brings back manual value" test "$(ctrl white_balance_temperature value)" = 3500
check "restore brings back brightness" test "$(ctrl brightness value)" = 10

# Reset puts manual values back before re-enabling auto modes.
"$ctl" reset-controls /dev/video4
check "reset re-enables auto" test "$(ctrl white_balance_automatic value)" = 1
check "reset restores manual default too" test "$(ctrl white_balance_temperature value)" = 4600
check "reset forgets saved values" test ! -e "$saved"

# restore with no argument walks every listed camera and tolerates ones
# without saved settings or without v4l2 access.
"$ctl" set-controls /dev/video4 gamma=150
rm -f "$FAKE_V4L2_STATE"/gamma
"$ctl" restore
check "restore-all reapplies" test "$(ctrl gamma value)" = 150

echo "ok - $pass checks passed"
