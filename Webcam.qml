import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar widget: pick the system (PipeWire default) camera and open a live
// preview. All device discovery and switching goes through bin/webcamctl;
// the preview runs in its own process so a stuck camera driver can't hang
// the shell.
Panel {
  id: root
  moduleName: "ninepointlabs.webcam"
  ipcTarget: "ninepointlabs.webcam"
  manageIpc: false

  property var cameras: []
  property int selectedIndex: 0
  property bool cursorActive: false
  property bool previewRunning: false
  property string lastError: ""
  property var knownDevices: []

  readonly property string webcamctl: String(Qt.resolvedUrl("bin/webcamctl")).replace(/^file:\/\//, "")
  readonly property bool showIr: setting("showIr", true) === true
  readonly property int previewWidth: Math.max(240, Math.min(1280, Number(setting("previewWidth", 480)) || 480))
  readonly property var visibleCameras: cameras.filter(function(c) { return root.showIr || !c.ir })
  readonly property var defaultCamera: {
    for (var i = 0; i < cameras.length; i++) if (cameras[i].default) return cameras[i]
    return null
  }
  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color dim: Qt.darker(foreground, 1.4)

  readonly property string glyphWebcam: "\u{F05A0}"
  readonly property string glyphCamera: "\u{F0100}"
  readonly property string glyphPreview: "\u{F0567}"
  readonly property string glyphStop: "\u{F04DB}"
  readonly property string glyphSettings: "\u{F0493}"

  function refresh() {
    if (!listProc.running) listProc.running = true
    if (!statusProc.running) statusProc.running = true
  }

  function parseCameras(text) {
    try {
      var parsed = JSON.parse(text)
      if (!Array.isArray(parsed)) throw new Error("expected a JSON array")
      // Keep only the fields we render, as plain strings/numbers.
      cameras = parsed.slice(0, 32).map(function(c) {
        return {
          id: Number(c.id),
          label: String(c.label || c.name || "Camera"),
          device: String(c.device || ""),
          ir: c.ir === true,
          default: c.default === true
        }
      })
      lastError = ""
      restoreNewCameras()
    } catch (e) {
      lastError = "Could not read camera list"
    }
    if (selectedIndex >= visibleCameras.length) selectedIndex = Math.max(0, visibleCameras.length - 1)
  }

  // Image controls reset when a camera is plugged in (or at boot); reapply
  // the ones saved by webcamctl whenever a camera we haven't seen shows up.
  function restoreNewCameras() {
    var devices = cameras.map(function(c) { return c.device })
    var appeared = devices.some(function(d) { return knownDevices.indexOf(d) < 0 })
    knownDevices = devices
    if (appeared && !restoreProc.running) restoreProc.running = true
  }

  function run(args) {
    if (actionProc.running) return
    actionProc.command = [webcamctl].concat(args)
    actionProc.running = true
  }

  function setDefault(camera) {
    if (!camera || camera.default) return
    run(["set-default", String(camera.id)])
  }

  // With no camera, webcamctl previews whatever is the default right now.
  function preview(camera, withControls) {
    previewProc.command = camera ? [webcamctl, "preview", camera.device] : [webcamctl, "preview"]
    previewProc.environment = {
      WEBCAM_NAME: camera ? camera.label : "",
      WEBCAM_FG: String(Color.popups.text),
      WEBCAM_BG: String(Color.popups.background),
      WEBCAM_ACCENT: String(Color.accent),
      WEBCAM_BORDER: String(Color.popups.border),
      WEBCAM_FONT: root.fontFamily,
      WEBCAM_WIDTH: String(root.previewWidth),
      WEBCAM_CONTROLS: withControls === true ? "1" : "0"
    }
    previewProc.running = true
  }

  function stopPreview() { run(["stop-preview"]) }

  function moveCursor(delta) {
    var n = visibleCameras.length
    if (n === 0) return
    if (!cursorActive) { cursorActive = true; return }
    selectedIndex = (selectedIndex + delta + n) % n
  }

  IpcHandler {
    target: "ninepointlabs.webcam"

    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    // Preview the current default camera without opening the popup.
    function preview(): void { root.preview(null) }
    function stopPreview(): void { root.stopPreview() }
    // Preview the default camera with its image controls expanded.
    function settings(): void { root.preview(null, true) }
  }

  onOpenedChanged: {
    if (!opened) return
    refresh()
    cursorActive = false
    var idx = visibleCameras.indexOf(defaultCamera)
    selectedIndex = idx >= 0 ? idx : 0
  }

  Component.onCompleted: refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Process {
    id: listProc
    command: [root.webcamctl, "list"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.parseCameras(text) }
    onExited: function(code) { if (code !== 0) root.lastError = "webcamctl list failed" }
  }

  Process {
    id: statusProc
    command: [root.webcamctl, "preview-running"]
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.previewRunning = text.trim() === "true" }
  }

  Process {
    id: restoreProc
    command: [root.webcamctl, "restore"]
  }

  Process {
    id: actionProc
    stderr: StdioCollector { id: actionErr; waitForEnd: true }
    onExited: function(code) {
      root.lastError = code === 0 ? "" : (actionErr.text.trim().split("\n").pop() || "Command failed")
      root.refresh()
    }
  }

  Process {
    id: previewProc
    stderr: StdioCollector { id: previewErr; waitForEnd: true }
    onExited: function(code) {
      root.lastError = code === 0 ? "" : (previewErr.text.trim().split("\n").pop() || "Preview failed")
      root.refresh()
    }
  }

  // Cameras come and go (USB hotplug); keep the list fresh while visible.
  Timer { interval: 3000; running: root.opened; repeat: true; onTriggered: root.refresh() }
  // Occasional background refresh keeps the bar tooltip honest and notices
  // replugged cameras so their saved image controls come back.
  Timer { interval: 10000; running: !root.opened; repeat: true; onTriggered: root.refresh() }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyphWebcam
    active: root.previewRunning
    tooltipText: root.defaultCamera ? "Camera: " + root.defaultCamera.label : "Webcam"
    onPressed: function(b) {
      if (b === Qt.RightButton) root.previewRunning ? root.stopPreview() : root.preview(null)
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(380))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) { root.moveCursor(dy !== 0 ? dy : dx) }
      onActivateRequested: if (root.cursorActive) root.setDefault(root.visibleCameras[root.selectedIndex])
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        if (t === "p") root.preview(root.cursorActive ? root.visibleCameras[root.selectedIndex] : null)
        else if (t === "a") root.preview(root.cursorActive ? root.visibleCameras[root.selectedIndex] : null, true)
        else if (t === "s") root.stopPreview()
        else if (t === "r") root.refresh()
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(14)

        // ---------- Hero ----------
        Item {
          width: parent.width
          implicitHeight: Math.max(heroIcon.implicitHeight, heroLabels.implicitHeight)

          Text {
            id: heroIcon
            textFormat: Text.PlainText
            text: root.glyphWebcam
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.display
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
          }

          Column {
            id: heroLabels
            anchors.left: heroIcon.right
            anchors.leftMargin: Style.space(14)
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            spacing: Style.space(2)

            Text {
              textFormat: Text.PlainText
              text: root.defaultCamera ? root.defaultCamera.label : "Webcam"
              color: root.foreground
              font.family: root.fontFamily
              font.pixelSize: Style.font.title
              font.bold: true
              elide: Text.ElideRight
              width: parent.width
            }

            Text {
              textFormat: Text.PlainText
              text: root.lastError !== "" ? root.lastError.toUpperCase()
                : root.previewRunning ? "PREVIEW OPEN"
                : root.cameras.length === 0 ? "NO CAMERAS FOUND"
                : "SYSTEM CAMERA"
              color: root.lastError !== "" ? Color.urgent : root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
              font.bold: true
              font.letterSpacing: 1.2
              elide: Text.ElideRight
              width: parent.width
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        // ---------- Camera list ----------
        Column {
          width: parent.width
          spacing: Style.space(4)

          PanelSectionHeader {
            text: "CAMERAS"
            foreground: root.foreground
            fontFamily: root.fontFamily
          }

          Repeater {
            model: root.visibleCameras
            CameraRow {
              required property var modelData
              required property int index
              width: parent.width
              camera: modelData
              rowIndex: index
            }
          }
        }

        // ---------- Actions ----------
        Row {
          id: actionRow
          width: parent.width
          spacing: Style.space(6)
          readonly property real cellWidth: (width - spacing) / 2

          Button {
            width: actionRow.cellWidth
            iconText: root.previewRunning ? root.glyphStop : root.glyphPreview
            text: root.previewRunning ? "Stop preview" : "Preview"
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            enabled: root.previewRunning || root.defaultCamera !== null
            onClicked: root.previewRunning ? root.stopPreview() : root.preview(null)
          }

          Button {
            width: actionRow.cellWidth
            iconText: "\u{F0450}"
            text: "Refresh"
            fontSize: Style.font.bodySmall
            foreground: root.foreground
            fontFamily: root.fontFamily
            bordered: true
            onClicked: root.refresh()
          }
        }
      }
    }
  }

  // One camera: click the row to make it the system camera, click the
  // preview glyph to watch it.
  component CameraRow: CursorSurface {
    id: row
    property var camera: ({})
    property int rowIndex: 0

    hasCursor: root.cursorActive && root.selectedIndex === rowIndex
    current: camera.default === true
    foreground: root.foreground
    implicitHeight: rowInner.implicitHeight + Style.spacing.xl
    opacity: camera.ir ? 0.7 : 1

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: if (containsMouse) {
        root.cursorActive = true
        root.selectedIndex = row.rowIndex
      }
      onClicked: root.setDefault(row.camera)
    }

    Row {
      id: rowInner
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(6)
      anchors.rightMargin: Style.space(4)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: row.camera.default ? root.glyphWebcam : root.glyphCamera
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        width: Style.space(22)
        horizontalAlignment: Text.AlignHCenter
        anchors.verticalCenter: parent.verticalCenter
      }

      Column {
        width: parent.width - Style.space(22) - previewButton.width - settingsButton.width - parent.spacing * 3
        anchors.verticalCenter: parent.verticalCenter
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          text: row.camera.label
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          font.bold: row.camera.default === true
          elide: Text.ElideRight
          width: parent.width
        }

        Text {
          textFormat: Text.PlainText
          text: row.camera.device + (row.camera.ir ? " · infrared" : "") + (row.camera.default ? " · default" : "")
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
          width: parent.width
        }
      }

      Button {
        id: settingsButton
        anchors.verticalCenter: parent.verticalCenter
        iconText: root.glyphSettings
        iconSize: Style.font.title
        tooltipText: "Image settings"
        foreground: root.foreground
        fontFamily: root.fontFamily
        horizontalPadding: Style.space(6)
        onClicked: root.preview(row.camera, true)
      }

      Button {
        id: previewButton
        anchors.verticalCenter: parent.verticalCenter
        iconText: root.glyphPreview
        iconSize: Style.font.title
        tooltipText: "Preview"
        foreground: root.foreground
        fontFamily: root.fontFamily
        horizontalPadding: Style.space(6)
        onClicked: root.preview(row.camera)
      }
    }
  }
}
