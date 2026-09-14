.pragma library

function emptyConfig() {
  return { version: 1, layout: "stack", sections: [], hiddenApps: [] }
}

function layoutOf(config) {
  return config && config.layout === "tile" ? "tile" : "stack"
}

function setLayout(config, layout) {
  var next = clone(config || emptyConfig())
  next.layout = layout === "tile" ? "tile" : "stack"
  return next
}

function normalizeDesktopId(id) {
  var value = String(id || "").trim()
  if (value.slice(-8) === ".desktop") value = value.slice(0, -8)
  return value
}

function slugify(value) {
  var slug = String(value || "").toLowerCase().replace(/[^a-z0-9]+/g, "-").replace(/^-+|-+$/g, "")
  return slug || "section"
}

function isReservedSectionId(id) {
  var key = String(id || "")
  return key === "hidden" || key === "all" || key === "uncategorized" || key === "menu"
}

function uniqueSectionId(config, name, preferred) {
  var base = normalizeDesktopId(preferred) || ""
  if (!base || isReservedSectionId(base)) base = slugify(name)
  if (!base || isReservedSectionId(base)) base = "section"
  var used = {}
  var sections = (config && config.sections) || []
  for (var i = 0; i < sections.length; i++) {
    var id = String((sections[i] && sections[i].id) || "")
    if (id) used[id] = true
  }
  if (!used[base] && !isReservedSectionId(base)) return base
  var n = 2
  var candidate = base + "-" + n
  while (used[candidate] || isReservedSectionId(candidate)) {
    n++
    candidate = base + "-" + n
  }
  return candidate
}

function clone(value) {
  return JSON.parse(JSON.stringify(value === undefined ? null : value))
}

function parse(raw) {
  var fallback = emptyConfig()
  var text = String(raw || "").trim()
  if (!text) return { config: fallback, repaired: false, error: "" }

  var parsed
  try {
    parsed = JSON.parse(text)
  } catch (e) {
    return { config: fallback, repaired: false, error: String(e) }
  }

  if (!parsed || typeof parsed !== "object" || Array.isArray(parsed))
    return { config: fallback, repaired: false, error: "config root must be an object" }

  var next = emptyConfig()
  var repaired = false
  var version = Number(parsed.version)
  next.version = isFinite(version) && version > 0 ? Math.floor(version) : 1

  var hidden = []
  var hiddenSeen = {}
  var rawHidden = Array.isArray(parsed.hiddenApps) ? parsed.hiddenApps : []
  for (var h = 0; h < rawHidden.length; h++) {
    var hid = normalizeDesktopId(rawHidden[h])
    if (!hid || hiddenSeen[hid]) continue
    hiddenSeen[hid] = true
    hidden.push(hid)
  }
  next.hiddenApps = hidden
  next.layout = parsed.layout === "tile" ? "tile" : "stack"

  var sections = []
  var sectionIds = {}
  var rawSections = Array.isArray(parsed.sections) ? parsed.sections : []
  for (var i = 0; i < rawSections.length; i++) {
    var src = rawSections[i]
    if (!src || typeof src !== "object") continue
    var name = String(src.name || "").trim()
    var sid = String(src.id || "").trim()
    if (!sid || isReservedSectionId(sid)) {
      sid = uniqueSectionId({ sections: sections }, name || "section")
      repaired = true
    }
    if (sectionIds[sid]) {
      repaired = true
      continue
    }
    sectionIds[sid] = true
    var apps = []
    var seen = {}
    var rawApps = Array.isArray(src.apps) ? src.apps : []
    for (var a = 0; a < rawApps.length; a++) {
      var appId = normalizeDesktopId(rawApps[a])
      if (!appId || seen[appId]) continue
      seen[appId] = true
      apps.push(appId)
    }
    sections.push({
      id: sid,
      name: name || sid,
      apps: apps
    })
  }
  next.sections = sections
  return { config: next, repaired: repaired, error: "" }
}

function serialize(config) {
  var parsed = parse(JSON.stringify(config || emptyConfig()))
  return JSON.stringify(parsed.config, null, 2) + "\n"
}

function hiddenIds(config) {
  var ids = []
  var seen = {}
  var hidden = (config && config.hiddenApps) || []
  var n = hidden.length
  if (typeof n !== "number") {
    try {
      hidden = Array.prototype.slice.call(hidden)
      n = hidden.length
    } catch (e) {
      return ids
    }
  }
  for (var i = 0; i < n; i++) {
    var id = normalizeDesktopId(hidden[i])
    if (!id || seen[id]) continue
    seen[id] = true
    ids.push(id)
  }
  return ids
}

function hiddenSet(config) {
  var set = {}
  var ids = hiddenIds(config)
  for (var i = 0; i < ids.length; i++) set[ids[i]] = true
  return set
}

function assignedSet(config) {
  var set = {}
  var sections = (config && config.sections) || []
  for (var i = 0; i < sections.length; i++) {
    var apps = (sections[i] && sections[i].apps) || []
    for (var a = 0; a < apps.length; a++) {
      var id = normalizeDesktopId(apps[a])
      if (id) set[id] = true
    }
  }
  return set
}

function sectionIndex(config, sectionId) {
  var sections = (config && config.sections) || []
  for (var i = 0; i < sections.length; i++) {
    if (sections[i] && sections[i].id === sectionId) return i
  }
  return -1
}

function addSection(config, name) {
  var next = clone(config || emptyConfig())
  var title = String(name || "").trim()
  if (!title) return next
  next.sections.push({
    id: uniqueSectionId(next, title),
    name: title,
    apps: []
  })
  return next
}

function renameSection(config, sectionId, name) {
  var next = clone(config || emptyConfig())
  var index = sectionIndex(next, sectionId)
  var title = String(name || "").trim()
  if (index < 0 || !title) return next
  next.sections[index].name = title
  return next
}

function deleteSection(config, sectionId) {
  var next = clone(config || emptyConfig())
  next.sections = next.sections.filter(function(section) {
    return section && section.id !== sectionId
  })
  return next
}

function moveSection(config, sectionId, delta) {
  var next = clone(config || emptyConfig())
  var index = sectionIndex(next, sectionId)
  if (index < 0) return next
  var dest = index + delta
  if (dest < 0 || dest >= next.sections.length) return next
  var row = next.sections.splice(index, 1)[0]
  next.sections.splice(dest, 0, row)
  return next
}

function moveSectionBefore(config, sectionId, beforeSectionId) {
  var next = clone(config || emptyConfig())
  var from = sectionIndex(next, sectionId)
  if (from < 0) return next
  var before = String(beforeSectionId || "")
  var dest = next.sections.length
  if (before) {
    var to = sectionIndex(next, before)
    if (to < 0) return next
    dest = to
  }
  if (dest === from || dest === from + 1) return next
  var row = next.sections.splice(from, 1)[0]
  if (dest > from) dest--
  next.sections.splice(dest, 0, row)
  return next
}

function removeAppFromSections(config, appId) {
  var id = normalizeDesktopId(appId)
  var next = clone(config || emptyConfig())
  for (var i = 0; i < next.sections.length; i++) {
    next.sections[i].apps = (next.sections[i].apps || []).filter(function(value) {
      return normalizeDesktopId(value) !== id
    })
  }
  return next
}

function moveAppToSection(config, appId, sectionId, beforeAppId) {
  var id = normalizeDesktopId(appId)
  if (!id) return clone(config || emptyConfig())
  var next = clone(config || emptyConfig())
  var before = normalizeDesktopId(beforeAppId)
  var fromSection = -1
  var fromIndex = -1
  for (var i = 0; i < next.sections.length; i++) {
    var apps = next.sections[i].apps || []
    for (var a = 0; a < apps.length; a++) {
      if (normalizeDesktopId(apps[a]) === id) {
        fromSection = i
        fromIndex = a
      }
    }
  }

  var destSection = (!sectionId || sectionId === "uncategorized") ? -1 : sectionIndex(next, sectionId)
  if (destSection < 0) return removeAppFromSections(next, id)
  if (!next.sections[destSection].apps) next.sections[destSection].apps = []
  var destApps = next.sections[destSection].apps
  var destIndex = destApps.length
  if (before) {
    for (var b = 0; b < destApps.length; b++) {
      if (normalizeDesktopId(destApps[b]) === before) {
        destIndex = b
        break
      }
    }
  }

  if (fromSection === destSection && fromIndex >= 0) {
    if (destIndex === fromIndex || destIndex === fromIndex + 1) return next
    destApps.splice(fromIndex, 1)
    if (destIndex > fromIndex) destIndex--
    destApps.splice(destIndex, 0, id)
    return next
  }

  next = removeAppFromSections(next, id)
  destSection = sectionIndex(next, sectionId)
  if (destSection < 0) return next
  if (!next.sections[destSection].apps) next.sections[destSection].apps = []
  destApps = next.sections[destSection].apps
  if (destIndex > destApps.length) destIndex = destApps.length
  destApps.splice(destIndex, 0, id)
  return next
}

function setHidden(config, appId, hidden) {
  var id = normalizeDesktopId(appId)
  var next = clone(config || emptyConfig())
  next.hiddenApps = (next.hiddenApps || []).filter(function(value) {
    return normalizeDesktopId(value) !== id
  })
  if (hidden && id) next.hiddenApps.push(id)
  return next
}

if (typeof module !== "undefined") {
  module.exports = {
    emptyConfig: emptyConfig,
    layoutOf: layoutOf,
    setLayout: setLayout,
    normalizeDesktopId: normalizeDesktopId,
    slugify: slugify,
    isReservedSectionId: isReservedSectionId,
    uniqueSectionId: uniqueSectionId,
    clone: clone,
    parse: parse,
    serialize: serialize,
    hiddenIds: hiddenIds,
    hiddenSet: hiddenSet,
    assignedSet: assignedSet,
    sectionIndex: sectionIndex,
    addSection: addSection,
    renameSection: renameSection,
    deleteSection: deleteSection,
    moveSection: moveSection,
    moveSectionBefore: moveSectionBefore,
    removeAppFromSections: removeAppFromSections,
    moveAppToSection: moveAppToSection,
    setHidden: setHidden
  }
}
