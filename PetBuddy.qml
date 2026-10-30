import QtQuick
import Quickshell
import Quickshell.Io

// Build buddy: watches the tiny event file the optional shell hook writes
// ($XDG_RUNTIME_DIR/desktop-pet/buddy.json: {t, cmd, code, dur}; command name
// only, never arguments) and emits commandFinished(). Polls every 2 s while
// enabled; reading a ~60-byte file is cheaper than juggling inotify on a file
// that is replaced by rename.
Item {
  id: buddy
  property bool enabled: true
  property real lastT: -1
  signal commandFinished(string cmd, int code, int dur)

  FileView {
    id: ev
    path: (Quickshell.env("XDG_RUNTIME_DIR") || "/tmp") + "/desktop-pet/buddy.json"
    printErrors: false
    onLoaded: {
      var e = null
      try { e = JSON.parse(text()) } catch (x) { return }
      if (!e || typeof e.t !== "number") return
      if (buddy.lastT < 0) { buddy.lastT = e.t; return }   // ignore what happened before we started
      if (e.t === buddy.lastT) return
      buddy.lastT = e.t
      buddy.commandFinished(String(e.cmd || "").substring(0, 40), Number(e.code) || 0, Number(e.dur) || 0)
    }
    onLoadFailed: if (buddy.lastT < 0) buddy.lastT = 0
  }
  Timer { interval: 2000; repeat: true; running: buddy.enabled; onTriggered: ev.reload() }
}
