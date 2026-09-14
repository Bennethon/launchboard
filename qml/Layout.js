.pragma library

.import "AppSearch.js" as AppSearch
.import "Config.js" as Config

function appById(apps, id) {
  var key = Config.normalizeDesktopId(id)
  if (!key) return null
  for (var i = 0; i < apps.length; i++) {
    if (apps[i] && Config.normalizeDesktopId(apps[i].id) === key) return apps[i]
  }
  return null
}

function stubApp(id) {
  var key = Config.normalizeDesktopId(id)
  return {
    id: key,
    name: key,
    genericName: "",
    comment: "",
    keywords: [],
    categories: [],
    icon: ""
  }
}

function isHiddenApp(hidden, app) {
  if (!app) return false
  return hidden[Config.normalizeDesktopId(app.id)] === true
}

function decorate(app, query, extra) {
  var row = {
    id: app.id,
    name: app.name,
    genericName: app.genericName || "",
    comment: app.comment || "",
    keywords: app.keywords || [],
    categories: app.categories || [],
    icon: app.icon || "",
    hidden: extra && extra.hidden === true,
    score: AppSearch.fuzzyScore(app, query)
  }
  return row
}

function collectIds(apps, ids, query, hiddenSet, includeHidden) {
  var rows = []
  for (var i = 0; i < ids.length; i++) {
    var app = appById(apps, ids[i])
    if (!app) continue
    var isHidden = isHiddenApp(hiddenSet, app)
    if (isHidden && !includeHidden) continue
    if (!AppSearch.matches(app, query)) continue
    rows.push(decorate(app, query, { hidden: isHidden }))
  }
  return rows
}

function uncategorizedApps(apps, config, query, includeHidden) {
  var hidden = Config.hiddenSet(config)
  var assigned = Config.assignedSet(config)
  var rows = []
  for (var i = 0; i < apps.length; i++) {
    var app = apps[i]
    if (!app || assigned[app.id]) continue
    var isHidden = isHiddenApp(hidden, app)
    if (isHidden && !includeHidden) continue
    if (!AppSearch.matches(app, query)) continue
    rows.push(decorate(app, query, { hidden: isHidden }))
  }
  rows.sort(function(a, b) {
    if (a.name.toLowerCase() < b.name.toLowerCase()) return -1
    if (a.name.toLowerCase() > b.name.toLowerCase()) return 1
    return 0
  })
  return rows
}

function sortApps(rows, query) {
  if (String(query || "").trim()) {
    rows.sort(function(a, b) {
      if (a.score !== b.score) return b.score - a.score
      if (a.name.toLowerCase() < b.name.toLowerCase()) return -1
      if (a.name.toLowerCase() > b.name.toLowerCase()) return 1
      return 0
    })
  } else {
    rows.sort(function(a, b) {
      if (a.name.toLowerCase() < b.name.toLowerCase()) return -1
      if (a.name.toLowerCase() > b.name.toLowerCase()) return 1
      return 0
    })
  }
  return rows
}

function hiddenApps(apps, config, query) {
  var ids = Config.hiddenIds(config)
  var rows = []
  var seen = {}
  for (var i = 0; i < ids.length; i++) {
    var id = ids[i]
    if (!id || seen[id]) continue
    seen[id] = true
    var app = appById(apps, id) || stubApp(id)
    if (!AppSearch.matches(app, query)) continue
    rows.push(decorate(app, query, { hidden: true }))
  }
  return sortApps(rows, query)
}

function allApps(apps, config, query) {
  var hidden = Config.hiddenSet(config)
  var rows = []
  for (var i = 0; i < apps.length; i++) {
    var app = apps[i]
    if (!app) continue
    if (isHiddenApp(hidden, app)) continue
    if (!AppSearch.matches(app, query)) continue
    rows.push(decorate(app, query, { hidden: false }))
  }
  return sortApps(rows, query)
}

function pushSection(sections, flat, spec) {
  sections.push(spec)
  var rows = spec.apps || []
  for (var i = 0; i < rows.length; i++) {
    rows[i].sectionId = spec.id
    rows[i].flatIndex = flat.length
    flat.push(rows[i])
  }
}

function bestIndex(flatApps) {
  if (!flatApps.length) return 0
  var best = 0
  for (var i = 1; i < flatApps.length; i++) {
    if ((flatApps[i].score || 0) > (flatApps[best].score || 0)) best = i
  }
  return best
}

function build(apps, config, query, allAppsView, editMode) {
  var hidden = Config.hiddenSet(config)
  var sections = []
  var flat = []
  var q = String(query || "")
  var showHidden = allAppsView === true || editMode === true

  if (allAppsView) {
    var hiddenRows = hiddenApps(apps, config, q)
    if (hiddenRows.length > 0) {
      pushSection(sections, flat, {
        id: "hidden",
        name: "Hidden",
        kind: "hidden",
        apps: hiddenRows
      })
    }
    var library = allApps(apps, config, q)
    if (library.length > 0 || !q) {
      pushSection(sections, flat, {
        id: "all",
        name: "All Apps",
        kind: "all",
        apps: library
      })
    }
    return { sections: sections, flatApps: flat, selectedIndex: bestIndex(flat) }
  }

  var rawSections = (config && config.sections) || []
  for (var i = 0; i < rawSections.length; i++) {
    var src = rawSections[i]
    if (!src) continue
    var rows = collectIds(apps, src.apps || [], q, hidden, false)
    if (rows.length === 0 && q) continue
    sections.push({
      id: src.id,
      name: src.name,
      kind: "user",
      apps: rows
    })
    for (var r = 0; r < rows.length; r++) {
      rows[r].sectionId = src.id
      rows[r].flatIndex = flat.length
      flat.push(rows[r])
    }
  }

  var uncategorized = uncategorizedApps(apps, config, q, false)
  if (uncategorized.length > 0 || (rawSections.length === 0 && !q)) {
    sections.push({
      id: "uncategorized",
      name: "Uncategorized",
      kind: "uncategorized",
      apps: uncategorized
    })
    for (var u = 0; u < uncategorized.length; u++) {
      uncategorized[u].sectionId = "uncategorized"
      uncategorized[u].flatIndex = flat.length
      flat.push(uncategorized[u])
    }
  }

  if (showHidden) {
    var hiddenMain = hiddenApps(apps, config, q)
    if (hiddenMain.length > 0) {
      pushSection(sections, flat, {
        id: "hidden",
        name: "Hidden",
        kind: "hidden",
        apps: hiddenMain
      })
    }
  }

  return { sections: sections, flatApps: flat, selectedIndex: bestIndex(flat) }
}
