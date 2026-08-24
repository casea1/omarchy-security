import QtQuick
import Quickshell
import Quickshell.Io

// Reads what the privileged collectors left in /run and turns it into the
// shape the panel renders. Deliberately inert: this file never runs a
// command and never needs a privilege, so opening the panel can never
// produce an authentication prompt.
Item {
  id: root
  visible: false

  property var settings: ({})
  property int staleAfterSec: 300

  readonly property string runtimeDir: "/run/omarchy-security"

  property var statusDoc: null
  property var integrityDoc: null
  property bool statusMissing: true
  property bool integrityMissing: true

  // Ticks so `ageSec` stays live while the panel is open.
  property int nowUnix: Math.floor(Date.now() / 1000)

  readonly property bool collectorInstalled: !statusMissing || !integrityMissing
  readonly property int generatedAtUnix: statusDoc && statusDoc.generatedAtUnix ? statusDoc.generatedAtUnix : 0
  readonly property int ageSec: generatedAtUnix > 0 ? Math.max(0, nowUnix - generatedAtUnix) : -1
  readonly property bool stale: collectorInstalled && (ageSec < 0 || ageSec > staleAfterSec)

  readonly property int integrityAgeSec: integrityDoc && integrityDoc.generatedAtUnix
    ? Math.max(0, nowUnix - integrityDoc.generatedAtUnix) : -1

  readonly property var sectionOrder: [
    { key: "firewall", title: "Firewall", source: "status" },
    { key: "exposure", title: "Exposure", source: "status" },
    { key: "network", title: "Network", source: "status" },
    { key: "integrity", title: "Integrity", source: "integrity" }
  ]

  readonly property var sections: buildSections()
  readonly property string worst: worstOf(sections)
  readonly property int issueCount: countIssues(sections)

  function rank(status) {
    switch (status) {
      case "fail": return 3
      case "warn": return 2
      case "unknown": return 1
      default: return 0   // ok and info never raise the roll-up
    }
  }

  function buildSections() {
    var out = []
    for (var i = 0; i < sectionOrder.length; i++) {
      var spec = sectionOrder[i]
      var doc = spec.source === "status" ? statusDoc : integrityDoc
      var body = doc && doc.sections ? doc.sections[spec.key] : null
      if (!body) {
        out.push({
          key: spec.key, title: spec.title, status: "unknown",
          summary: "no data", checks: [], listeners: [], missing: true
        })
        continue
      }
      out.push({
        key: spec.key,
        title: spec.title,
        status: body.status || "unknown",
        summary: body.summary || "",
        checks: body.checks instanceof Array ? body.checks : [],
        listeners: body.listeners instanceof Array ? body.listeners : [],
        missing: false
      })
    }
    return out
  }

  function worstOf(list) {
    if (!collectorInstalled) return "unknown"
    // Data we know to be old is not evidence that things are still fine.
    if (stale) return "unknown"
    var best = "ok", bestRank = 0
    for (var i = 0; i < list.length; i++) {
      var r = rank(list[i].status)
      if (r > bestRank) { bestRank = r; best = list[i].status }
    }
    return best
  }

  function countIssues(list) {
    var n = 0
    for (var i = 0; i < list.length; i++) {
      var checks = list[i].checks
      for (var j = 0; j < checks.length; j++) {
        var s = checks[j].status
        if (s === "warn" || s === "fail") n++
      }
    }
    return n
  }

  function parseInto(text, which) {
    var parsed = null
    try {
      parsed = JSON.parse(String(text || ""))
    } catch (e) {
      console.warn("omarchy-security", "ignoring unparseable", which, e)
      parsed = null
    }
    if (which === "status") {
      statusDoc = parsed
      statusMissing = parsed === null
    } else {
      integrityDoc = parsed
      integrityMissing = parsed === null
    }
  }

  FileView {
    id: statusFile
    path: root.runtimeDir + "/status.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseInto(text(), "status")
    onLoadFailed: { root.statusDoc = null; root.statusMissing = true }
  }

  FileView {
    id: integrityFile
    path: root.runtimeDir + "/integrity.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseInto(text(), "integrity")
    onLoadFailed: { root.integrityDoc = null; root.integrityMissing = true }
  }

  // The collectors publish by rename, which swaps the inode out from under
  // the file watcher, so a watch that silently stops watching is the
  // expected failure rather than a surprising one. Re-read on a slow beat
  // regardless; it is two small reads from tmpfs.
  Timer {
    interval: 10000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      root.nowUnix = Math.floor(Date.now() / 1000)
      statusFile.reload()
      integrityFile.reload()
    }
  }
}
