import Quickshell
import QtQuick
import qs.Ui
import qs.Commons

// Loads the real Webcam.qml the way the bar hosts a third-party widget (a
// qs.Ui PluginBarApi), opens the popup and walks the About page, then prints
// one RESULT line of JSON for test/panel.test.sh. Run only through that
// script. It never presses Email or Copy (no mail app, no clipboard) and never
// starts a preview, so no camera is opened.
ShellRoot {
  id: h

  readonly property string pluginDir: Quickshell.env("WEBCAM_PLUGIN")
  readonly property string versionRe: "@MANIFEST_VERSION_RE@"
  property var results: []
  property var w: widgetLoader.item

  function check(name, cond, detail) {
    var next = h.results.slice()
    next.push({ name: name, ok: !!cond, detail: String(detail === undefined ? "" : detail) })
    h.results = next
  }

  function finish() {
    console.log("RESULT " + JSON.stringify(h.results))
    Qt.quit()
  }

  // Depth-first search of the object tree, through popup windows and loaders.
  function find(obj, pred, seen) {
    if (!obj) return null
    seen = seen || []
    if (seen.indexOf(obj) >= 0) return null
    seen.push(obj)
    if (pred(obj)) return obj
    var kids = []
    try { if (obj.children) for (var i = 0; i < obj.children.length; i++) kids.push(obj.children[i]) } catch (e) {}
    try { if (obj.data) for (var j = 0; j < obj.data.length; j++) kids.push(obj.data[j]) } catch (e) {}
    try { if (obj.contentItem) kids.push(obj.contentItem) } catch (e) {}
    try { if (obj.item) kids.push(obj.item) } catch (e) {}
    for (var k = 0; k < kids.length; k++) {
      var found = find(kids[k], pred, seen)
      if (found) return found
    }
    return null
  }

  function byName(name) { return h.find(h.w, function(o) { return o.objectName === name }) }

  PluginBarApi {
    id: hostBar
    pluginId: "ninepointlabs.webcam"
    moduleName: "ninepointlabs.webcam"
    shell: hostShell
    foreground: "#cacccc"
    barForeground: "#cacccc"
    background: "#101315"
    urgent: "#a55555"
    barSize: 26
    _moduleWidgets: function(id) { return widgetLoader.item ? [widgetLoader.item] : [] }
    _switchPanelFrom: function(owner, direction) { return false }
    _targetBelongsToWindow: function(target, window) { return false }
  }

  QtObject {
    id: hostShell
    function serviceFor(id) { return null }
    function updateEntryInline(id, entry) { return false }
  }

  Loader {
    id: widgetLoader
    source: "file://" + h.pluginDir + "/Webcam.qml"
    onLoaded: {
      item.bar = hostBar
      item.settings = { previewWidth: 480, showIr: true }
    }
    onStatusChanged: if (status === Loader.Error) { h.check("Webcam.qml loads", false); h.finish() }
  }

  readonly property var steps: [
    function() {
      h.check("Webcam.qml loads", !!h.w)
      h.w.open()
    },
    function() {
      var aboutButton = h.byName("aboutButton")
      h.check("About button in the popup header", !!aboutButton && aboutButton.visible)
      h.check("About hidden at first", h.w.showAbout === false && !h.byName("aboutVersion").visible)
      aboutButton.clicked()
      h.check("About button opens the About page", h.w.showAbout === true && h.byName("aboutVersion").visible
        && !h.byName("aboutButton").visible)
    },
    function() {
      var version = h.byName("aboutVersion").text
      h.check("About shows the manifest version", new RegExp("^Version " + h.versionRe + "$").test(version), version)
      h.check("About states privacy", String(h.byName("aboutPrivacy").text).indexOf("no network access") >= 0)
      h.check("About credits Nine Point Labs", !!h.find(h.w, function(o) { return o.text === "Nine Point Labs" && o.visible }))
      h.check("About lists the support address", !!h.find(h.w, function(o) { return o.text === "help@ninepointlabs.com" && o.visible }))
      h.check("Copy version details button", !!h.byName("aboutCopyDetails"))
      var view = h.find(h.w, function(o) { return typeof o.backRequested === "function" && o.details !== undefined })
      h.check("details name the versions", !!view && new RegExp("^Omarchy Webcam " + h.versionRe + "\\nQuickshell 0\\.\\d+, Qt 6\\.\\d+\\n").test(view.details),
        view ? view.details : "")
      h.check("license text hidden at first", !h.byName("aboutLicenseText").visible)
      h.byName("aboutLicense").clicked()
    },
    function() {
      var text = h.byName("aboutLicenseText")
      h.check("license text readable", text.visible && String(text.text).indexOf("MIT License\n\nCopyright (c) 2026 Nine Point Labs") === 0,
        String(text.text).substring(0, 60))
      h.byName("aboutBack").clicked()
      h.check("Back returns to the cameras", h.w.showAbout === false && h.byName("aboutButton").visible
        && !h.byName("aboutVersion").visible)
      h.check("Back hides the license again", !h.byName("aboutLicenseText").visible)
      h.w.close()
    },
    function() {
      var ipc = h.find(h.w, function(o) { return typeof o.about === "function" && typeof o.stopPreview === "function" })
      h.check("IPC handler has about()", !!ipc)
      if (ipc) ipc.about()
      h.check("IPC about opens the popup on About", h.w.opened === true && h.w.showAbout === true)
      h.w.close()
      h.check("closing the popup leaves About", h.w.showAbout === false)
      h.finish()
    }
  ]

  property int step: 0
  Timer {
    interval: 400
    running: true
    repeat: true
    onTriggered: {
      if (!h.w) return
      if (h.step >= h.steps.length) { stop(); return }
      try {
        h.steps[h.step++]()
      } catch (e) {
        h.check("step " + h.step + " ran", false, e)
        h.finish()
      }
    }
  }
}
