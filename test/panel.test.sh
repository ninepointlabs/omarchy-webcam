#!/usr/bin/env bash
# The popup's About page in a real Quickshell.
# Usage: test/panel.test.sh
#
# Loads Webcam.qml from a scratch copy of this checkout with the installed
# shell's Ui/ and Commons/, through the harness in test/qml/PanelHarness.qml.
# webcamctl runs against the recorded pw-dump and the fake v4l2-ctl, with
# scratch state/runtime dirs, inside a network namespace (unshare -Urn), so no
# real camera, setting or network is touched. It needs the Wayland session:
# the popup opens briefly on screen.
set -u
root=$(CDPATH= cd -- "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)
shell_src="${OMARCHY_PATH:-/usr/share/omarchy}/shell"

skip() { printf 'skip panel tests (%s)\n' "$1"; exit 0; }
command -v qs >/dev/null || skip "qs not installed"
command -v jq >/dev/null || skip "jq not installed"
[[ -d "$shell_src/Ui" && -d "$shell_src/Commons" ]] || skip "no Omarchy shell at $shell_src"
[[ -n "${WAYLAND_DISPLAY:-}" ]] || skip "no Wayland session"
unshare -Urn true 2>/dev/null || skip "unshare -Urn unavailable"

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/root" "$work/plugin" "$work/state" "$work/v4l"

# qs resolves qs.Ui / qs.Commons relative to the config root.
cp -r "$shell_src/Ui" "$shell_src/Commons" "$work/root/"
cp "$root/test/qml/PanelHarness.qml" "$work/root/shell.qml"
version_re=$(jq -r .version "$root/manifest.json" | sed 's/\./\\\\./g')
sed -i "s/@MANIFEST_VERSION_RE@/$version_re/" "$work/root/shell.qml"
cp "$root"/*.qml "$root"/*.js "$root/manifest.json" "$root/LICENSE" "$work/plugin/"
cp -r "$root/bin" "$work/plugin/"

WEBCAMCTL_PW_DUMP="$root/test/fixtures/pw-dump.json" \
  WEBCAMCTL_WPCTL=/bin/false \
  WEBCAMCTL_V4L2CTL="$root/test/fixtures/fake-v4l2-ctl" \
  WEBCAMCTL_V4L_DIR="$work/v4l" FAKE_V4L2_STATE="$work/v4l2" \
  XDG_STATE_HOME="$work/state" \
  WEBCAM_PLUGIN="$work/plugin" \
  unshare -Urn timeout 60 qs --no-color -p "$work/root/shell.qml" >"$work/log" 2>&1
rc=$?

line=$(grep -o 'RESULT .*' "$work/log" | tail -1)
if [[ -z "$line" ]]; then
  printf 'FAIL harness produced no result (qs exit %d). Log tail:\n' "$rc"
  tail -30 "$work/log"
  exit 1
fi

warnings=$(grep -E 'WARN|ERROR' "$work/log" | grep -v 'qt\.qpa\.' | grep -v 'RESULT ')
json=${line#RESULT }
jq -r '.[] | if .ok then "ok   " + .name else "FAIL " + .name + " -- " + .detail end' <<<"$json"
pass=$(jq '[.[] | select(.ok)] | length' <<<"$json")
failn=$(jq '[.[] | select(.ok | not)] | length' <<<"$json")
if [[ -n "$warnings" ]]; then
  failn=$((failn + 1))
  printf 'FAIL QML warnings:\n%s\n' "$warnings"
fi

printf '\n%d passed, %d failed\n' "$pass" "$failn"
[[ "$failn" -eq 0 ]]
