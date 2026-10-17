// Node test runner (`node --test test/about.test.cjs`) for the About page's
// facts: they come from the repo's own files (manifest.json, LICENSE, git
// history), so these check About.js against the real files.
const test = require("node:test")
const assert = require("node:assert/strict")
const fs = require("node:fs")
const path = require("node:path")
const { execFileSync } = require("node:child_process")
const About = require("../About.js")

const ROOT = path.join(__dirname, "..")
const read = (name) => fs.readFileSync(path.join(ROOT, name), "utf8")

test("version comes from manifest.json", () => {
  const manifest = JSON.parse(read("manifest.json"))
  assert.equal(About.manifestVersion(read("manifest.json")), manifest.version)
  assert.match(About.manifestVersion(read("manifest.json")), /^\d+\.\d+\.\d+$/)
  assert.equal(About.manifestVersion("not json"), "")
  assert.equal(About.manifestVersion('{"version":"1.0 <b>"}'), "")
  assert.equal(manifest.author, "Nine Point Labs")
})

test("license summary and text come from LICENSE", () => {
  const text = read("LICENSE")
  assert.equal(About.licenseSummary(text), "MIT License, © 2026 Nine Point Labs")
  const body = About.licenseBody(text)
  assert.ok(body.startsWith("MIT License\n\nCopyright (c) 2026 Nine Point Labs\n\nPermission is hereby granted"))
  assert.ok(body.includes("THE SOFTWARE IS PROVIDED \"AS IS\""))
  assert.ok(!body.includes("a copy\nof"), "one line per paragraph")
})

test("facts: Nine Point Labs, created date, support address", () => {
  assert.equal(About.ORGANIZATION, "Nine Point Labs")
  assert.equal(About.SUPPORT_EMAIL, "help@ninepointlabs.com")
  const first = execFileSync("git", ["log", "--reverse", "--format=%ad", "--date=format:%B %Y"], { cwd: ROOT, encoding: "utf8" }).split("\n")[0]
  assert.equal(About.CREATED, first)
})

// Every file the plugin ships, for the checks below.
function sources() {
  const out = []
  const walk = (dir) => {
    for (const entry of fs.readdirSync(path.join(ROOT, dir), { withFileTypes: true })) {
      const rel = path.join(dir, entry.name)
      if (entry.isDirectory()) {
        if (![".git", "test", "assets"].includes(entry.name)) walk(rel)
      } else if (/\.(qml|js)$/.test(entry.name) || dir === "bin") {
        out.push(rel)
      }
    }
  }
  walk(".")
  return out
}

test("privacy: no network host appears in the code without being named", () => {
  assert.match(About.PRIVACY, /no telemetry and no network access/)
  assert.match(About.PRIVACY, /nothing is recorded, photographed or saved/)
  assert.match(About.PRIVACY, /~\/\.local\/state\/omarchy-webcam\/controls\//)
  assert.match(About.PRIVACY, /~\/\.config\/omarchy\/shell\.json/)
  const files = sources()
  assert.ok(files.includes(path.join("bin", "webcamctl")) && files.includes(path.join("preview", "shell.qml")))
  const hosts = new Set()
  for (const f of files) {
    const text = fs.readFileSync(path.join(ROOT, f), "utf8")
    for (const m of text.matchAll(/(?:https?|wss?|ftp):\/\/([^/"'\s$`)]+)/g)) hosts.add(m[1])
    // A network client would make "no network access" untrue.
    assert.doesNotMatch(text, /\b(curl|wget|XMLHttpRequest|WebSocket|NetworkAccessManager|nc|ncat|socat)\b/, f)
  }
  for (const host of hosts) assert.ok(About.PRIVACY.includes(host), `${host} is not named in the privacy text`)
})

test("privacy: the preview only displays video, it never captures or records", () => {
  const preview = read("preview/shell.qml")
  assert.match(preview, /CaptureSession\s*\{/)
  assert.doesNotMatch(preview, /\b(ImageCapture|MediaRecorder|grabToImage|saveToFile)\b/)
})

test("mailto prefills subject and version details", () => {
  const details = About.details("0.2.0", "0.3", "6.11", "Hyprland, wayland")
  assert.equal(details, "Omarchy Webcam 0.2.0\nQuickshell 0.3, Qt 6.11\nHyprland, wayland")
  const url = About.mailto("0.2.0", details)
  assert.ok(url.startsWith("mailto:help@ninepointlabs.com?subject=Omarchy%20Webcam%200.2.0&body="))
  assert.equal(decodeURIComponent(url.split("&body=")[1]), "\n\n--\n" + details)
  assert.equal(About.builtWith("", ""), "Quickshell and Qt")
})

test("toolkit versions are probed from yes/no checks", () => {
  assert.equal(About.probedVersion((major, minor) => major === 6 && minor <= 11, 6), "6.11")
  assert.equal(About.probedVersion((major, minor) => major === 0 && minor <= 3, 0), "0.3")
  assert.equal(About.probedVersion(() => false, 6), "")
  assert.equal(About.probedVersion(null, 6), "")
})
