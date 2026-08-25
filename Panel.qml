import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Security posture for the bar: one shield whose colour is the worst thing
// currently true about this machine, and a panel that says what that thing
// is and offers to fix it.
//
// The panel shows problems and folds everything else away. A passing check
// is worth one line in a section summary, not four lines of its own — the
// list you actually read should be short enough to read.
//
// All data arrives from /run/omarchy-security or the user's runtime dir via
// Service.qml. Nothing here shells out for state, so opening the panel can
// never produce an authentication prompt. Actions are the exception, and
// they are explicit: the command comes from the collector, and running one
// is always a deliberate click.
Panel {
  id: root
  moduleName: "io.github.casea1.security"
  ipcTarget: "io.github.casea1.security"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color textColor: Color.popups.text
  readonly property color dimColor: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.58)
  readonly property color fainterColor: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.34)

  // Omarchy themes carry no "warning" role — only foreground, accent and
  // urgent — so amber is a plain default, overridable for palettes it fights.
  readonly property color warnColor: setting("warnColor", "") !== ""
    ? setting("warnColor", "") : "#d79921"

  readonly property bool showBadge: setting("showBadge", true)
  readonly property bool showLocalListeners: setting("showLocalListeners", false)

  // Nerd Font code points sit above the BMP, where \u cannot reach them, and
  // embedding raw glyphs would make this file's encoding load-bearing.
  readonly property string glyphShield: String.fromCodePoint(0xF132)
  readonly property string glyphAlert: String.fromCodePoint(0xF071)
  readonly property string glyphCollapsed: String.fromCodePoint(0x25B8)
  readonly property string glyphExpanded: String.fromCodePoint(0x25BE)

  // ---- section expansion ------------------------------------------------
  // A plain array rather than a mutated object, so the bindings that depend
  // on it actually re-evaluate.
  property var expandedSections: []

  function isExpanded(key) { return expandedSections.indexOf(key) >= 0 }

  function toggleSection(key) {
    var next = expandedSections.slice()
    var i = next.indexOf(key)
    if (i >= 0) next.splice(i, 1)
    else next.push(key)
    expandedSections = next
  }

  function isProblem(status) {
    return status === "fail" || status === "warn" || status === "unknown"
  }

  // Collapsed sections show only what needs attention; expanded shows all.
  function visibleChecks(section) {
    if (isExpanded(section.key)) return section.checks
    return section.checks.filter(function (c) { return root.isProblem(c.status) })
  }

  function foldedCount(section) {
    return section.checks.length - visibleChecks(section).length
  }

  // The listener table is the exposure section's evidence, not its content:
  // collapsed, it shows only sockets something can actually reach.
  function visibleListeners(section) {
    if (section.key !== "exposure") return []
    var all = section.listeners || []
    if (!isExpanded("exposure"))
      return all.filter(function (l) { return l.verdict === "allowed" || l.verdict === "unknown" })
    return all.filter(function (l) {
      return root.showLocalListeners
        || (l.scope !== "local" && l.scope !== "linklocal" && l.scope !== "multicast")
    })
  }

  function statusColor(status) {
    switch (status) {
      case "fail": return root.urgentColor
      case "warn": return root.warnColor
      case "unknown": return root.dimColor
      case "info": return root.dimColor
      default: return root.textColor
    }
  }

  // Shape as well as colour, so state survives a colour-blind reader.
  function statusMark(status) {
    switch (status) {
      case "fail": return String.fromCodePoint(0x2717)
      case "warn": return String.fromCodePoint(0x25B2)
      case "unknown": return "?"
      case "info": return String.fromCodePoint(0x00B7)
      default: return String.fromCodePoint(0x2713)
    }
  }

  function relativeAge(seconds) {
    if (seconds < 0) return "never"
    if (seconds < 90) return seconds + "s ago"
    if (seconds < 5400) return Math.round(seconds / 60) + "m ago"
    if (seconds < 172800) return Math.round(seconds / 3600) + "h ago"
    return Math.round(seconds / 86400) + "d ago"
  }

  function listenerLabel(entry) {
    switch (entry.scope) {
      case "all": return entry.verdict === "allowed"
        ? "reachable" + (entry.allowedFrom ? " from " + entry.allowedFrom : "")
        : (entry.verdict === "blocked" ? "firewalled" : "unresolved")
      case "specific": return entry.verdict === "allowed" ? "reachable" : "firewalled"
      case "tailnet": return "tailnet only"
      case "container": return "container bridge"
      case "orphan": return "address is gone"
      case "multicast": return "multicast"
      case "linklocal": return "link-local"
      default: return "loopback"
    }
  }

  function listenerColor(entry) {
    if (entry.verdict === "allowed") return root.urgentColor
    if (entry.verdict === "unknown") return root.warnColor
    return root.fainterColor
  }

  // ---- actions ----------------------------------------------------------

  function runAction(action) {
    if (!action || !action.command) return
    if (action.kind === "url") {
      Quickshell.execDetached(["xdg-open", action.command])
    } else {
      // A terminal, not a detached process: these commands want sudo to be
      // able to prompt, and their output is the point. Holding the window
      // open afterwards means a command that fails is still readable.
      Quickshell.execDetached([
        "omarchy-launch-tui", "--app-id=org.omarchy.security", "bash", "-lc",
        action.command
          + "\nstatus=$?"
          + "\nprintf '\\n\\033[2m── finished (exit %s) ──\\033[0m\\n' \"$status\""
          + "\nread -rsn1 -p 'Press any key to close'"
      ])
    }
    root.close()
  }

  Service {
    id: sec
    settings: root.settings
    staleAfterSec: root.setting("staleAfterSec", 300)
  }

  readonly property string worst: sec.worst
  readonly property color barIconColor: {
    if (!sec.haveData) return Qt.darker(root.barForeground, 1.7)
    switch (worst) {
      case "fail": return root.urgentColor
      case "warn": return root.warnColor
      case "unknown": return Qt.darker(root.barForeground, 1.7)
      default: return root.barForeground
    }
  }

  readonly property string heroMeta: {
    if (!sec.haveData) return sec.selfCollecting ? "Collecting…" : "No data yet"
    if (sec.stale) return "Stale — last collected " + relativeAge(sec.ageSec)
    if (sec.issueCount === 0) return "Nothing needs your attention"
    return sec.issueCount + (sec.issueCount === 1 ? " item needs" : " items need") + " your attention"
  }

  function refresh() { sec.refresh() }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      Item {
        Text {
          anchors.centerIn: parent
          text: root.worst === "fail" ? root.glyphAlert : root.glyphShield
          color: root.barIconColor
          font.family: root.fontFamily
          font.pixelSize: Style.bar.iconFont
          opacity: sec.haveData ? 1.0 : 0.5
        }
        Text {
          visible: root.showBadge && sec.haveData && sec.issueCount > 0 && !root.vertical
          anchors.right: parent.right
          anchors.top: parent.top
          anchors.rightMargin: -Style.space(3)
          anchors.topMargin: -Style.space(2)
          text: sec.issueCount > 9 ? "9+" : String(sec.issueCount)
          color: root.barIconColor
          font.family: root.fontFamily
          font.pixelSize: Math.max(7, Style.font.caption - 2)
          font.bold: true
        }
      }
    }
    tooltipText: {
      if (!sec.haveData) return "Security: collecting…"
      if (sec.stale) return "Security: data is stale"
      return sec.issueCount > 0
        ? "Security: " + sec.issueCount + " to look at"
        : "Security: all clear"
    }
    onPressed: function (buttonCode) {
      if (buttonCode === Qt.MiddleButton || buttonCode === Qt.RightButton) root.refresh()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(420))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(560))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) {
        if (t === "r" || t === "R") root.refresh()
        else if (t === "e" || t === "E") {
          // Expand-all / collapse-all, for when you do want the full dump.
          root.expandedSections = root.expandedSections.length > 0
            ? [] : ["firewall", "exposure", "network", "integrity"]
        }
      }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar {
          // Always on once there is anything to scroll. "Discoverable only
          // after you already scrolled" is not discoverable.
          policy: flick.interactive ? ScrollBar.AlwaysOn : ScrollBar.AlwaysOff
          width: Style.space(4)
        }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(9)

          PanelHero {
            width: parent.width
            title: "Security"
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              Text {
                text: root.worst === "fail" ? root.glyphAlert : root.glyphShield
                color: root.statusColor(root.worst)
                font.family: root.fontFamily
                font.pixelSize: Style.font.display
              }
            }
          }

          Text {
            width: parent.width
            visible: !sec.haveData
            wrapMode: Text.WordWrap
            text: sec.selfCollecting ? "Running the first check…" : "Waiting for the first check to run."
            color: root.dimColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
          }

          // Optional upgrade, and the stale-collector prompt. Hidden once
          // taken, because everything already works without it.
          Item {
            id: upgradeRow
            width: parent.width
            visible: sec.haveData && (!sec.privileged || sec.collectorOutdated)
            implicitHeight: upgradeText.implicitHeight + Style.space(12)

            Rectangle {
              anchors.fill: parent
              radius: Style.space(4)
              color: upgradeMouse.containsMouse && !sec.installing
                ? Style.hoverFillFor(root.foreground, Color.accent, root.urgentColor)
                : Style.normalFillFor(root.foreground, Color.accent, root.urgentColor)
              border.width: 1
              border.color: Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.18)
            }

            Column {
              id: upgradeText
              anchors.left: parent.left
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              anchors.leftMargin: Style.space(8)
              anchors.rightMargin: Style.space(8)
              spacing: Style.space(2)

              Text {
                width: parent.width
                text: sec.installing
                  ? "Authorising…"
                  : (sec.collectorOutdated ? "Update the system collector" : "Enable full checks")
                color: root.textColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.bodySmall
                font.bold: true
              }

              Text {
                width: parent.width
                wrapMode: Text.WordWrap
                text: sec.installError !== ""
                  ? sec.installError
                  : (sec.collectorOutdated
                     ? "The installed collector is "
                       + (sec.systemCollectorVersion === ""
                          ? "older than this plugin (v" + sec.pluginVersion + ")."
                          : "v" + sec.systemCollectorVersion + " but this plugin is v"
                            + sec.pluginVersion + ".")
                     : "Names every listening process and completes the file-integrity "
                       + "sweep. Asks for your password once, then runs on a timer.")
                color: sec.installError !== "" ? root.urgentColor : root.dimColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption
              }
            }

            MouseArea {
              id: upgradeMouse
              anchors.fill: parent
              hoverEnabled: true
              enabled: !sec.installing
              cursorShape: Qt.PointingHandCursor
              onClicked: sec.installSystemCollector()
            }
          }

          Repeater {
            model: sec.haveData ? sec.sections : []

            Column {
              id: sectionBlock
              required property var modelData
              readonly property bool expanded: root.isExpanded(modelData.key)
              readonly property var shownChecks: root.visibleChecks(modelData)
              readonly property var shownListeners: root.visibleListeners(modelData)
              readonly property int folded: root.foldedCount(modelData)
              width: column.width
              spacing: Style.space(4)

              PanelSeparator { width: parent.width; foreground: root.foreground }

              // The whole header is the hit target: a chevron alone is a
              // small thing to ask someone to aim at.
              Item {
                width: parent.width
                implicitHeight: Math.max(headerText.implicitHeight, summaryText.implicitHeight)
                  + Style.space(2)

                Rectangle {
                  anchors.fill: parent
                  anchors.margins: -Style.space(2)
                  radius: Style.space(3)
                  visible: headerMouse.containsMouse
                  color: Style.hoverFillFor(root.foreground, Color.accent, root.urgentColor)
                }

                Text {
                  id: chevron
                  anchors.left: parent.left
                  anchors.verticalCenter: headerText.verticalCenter
                  text: sectionBlock.expanded ? root.glyphExpanded : root.glyphCollapsed
                  color: headerMouse.containsMouse ? root.textColor : root.fainterColor
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                PanelSectionHeader {
                  id: headerText
                  anchors.left: chevron.right
                  anchors.leftMargin: Style.space(4)
                  text: sectionBlock.modelData.title.toUpperCase()
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Text {
                  id: summaryText
                  anchors.right: parent.right
                  anchors.baseline: headerText.baseline
                  width: Math.max(0, parent.width - headerText.width - chevron.width - Style.space(16))
                  horizontalAlignment: Text.AlignRight
                  elide: Text.ElideRight
                  text: sectionBlock.modelData.summary
                  color: root.statusColor(sectionBlock.modelData.status)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }

                MouseArea {
                  id: headerMouse
                  anchors.fill: parent
                  hoverEnabled: true
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleSection(sectionBlock.modelData.key)
                }
              }

              Repeater {
                model: sectionBlock.shownChecks

                Item {
                  id: checkRow
                  required property var modelData
                  readonly property var rowActions: checkRow.modelData.actions || []
                  width: sectionBlock.width
                  implicitHeight: rowText.implicitHeight

                  Text {
                    id: markText
                    anchors.left: parent.left
                    anchors.top: parent.top
                    width: Style.space(14)
                    text: root.statusMark(checkRow.modelData.status)
                    color: root.statusColor(checkRow.modelData.status)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.bodySmall
                  }

                  Column {
                    id: rowText
                    anchors.left: markText.right
                    anchors.right: parent.right
                    spacing: Style.space(1)

                    Text {
                      width: parent.width
                      text: checkRow.modelData.label
                      color: root.textColor
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.bodySmall
                    }

                    Text {
                      width: parent.width
                      visible: text !== ""
                      wrapMode: Text.WordWrap
                      text: checkRow.modelData.detail || ""
                      color: root.dimColor
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                    }

                    // Buttons replace the old advisory text. A remedy you can
                    // click beats a remedy you have to retype.
                    Flow {
                      width: parent.width
                      spacing: Style.space(5)
                      topPadding: checkRow.rowActions.length > 0 ? Style.space(3) : 0
                      bottomPadding: checkRow.rowActions.length > 0 ? Style.space(2) : 0

                      Repeater {
                        model: checkRow.rowActions

                        Rectangle {
                          id: pill
                          required property var modelData
                          readonly property bool isUrl: pill.modelData.kind === "url"
                          implicitWidth: pillText.implicitWidth + Style.space(14)
                          implicitHeight: pillText.implicitHeight + Style.space(6)
                          radius: height / 2
                          color: pillMouse.containsMouse
                            ? Style.hoverFillFor(root.foreground, Color.accent, root.urgentColor)
                            : Style.normalFillFor(root.foreground, Color.accent, root.urgentColor)
                          border.width: 1
                          border.color: pillMouse.containsMouse
                            ? Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.45)
                            : Qt.rgba(root.textColor.r, root.textColor.g, root.textColor.b, 0.18)

                          Text {
                            id: pillText
                            anchors.centerIn: parent
                            // A trailing arrow marks the ones that leave for
                            // a browser, so a click is never a surprise.
                            text: pill.modelData.label + (pill.isUrl ? " " + String.fromCodePoint(0x2197) : "")
                            color: pillMouse.containsMouse ? root.textColor : root.dimColor
                            font.family: root.fontFamily
                            font.pixelSize: Style.font.caption
                          }

                          MouseArea {
                            id: pillMouse
                            anchors.fill: parent
                            hoverEnabled: true
                            cursorShape: Qt.PointingHandCursor
                            onClicked: root.runAction(pill.modelData)
                          }
                        }
                      }
                    }
                  }
                }
              }

              // What the fold is hiding, and how to see it.
              Text {
                width: parent.width
                visible: sectionBlock.folded > 0 && !sectionBlock.expanded
                text: "    " + sectionBlock.folded + " check"
                      + (sectionBlock.folded === 1 ? "" : "s") + " passed"
                color: root.fainterColor
                font.family: root.fontFamily
                font.pixelSize: Style.font.caption

                MouseArea {
                  anchors.fill: parent
                  cursorShape: Qt.PointingHandCursor
                  onClicked: root.toggleSection(sectionBlock.modelData.key)
                }
              }

              Repeater {
                model: sectionBlock.shownListeners

                Item {
                  id: listenerRow
                  required property var modelData
                  width: sectionBlock.width
                  implicitHeight: portText.implicitHeight

                  Text {
                    id: portText
                    anchors.left: parent.left
                    width: Style.space(86)
                    text: "    " + listenerRow.modelData.proto + "/" + listenerRow.modelData.port
                    color: root.dimColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    id: procText
                    anchors.left: portText.right
                    width: Style.space(118)
                    elide: Text.ElideRight
                    text: listenerRow.modelData.process || String.fromCodePoint(0x2014)
                    color: root.dimColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    anchors.left: procText.right
                    anchors.right: parent.right
                    elide: Text.ElideRight
                    text: root.listenerLabel(listenerRow.modelData)
                    color: root.listenerColor(listenerRow.modelData)
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }
                }
              }
            }
          }

          PanelSeparator {
            width: parent.width
            foreground: root.foreground
            visible: sec.haveData
          }

          Item {
            width: parent.width
            visible: sec.haveData
            implicitHeight: footerLeft.implicitHeight

            Text {
              id: footerLeft
              anchors.left: parent.left
              text: "updated " + root.relativeAge(sec.ageSec) + (sec.privileged ? " · full" : "")
              color: root.fainterColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.right: parent.right
              anchors.baseline: footerLeft.baseline
              text: "e · expand    r · refresh"
              color: root.fainterColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }

      // Scroll affordances. The scrollbar says there is more; the fades say
      // which way, and survive a theme where a thin bar is easy to miss.
      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        height: Style.space(18)
        visible: flick.interactive && flick.contentY > 1
        gradient: Gradient {
          GradientStop { position: 0.0; color: Color.popups.background }
          GradientStop { position: 1.0; color: "transparent" }
        }
      }

      Rectangle {
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.bottom: parent.bottom
        height: Style.space(22)
        visible: flick.interactive
          && flick.contentY < flick.contentHeight - flick.height - 1
        gradient: Gradient {
          GradientStop { position: 0.0; color: "transparent" }
          GradientStop { position: 1.0; color: Color.popups.background }
        }

        Text {
          anchors.horizontalCenter: parent.horizontalCenter
          anchors.bottom: parent.bottom
          text: String.fromCodePoint(0x25BE) + " more"
          color: root.fainterColor
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
        }
      }
    }
  }
}
