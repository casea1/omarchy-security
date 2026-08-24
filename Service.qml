import QtQuick
import Quickshell
import Quickshell.Io

// Supplies the panel with data, from whichever of two sources is fresher.
//
// The widget works with nothing installed: it runs the collectors itself, as
// you, on a timer. Everything that matters is readable without privilege —
// ufw keeps its ruleset in world-readable files, and the "### tuple ###"
// lines there are a better source than the root-only CLI output.
//
// If the optional system timers are installed, their snapshot in /run is
// newer and richer (it can name every listening process), so it wins and the
// self-run stops. Neither path ever asks the panel for a privilege.
Item {
  id: root
  visible: false

  property var settings: ({})
  property int staleAfterSec: 300

  readonly property string systemDir: "/run/omarchy-security"
  readonly property string userDir: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/omarchy-security"

  readonly property string collectPath: stripScheme(Qt.resolvedUrl("system/omarchy-security-collect"))
  readonly property string auditPath: stripScheme(Qt.resolvedUrl("system/omarchy-security-audit"))
  readonly property string installPath: stripScheme(Qt.resolvedUrl("system/install.sh"))

  function stripScheme(url) { return String(url).replace(/^file:\/\//, "") }

  property var systemStatus: null
  property var userStatus: null
  property var systemIntegrity: null
  property var userIntegrity: null

  // Seeded rather than left blank so a slow or failed manifest read cannot
  // make a stale collector look current.
  property string pluginVersion: "1.0.0"
  readonly property string systemCollectorVersion:
    systemStatus && systemStatus.collectorVersion ? systemStatus.collectorVersion : ""

  // A plugin update refreshes the scripts in this directory but cannot touch
  // the root-installed copies, so say when they have drifted apart rather
  // than quietly serving data from an old collector.
  readonly property bool collectorOutdated: systemCollectorInstalled
    && pluginVersion !== "" && systemCollectorVersion !== pluginVersion

  property int nowUnix: Math.floor(Date.now() / 1000)
  property int lastSelfAuditUnix: 0
  property bool selfCollecting: false
  property bool installing: false
  property string installError: ""

  function newer(a, b) {
    if (!a) return b
    if (!b) return a
    return (a.generatedAtUnix || 0) >= (b.generatedAtUnix || 0) ? a : b
  }

  readonly property var statusDoc: newer(systemStatus, userStatus)
  readonly property var integrityDoc: newer(systemIntegrity, userIntegrity)

  readonly property bool haveData: statusDoc !== null
  readonly property bool privileged: statusDoc ? statusDoc.privileged === true : false
  readonly property bool systemCollectorInstalled: systemStatus !== null

  readonly property int generatedAtUnix: statusDoc && statusDoc.generatedAtUnix ? statusDoc.generatedAtUnix : 0
  readonly property int ageSec: generatedAtUnix > 0 ? Math.max(0, nowUnix - generatedAtUnix) : -1
  readonly property bool stale: haveData && (ageSec < 0 || ageSec > staleAfterSec)

  readonly property int integrityAgeSec: integrityDoc && integrityDoc.generatedAtUnix
    ? Math.max(0, nowUnix - integrityDoc.generatedAtUnix) : -1

  // True while the system snapshot is recent enough that self-running would
  // only duplicate work.
  readonly property bool systemFresh: systemStatus !== null
    && (nowUnix - (systemStatus.generatedAtUnix || 0)) < 150

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
          summary: spec.key === "integrity" ? "not collected yet" : "no data",
          checks: [], listeners: [], missing: true
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
    if (!haveData) return "unknown"
    // Data known to be old is not evidence that things are still fine.
    if (stale) return "unknown"
    var best = "ok", bestRank = 0
    for (var i = 0; i < list.length; i++) {
      // A section that simply has not been collected yet is not a finding.
      if (list[i].missing && list[i].key === "integrity") continue
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

  function assign(which, parsed) {
    switch (which) {
      case "systemStatus": systemStatus = parsed; break
      case "userStatus": userStatus = parsed; break
      case "systemIntegrity": systemIntegrity = parsed; break
      case "userIntegrity": userIntegrity = parsed; break
    }
  }

  function parseInto(text, which) {
    try {
      var parsed = JSON.parse(String(text || ""))
      assign(which, parsed && typeof parsed === "object" ? parsed : null)
    } catch (e) {
      console.warn("omarchy-security", "ignoring unparseable", which, e)
      assign(which, null)
    }
  }

  // ---- collection -------------------------------------------------------

  function collectNow() {
    if (collectProc.running) return
    selfCollecting = true
    collectProc.running = true
  }

  function auditNow() {
    if (auditProc.running) return
    lastSelfAuditUnix = nowUnix
    auditProc.running = true
  }

  function refresh() {
    if (systemCollectorInstalled) {
      // The units are read-only oneshots and the installed polkit rule lets
      // wheel start them, so this is prompt-free where it is installed.
      systemRefreshProc.running = false
      systemRefreshProc.running = true
    }
    collectNow()
    auditNow()
  }

  function installSystemCollector() {
    if (installProc.running) return
    installError = ""
    installing = true
    installProc.running = true
  }

  Process {
    id: collectProc
    // Cheap, but there is no reason for a background check to compete with
    // anything the user is actually doing.
    command: ["nice", "-n", "10", root.collectPath]
    onExited: {
      root.selfCollecting = false
      userStatusFile.reload()
    }
  }

  Process {
    id: auditProc
    // The once-a-day file sweep inside this one checksums every packaged
    // file, so it is pushed as far down the scheduler as it will go.
    command: ["nice", "-n", "19", root.auditPath]
    onExited: userIntegrityFile.reload()
  }

  Process {
    id: systemRefreshProc
    command: ["systemctl", "start",
              "omarchy-security-collect.service", "omarchy-security-audit.service"]
  }

  Process {
    id: installProc
    // pkexec raises the password dialog through the session's polkit agent,
    // which Omarchy already runs inside this same shell process.
    command: ["pkexec", root.installPath]
    stderr: StdioCollector {
      waitForEnd: true
      onStreamFinished: root.installError = String(text || "").trim()
    }
    onExited: function (code) {
      root.installing = false
      if (code === 0) {
        root.installError = ""
        systemStatusFile.reload()
        systemIntegrityFile.reload()
      } else if (root.installError === "") {
        root.installError = code === 126 || code === 127
          ? "Cancelled" : "Install failed (exit " + code + ")"
      }
    }
  }

  // ---- sources ----------------------------------------------------------

  FileView {
    path: root.stripScheme(Qt.resolvedUrl("manifest.json"))
    printErrors: false
    onLoaded: {
      try {
        var v = JSON.parse(text()).version
        if (v) root.pluginVersion = v
      } catch (e) { /* keep the seeded value */ }
    }
  }

  FileView {
    id: systemStatusFile
    path: root.systemDir + "/status.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseInto(text(), "systemStatus")
    onLoadFailed: root.systemStatus = null
  }

  FileView {
    id: systemIntegrityFile
    path: root.systemDir + "/integrity.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseInto(text(), "systemIntegrity")
    onLoadFailed: root.systemIntegrity = null
  }

  FileView {
    id: userStatusFile
    path: root.userDir + "/status.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseInto(text(), "userStatus")
    onLoadFailed: root.userStatus = null
  }

  FileView {
    id: userIntegrityFile
    path: root.userDir + "/integrity.json"
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.parseInto(text(), "userIntegrity")
    onLoadFailed: root.userIntegrity = null
  }

  // The collectors publish by rename, which swaps the inode out from under a
  // file watcher, so re-reading on a slow beat is the expected belt-and-
  // braces rather than a surprise. This is also where self-collection is
  // driven from.
  Timer {
    interval: 10000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: {
      root.nowUnix = Math.floor(Date.now() / 1000)
      systemStatusFile.reload()
      systemIntegrityFile.reload()
      userStatusFile.reload()
      userIntegrityFile.reload()

      if (root.systemFresh) return   // the timers have it covered

      var userAge = root.userStatus
        ? root.nowUnix - (root.userStatus.generatedAtUnix || 0)
        : 1e9
      if (userAge >= 60) root.collectNow()

      var integrityAge = root.userIntegrity
        ? root.nowUnix - (root.userIntegrity.generatedAtUnix || 0)
        : 1e9
      if (integrityAge >= 3600 && root.nowUnix - root.lastSelfAuditUnix >= 3600)
        root.auditNow()
    }
  }
}
