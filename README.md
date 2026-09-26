# Omarchy Webcam

A bar widget for the Omarchy shell that lets you choose which camera your system uses (built-in, USB, and so on) and opens a small live preview so you can check what that camera sees.

![Webcam popup](preview.png)

## What it does

- **Lists every camera** that PipeWire knows about, including USB webcams as they're plugged in. Infrared (Windows Hello-style) sensors are flagged and dimmed.
- **Sets the system camera.** Clicking a camera makes it PipeWire's default video source (`wpctl set-default`). WirePlumber saves this choice, so it persists after a reboot.
- **Opens a live preview window** in the bottom-right corner. It shows the camera name, resolution and frame rate. You can drag the title bar to move it, press `⇆` or `m` to mirror the image, and press `✕`, `Esc` or `q` to close it.

### Which apps respect the choice?

Apps that access cameras through PipeWire or the camera portal (Firefox, Chromium/Chrome with PipeWire camera support, OBS's PipeWire source, GNOME/KDE apps) treat the default camera as the preferred one. Apps that open `/dev/videoN` directly, such as older V4L2 tools, still choose their own device, usually through a setting inside the app.

## Using it

| Action | How |
| --- | --- |
| Open the camera picker | Click the bar icon |
| Make a camera the default | Click its row (or use arrow keys / `j` `k` and `Enter`) |
| Preview a specific camera | Click the video icon on its row, or highlight it and press `p` |
| Preview or stop the default camera | Right-click the bar icon, or use the **Preview** button |
| Stop the preview | `s` in the popup, `✕` / `Esc` in the preview window |

### Keybinding / scripting

```bash
omarchy-shell ninepointlabs.webcam toggle        # open/close the picker
omarchy-shell ninepointlabs.webcam preview       # preview the current default camera
omarchy-shell ninepointlabs.webcam stopPreview

# The helper works on its own, too:
bin/webcamctl list                 # JSON camera list
bin/webcamctl set-default 88       # PipeWire node id from `list`
bin/webcamctl toggle-preview       # handy for a Hyprland keybinding
```

## Settings

These go on the widget's entry in `~/.config/omarchy/shell.json`:

| Key | Default | Meaning |
| --- | --- | --- |
| `previewWidth` | `480` | Width of the preview window in logical pixels (240–1280) |
| `showIr` | `true` | Include infrared sensors in the list |

## Install

```bash
omarchy plugin add <git-url> --enable
```

For development, symlink a checkout instead:

```bash
ln -sfn ~/Projects/omarchy-webcam ~/.config/omarchy/plugins/ninepointlabs.webcam
omarchy-shell shell rescanPlugins
omarchy plugin enable ninepointlabs.webcam
```

Requirements: PipeWire + WirePlumber (`pw-dump`, `wpctl`), `jq`, and `qt6-multimedia` with the FFmpeg backend for the preview. All of these ship with Omarchy. `v4l2-ctl` (from `v4l-utils`) is optional and is used to detect IR sensors.

## How it's built

- `Webcam.qml`: the bar icon and popup. It never parses devices on its own; it only renders the JSON that `webcamctl list` returns.
- `bin/webcamctl`: reads the camera list from `pw-dump`, validates every node id and device path, switches the default with `wpctl`, and manages a single preview process. It keeps a pid file under `$XDG_RUNTIME_DIR` and checks the process's identity before sending it a signal.
- `preview/shell.qml`: a standalone Quickshell layer-shell window that uses QtMultimedia. It runs as a **separate process**, so a stuck or crashing camera driver cannot take down the Omarchy shell and bar.

## Tests

```bash
test/webcamctl.test.sh
```

Runs the helper against a recorded `pw-dump` fixture and a fake `wpctl`. It does not need real cameras.
