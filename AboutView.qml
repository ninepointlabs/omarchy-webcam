import QtQuick
import Quickshell
import qs.Commons
import qs.Ui
import "About.js" as About

// The popup's About page: who made the widget, its version and license,
// where to get help, and what it does with your data. Webcam.qml swaps it in
// for the camera list (info button, `i`, or the `about` IPC call).
Column {
  id: root

  property color foreground: Color.foreground
  property color accent: Color.accent
  property string fontFamily: Style.font.family
  property string version: ""
  property string licenseText: ""
  property bool showLicense: false
  property string notice: ""

  signal backRequested()

  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string quickshellVersion: About.probedVersion(function(a, b) { return Quickshell.hasVersion(a, b) }, 0)
  readonly property string qtVersion: About.probedVersion(function(a, b) { return Quickshell.hasQtVersion(a, b) }, 6)
  readonly property string details: About.details(root.version, root.quickshellVersion, root.qtVersion,
    (Quickshell.env("XDG_CURRENT_DESKTOP") || "unknown desktop") + ", " + Qt.platform.pluginName)
  readonly property real labelWidth: Style.space(80)

  function copy(text, what) {
    Quickshell.clipboardText = text
    root.notice = what + " copied"
    noticeTimer.restart()
  }

  spacing: Style.space(12)
  onVisibleChanged: if (!visible) { root.showLicense = false; root.notice = "" }

  Timer { id: noticeTimer; interval: 2500; onTriggered: root.notice = "" }

  component Label: Text {
    width: root.labelWidth
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
    font.bold: true
    font.letterSpacing: 1.2
  }

  component Value: Text {
    textFormat: Text.PlainText
    wrapMode: Text.WordWrap
    color: root.foreground
    font.family: root.fontFamily
    font.pixelSize: Style.font.bodySmall
  }

  Item {
    width: parent.width
    height: backButton.implicitHeight

    Button {
      id: backButton
      objectName: "aboutBack"
      iconText: "󰁍"
      text: "Back"
      tooltipText: "Back to cameras (Esc)"
      foreground: root.foreground
      accent: root.accent
      fontFamily: root.fontFamily
      fontSize: Style.font.bodySmall
      onClicked: root.backRequested()
    }
  }

  Row {
    width: parent.width
    spacing: Style.space(14)

    Text {
      id: appIcon
      textFormat: Text.PlainText
      text: "\u{F05A0}"
      color: root.accent
      font.family: root.fontFamily
      font.pixelSize: Style.font.display
      anchors.verticalCenter: parent.verticalCenter
    }

    Column {
      width: parent.width - appIcon.width - parent.spacing
      spacing: Style.space(3)
      anchors.verticalCenter: parent.verticalCenter

      Text {
        textFormat: Text.PlainText
        text: About.NAME
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.title
        font.bold: true
      }
      Value { width: parent.width; text: About.TAGLINE }
      Text {
        objectName: "aboutVersion"
        textFormat: Text.PlainText
        text: "Version " + (root.version || "unknown")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  PanelSeparator { foreground: root.foreground }

  Grid {
    id: facts
    width: parent.width
    columns: 2
    columnSpacing: Style.space(10)
    rowSpacing: Style.space(8)
    readonly property real valueWidth: width - root.labelWidth - columnSpacing

    Label { text: "MADE BY" }
    Value { width: facts.valueWidth; text: About.ORGANIZATION }

    Label { text: "CREATED" }
    Value { width: facts.valueWidth; text: About.CREATED }

    Label { text: "LICENSE" }
    Column {
      width: facts.valueWidth
      spacing: Style.space(4)
      Value { width: parent.width; text: About.licenseSummary(root.licenseText) || "MIT License" }
      Button {
        objectName: "aboutLicense"
        text: root.showLicense ? "Hide license" : "Read license"
        bordered: true
        foreground: root.foreground
        accent: root.accent
        fontFamily: root.fontFamily
        fontSize: Style.font.caption
        onClicked: root.showLicense = !root.showLicense
      }
    }

    Label { text: "SUPPORT" }
    Column {
      width: facts.valueWidth
      spacing: Style.space(4)
      Value { width: parent.width; text: About.SUPPORT_EMAIL }
      Flow {
        width: parent.width
        spacing: Style.space(6)
        Button {
          text: "Email"
          tooltipText: "Opens your mail app with the version details filled in"
          bordered: true
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          onClicked: Qt.openUrlExternally(About.mailto(root.version, root.details))
        }
        Button {
          text: "Copy"
          tooltipText: "Copy the address"
          bordered: true
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          onClicked: root.copy(About.SUPPORT_EMAIL, "Address")
        }
        Button {
          objectName: "aboutCopyDetails"
          text: "Copy version details"
          bordered: true
          foreground: root.foreground
          accent: root.accent
          fontFamily: root.fontFamily
          fontSize: Style.font.caption
          onClicked: root.copy(root.details, "Version details")
        }
      }
    }

    Label { text: "PRIVACY" }
    Value { objectName: "aboutPrivacy"; width: facts.valueWidth; font.pixelSize: Style.font.caption; text: About.PRIVACY }

    Label { text: "BUILT WITH" }
    Value { width: facts.valueWidth; color: root.dim; font.pixelSize: Style.font.caption; text: About.builtWith(root.quickshellVersion, root.qtVersion) }
  }

  Text {
    width: parent.width
    visible: root.notice !== ""
    horizontalAlignment: Text.AlignRight
    text: root.notice
    color: root.dim
    font.family: root.fontFamily
    font.pixelSize: Style.font.caption
  }

  Rectangle {
    width: parent.width
    height: Style.space(150)
    visible: root.showLicense
    color: "transparent"
    radius: Style.cornerRadius
    border.width: 1
    border.color: Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.25)

    Flickable {
      id: licenseView
      anchors.fill: parent
      anchors.margins: Style.space(8)
      clip: true
      contentHeight: licenseBody.implicitHeight
      boundsBehavior: Flickable.StopAtBounds

      Text {
        id: licenseBody
        objectName: "aboutLicenseText"
        width: licenseView.width
        wrapMode: Text.WordWrap
        textFormat: Text.PlainText
        text: About.licenseBody(root.licenseText) || "LICENSE could not be read from the plugin folder."
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }
}
