import QtQuick
import QtMultimedia
import Quickshell
import Quickshell.Io
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
//   WEBCAM_CONTROLS=1  open with the image controls panel expanded
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

  // ---------- Image controls (brightness, white balance, ...) ----------
  // Read and written through webcamctl, which remembers changes per camera.
  // Relative URLs outside the config dir resolve to nothing in Quickshell,
  // so webcamctl passes its own path in.
  readonly property string webcamctl: Quickshell.env("WEBCAMCTL") || (Quickshell.shellDir + "/../bin/webcamctl")
  readonly property string controlDevice: device ? String(device.id) : ""
  property bool showControls: Quickshell.env("WEBCAM_CONTROLS") === "1"
  property var cameraControls: []
  property var pendingControls: ({})
  property string controlsError: ""
  readonly property int controlsHeight: Math.min(320, controlsColumn.implicitHeight + 16)

  function loadControls() {
    if (controlDevice === "" || listControlsProc.running) return
    listControlsProc.command = [webcamctl, "controls", controlDevice]
    listControlsProc.running = true
  }

  // Sliders fire continuously while dragged; batch the latest value per
  // control and send them at most every ~100ms.
  function queueControl(name, value) {
    pendingControls[name] = Math.round(value)
    if (!flushTimer.running) flushTimer.start()
  }

  function flushControls() {
    if (setControlsProc.running) { flushTimer.start(); return }
    var args = [webcamctl, "set-controls", controlDevice]
    for (var name in pendingControls) args.push(name + "=" + pendingControls[name])
    pendingControls = ({})
    if (args.length === 3) return
    setControlsProc.command = args
    setControlsProc.running = true
  }

  function resetControls() {
    if (setControlsProc.running) return
    pendingControls = ({})
    setControlsProc.command = [webcamctl, "reset-controls", controlDevice]
    setControlsProc.running = true
  }

  onControlDeviceChanged: loadControls()

  Timer { id: flushTimer; interval: 100; onTriggered: shell.flushControls() }

  Process {
    id: listControlsProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var parsed = JSON.parse(text)
          shell.cameraControls = Array.isArray(parsed) ? parsed : []
        } catch (e) {
          shell.cameraControls = []
        }
      }
    }
  }

  Process {
    id: setControlsProc
    stderr: StdioCollector { id: setControlsErr; waitForEnd: true }
    // Re-read afterwards: switching an auto mode enables or disables the
    // matching manual control.
    onExited: function(code) {
      var err = setControlsErr.text.trim()
      shell.controlsError = err === "" ? "" : err.split("\n").pop().replace(/^webcamctl: /, "")
      shell.loadControls()
    }
  }

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
    implicitHeight: header.height + videoArea.height + (shell.showControls ? shell.controlsHeight : 0)
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
            label: "\u{F0493}"
            active: shell.showControls
            visible: shell.cameraControls.length > 0
            onClicked: shell.showControls = !shell.showControls
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
        id: videoArea
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: header.bottom
        anchors.leftMargin: 1
        anchors.rightMargin: 1
        height: Math.round(shell.previewWidth / shell.aspect)
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

    Flickable {
      id: controlsPanel
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.bottom: parent.bottom
      anchors.margins: 1
      height: shell.showControls ? shell.controlsHeight - 1 : 0
      visible: shell.showControls
      clip: true
      contentHeight: controlsColumn.implicitHeight + 16
      boundsBehavior: Flickable.StopAtBounds

      Column {
        id: controlsColumn
        x: 12
        y: 8
        width: controlsPanel.width - 24
        spacing: 10

        Repeater {
          model: shell.cameraControls
          ControlRow {
            required property var modelData
            width: controlsColumn.width
            control: modelData
          }
        }

        Item {
          width: parent.width
          height: 24

          Text {
            anchors.left: parent.left
            anchors.right: resetButton.left
            anchors.rightMargin: 8
            anchors.verticalCenter: parent.verticalCenter
            textFormat: Text.PlainText
            elide: Text.ElideRight
            color: shell.controlsError !== "" ? shell.accent : Qt.rgba(shell.fg.r, shell.fg.g, shell.fg.b, 0.5)
            font.family: shell.fontFamily
            font.pixelSize: 10
            text: shell.controlsError !== "" ? shell.controlsError : "Saved for this camera · double-click a name to reset it"
          }

          Chip {
            id: resetButton
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            label: "Reset all"
            onClicked: shell.resetControls()
          }
        }
      }
    }

    Item {
      anchors.fill: parent
      focus: true
      Keys.onPressed: function(event) {
        if (event.key === Qt.Key_Escape || event.key === Qt.Key_Q) Qt.quit()
        else if (event.key === Qt.Key_M) shell.mirrored = !shell.mirrored
        else if (event.key === Qt.Key_C && shell.cameraControls.length > 0) shell.showControls = !shell.showControls
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

  // One control: a slider for ranges, a switch for on/off, chips for menus.
  // Controls the driver marks inactive (e.g. exposure time while exposure is
  // automatic) are shown dimmed and cannot be changed.
  component ControlRow: Column {
    id: ctl
    property var control: ({})
    readonly property bool editable: control.inactive !== true
    readonly property string valueText: {
      if (control.type === "bool") return ""
      if (control.type === "menu") return ""
      return String(slider.shownValue)
    }

    spacing: 4
    opacity: editable ? 1 : 0.4

    Item {
      width: parent.width
      height: 16

      Text {
        anchors.left: parent.left
        anchors.verticalCenter: parent.verticalCenter
        textFormat: Text.PlainText
        color: shell.fg
        font.family: shell.fontFamily
        font.pixelSize: 11
        text: ctl.control.label + (ctl.control.value !== ctl.control.default ? " •" : "")

        MouseArea {
          anchors.fill: parent
          enabled: ctl.editable
          onDoubleClicked: shell.queueControl(ctl.control.name, ctl.control.default)
        }
      }

      Text {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: ctl.control.type === "int"
        textFormat: Text.PlainText
        color: Qt.rgba(shell.fg.r, shell.fg.g, shell.fg.b, 0.6)
        font.family: shell.fontFamily
        font.pixelSize: 11
        text: ctl.valueText
      }

      Switch {
        anchors.right: parent.right
        anchors.verticalCenter: parent.verticalCenter
        visible: ctl.control.type === "bool"
        checked: ctl.control.value !== 0
        enabled: ctl.editable
        onToggled: shell.queueControl(ctl.control.name, checked ? 0 : 1)
      }
    }

    Slider {
      id: slider
      width: parent.width
      visible: ctl.control.type === "int"
      enabled: ctl.editable
      from: ctl.control.min
      to: ctl.control.max
      step: Math.max(1, ctl.control.step)
      value: ctl.control.value
      defaultValue: ctl.control.default
      onMoved: function(v) { shell.queueControl(ctl.control.name, v) }
    }

    Flow {
      width: parent.width
      spacing: 4
      visible: ctl.control.type === "menu"

      Repeater {
        model: ctl.control.type === "menu" ? ctl.control.options : []
        Chip {
          required property var modelData
          label: modelData.label
          active: ctl.control.value === modelData.value
          enabled: ctl.editable
          onClicked: shell.queueControl(ctl.control.name, modelData.value)
        }
      }
    }
  }

  component Slider: Item {
    id: sl
    property real from: 0
    property real to: 100
    property real step: 1
    property real value: 0
    property real defaultValue: 0
    property real dragValue: 0
    readonly property bool dragging: dragArea.pressed
    readonly property real shownValue: dragging ? dragValue : value
    readonly property real span: Math.max(1, to - from)
    signal moved(real v)

    function snap(v) {
      v = Math.max(from, Math.min(to, v))
      return from + Math.round((v - from) / step) * step
    }
    function valueAt(x) { return snap(from + (x / width) * span) }
    function fraction(v) { return (v - from) / span }

    height: 16

    Rectangle {
      id: track
      anchors.verticalCenter: parent.verticalCenter
      width: parent.width
      height: 4
      color: Qt.rgba(shell.fg.r, shell.fg.g, shell.fg.b, 0.15)
    }

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      width: Math.max(0, Math.min(1, sl.fraction(sl.shownValue))) * parent.width
      height: 4
      color: shell.accent
    }

    // Tick where the driver default sits, so "back to normal" is findable.
    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      x: sl.fraction(sl.defaultValue) * (parent.width - width)
      width: 2
      height: 10
      color: Qt.rgba(shell.fg.r, shell.fg.g, shell.fg.b, 0.35)
    }

    Rectangle {
      anchors.verticalCenter: parent.verticalCenter
      x: Math.max(0, Math.min(1, sl.fraction(sl.shownValue))) * (parent.width - width)
      width: 10
      height: 14
      color: dragArea.pressed || dragArea.containsMouse ? shell.accent : shell.fg
    }

    MouseArea {
      id: dragArea
      anchors.fill: parent
      anchors.margins: -4
      enabled: sl.enabled
      hoverEnabled: true
      cursorShape: sl.enabled ? Qt.PointingHandCursor : Qt.ArrowCursor
      function update(mx) {
        var v = sl.valueAt(mx - 4)
        if (v !== sl.dragValue || !pressed) { sl.dragValue = v; sl.moved(v) }
      }
      onPressed: function(m) { sl.dragValue = sl.value; update(m.x) }
      onPositionChanged: function(m) { if (pressed) update(m.x) }
      onWheel: function(w) {
        var coarse = Math.max(sl.step, sl.snap(sl.from + sl.span / 50) - sl.from)
        var v = sl.snap(sl.value + (w.angleDelta.y > 0 ? coarse : -coarse))
        if (v !== sl.value) sl.moved(v)
      }
    }
  }

  component Switch: Rectangle {
    id: sw
    property bool checked: false
    signal toggled()

    width: 30
    height: 16
    color: checked ? shell.accent : Qt.rgba(shell.fg.r, shell.fg.g, shell.fg.b, 0.2)

    Rectangle {
      width: 12
      height: 12
      y: 2
      x: sw.checked ? sw.width - width - 2 : 2
      color: shell.bg
      Behavior on x { NumberAnimation { duration: 120 } }
    }

    MouseArea {
      anchors.fill: parent
      enabled: sw.enabled
      cursorShape: Qt.PointingHandCursor
      onClicked: sw.toggled()
    }
  }

  component Chip: Rectangle {
    id: chip
    property string label: ""
    property bool active: false
    signal clicked()

    width: chipText.implicitWidth + 16
    height: 22
    color: active ? Qt.rgba(shell.accent.r, shell.accent.g, shell.accent.b, 0.22)
      : chipArea.containsMouse ? Qt.rgba(shell.fg.r, shell.fg.g, shell.fg.b, 0.1) : "transparent"
    border.width: 1
    border.color: active ? shell.accent : Qt.rgba(shell.fg.r, shell.fg.g, shell.fg.b, 0.25)

    Text {
      id: chipText
      anchors.centerIn: parent
      textFormat: Text.PlainText
      text: chip.label
      color: chip.active ? shell.accent : shell.fg
      font.family: shell.fontFamily
      font.pixelSize: 11
    }

    MouseArea {
      id: chipArea
      anchors.fill: parent
      enabled: chip.enabled
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: chip.clicked()
    }
  }
}
