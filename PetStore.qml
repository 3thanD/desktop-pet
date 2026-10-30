import QtQuick
import Quickshell
import Quickshell.Io

// Persistent pet state: ~/.local/state/desktop-pet/state.json (never in the
// plugin directory, so `omarchy plugin update` can't touch it).
//
//  { "version": 2, "pets": { "<species>": {record}, ... },
//    "pos": {"x","y"}, "hintShown": bool, "savedAt": ms }
//
// record = { hatchedAt, stage, variant, meals, lettersEaten,
//            diet: {digits, vowels, consonants}, careDays, lastCareDay,
//            hunger, happiness, energy, lastMealAt, lastPetAt, plays, bestThrow }
//
// Writes are atomic (temp file + rename). A rolling state.json.bak is
// refreshed every 10 minutes. A file that fails to parse is kept as
// state.json.corrupt-<time> and the .bak is used instead, so a beloved pet is
// never silently reset.
Item {
  id: store

  property string dir: Quickshell.env("HOME") + "/.local/state/desktop-pet"
  property var doc: null          // null until loaded
  property bool ready: false
  property real lastBak: 0
  property string recovered: ""    // "", "bak" or "fresh-after-corrupt"
  signal loaded()

  function blank() { return { version: 2, pets: {}, pos: null, hintShown: false, savedAt: 0 } }

  function newRecord(now) {
    return { hatchedAt: now, stage: 1, variant: "classic", meals: 0, lettersEaten: 0,
             diet: { digits: 0, vowels: 0, consonants: 0 }, careDays: 0, lastCareDay: "",
             hunger: 80, happiness: 80, energy: 80, lastMealAt: 0, lastPetAt: now, plays: 0, bestThrow: 0 }
  }

  // v1 (one flat object for the current pet) -> v2
  function migrate(s) {
    if (s && s.version === 2 && s.pets) return s
    var d = blank()
    if (s && typeof s.hunger === "number" && s.pet) {
      var r = newRecord(typeof s.savedAt === "number" ? s.savedAt : Date.now())
      var keys = ["hunger", "happiness", "energy", "meals", "lettersEaten", "lastMealAt", "lastPetAt"]
      for (var i = 0; i < keys.length; i++) if (typeof s[keys[i]] === "number") r[keys[i]] = s[keys[i]]
      if (r.meals > 0) r.careDays = 1
      d.pets[s.pet] = r
      if (typeof s.posX === "number") d.pos = { x: s.posX, y: s.posY }
      d.hintShown = !!s.hintShown
      d.savedAt = s.savedAt || 0
    }
    return d
  }

  function parse(raw) {
    if (!raw || !String(raw).trim()) return null
    try {
      var s = JSON.parse(raw)
      return (s && typeof s === "object") ? s : null
    } catch (e) { return null }
  }

  property bool migrated: false
  function finish(d, how) {
    migrated = !!d && d.version !== 2
    doc = migrate(d)
    recovered = how
    ready = true
    loaded()
  }

  function save() {
    if (!ready || !doc) return
    doc.savedAt = Date.now()
    var raw = JSON.stringify(doc, null, 1) + "\n"
    stateFile.setText(raw)
    if (Date.now() - lastBak > 10 * 60000) { bakFile.setText(raw); lastBak = Date.now() }
  }

  FileView {
    id: stateFile
    path: store.dir + "/state.json"
    printErrors: false
    atomicWrites: true
    onLoaded: {
      if (store.ready) return
      var raw = text()
      var s = store.parse(raw)
      if (s) { store.finish(s, ""); return }
      if (raw && raw.trim()) {   // corrupt: keep it for inspection, fall back to the .bak
        keepCorrupt.command = ["cp", "-f", path, path + ".corrupt-" + Date.now()]
        keepCorrupt.running = true
      }
      store.wantBak = true
      bakFile.reload()
    }
    onLoadFailed: { if (store.ready) return; store.wantBak = true; bakFile.reload() }
  }
  property bool wantBak: false
  FileView {
    id: bakFile
    path: store.dir + "/state.json.bak"
    printErrors: false
    atomicWrites: true
    onLoaded: {
      if (!store.wantBak || store.ready) return
      var s = store.parse(text())
      store.finish(s || store.blank(), s ? "bak" : "")
    }
    onLoadFailed: { if (store.wantBak && !store.ready) store.finish(store.blank(), "") }
  }
  Process { id: keepCorrupt }
  Process {
    id: mkdir
    command: ["mkdir", "-p", store.dir]
    running: true
    onExited: stateFile.reload()
  }
}
