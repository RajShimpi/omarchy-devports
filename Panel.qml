import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

// Dev Ports: the local servers that listen on TCP ports, one card per process,
// labelled with the project folder and framework it runs. Open or copy a URL,
// open the project in the editor, or stop it (SIGTERM, then SIGKILL after a
// grace period). scripts/devports does the work and prints JSON.
Panel {
  id: root
  moduleName: "techspawn.devports"
  ipcTarget: "techspawn.devports"
  manageIpc: true

  readonly property string helper: Qt.resolvedUrl("scripts/devports").toString().replace(/^file:\/\//, "")
  readonly property color fg: root.bar ? root.bar.foreground : Commons.Color.foreground
  readonly property string font: root.bar ? root.bar.fontFamily : Style.font.family

  // Nerd Font (Material Design) glyphs: md-server_network, md-reload, md-folder, md-server, md-code_braces,
  // md-web, md-open_in_new, md-content_copy, md-file_code, md-stop, md-skull, md-docker, md-bug, md-pencil.
  readonly property var glyphs: ({ hub: 0xf048d, refresh: 0xf0453, folder: 0xf024b, system: 0xf048b, process: 0xf0169,
                                   network: 0xf059f, open: 0xf03cc, copy: 0xf018f, editor: 0xf022e, stop: 0xf04db,
                                   kill: 0xf068c, docker: 0xf0868, debug: 0xf00e4, edit: 0xf03eb })
  function glyph(name) { return String.fromCodePoint(glyphs[name]) }

  property var ports: []
  property string lastText: ""
  property string listError: ""
  property bool showAll: false
  property string status: ""
  property bool statusError: false
  property int busyPid: 0
  property string selectedKey: ""
  property var pending: null      // { how, pid, port, label } waiting for the confirm dialog

  readonly property var sectionTitles: ({ dev: "DEV SERVERS", docker: "DOCKER", app: "APPS", system: "SYSTEM" })

  // One card per process (system services and containers: one per name).
  readonly property var procs: {
    var byKey = {}, order = []
    ports.forEach(function(p) {
      var kind = p.kind || (p.system ? "system" : p.noise ? "app" : "dev")
      if (!showAll && (kind === "app" || kind === "system")) return
      var key = p.pid ? "pid:" + p.pid : kind + ":" + p.name
      var e = byKey[key]
      if (!e) {
        e = byKey[key] = { key: key, kind: kind, pid: p.pid, name: p.name, cmd: p.cmd, cwd: p.cwd, age: p.age,
                           project: p.project, framework: p.framework || "", unit: p.unit || "", user: p.user || "",
                           container: p.container || null, network: false, ports: [], url: "" }
        order.push(e)
      }
      e.ports.push({ port: p.port, url: p.url, http: p.http !== false, label: p.label || "" })
      if (p["public"]) e.network = true
      if (!e.url && p.http !== false) e.url = p.url
    })
    var last = ""
    order.forEach(function(e) { e.first = e.kind !== last; last = e.kind })
    return order
  }
  readonly property int selectedIndex: {
    for (var i = 0; i < procs.length; i++) if (procs[i].key === selectedKey) return i
    return -1
  }
  readonly property var selected: selectedIndex >= 0 ? procs[selectedIndex] : null
  // Dev servers grouped by project: [{ name, pids }]. A project with several processes counts once.
  readonly property var devGroups: {
    var byKey = {}, out = []
    ports.forEach(function(p) {
      if ((p.kind || (p.system ? "system" : p.noise ? "app" : "dev")) !== "dev") return
      var key = p.project ? p.project.path : "pid:" + p.pid
      var g = byKey[key]
      if (!g) { g = byKey[key] = { name: p.project ? p.project.name : (p.framework || p.name), pids: [] }; out.push(g) }
      if (g.pids.indexOf(p.pid) < 0) g.pids.push(p.pid)
    })
    return out
  }
  readonly property int devCount: devGroups.length
  readonly property int procCount: devGroups.reduce(function(n, g) { return n + g.pids.length }, 0)
  readonly property int portCount: ports.filter(function(p) { return showAll || (p.kind || "dev") === "dev" || p.kind === "docker" }).length

  function refresh() { if (!listProc.running) listProc.running = true }

  function say(text, isError) { status = text; statusError = !!isError }

  function title(e) {
    if (e.kind === "docker") return e.name
    if (e.project) return e.project.name
    return e.framework || e.name
  }
  function icon(e) {
    if (e.kind === "docker") return glyph("docker")
    if (e.kind === "system") return glyph("system")
    return e.project ? glyph("folder") : glyph("process")
  }
  function meta(e) {
    var bits = []
    if (e.kind === "docker") bits.push(e.framework)
    else if (e.kind === "system") bits.push("runs as " + e.user + (e.unit ? " · " + e.unit : ""))
    else {
      if (e.project && e.framework) bits.push(e.framework)
      bits.push(e.name + " · pid " + e.pid + " · up " + ageText(e.age))
      if (e.unit) bits.push(e.unit)
    }
    if (e.network) bits.push(glyph("network") + " network")
    return bits.join(" · ")
  }

  function ageText(s) {
    if (s < 60) return s + "s"
    if (s < 3600) return Math.floor(s / 60) + "m"
    if (s < 86400) return Math.floor(s / 3600) + "h " + Math.floor(s % 3600 / 60) + "m"
    return Math.floor(s / 86400) + "d " + Math.floor(s % 86400 / 3600) + "h"
  }

  function shortCmd(c) {
    var home = Quickshell.env("HOME")
    return String(c).split(home + "/").join("~/").replace(/~\/\.local\/share\/mise\/installs\/[^/]+\/[^/]+\/bin\//g, "")
  }

  function select(index) {
    if (procs.length === 0) { selectedKey = ""; return }
    var i = Math.max(0, Math.min(procs.length - 1, index))
    selectedKey = procs[i].key
    ensureVisible(i)
  }
  function ensureVisible(i) {
    var item = cards.itemAt(i)
    if (!item) return
    if (item.y < list.contentY) list.contentY = item.y
    else if (item.y + item.height > list.contentY + list.height) list.contentY = item.y + item.height - list.height
  }
  function current() { return selected || (procs.length ? procs[0] : null) }

  function openUrl(url) {
    if (!url) return
    Quickshell.execDetached(["xdg-open", url])
    root.close()
  }
  function copy(text) {
    if (!text) return
    Quickshell.execDetached(["wl-copy", text])
    say("Copied " + text, false)
  }
  function openEditor(e) {
    if (!e || !e.project || editorProc.running) return
    editorProc.command = [helper, "editor", e.project.path]
    editorProc.running = true
  }

  function askStop(e, how) {
    if (!e || e.pid <= 0 || actProc.running) return
    var p = e.ports.length ? e.ports[0].port : 0
    var label = title(e) + (e.project && e.framework ? " (" + e.framework + ")" : "")
    pending = { how: how, pid: e.pid, port: p, label: label, unit: e.unit }
    confirm.selectedIndex = 1
  }
  function runPending() {
    var p = pending
    pending = null
    if (!p || actProc.running) return
    busyPid = p.pid
    say((p.how === "kill" ? "Killing " : "Stopping ") + p.label + "…", false)
    actProc.label = p.label
    actProc.command = [helper, p.how, String(p.pid)].concat(p.port ? [String(p.port)] : [])
    actProc.running = true
  }

  onOpenedChanged: if (opened) { status = ""; pending = null; selectedKey = ""; list.contentY = 0; refresh() }

  Process {
    id: listProc
    command: [root.helper, "list"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (text === root.lastText) return
        root.lastText = text
        try {
          var d = JSON.parse(text)
          root.ports = d.ports || []
          root.listError = d.error || ""
        } catch (e) {
          root.listError = "Couldn't read the port list (scripts/devports list)"
        }
      }
    }
  }

  Process {
    id: actProc
    property string label: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          if (d.error) root.say(d.error, true)
          else root.say((d.forced ? "Force-stopped " : "Stopped ") + actProc.label, false)
        } catch (e) { root.say("Stop failed", true) }
      }
    }
    onExited: { root.busyPid = 0; root.lastText = ""; root.refresh() }
  }

  Process {
    id: editorProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        try {
          var d = JSON.parse(text)
          if (d.error) root.say(d.error, true)
          else root.close()
        } catch (e) { root.say("Couldn't open the editor", true) }
      }
    }
  }

  Timer { interval: root.opened ? 3000 : 30000; repeat: true; running: true; onTriggered: root.refresh() }
  Component.onCompleted: refresh()

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: root.glyph("hub")
    tooltipText: root.devCount === 0 ? "No dev servers running"
      : "Dev servers: " + root.devGroups.map(function(g) { return g.name + (g.pids.length > 1 ? " (" + g.pids.length + " processes)" : "") }).join(", ")
    onPressed: function(b) { root.toggle() }

    Rectangle {
      visible: root.devCount > 0
      anchors.right: parent.right
      anchors.top: parent.top
      anchors.rightMargin: -2
      width: Math.max(height, countText.implicitWidth + 3)
      height: countText.implicitHeight
      radius: height / 2
      color: Commons.Color.accent
      Text {
        id: countText
        anchors.centerIn: parent
        text: root.devCount > 9 ? "9+" : String(root.devCount)
        color: root.bar ? root.bar.background : Commons.Color.background
        font.family: root.font
        font.pixelSize: Math.max(7, Math.round(Style.font.caption * 0.7))
        font.bold: true
      }
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(560))
    contentHeight: panel.fittedContentHeight(Math.max(column.implicitHeight, root.pending ? Style.space(220) : 0))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: {
        if (root.pending) root.pending = null
        else root.close()
      }
      onTabRequested: function(direction) {
        if (root.pending) confirm.selectedIndex = confirm.selectedIndex === 0 ? 1 : 0
        else root.switchPanel(direction)
      }
      onMoveRequested: function(dx, dy) {
        if (root.pending) { if (dx) confirm.selectedIndex = confirm.selectedIndex === 0 ? 1 : 0; return }
        if (dy) root.select(root.selectedIndex < 0 ? 0 : root.selectedIndex + dy)
      }
      onActivateRequested: {
        if (root.pending) { if (confirm.selectedIndex === 0) root.pending = null; else root.runPending(); return }
        var e = root.current()
        if (e) root.openUrl(e.url)
      }
      onDeleteRequested: if (!root.pending) root.askStop(root.current(), "stop")
      onTextKey: function(t) {
        if (root.pending) return
        var e = root.current()
        if (t === "r") { root.lastText = ""; root.refresh() }
        else if (t === "a") root.showAll = !root.showAll
        else if (t === "o") { if (e) root.openUrl(e.url) }
        else if (t === "c") { if (e) root.copy(e.url) }
        else if (t === "e") root.openEditor(e)
        else if (t === "s") root.askStop(e, "stop")
        else if (t === "K") root.askStop(e, "kill")
      }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        Column {
          id: chrome
          width: parent.width
          spacing: Style.space(10)

          Item {
            width: parent.width
            implicitHeight: hero.implicitHeight
            Row {
              id: hero
              spacing: Style.space(14)
              Text { text: root.glyph("hub"); color: root.fg; font.family: root.font; font.pixelSize: Style.font.display; anchors.verticalCenter: parent.verticalCenter }
              Column {
                anchors.verticalCenter: parent.verticalCenter
                spacing: Style.space(2)
                Text { text: "Dev Ports"; color: root.fg; font.family: root.font; font.pixelSize: Style.font.title; font.bold: true }
                Text {
                  text: (root.devCount + " running · " + root.procCount + " process" + (root.procCount === 1 ? "" : "es") + " · " + root.portCount + " port" + (root.portCount === 1 ? "" : "s")).toUpperCase()
                  color: Qt.darker(root.fg, 1.4); font.family: root.font; font.pixelSize: Style.font.caption; font.bold: true; font.letterSpacing: 1.2
                }
              }
            }
            Row {
              anchors.right: parent.right
              anchors.verticalCenter: parent.verticalCenter
              spacing: Style.space(6)
              Button {
                text: root.showAll ? "Dev only" : "Show all"
                tooltipText: root.showAll ? "Only dev servers and containers (a)" : "Also list desktop apps and system services (a)"
                fontSize: Style.font.caption
                foreground: root.fg; fontFamily: root.font; bordered: true
                onClicked: root.showAll = !root.showAll
              }
              Button {
                iconText: root.glyph("refresh"); tooltipText: "Refresh (r)"
                iconSpinning: listProc.running
                foreground: root.fg; fontFamily: root.font
                onClicked: { root.lastText = ""; root.refresh() }
              }
              Button {
                iconText: root.glyph("edit"); tooltipText: "Settings: editor, stop grace period, apps to hide"
                foreground: root.fg; fontFamily: root.font
                onClicked: { if (!editorProc.running) { editorProc.command = [root.helper, "settings"]; editorProc.running = true } }
              }
            }
          }

          Text {
            visible: root.listError !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: root.listError
            color: Commons.Color.urgent; font.family: root.font; font.pixelSize: Style.font.bodySmall
          }

          Text {
            visible: root.status !== ""
            width: parent.width
            wrapMode: Text.Wrap
            text: root.status
            color: root.statusError ? Commons.Color.urgent : Commons.Color.accent
            font.family: root.font; font.pixelSize: Style.font.bodySmall
          }
        }

        Item {
          width: parent.width
          height: list.height

          Flickable {
            id: list
            width: parent.width - (scrollbar.visible ? Style.space(8) : 0)
            // Never taller than the screen allows: the rest scrolls.
            height: Math.min(listCol.implicitHeight, Style.space(480),
                             Math.max(Style.space(120), panel.availableCardHeight - panel.verticalContentInset - chrome.height - column.spacing - 2))
            contentHeight: listCol.implicitHeight
            clip: true
            boundsBehavior: Flickable.StopAtBounds

            Column {
              id: listCol
              width: list.width
              spacing: Style.space(6)

              Repeater {
                id: cards
                model: root.procs

                delegate: Column {
                  id: entry
                  required property var modelData
                  required property int index
                  readonly property bool own: modelData.pid > 0
                  readonly property bool isSelected: root.selectedKey === modelData.key
                  width: listCol.width
                  spacing: Style.space(6)

                  PanelSectionHeader {
                    visible: entry.modelData.first && (root.showAll || entry.modelData.kind !== "dev" || entry.index > 0)
                    text: root.sectionTitles[entry.modelData.kind] || ""
                    foreground: root.fg; fontFamily: root.font
                  }

                  Rectangle {
                    id: card
                    width: entry.width
                    implicitHeight: cardCol.implicitHeight + Style.space(16)
                    radius: Style.cornerRadius
                    color: entry.isSelected || cardArea.containsMouse
                      ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.10)
                      : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, entry.own && entry.modelData.kind === "dev" ? 0.05 : 0.025)
                    border.width: 1
                    border.color: entry.isSelected ? Commons.Color.accent : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.12)
                    opacity: root.busyPid === entry.modelData.pid && entry.own ? 0.5 : 1

                    MouseArea {
                      id: cardArea
                      anchors.fill: parent
                      hoverEnabled: true
                      onEntered: root.selectedKey = entry.modelData.key
                    }

                    Column {
                      id: cardCol
                      anchors.left: parent.left
                      anchors.right: actions.left
                      anchors.leftMargin: Style.space(10)
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(4)

                      Text {
                        width: parent.width
                        text: root.icon(entry.modelData) + " " + root.title(entry.modelData)
                        color: root.fg; font.family: root.font; font.pixelSize: Style.font.bodySmall; font.bold: true
                        elide: Text.ElideRight
                      }

                      Text {
                        width: parent.width
                        text: root.meta(entry.modelData)
                        color: Qt.darker(root.fg, 1.5); font.family: root.font; font.pixelSize: Style.font.caption
                        elide: Text.ElideRight
                      }

                      Text {
                        visible: entry.own && entry.modelData.cmd !== ""
                        width: parent.width
                        text: root.shortCmd(entry.modelData.cmd)
                        color: Qt.darker(root.fg, 1.8); font.family: root.font; font.pixelSize: Style.font.caption
                        elide: Text.ElideMiddle
                      }

                      Flow {
                        width: parent.width
                        spacing: Style.space(4)
                        Repeater {
                          model: entry.modelData.ports
                          delegate: Rectangle {
                            id: chip
                            required property var modelData
                            height: portText.implicitHeight + Style.space(4)
                            width: portText.implicitWidth + Style.space(12)
                            radius: height / 2
                            color: portArea.containsMouse ? Qt.rgba(Commons.Color.accent.r, Commons.Color.accent.g, Commons.Color.accent.b, 0.3) : Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.1)
                            Text {
                              id: portText
                              anchors.centerIn: parent
                              text: ":" + chip.modelData.port + (chip.modelData.label === "debugger" ? " " + root.glyph("debug") + " debugger"
                                                                 : chip.modelData.http ? " " + root.glyph("open") : "")
                              color: root.fg; font.family: root.font; font.pixelSize: Style.font.caption; font.bold: true
                            }
                            MouseArea {
                              id: portArea
                              anchors.fill: parent
                              hoverEnabled: true
                              acceptedButtons: Qt.LeftButton | Qt.RightButton
                              cursorShape: Qt.PointingHandCursor
                              onClicked: function(mouse) {
                                if (mouse.button === Qt.RightButton || !chip.modelData.http) root.copy(chip.modelData.http ? chip.modelData.url : "localhost:" + chip.modelData.port)
                                else root.openUrl(chip.modelData.url)
                              }
                            }
                          }
                        }
                      }
                    }

                    Row {
                      id: actions
                      anchors.right: parent.right
                      anchors.rightMargin: Style.space(8)
                      anchors.verticalCenter: parent.verticalCenter
                      spacing: Style.space(4)

                      Button {
                        visible: entry.modelData.url !== ""
                        iconText: root.glyph("copy")
                        tooltipText: "Copy " + entry.modelData.url + " (c)"
                        foreground: root.fg; fontFamily: root.font; bordered: true
                        onClicked: root.copy(entry.modelData.url)
                      }
                      Button {
                        visible: !!entry.modelData.project && entry.modelData.kind !== "system"
                        iconText: root.glyph("editor")
                        tooltipText: "Open " + (entry.modelData.project ? entry.modelData.project.path : "") + " in the editor (e)"
                        foreground: root.fg; fontFamily: root.font; bordered: true
                        onClicked: root.openEditor(entry.modelData)
                      }
                      Button {
                        visible: entry.own
                        iconText: root.glyph("stop")
                        text: root.busyPid === entry.modelData.pid ? "…" : "Stop"
                        fontSize: Style.font.caption
                        tooltipText: "Stop it and its child processes (s)"
                        foreground: root.fg; fontFamily: root.font; bordered: true
                        onClicked: root.askStop(entry.modelData, "stop")
                      }
                      Button {
                        visible: entry.own
                        iconText: root.glyph("kill")
                        tooltipText: "Force kill right away (Shift+K)"
                        foreground: root.fg; fontFamily: root.font; bordered: true
                        onClicked: root.askStop(entry.modelData, "kill")
                      }
                    }
                  }
                }
              }

              Text {
                visible: root.procs.length === 0
                width: parent.width
                topPadding: Style.space(10)
                bottomPadding: Style.space(6)
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: root.listError !== "" ? "" : root.ports.length === 0 && root.lastText === "" ? "Looking for listening ports…"
                    : root.showAll ? "Nothing is listening on a TCP port" : "No dev servers running · a shows everything"
                color: Qt.darker(root.fg, 1.5); font.family: root.font; font.pixelSize: Style.font.bodySmall
              }

              Text {
                visible: root.procs.length > 0
                width: parent.width
                horizontalAlignment: Text.AlignHCenter
                wrapMode: Text.Wrap
                text: "j/k select · Enter open · c copy · e editor · s stop · Shift+K kill · a all · r refresh"
                color: Qt.darker(root.fg, 1.9); font.family: root.font; font.pixelSize: Style.font.caption
              }
            }
          }

          Rectangle {
            id: scrollbar
            visible: list.contentHeight > list.height + 1
            anchors.right: parent.right
            y: list.visibleArea.yPosition * list.height
            width: Style.space(3)
            height: Math.max(Style.space(20), list.visibleArea.heightRatio * list.height)
            radius: width / 2
            color: Qt.rgba(root.fg.r, root.fg.g, root.fg.b, 0.3)
          }
        }
      }

      ConfirmDialog {
        id: confirm
        anchors.fill: parent
        z: 10
        opened: root.pending !== null
        message: !root.pending ? ""
          : root.pending.how === "kill"
            ? "Force-kill " + root.pending.label + " (pid " + root.pending.pid + ") and its child processes now?"
            : "Stop " + root.pending.label + " (pid " + root.pending.pid + ") and its child processes?"
              + (root.pending.unit ? " " + root.pending.unit + " may start it again." : "")
        confirmText: root.pending && root.pending.how === "kill" ? "Kill" : "Stop"
        foreground: root.fg
        background: Commons.Color.popups.background
        fontFamily: root.font
        onCanceled: root.pending = null
        onConfirmed: root.runPending()
      }
    }
  }
}
