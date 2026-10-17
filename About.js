// Facts and text for the About page (AboutView.qml), kept out of QML so node
// can check them against the repo (test/about.test.cjs).
//
// The version comes from manifest.json and the license from LICENSE at run
// time, so neither is copied here and neither can drift from the real file.

var NAME = "Omarchy Webcam"
var TAGLINE = "Pick your system camera, preview it live and tune its image settings, from the bar."
var ORGANIZATION = "Nine Point Labs"
var CREATED = "September 2026" // first commit: 2026-09-26
var SUPPORT_EMAIL = "help@ninepointlabs.com"

// Must stay true to what the plugin does. Camera: only preview/shell.qml
// opens it (QtMultimedia CaptureSession -> VideoOutput, no ImageCapture or
// recorder). bin/webcamctl talks to pw-dump/wpctl and v4l2-ctl, writes saved
// controls under ~/.local/state/omarchy-webcam/controls/ and a pid file under
// $XDG_RUNTIME_DIR. No network code anywhere (test/about.test.cjs checks).
var PRIVACY = "No accounts, no telemetry and no network access. Video is only captured while a "
  + "preview window is showing, and the picture goes to that window and nowhere else: nothing is "
  + "recorded, photographed or saved. Listing cameras and changing image settings only ask the "
  + "driver (pw-dump, v4l2-ctl), never for a picture. Your camera choice is set with wpctl and kept by WirePlumber. "
  + "Image settings you change are saved per camera in ~/.local/state/omarchy-webcam/controls/ "
  + "(only the values that differ from the driver defaults); widget settings stay in "
  + "~/.config/omarchy/shell.json."

// "0.2.0" from manifest.json's text, or "" when it can't be read.
function manifestVersion(text) {
  try {
    var v = JSON.parse(String(text || "")).version
    return typeof v === "string" && /^[0-9A-Za-z.+-]{1,32}$/.test(v) ? v : ""
  } catch (e) {
    return ""
  }
}

// "MIT License, © 2026 Nine Point Labs" from LICENSE's text: its first line
// plus its copyright line, as written there.
function licenseSummary(text) {
  var lines = String(text || "").split("\n")
  var name = ""
  var holder = ""
  for (var i = 0; i < lines.length; i++) {
    var line = lines[i].trim()
    if (line === "") continue
    if (name === "") name = line
    var m = /^Copyright\s+(?:\(c\)|©)\s*(.+)$/i.exec(line)
    if (m) { holder = "© " + m[1]; break }
  }
  return holder ? name + ", " + holder : name
}

// LICENSE with one line per paragraph, so it wraps to the panel's width.
function licenseBody(text) {
  var paras = String(text || "").replace(/\r/g, "").split(/\n\s*\n/)
  var out = []
  for (var i = 0; i < paras.length; i++) {
    var p = paras[i].split(/\s+/).join(" ").trim()
    if (p !== "") out.push(p)
  }
  return out.join("\n\n")
}

// Highest minor version `has(major, minor)` accepts, as "major.minor"
// (Quickshell.hasVersion / hasQtVersion only answer yes or no), or "".
function probedVersion(has, major) {
  if (typeof has !== "function" || !has(major, 0)) return ""
  var minor = 0
  while (minor < 99 && has(major, minor + 1)) minor++
  return major + "." + minor
}

function builtWith(quickshell, qt) {
  var out = []
  if (quickshell) out.push("Quickshell " + quickshell)
  if (qt) out.push("Qt " + qt)
  return out.length ? out.join(", ") : "Quickshell and Qt"
}

// Version details to paste into a support email.
function details(version, quickshell, qt, desktop) {
  return NAME + " " + (version || "unknown version") + "\n"
    + builtWith(quickshell, qt) + "\n"
    + (desktop || "unknown desktop")
}

function mailto(version, detailText) {
  return "mailto:" + SUPPORT_EMAIL
    + "?subject=" + encodeURIComponent(NAME + " " + (version || ""))
    + "&body=" + encodeURIComponent("\n\n--\n" + detailText)
}

if (typeof module !== "undefined") {
  module.exports = {
    NAME: NAME, TAGLINE: TAGLINE, ORGANIZATION: ORGANIZATION, CREATED: CREATED,
    SUPPORT_EMAIL: SUPPORT_EMAIL, PRIVACY: PRIVACY,
    manifestVersion: manifestVersion, licenseSummary: licenseSummary, licenseBody: licenseBody,
    probedVersion: probedVersion, builtWith: builtWith, details: details, mailto: mailto
  }
}
