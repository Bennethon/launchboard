.pragma library

function entryName(app) {
  return String((app && app.name) || (app && app.id) || "")
}

function keywordText(app) {
  try {
    if (app && app.keywords && typeof app.keywords.join === "function")
      return app.keywords.join(" ")
  } catch (e) {
  }
  return ""
}

function categoryText(app) {
  try {
    if (app && app.categories && typeof app.categories.join === "function")
      return app.categories.join(" ")
  } catch (e) {
  }
  return ""
}

function searchText(app) {
  if (!app) return ""
  return [
    app.name, app.genericName, app.comment,
    keywordText(app), categoryText(app), app.id
  ].join(" ").toLowerCase()
}

function wordText(value) {
  return String(value || "")
    .replace(/([a-z0-9])([A-Z])/g, "$1 $2")
    .replace(/[._:/\\-]+/g, " ")
    .toLowerCase()
}

function words(value) {
  var values = wordText(value).split(/[^a-z0-9]+/)
  var result = []
  for (var i = 0; i < values.length; i++) {
    if (values[i]) result.push(values[i])
  }
  return result
}

function acronym(app) {
  var values = words([app && app.name, app && app.genericName, keywordText(app), app && app.id].join(" "))
  var result = ""
  for (var i = 0; i < values.length; i++) result += values[i].charAt(0)
  return result
}

function termMatches(app, term) {
  if (!term) return true
  var name = entryName(app).toLowerCase()
  var id = String((app && app.id) || "").toLowerCase()
  var haystack = searchText(app)
  if (name.indexOf(term) >= 0) return true
  if (id.indexOf(term) >= 0) return true
  if (haystack.indexOf(term) >= 0) return true
  return term.length <= 5 && acronym(app).indexOf(term) >= 0
}

function allTermsMatch(app, query) {
  var terms = String(query || "").toLowerCase().trim().split(/\s+/)
  for (var i = 0; i < terms.length; i++) {
    if (terms[i] && !termMatches(app, terms[i])) return false
  }
  return true
}

function fuzzyScore(app, query) {
  var q = String(query || "").trim().toLowerCase()
  if (!q) return 0
  if (!allTermsMatch(app, q)) return -1

  var name = entryName(app).toLowerCase()
  var id = String((app && app.id) || "").toLowerCase()
  var haystack = searchText(app)
  var directName = name.indexOf(q)
  var directId = id.indexOf(q)
  if (directName === 0) return 10000 - name.length
  if (directId === 0) return 9500 - id.length
  if (directName > 0) return 8000 - directName * 10 - name.length
  if (directId > 0) return 7600 - directId * 10 - id.length

  var hayIndex = haystack.indexOf(q)
  if (hayIndex >= 0) return 6000 - hayIndex

  var acr = acronym(app)
  var acronymIndex = acr.indexOf(q)
  if (acronymIndex === 0) return 5000 - acr.length
  if (acronymIndex > 0) return 4600 - acronymIndex * 10 - acr.length
  return 4000 - name.length
}

function matches(app, query) {
  return fuzzyScore(app, query) >= 0
}

if (typeof module !== "undefined") {
  module.exports = {
    entryName: entryName,
    keywordText: keywordText,
    categoryText: categoryText,
    searchText: searchText,
    wordText: wordText,
    words: words,
    acronym: acronym,
    termMatches: termMatches,
    allTermsMatch: allTermsMatch,
    fuzzyScore: fuzzyScore,
    matches: matches
  }
}
