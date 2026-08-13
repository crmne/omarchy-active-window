function normalized(value) {
  return String(value || "")
    .trim()
    .toLowerCase()
    .replace(/\.desktop$/, "")
}

function compact(value) {
  return normalized(value).replace(/[^a-z0-9]+/g, "")
}

function finalSegment(value) {
  var parts = normalized(value).split(/[.:/_-]+/).filter(function(part) { return part.length > 0 })
  return parts.length ? parts[parts.length - 1] : ""
}

function executableName(entry) {
  if (!entry) return ""

  try {
    if (entry.command && entry.command.length) {
      var command = String(entry.command[0] || "")
      if (command) return command.slice(command.lastIndexOf("/") + 1)
    }
  } catch (e) {
  }

  var exec = String(entry.execString || "").trim()
  if (!exec) return ""
  var first = exec.split(/\s+/)[0].replace(/^['"]|['"]$/g, "")
  return first.slice(first.lastIndexOf("/") + 1)
}

function candidateValues(candidates) {
  var result = []
  var source = Array.isArray(candidates) ? candidates : [candidates]
  for (var i = 0; i < source.length; i++) {
    var value = normalized(source[i])
    if (value && result.indexOf(value) === -1) result.push(value)
  }
  return result
}

function matchScore(entry, candidates) {
  if (!entry) return -1

  var ids = candidateValues(candidates)
  if (!ids.length) return -1

  var entryId = normalized(entry.id)
  var startupClass = normalized(entry.startupClass)
  var command = normalized(executableName(entry))
  var name = normalized(entry.name)
  var best = -1

  for (var i = 0; i < ids.length; i++) {
    var id = ids[i]
    var idCompact = compact(id)
    var idTail = finalSegment(id)

    if (entryId === id) best = Math.max(best, 1000)
    if (startupClass && startupClass === id) best = Math.max(best, 980)
    if (command && command === id) best = Math.max(best, 940)
    if (name && name === id) best = Math.max(best, 900)

    if (idCompact.length >= 4) {
      if (compact(entryId) === idCompact) best = Math.max(best, 880)
      if (startupClass && compact(startupClass) === idCompact) best = Math.max(best, 870)
    }

    if (idTail.length >= 3) {
      if (finalSegment(entryId) === idTail) best = Math.max(best, 820)
      if (startupClass && finalSegment(startupClass) === idTail) best = Math.max(best, 810)
      if (command === idTail) best = Math.max(best, 800)
    }
  }

  return best
}

function resolve(entries, candidates) {
  var values = entries || []
  var bestEntry = null
  var bestScore = -1

  for (var i = 0; i < values.length; i++) {
    var entry = values[i]
    var score = matchScore(entry, candidates)
    if (score > bestScore) {
      bestEntry = entry
      bestScore = score
    }
  }

  return bestScore >= 800 ? bestEntry : null
}

if (typeof module !== "undefined") {
  module.exports = {
    normalized: normalized,
    compact: compact,
    finalSegment: finalSegment,
    executableName: executableName,
    matchScore: matchScore,
    resolve: resolve
  }
}
