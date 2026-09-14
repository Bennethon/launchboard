#!/usr/bin/env node
"use strict"

const fs = require("fs")
const path = require("path")
const vm = require("vm")
const { spawnSync } = require("child_process")
const os = require("os")
const assert = require("assert")

const root = path.resolve(__dirname, "..")
let passed = 0
let failed = 0

function test(name, fn) {
  try {
    fn()
    passed += 1
    console.log("ok  - " + name)
  } catch (err) {
    failed += 1
    console.error("fail - " + name)
    console.error("      " + (err && err.stack ? err.stack.split("\n")[0] : err))
  }
}

function sameJson(actual, expected) {
  assert.strictEqual(JSON.stringify(actual), JSON.stringify(expected))
}

function loadLibrary(rel, extras) {
  const file = path.join(root, rel)
  let src = fs.readFileSync(file, "utf8")
  src = src.replace(/^\.pragma library\s*/m, "")
  src = src.replace(/^\.import .*$/gm, "")
  const module = { exports: {} }
  const sandbox = Object.assign({
    module: module,
    exports: module.exports,
    console: console
  }, extras || {})
  vm.runInNewContext(src, sandbox, { filename: file })
  return module.exports
}

const Config = loadLibrary("qml/Config.js")
const AppSearch = loadLibrary("qml/AppSearch.js")
const Layout = loadLibrary("qml/Layout.js", { Config: Config, AppSearch: AppSearch })

test("uniqueSectionId does not emit reserved ids", function() {
  const cfg = Config.emptyConfig()
  assert.notStrictEqual(Config.uniqueSectionId(cfg, "Hidden"), "hidden")
  assert.notStrictEqual(Config.uniqueSectionId(cfg, "All"), "all")
  assert.notStrictEqual(Config.uniqueSectionId(cfg, "Uncategorized"), "uncategorized")
  assert.notStrictEqual(Config.uniqueSectionId(cfg, "Menu"), "menu")
  assert.ok(!Config.isReservedSectionId(Config.uniqueSectionId(cfg, "Hidden")))
})

test("addSection('Hidden') does not collide with the Hidden bucket", function() {
  const next = Config.addSection(Config.emptyConfig(), "Hidden")
  assert.strictEqual(next.sections.length, 1)
  assert.notStrictEqual(next.sections[0].id, "hidden")
  assert.strictEqual(next.sections[0].name, "Hidden")
})

test("parse rewrites reserved section ids and reports repaired", function() {
  const raw = JSON.stringify({
    version: 1,
    layout: "stack",
    sections: [{ id: "hidden", name: "Hidden", apps: ["firefox"] }],
    hiddenApps: []
  })
  const parsed = Config.parse(raw)
  assert.strictEqual(parsed.error, "")
  assert.strictEqual(parsed.repaired, true)
  assert.strictEqual(parsed.config.sections.length, 1)
  assert.notStrictEqual(parsed.config.sections[0].id, "hidden")
  sameJson(parsed.config.sections[0].apps, ["firefox"])
})

test("parse keeps a valid layout and strips .desktop suffixes", function() {
  const parsed = Config.parse(JSON.stringify({
    version: 1,
    layout: "tile",
    sections: [{ id: "creative", name: "Creative", apps: ["org.gimp.GIMP.desktop"] }],
    hiddenApps: ["btop.desktop"]
  }))
  assert.strictEqual(parsed.error, "")
  assert.strictEqual(parsed.repaired, false)
  assert.strictEqual(parsed.config.layout, "tile")
  assert.strictEqual(parsed.config.sections[0].apps[0], "org.gimp.GIMP")
  sameJson(parsed.config.hiddenApps, ["btop"])
})

test("invalid JSON is an error, not a silent empty repair", function() {
  const parsed = Config.parse("{ not json")
  assert.ok(parsed.error)
  assert.strictEqual(parsed.repaired, false)
  assert.deepStrictEqual(parsed.config, Config.emptyConfig())
})

test("empty input is a valid first-run config", function() {
  const parsed = Config.parse("")
  assert.strictEqual(parsed.error, "")
  assert.strictEqual(parsed.repaired, false)
  assert.deepStrictEqual(parsed.config, Config.emptyConfig())
})

test("serialize round-trips a repaired reserved id", function() {
  const parsed = Config.parse(JSON.stringify({
    version: 1,
    sections: [{ id: "all", name: "Mine", apps: [] }]
  }))
  const again = Config.parse(Config.serialize(parsed.config))
  assert.strictEqual(again.repaired, false)
  assert.notStrictEqual(again.config.sections[0].id, "all")
})

test("fuzzy search ranks a name prefix first", function() {
  const firefox = { id: "firefox", name: "Firefox", genericName: "Web Browser", comment: "", keywords: ["browser"] }
  const files = { id: "org.gnome.Nautilus", name: "Files", genericName: "File Manager", comment: "", keywords: [] }
  assert.ok(AppSearch.matches(firefox, "fire"))
  assert.ok(AppSearch.fuzzyScore(firefox, "firefox") > AppSearch.fuzzyScore(files, "firefox"))
  assert.ok(AppSearch.matches(firefox, "ff") || AppSearch.matches(firefox, "web"))
})

test("hidden section skips stock-hidden ids that are no longer in the library", function() {
  const apps = [{ id: "obsidian", name: "Obsidian", genericName: "", comment: "", keywords: [], categories: [], icon: "" }]
  const config = {
    version: 1,
    layout: "stack",
    sections: [],
    hiddenApps: ["obsidian", "btop", "cups"]
  }
  const rows = Layout.hiddenApps(apps, config, "")
  assert.strictEqual(rows.length, 1)
  assert.strictEqual(rows[0].id, "obsidian")
})

test("build does not put stock-missing ids into Uncategorized", function() {
  const apps = [
    { id: "firefox", name: "Firefox", genericName: "", comment: "", keywords: [], categories: [], icon: "" }
  ]
  const config = Config.emptyConfig()
  const built = Layout.build(apps, config, "", false, false)
  const ids = built.flatApps.map(function(app) { return app.id })
  sameJson(ids, ["firefox"])
  assert.strictEqual(built.sections[0].id, "uncategorized")
})

test("awk strip removes a balanced LaunchBoard block", function() {
  const awk = path.join(root, "scripts/strip-launchboard-block.awk")
  const input = [
    "-- keep me",
    "-- BEGIN launchboard",
    "pcall(dofile, \"gone.lua\")",
    "-- END launchboard",
    "-- also keep me",
    ""
  ].join("\n")
  const result = spawnSync("awk", ["-f", awk], { input: input, encoding: "utf8" })
  assert.strictEqual(result.status, 0, result.stderr)
  assert.ok(result.stdout.indexOf("keep me") >= 0)
  assert.ok(result.stdout.indexOf("also keep me") >= 0)
  assert.ok(result.stdout.indexOf("BEGIN launchboard") < 0)
})

test("awk strip refuses to edit unbalanced markers", function() {
  const awk = path.join(root, "scripts/strip-launchboard-block.awk")
  const dir = fs.mkdtempSync(path.join(os.tmpdir(), "launchboard-"))
  const file = path.join(dir, "bindings.lua")
  const original = "-- keep\n-- BEGIN launchboard\nh.unbind(\"SUPER + ALT + SPACE\")\n-- missing end\n-- survivor\n"
  fs.writeFileSync(file, original)
  const result = spawnSync("awk", ["-f", awk, file], { encoding: "utf8" })
  assert.notStrictEqual(result.status, 0)
  assert.strictEqual(fs.readFileSync(file, "utf8"), original)
  fs.rmSync(dir, { recursive: true, force: true })
})

console.log("")
console.log(passed + " passed, " + failed + " failed")
process.exit(failed === 0 ? 0 : 1)
