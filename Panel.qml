import QtQuick
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// Bar widget + click-open panel for Dotstate. Shows the sync state written
// by backup.sh (see ../backup.sh) and offers quick actions.
//
// IMPORTANT: `omarchy plugin add` clones this repo into its own directory
// under ~/.config/omarchy/plugins/<id>/, separate from wherever you keep
// your actual working dotfiles checkout (the one with your real home/ and
// packages/, where install.sh/backup.sh actually run). This widget can't
// assume it lives inside that checkout, so the path is a per-instance
// setting (dotfilesRepo) instead of being inferred - set it once in the
// panel itself (the text field below), which persists it inline in
// ~/.config/omarchy/shell.json via bar.shell.updateEntryInline(). There is
// no separate "settings" UI for third-party widgets in Setup > Plugins as
// of this Omarchy version, so the panel has to own this itself.
Panel {
  id: root
  moduleName: "io.github.marcmeier.dotstate"
  ipcTarget: "io.github.marcmeier.dotstate"
  manageIpc: false

  readonly property string rawRepoDir: String(setting("dotfilesRepo", ""))
  readonly property string repoDir: rawRepoDir.replace(/^~/, Quickshell.env("HOME"))
  readonly property bool configured: repoDir !== ""
  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 60, 10, 3600)
  readonly property string statusPath: Quickshell.env("HOME") + "/.cache/dotstate/status.json"

  property var status: Model.defaultStatus()
  property bool syncing: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)

  readonly property color iconColor: {
    if (!configured || !status.known) return dim
    if (!status.ok) return urgent
    return foreground
  }

  readonly property string tooltipText: {
    if (!configured) return "Dotstate: click and set your dotfiles repo path below"
    if (!status.known) return "Dotstate: no sync run yet - click Sync now"
    var when = Model.relativeTime(status.lastRun)
    if (!status.ok) return "Dotstate: last sync failed " + when + (status.error ? " (" + status.error + ")" : "")
    if (status.dirty) return "Dotstate: synced " + when + ", but local changes remain"
    return "Dotstate: synced " + when
  }

  function setting(name, fallback) {
    var value = root.settings ? root.settings[name] : undefined
    return value === undefined || value === null || value === "" ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function refresh() {
    statusFile.reload()
  }

  // Persists dotfilesRepo inline into this widget's own bar.layout entry in
  // ~/.config/omarchy/shell.json, the same mechanism Power/Tailscale/Clock
  // use for their own per-instance settings (see shell/shell.qml's
  // updateEntryInline - it replaces the entry with {id, ...settings}, so the
  // full settings object must be passed, not just the changed key).
  function saveDotfilesRepo(path) {
    var trimmed = String(path || "").trim()
    if (trimmed === rawRepoDir) return
    var next = Object.assign({}, root.settings, { dotfilesRepo: trimmed })
    if (root.bar && root.bar.shell && typeof root.bar.shell.updateEntryInline === "function") {
      root.bar.shell.updateEntryInline(root.moduleName, next)
    }
  }

  function syncNow() {
    if (!configured || syncProc.running) return
    syncing = true
    syncProc.command = ["systemctl", "--user", "start", "dotstate-backup.service"]
    syncProc.running = true
  }

  // Best-effort: opens a floating terminal for the read-only check scripts,
  // matching the pattern first-party widgets use (see SystemUpdate.qml's
  // "omarchy-launch-floating-terminal-with-presentation" call). Verify this
  // renders as expected on a real Omarchy session - it wasn't runnable from
  // where this plugin was authored.
  function runInFloatingTerminal(scriptName) {
    if (!configured || !root.bar) return
    var inner = "cd " + Util.shellQuote(repoDir) + " && ./" + scriptName + "; echo; read -n1 -p 'Press any key to close'"
    var cmd = "bash -lc " + Util.shellQuote(inner)
    root.bar.run("omarchy-launch-floating-terminal-with-presentation " + cmd)
  }

  function openRepo() {
    if (!configured) return
    Quickshell.execDetached(["xdg-open", repoDir])
  }

  FileView {
    id: statusFile
    path: root.statusPath
    watchChanges: true
    printErrors: false
    onFileChanged: reload()
    onLoaded: root.status = Model.parseStatus(text())
    onLoadFailed: root.status = Model.defaultStatus()
  }

  Process {
    id: syncProc
    command: []
    onExited: {
      root.syncing = false
      settleTimer.restart()
    }
  }

  Timer {
    id: settleTimer
    interval: 2000
    repeat: false
    onTriggered: root.refresh()
  }

  Timer {
    interval: root.refreshIntervalSec * 1000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  visible: true
  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) root.refresh()

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): void { root.refresh() }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    text: ""
    foreground: root.iconColor
    tooltipText: root.tooltipText
    onPressed: root.toggle()
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(320))
    contentHeight: panel.fittedContentHeight(column.implicitHeight)

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }

      Column {
        id: column
        anchors.left: parent.left
        anchors.right: parent.right
        anchors.top: parent.top
        spacing: Style.space(10)

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: root.tooltipText
          color: root.foreground
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
          wrapMode: Text.WordWrap
        }

        Text {
          textFormat: Text.PlainText
          width: parent.width
          text: "DOTFILES REPO PATH"
          color: root.dim
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.caption
        }

        Row {
          width: parent.width
          spacing: Style.space(6)

          TextField {
            id: repoField
            width: parent.width - saveButton.width - parent.spacing
            text: root.rawRepoDir
            placeholderText: "~/Projects/dotfiles"
            foreground: root.foreground
            font.family: root.bar ? root.bar.fontFamily : Style.font.family
            onAccepted: root.saveDotfilesRepo(repoField.text)
          }

          Button {
            id: saveButton
            text: "Save"
            foreground: root.foreground
            fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
            bordered: true
            onClicked: root.saveDotfilesRepo(repoField.text)
          }
        }

        PanelSeparator {
          foreground: root.foreground
        }

        Button {
          width: parent.width
          text: root.syncing ? "Syncing…" : "Sync now"
          enabled: root.configured && !root.syncing
          foreground: root.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          bordered: true
          onClicked: root.syncNow()
        }

        Button {
          width: parent.width
          text: "Check package drift"
          enabled: root.configured
          foreground: root.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          bordered: true
          onClicked: root.runInFloatingTerminal("check-drift.sh")
        }

        Button {
          width: parent.width
          text: "Check symlinks"
          enabled: root.configured
          foreground: root.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          bordered: true
          onClicked: root.runInFloatingTerminal("check-links.sh")
        }

        Button {
          width: parent.width
          text: "Open repo"
          enabled: root.configured
          foreground: root.foreground
          fontFamily: root.bar ? root.bar.fontFamily : Style.font.family
          bordered: true
          onClicked: root.openRepo()
        }
      }
    }
  }
}
