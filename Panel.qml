import QtQuick
import QtQuick.Controls
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui

// Security posture for the bar: one shield whose colour is the worst thing
// currently true about this machine, and a panel that says what that thing
// is and what to do about it.
//
// All of the data arrives from /run/omarchy-security via Service.qml, which
// the privileged collectors write on a timer. Nothing here shells out for
// state, so the panel can never trigger an authentication prompt just by
// being opened.
Panel {
  id: root
  moduleName: "io.github.caseaustin12.security"
  ipcTarget: "io.github.caseaustin12.security"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgentColor: bar ? bar.urgent : Color.urgent
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family
  readonly property color textColor: Color.popups.text
  readonly property color dimColor: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.55)
  readonly property color fainterColor: Qt.rgba(textColor.r, textColor.g, textColor.b, 0.35)

  // Omarchy themes carry no "warning" role — only foreground, accent and
  // urgent — so amber is a plain default rather than a theme lookup, and the
  // setting exists for anyone whose palette it fights with.
  readonly property color warnColor: setting("warnColor", "") !== ""
    ? setting("warnColor", "")
    : "#d79921"

  readonly property bool showBadge: setting("showBadge", true)
  readonly property bool showLocalListeners: setting("showLocalListeners", false)

  // Nerd Font code points live above the BMP, where a \u escape cannot
  // reach them, and embedding the raw glyph makes this file's encoding
  // load-bearing. Build them from code points instead.
  readonly property string glyphShield: String.fromCodePoint(0xF132)
  readonly property string glyphAlert: String.fromCodePoint(0xF071)

  function statusColor(status) {
    switch (status) {
      case "fail": return root.urgentColor
      case "warn": return root.warnColor
      case "unknown": return root.dimColor
      case "info": return root.dimColor
      default: return root.textColor
    }
  }

  // Shape as well as colour, so the state survives a colour-blind reader and
  // a monochrome screenshot.
  function statusMark(status) {
    switch (status) {
      case "fail": return String.fromCodePoint(0x2717)
      case "warn": return String.fromCodePoint(0x25B2)
      case "unknown": return "?"
      case "info": return String.fromCodePoint(0x00B7)
      default: return String.fromCodePoint(0x2713)
    }
  }

  function statusWord(status) {
    switch (status) {
      case "fail": return "action needed"
      case "warn": return "check this"
      case "unknown": return "unknown"
      case "info": return ""
      default: return "ok"
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
    if (entry.scope === "local") return root.fainterColor
    return root.dimColor
  }

  Service {
    id: sec
    settings: root.settings
    staleAfterSec: root.setting("staleAfterSec", 300)
  }

  readonly property string worst: sec.worst
  readonly property color barIconColor: {
    if (!sec.collectorInstalled) return Qt.darker(root.barForeground, 1.7)
    switch (worst) {
      case "fail": return root.urgentColor
      case "warn": return root.warnColor
      case "unknown": return Qt.darker(root.barForeground, 1.7)
      default: return root.barForeground
    }
  }

  readonly property string heroMeta: {
    if (!sec.collectorInstalled) return "Collector is not installed"
    if (sec.stale) return "Data is stale — last collected " + relativeAge(sec.ageSec)
    if (sec.issueCount === 0) return "Nothing needs your attention"
    return sec.issueCount + (sec.issueCount === 1 ? " item needs" : " items need") + " your attention"
  }

  function refresh() {
    refreshProc.running = false
    refreshProc.running = true
  }

  Process {
    id: refreshProc
    // Permitted without a password by the polkit rule the installer drops in;
    // without that rule this quietly fails and the timers still keep the
    // data current on their own.
    command: ["systemctl", "start",
              "omarchy-security-collect.service", "omarchy-security-audit.service"]
  }

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
          opacity: sec.collectorInstalled ? 1.0 : 0.5
        }

        Text {
          visible: root.showBadge && sec.collectorInstalled && sec.issueCount > 0 && !root.vertical
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
      if (!sec.collectorInstalled) return "Security: collector not installed"
      if (sec.stale) return "Security: data is stale"
      return "Security: " + root.statusWord(root.worst)
        + (sec.issueCount > 0 ? " (" + sec.issueCount + ")" : "")
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
    contentWidth: panel.fittedContentWidth(Style.space(430))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(620))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function (direction) { root.switchPanel(direction) }
      onTextKey: function (t) { if (t === "r" || t === "R") root.refresh() }

      Flickable {
        id: flick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: flick.width
          spacing: Style.space(10)

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

          // Without the privileged half there is nothing to show, so say so
          // plainly rather than rendering four empty sections.
          Column {
            width: parent.width
            spacing: Style.space(4)
            visible: !sec.collectorInstalled

            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "No data in /run/omarchy-security. The collectors run as root on a "
                    + "systemd timer and this widget only reads what they write."
              color: root.dimColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
            Text {
              width: parent.width
              wrapMode: Text.WordWrap
              text: "Install them with:  ~/.config/omarchy/plugins/"
                    + "io.github.caseaustin12.security/system/install.sh"
              color: root.textColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          Repeater {
            model: sec.collectorInstalled ? sec.sections : []

            Column {
              id: sectionBlock
              required property var modelData
              width: column.width
              spacing: Style.space(5)

              PanelSeparator {
                width: parent.width
                foreground: root.foreground
              }

              Item {
                width: parent.width
                implicitHeight: Math.max(headerText.implicitHeight, summaryText.implicitHeight)

                PanelSectionHeader {
                  id: headerText
                  anchors.left: parent.left
                  text: sectionBlock.modelData.title.toUpperCase()
                  foreground: root.foreground
                  fontFamily: root.fontFamily
                }

                Text {
                  id: summaryText
                  anchors.right: parent.right
                  anchors.baseline: headerText.baseline
                  text: sectionBlock.modelData.summary
                  color: root.statusColor(sectionBlock.modelData.status)
                  font.family: root.fontFamily
                  font.pixelSize: Style.font.caption
                }
              }

              Repeater {
                model: sectionBlock.modelData.checks

                Item {
                  id: checkRow
                  required property var modelData
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

                    // A remedy is only useful next to something actionable,
                    // so informational rows keep theirs hidden.
                    Text {
                      width: parent.width
                      visible: text !== ""
                        && (checkRow.modelData.status === "warn"
                            || checkRow.modelData.status === "fail"
                            || checkRow.modelData.status === "unknown")
                      wrapMode: Text.WordWrap
                      text: checkRow.modelData.remedy || ""
                      color: root.fainterColor
                      font.family: root.fontFamily
                      font.pixelSize: Style.font.caption
                      font.italic: true
                    }
                  }
                }
              }

              // The exposure table is the reason this widget exists: a
              // listening socket on its own is noise, a listening socket the
              // firewall permits is the finding.
              Repeater {
                model: sectionBlock.modelData.key === "exposure"
                  ? sectionBlock.modelData.listeners.filter(function (l) {
                      return root.showLocalListeners
                        || (l.scope !== "local" && l.scope !== "linklocal" && l.scope !== "multicast")
                    })
                  : []

                Item {
                  id: listenerRow
                  required property var modelData
                  width: sectionBlock.width
                  implicitHeight: portText.implicitHeight

                  Text {
                    id: portText
                    anchors.left: parent.left
                    width: Style.space(96)
                    text: "  " + listenerRow.modelData.proto + "/" + listenerRow.modelData.port
                    color: root.dimColor
                    font.family: root.fontFamily
                    font.pixelSize: Style.font.caption
                  }

                  Text {
                    id: procText
                    anchors.left: portText.right
                    width: Style.space(120)
                    elide: Text.ElideRight
                    text: listenerRow.modelData.process || "—"
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
            visible: sec.collectorInstalled
          }

          Item {
            width: parent.width
            visible: sec.collectorInstalled
            implicitHeight: footerLeft.implicitHeight

            Text {
              id: footerLeft
              anchors.left: parent.left
              text: "updated " + root.relativeAge(sec.ageSec)
                    + (sec.integrityAgeSec >= 0
                       ? "  ·  advisories " + root.relativeAge(sec.integrityAgeSec)
                       : "")
              color: root.fainterColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }

            Text {
              anchors.right: parent.right
              anchors.baseline: footerLeft.baseline
              text: "r · refresh"
              color: root.fainterColor
              font.family: root.fontFamily
              font.pixelSize: Style.font.caption
            }
          }
        }
      }
    }
  }
}
