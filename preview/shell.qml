import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Wayland

// Standalone camera preview. Runs as its own Quickshell process (started by
// bin/webcamctl preview) so a misbehaving camera driver can never take the
// Omarchy shell and its bar down with it. The window is a layer-shell
// surface, so Hyprland places it where we ask instead of tiling it.
//
// Inputs (environment):
//   WEBCAM_DEVICE  V4L2 path to show, e.g. /dev/video4 (default: Qt default)
//   WEBCAM_NAME    friendly camera name for the title bar
//   WEBCAM_FG / WEBCAM_BG / WEBCAM_ACCENT / WEBCAM_BORDER / WEBCAM_FONT  theme hints
//   WEBCAM_WIDTH   preview width in logical px (default 480)
ShellRoot {
  id: shell

  readonly property string requestedDevice: Quickshell.env("WEBCAM_DEVICE") || ""
  readonly property color fg: Quickshell.env("WEBCAM_FG") || "#e6e6e6"
  readonly property color bg: Quickshell.env("WEBCAM_BG") || "#161616"
  readonly property color accent: Quickshell.env("WEBCAM_ACCENT") || fg
  readonly property color border: Quickshell.env("WEBCAM_BORDER") || Qt.rgba(fg.r, fg.g, fg.b, 0.25)
  readonly property string displayName: Quickshell.env("WEBCAM_NAME")
    || (device ? String(device.description).replace(/:.*$/, "") : "")
  readonly property string fontFamily: Quickshell.env("WEBCAM_FONT") || "monospace"
  readonly property int previewWidth: Math.max(240, Math.min(1280, Number(Quickshell.env("WEBCAM_WIDTH")) || 480))

  property bool mirrored: true
  property string errorText: ""

  MediaDevices { id: mediaDevices }

  readonly property var device: {
    var inputs = mediaDevices.videoInputs
    for (var i = 0; i < inputs.length; i++) {
      if (inputs[i].id == requestedDevice) return inputs[i]
    }
    return requestedDevice === "" ? mediaDevices.defaultVideoInput : null
  }

  // Prefer the sharpest format that is still cheap to decode for a thumbnail:
  // at most 1280 wide, then highest frame rate, then largest area.
  function pickFormat(dev) {
    if (!dev) return null
    var best = null
    var formats = dev.videoFormats
    for (var i = 0; i < formats.length; i++) {
      var f = formats[i]
      if (f.resolution.width > 1280) continue
      if (!best) { best = f; continue }
      var area = f.resolution.width * f.resolution.height
      var bestArea = best.resolution.width * best.resolution.height
      if (area > bestArea || (area === bestArea && f.maxFrameRate > best.maxFrameRate)) best = f
    }
    return best || (formats.length > 0 ? formats[0] : null)
  }

  readonly property var format: pickFormat(device)
  readonly property real aspect: format && format.resolution.height > 0
    ? format.resolution.width / format.resolution.height : 16 / 9
  readonly property string formatLabel: format
    ? format.resolution.width + "×" + format.resolution.height + " · " + Math.round(format.maxFrameRate) + " fps"
    : ""

  CaptureSession {
    camera: Camera {
      id: camera
      cameraDevice: shell.device ? shell.device : mediaDevices.defaultVideoInput
      cameraFormat: shell.format
      active: shell.device !== null
      onErrorOccurred: function(error, errorString) { shell.errorText = errorString || "Camera error" }
    }
    videoOutput: video
  }

  PanelWindow {
    id: win

    anchors.right: true
    anchors.bottom: true
    margins.right: 24
    margins.bottom: 24
    implicitWidth: shell.previewWidth
    implicitHeight: header.height + Math.round(shell.previewWidth / shell.aspect)
    color: "transparent"
    exclusionMode: ExclusionMode.Ignore
    WlrLayershell.namespace: "omarchy-webcam-preview"
    WlrLayershell.layer: WlrLayer.Overlay
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.OnDemand

    Rectangle {
      id: frame
      anchors.fill: parent
      color: shell.bg
      border.color: shell.border
      border.width: 1
      clip: true

      Item {
        id: header
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: 32

        // Drag the header to move the preview around the screen.
        MouseArea {
          anchors.fill: parent
          cursorShape: Qt.SizeAllCursor
          property point last
          onPressed: function(m) { last = mapToGlobal(m.x, m.y) }
          onPositionChanged: function(m) {
            var p = mapToGlobal(m.x, m.y)
            win.margins.right = Math.max(0, win.margins.right - (p.x - last.x))
            win.margins.bottom = Math.max(0, win.margins.bottom - (p.y - last.y))
            last = p
          }
        }

        Text {
          anchors.left: parent.left
          anchors.leftMargin: 10
          anchors.right: controls.left
          anchors.rightMargin: 8
          anchors.verticalCenter: parent.verticalCenter
          textFormat: Text.PlainText
          elide: Text.ElideRight
          color: shell.fg
          font.family: shell.fontFamily
          font.pixelSize: 12
          font.bold: true
          text: shell.device ? shell.displayName : "No camera"
        }

        Row {
          id: controls
          anchors.right: parent.right
          anchors.rightMargin: 4
          anchors.verticalCenter: parent.verticalCenter
          spacing: 2

          Text {
            anchors.verticalCenter: parent.verticalCenter
            rightPadding: 6
            textFormat: Text.PlainText
            color: Qt.rgba(shell.fg.r, shell.fg.g, shell.fg.b, 0.6)
            font.family: shell.fontFamily
            font.pixelSize: 11
            text: shell.formatLabel
          }

          HeaderButton {
            label: "⇆"
            active: shell.mirrored
            onClicked: shell.mirrored = !shell.mirrored
          }
          HeaderButton {
            label: "✕"
            onClicked: Qt.quit()
          }
        }
      }

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.bottom: parent.bottom
        anchors.margins: 1
        anchors.topMargin: 0
        color: "black"

        VideoOutput {
          id: video
          anchors.fill: parent
          fillMode: VideoOutput.PreserveAspectCrop
          transform: Scale {
            origin.x: video.width / 2
            xScale: shell.mirrored ? -1 : 1
          }
        }

        Text {
          anchors.centerIn: parent
          width: parent.width - 32
          horizontalAlignment: Text.AlignHCenter
          wrapMode: Text.Wrap
          textFormat: Text.PlainText
          visible: text !== ""
          color: shell.fg
          font.family: shell.fontFamily
          font.pixelSize: 13
          text: shell.errorText !== "" ? shell.errorText
            : shell.device === null ? "Camera " + shell.requestedDevice + " not found"
            : !camera.active ? "Starting…" : ""
        }
      }
    }

    Item {
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) Qt.quit()
        else if (event.key === Qt.Key_M) shell.mirrored = !shell.mirrored
      }
    }
  }

  component HeaderButton: Rectangle {
    id: btn
    property string label: ""
    property bool active: false
    signal clicked()

    width: 26
    height: 24
    radius: 0
    color: area.containsMouse ? Qt.rgba(shell.fg.r, shell.fg.g, shell.fg.b, 0.14) : "transparent"

    Text {
      anchors.centerIn: parent
      text: btn.label
      color: btn.active ? shell.accent : shell.fg
      font.family: shell.fontFamily
      font.pixelSize: 14
    }

    MouseArea {
      id: area
      anchors.fill: parent
      hoverEnabled: true
      onClicked: btn.clicked()
    }
  }
}
