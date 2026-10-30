import QtQuick
import Quickshell
import Quickshell.Io
import Quickshell.Wayland
import "Sprites.js" as Sprites

// Desktop pet service. Two layer-shell windows:
//  - overlayWin: sized to the target terminal, draws "eaten"/"burned" cell
//    patches. Created first and kept mapped (1x1 when idle) so the pet window
//    always stacks above it.
//  - petWin: a small click-through window (only the sprite/card take input)
//    that moves by changing its layer-shell margins.
// Nothing animates continuously: a slow brain timer drives behavior, a 20 fps
// timer runs only while walking, and a ~2 fps timer flips idle frames.
// Host-independent: everything desktop-specific (theme colors, theme name, UI
// font) comes from `host` (OmarchyHost.qml on Omarchy). With no host it falls
// back to a built-in palette, so a plain-Quickshell entry point can reuse it.
Item {
  id: root

  property var host: null
  // Plugin directory (scripts/, bin/). Entry points may override it.
  property string pluginDir: decodeURIComponent(Qt.resolvedUrl(".").toString().replace("file://", "")).replace(/\/$/, "")

  readonly property string home: Quickshell.env("HOME")
  readonly property string helper: pluginDir + "/scripts/helper.py"
  readonly property string stateDir: home + "/.local/state/desktop-pet"
  readonly property string configPath: home + "/.config/desktop-pet/config.json"

  // ---------------------------------------------------------------- config
  property var cfg: ({ pet: "slime", names: {}, accessory: "auto", eat: true, goblinSteal: true,
                       chatty: "low", brain: true, brainContext: false, themePets: {}, size: 100, color: "theme", fetch: true, buddy: true })

  // ---- from the host (or fallbacks)
  readonly property string themeName: host ? host.themeName : ""
  readonly property string uiFont: host && host.uiFont ? host.uiFont : "monospace"
  readonly property var tc: Sprites.themeColors(host ? host.colorsRaw : "", host ? {
    accent: String(host.accent), foreground: String(host.foreground), background: String(host.background) } : {})
  readonly property color cAccent: tc.accent
  readonly property color cBg: tc.background
  readonly property color cFg: tc.foreground
  readonly property var themeInfo: Sprites.themeInfo(themeName)
  readonly property string pet: {
    var tp = cfg.themePets || {}
    var mapped = tp[Sprites.slug(themeName)]
    var p = (mapped && Sprites.PET_NAMES.indexOf(mapped) >= 0) ? mapped : cfg.pet
    return Sprites.PET_NAMES.indexOf(p) >= 0 ? p : "slime"
  }
  readonly property string petName: (cfg.names && cfg.names[pet]) ? String(cfg.names[pet]) : ""
  readonly property string displayName: petName !== "" ? petName : "your " + pet
  readonly property var acc: Sprites.accessoriesFor(themeName, cfg.accessory)
  readonly property var pal: Sprites.palette(pet, tc, !!themeInfo.mono, cfg.color)
  readonly property color patchColor: tc.background
  readonly property color fireColor: tc.red

  // ---------------------------------------------------------------- stats
  property real hunger: 80
  property real happiness: 80
  property real energy: 80
  property int lettersEaten: 0
  property int meals: 0
  property real lastTick: Date.now()
  property real lastMealAt: 0
  property real lastPetAt: Date.now()
  property real wakeUntil: 0
  property bool napping: false
  property bool ignoredLogged: false
  property bool stateLoaded: false
  property bool hintShown: false

  // ---------------------------------------------------------------- growth
  // (per species; see PetStore.qml and evolution thresholds in stageFor())
  property real hatchedAt: Date.now()
  property int stage: 1                 // 1 baby, 2 teen, 3 adult, 4 elder
  property string variant: "classic"    // adult form: classic | cyber | chonk
  property var diet: ({ digits: 0, vowels: 0, consonants: 0 })
  property int careDays: 0
  property string lastCareDay: ""
  property int plays: 0
  property real bestThrow: 0
  property bool egg: false              // waiting to hatch
  readonly property real ageDays: Math.max(0, (clock.date.getTime() - hatchedAt) / 86400000)
  readonly property string stageName: Sprites.STAGES[stage] + (stage === 3 && variant !== "classic" ? " (" + variant + ")" : "")

  // ---------------------------------------------------------------- behavior
  property string mode: "idle"          // idle walk eat fire sleep heist treat
  property string task: ""              // what a walk is for
  property real posX: 1400
  property real posY: 700
  property int dir: 1
  property int frame: 0
  property bool blink: false
  property bool mouthOpen: false
  property real hopY: 0
  property var goal: null
  property var arrive: null
  property real nextFoodTry: 0
  property real nextFireAt: Date.now() + 4 * 60000
  property string carryIcon: ""
  property var heist: null              // {mode, id, returnAt}
  property bool dockInstalled: true
  property int zstep: 0

  // Size: whole-pixel multiples keep the art crisp (50/100/200% = 2/4/8 px per art pixel).
  readonly property int sizePct: [50, 100, 200].indexOf(Number(cfg.size)) >= 0 ? Number(cfg.size) : 100
  readonly property int px: sizePct === 50 ? 2 : (sizePct === 200 ? 8 : Sprites.SCALE)
  readonly property real k: px / Sprites.SCALE                 // 0.5 / 1 / 2
  readonly property int fireDist: Math.round(46 * k)
  readonly property int winW: Math.max(220, spr + 2 * (fireDist + 30))
  readonly property int winH: spr + 120
  readonly property int spr: Sprites.GRID_W * px               // 40 / 80 / 160 px
  onPxChanged: {
    keepOnScreen()
    if (mode === "eat" || mode === "fire" || task === "eat" || task === "fire") resetActivity()
    sprite.requestPaint()
  }
  // babies are drawn smaller, bottom-centred in the same box
  readonly property int cellPx: stage === 1 && !egg ? Sprites.babyPx(px) : px
  readonly property int artX: Math.round((spr - Sprites.GRID_W * cellPx) / 2)
  readonly property int artY: spr - Sprites.GRID_W * cellPx
  readonly property int artTop: artY + Sprites.topCell(pet, egg ? [] : acc, stage) * cellPx
  readonly property int sprLeft: (winW - spr) / 2
  // a small floor margin so bob frames and the outline never touch/cross the monitor edge
  readonly property int floorPad: Math.max(3, px)
  readonly property int sprTop: winH - spr - floorPad
  // The pet lives on the focused monitor (switches when it is idle).
  property string screenName: ""
  function screenByName(n) {
    var list = Quickshell.screens
    for (var i = 0; i < list.length; i++) if (list[i].name === n) return list[i]
    return list.length ? list[0] : null
  }
  readonly property var petScreen: screenByName(screenName)
  readonly property int screenW: petScreen ? petScreen.width : 1280
  readonly property int screenH: petScreen ? petScreen.height : 720
  readonly property real maxX: Math.max(0, screenW - winW)
  readonly property real maxY: Math.max(0, screenH - winH)
  // Keep the whole window (and so the whole sprite) on the monitor: called on
  // every size / monitor change and by the watchdog in think().
  function keepOnScreen() {
    var x = clamp(posX, 0, maxX), y = clamp(posY, 0, maxY)
    if (x !== posX || y !== posY) {
      posX = x; posY = y
      if (goal) goal = { x: clamp(goal.x, 0, maxX), y: clamp(goal.y, 0, maxY) }
      return true
    }
    return false
  }
  onScreenWChanged: keepOnScreen()
  onScreenHChanged: keepOnScreen()
  readonly property bool night: { var h = clock.hours; return h >= 23 || h < 7 }
  readonly property bool sleeping: mode === "sleep"

  SystemClock { id: clock; precision: SystemClock.Minutes }

  // ---------------------------------------------------------------- overlay data
  property var target: null             // {address,x,y,w,h,cw,ch,ox,oy}
  property bool targetVisible: false
  property var patches: []              // {addr,col,row,kind,ch,until}
  readonly property var shownPatches: {
    if (!target) return []
    var a = target.address
    return patches.filter(function (p) { return p.addr === a })
  }
  property var pendingRun: null

  // ---------------------------------------------------------------- talking
  property string bubbleText: ""
  property bool menuOpen: menuWin.open
  property var talkQueue: []
  property real nextChatAt: Date.now() + chatGapMs() * (0.4 + Math.random() * 0.4)
  property real lastClaudeClick: 0
  property real lastAutoTalk: 0

  function now() { return Date.now() }
  function clamp(v, a, b) { return Math.max(a, Math.min(b, v)) }
  function rnd(a, b) { return a + Math.random() * (b - a) }

  property string moodOverride: ""
  Timer { id: moodTimer; interval: 4000; onTriggered: { root.moodOverride = ""; sprite.requestPaint() } }
  function mood() {
    if (moodOverride !== "") return moodOverride
    if (sleeping) return "sleepy"
    if (hunger < 15) return "grumpy"
    if (happiness < 25) return "sad"
    if (energy < 15) return "tired"
    if (happiness > 75 && hunger > 50) return "happy"
    return "content"
  }

  function chatGapMs() {
    var c = cfg ? cfg.chatty : "low"
    if (c === "high") return 4 * 60000
    if (c === "normal") return 8 * 60000
    if (c === "off") return 1e12
    return 15 * 60000
  }
  function clickGapMs() {
    var c = cfg.chatty
    if (c === "high") return 30000
    if (c === "normal") return 60000
    return 180000
  }

  // ---------------------------------------------------------------- files
  FileView {
    id: configFile
    path: root.configPath
    watchChanges: true
    printErrors: false
    atomicWrites: true
    onFileChanged: reload()
    onLoaded: root.applyConfig(text())
    onLoadFailed: root.applyConfig("{}")
  }

  function applyConfig(raw) {
    var c = {}
    try { c = JSON.parse(raw || "{}") } catch (e) { return }
    var oldPet = pet
    var oldSteal = cfg.goblinSteal
    var n = { pet: "slime", names: {}, accessory: "auto", eat: true, goblinSteal: true,
              chatty: "low", brain: true, brainContext: false, themePets: {}, size: 100, color: "theme", fetch: true, buddy: true }
    for (var k in n) if (c[k] !== undefined && c[k] !== null) n[k] = c[k]
    cfg = n
    if (pet !== oldPet) petSwitched(oldPet)
    if (oldSteal && !cfg.goblinSteal) endHeist(true)
    sprite.requestPaint()
  }

  // Same file the CLI edits; unknown keys are preserved.
  function setConfig(key, value) {
    var c = {}
    try { c = JSON.parse(configFile.text() || "{}") } catch (e) { c = {} }
    if (typeof c !== "object" || c === null) c = {}
    c[key] = value
    var raw = JSON.stringify(c, null, 1) + "\n"
    configFile.setText(raw)
    applyConfig(raw)
  }

  function openMenu() {
    // pause: stop walking (a heist keeps its journal and return timer)
    if (mode === "walk") { moveTimer.stop(); goal = null; arrive = null; task = ""; hopY = 0; mode = "idle" }
    bubbleText = ""
    menuWin.show()
  }

  function sayToPet(text) {
    talk("say", "", true, true, text)
  }

  Process { id: offProc }
  function turnOff() {
    saveState()
    offProc.command = [pluginDir + "/bin/desktop-pet", "off"]
    offProc.running = true
  }

  function petSwitched(oldPet) {
    if (oldPet === "goblin") endHeist(true)
    resetActivity()
    if (store.ready) {
      if (!egg) store.doc.pets[oldPet] = recordOf()   // each species keeps its own save
      enterSpecies(pet, 0)
      saveState()
    }
    if (!egg) bubble("*poof* " + displayName + " is here!")
  }

  onTcChanged: sprite.requestPaint()

  PetStore { id: store; onLoaded: root.onStoreLoaded() }

  function onStoreLoaded() {
    var d = store.doc
    if (d.pos && typeof d.pos.x === "number") {
      posX = clamp(d.pos.x, 0, Math.max(0, screenW - winW)); posY = clamp(d.pos.y, 0, Math.max(0, screenH - winH))
    }
    hintShown = !!d.hintShown
    stateLoaded = true
    if (store.recovered === "bak") logEvent("woke up a bit confused (state restored from backup)")
    enterSpecies(pet, d.savedAt || 0)
    if (store.migrated || store.recovered !== "") saveSoon()
  }

  // Load a species' record into the live properties (or lay an egg).
  function enterSpecies(sp, savedAt) {
    var r = store.doc.pets[sp]
    if (!r) { startEgg(); return }
    egg = false
    hunger = r.hunger; happiness = r.happiness; energy = r.energy
    meals = r.meals || 0; lettersEaten = r.lettersEaten || 0
    lastMealAt = r.lastMealAt || 0; lastPetAt = r.lastPetAt || now()
    hatchedAt = r.hatchedAt || now(); stage = r.stage || 1; variant = r.variant || "classic"
    diet = r.diet || { digits: 0, vowels: 0, consonants: 0 }
    careDays = r.careDays || 0; lastCareDay = r.lastCareDay || ""
    plays = r.plays || 0; bestThrow = r.bestThrow || 0
    // time away: half-speed decay, never below 10
    if (savedAt > 0) {
      var mins = Math.max(0, (now() - savedAt) / 60000) / 2
      hunger = clamp(hunger - mins / 3, Math.min(hunger, 10), 100)
      happiness = clamp(happiness - mins / 4, Math.min(happiness, 10), 100)
      energy = clamp(energy + mins / 3, 0, 100)
    }
    lastTick = now()
    sprite.requestPaint()
  }

  function recordOf() {
    return { hatchedAt: hatchedAt, stage: stage, variant: variant, meals: meals, lettersEaten: lettersEaten,
             diet: diet, careDays: careDays, lastCareDay: lastCareDay,
             hunger: Math.round(hunger * 10) / 10, happiness: Math.round(happiness * 10) / 10,
             energy: Math.round(energy * 10) / 10, lastMealAt: lastMealAt, lastPetAt: lastPetAt,
             plays: plays, bestThrow: Math.round(bestThrow) }
  }

  function saveState(species) {
    if (!stateLoaded || !store.ready) return
    var sp = species || pet
    if (!egg) store.doc.pets[sp] = recordOf()
    store.doc.pos = { x: Math.round(posX), y: Math.round(posY) }
    store.doc.hintShown = hintShown
    store.doc.current = pet
    store.save()
    statusFile.setText(JSON.stringify(statusObj(), null, 1) + "\n")
  }
  Timer { id: saveSoonTimer; interval: 800; onTriggered: root.saveState() }
  function saveSoon() { saveSoonTimer.restart() }

  // A small read-only snapshot for the CLI (status when the IPC is unavailable).
  FileView { id: statusFile; path: root.stateDir + "/status.json"; printErrors: false; atomicWrites: true; blockLoading: true }
  function statusObj() {
    return { pet: pet, name: petName, mood: mood(), mode: mode, egg: egg,
      hunger: Math.round(hunger), happiness: Math.round(happiness), energy: Math.round(energy),
      stage: stage, stageName: stageName, variant: variant, ageDays: Math.floor(ageDays), meals: meals,
      lettersEaten: lettersEaten, careDays: careDays, plays: plays,
      theme: themeName, accessory: acc.join(","), patches: patches.length,
      heist: heist, target: target ? target.cls : "", x: Math.round(posX), y: Math.round(posY), savedAt: now() }
  }

  // Count a day of care (fed, petted or played with) for evolution.
  function careTick() {
    var d = new Date(), day = d.getFullYear() + "-" + (d.getMonth() + 1) + "-" + d.getDate()
    if (day !== lastCareDay) { lastCareDay = day; careDays++ }
  }

  // ---------------------------------------------------------------- processes
  Process {
    id: scanProc
    property string purpose: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onScan(scanProc.purpose, text) }
  }
  Process {
    id: geomProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onGeom(text) }
  }
  Process {
    id: dockProc
    property string purpose: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onDock(dockProc.purpose, text) }
  }
  Process {
    id: monitorProc
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onMonitor(text) }
  }
  Process {
    id: notifyProc
  }
  Process {
    id: talkProc
    property string trigger: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onTalk(talkProc.trigger, text) }
    onExited: root.pumpTalk()
  }

  function runHelper(proc, args) {
    if (proc.running) return false
    proc.command = ["python3", "-I", helper].concat(args)
    proc.running = true
    return true
  }

  // ---------------------------------------------------------------- timers
  Timer {
    id: brainTimer
    interval: 3000
    running: true
    repeat: true
    property int ticks: 0
    triggeredOnStart: true
    onTriggered: {
      if (ticks % 10 === 0) root.runHelper(monitorProc, ["monitor"])
      if (ticks > 0) root.think()
      ticks++
      if (ticks % 20 === 0) root.saveState()
    }
  }

  Timer {
    id: moveTimer
    interval: 66   // ~15 fps steps; hops move the window, not its content
    repeat: true
    onTriggered: root.step()
  }

  Timer {
    id: animTimer
    interval: root.sleeping ? 900 : 550
    repeat: true
    running: !moveTimer.running && root.mode !== "eat"
    onTriggered: {
      root.frame = root.frame ? 0 : 1
      if (root.sleeping) { root.blink = true; root.zstep = (root.zstep + 1) % 6 }
      else root.blink = Math.random() < 0.1
      sprite.requestPaint()
    }
  }

  Timer {
    id: geomTimer
    interval: 2000
    repeat: true
    running: root.patches.length > 0 || root.mode === "eat" || root.mode === "fire" || root.task === "eat" || root.task === "fire"
    triggeredOnStart: true
    onTriggered: if (root.target) root.runHelper(geomProc, ["geom", root.target.address])
  }

  Timer {
    id: healTimer
    interval: 15000
    repeat: true
    running: root.patches.length > 0
    onTriggered: {
      var t = root.now()
      var keep = root.patches.filter(function (p) { return p.until > t })
      if (keep.length !== root.patches.length) root.patches = keep
    }
  }

  Timer { id: bubbleTimer; interval: 6500; onTriggered: root.bubbleText = "" }

  // ---------------------------------------------------------------- brain
  function think() {
    var t = now()
    var dt = Math.min(5, (t - lastTick) / 60000)
    lastTick = t
    if (keepOnScreen()) saveSoon()   // watchdog: never stay off-screen (stale saves, monitor changes)
    if (egg || !stateLoaded) return
    if (sleeping) {
      hunger -= dt / 6; energy += dt * 0.6; happiness -= dt / 12
    } else {
      hunger -= dt / 3; energy -= dt / 5
      happiness -= dt / (hunger < 20 ? 2 : 4)
    }
    hunger = clamp(hunger, 0, 100); happiness = clamp(happiness, 0, 100); energy = clamp(energy, 0, 100)

    checkEvolution()
    if (!ignoredLogged && t - lastPetAt > 2 * 3600000) { ignoredLogged = true; logEvent("nobody has petted me for over two hours") }

    var shouldSleep = ((night && t > wakeUntil) || napping)
    if (energy < 8 && !night && t > wakeUntil) { napping = true; shouldSleep = true }
    if (napping && energy > 45) napping = false

    if (shouldSleep && mode === "idle") { goSleep(); return }
    if (!shouldSleep && sleeping) { wakeUp(false); return }
    if (mode !== "idle" || menuOpen) return

    // heist return
    if (heist && t > heist.returnAt) { returnIcon(); return }

    if (hunger < 45 && t - lastMealAt > 6 * 60000 && t > nextFoodTry) { startMeal(); return }
    if (pet === "dragon" && cfg.eat && t > nextFireAt && hunger > 30) { nextFireAt = t + rnd(10, 20) * 60000; startFire(); return }
    if (t > nextChatAt && cfg.brain && cfg.chatty !== "off") {
      nextChatAt = t + chatGapMs() * rnd(0.8, 1.3)
      talk("auto", "", true, true)
    }
    if (Math.random() < 0.06) wander()
  }

  // ---------------------------------------------------------------- evolution
  // Real calendar time AND care (days on which it was fed, petted or played with):
  //   teen   2+ days old, 20+ meals, 2+ care days
  //   adult  7+ days old, 70+ meals, 5+ care days   (diet picks classic / cyber / chonk)
  //   elder  30+ days old, 300+ meals, 20+ care days, happy (70+) at the time
  function stageFor() {
    var a = ageDays, st = 1
    if (a >= 2 && meals >= 20 && careDays >= 2) st = 2
    if (st === 2 && a >= 7 && meals >= 70 && careDays >= 5) st = 3
    if (st === 3 && a >= 30 && meals >= 300 && careDays >= 20 && happiness >= 70) st = 4
    return st
  }
  function dietVariant() {
    var d = diet, letters = d.vowels + d.consonants, total = letters + d.digits
    if (total < 30) return "classic"
    if (d.digits / total >= 0.4) return "cyber"
    if (letters > 0 && d.vowels / letters >= 0.42) return "chonk"
    return "classic"
  }
  function checkEvolution() {
    var ns = stageFor()
    if (ns > stage && mode === "idle") evolve(ns, "")
  }
  function evolve(ns, forcedVariant) {
    if (ns >= 3 && (stage < 3 || forcedVariant)) variant = forcedVariant || dietVariant()
    if (ns < 3) variant = "classic"
    var grew = ns > stage
    stage = ns
    sprite.requestPaint()
    evoFx.play()
    if (grew) {
      bubble("✨ " + displayName + " evolved into " + (ns === 3 ? "an " : "a ") + stageName + "!")
      talk("evolve", "just evolved into a " + stageName + " " + pet, cfg.brain && cfg.chatty !== "off", true)
    }
    saveState()
  }

  // ---------------------------------------------------------------- egg
  property int eggFrame: 0
  property int eggTicks: 0
  function startEgg() {
    resetActivity()
    egg = true
    mode = "egg"
    eggTicks = 0
    eggFrame = 0
    stage = 1; variant = "classic"
    sprite.requestPaint()
    eggTimer.restart()
  }
  Timer {
    id: eggTimer
    interval: 450
    repeat: true
    onTriggered: {
      root.eggTicks++
      root.eggFrame = root.eggTicks > 34 ? 2 : (root.eggTicks % 2 && root.eggTicks > 6 ? 1 : 0)
      sprite.requestPaint()
      if (root.eggTicks >= 40) { stop(); root.hatch() }
    }
  }
  function hatch() {
    var r = store.newRecord(now())
    store.doc.pets[pet] = r
    egg = false
    mode = "idle"
    enterSpecies(pet, 0)
    evoFx.play()
    hearts.burst()
    if (petName === "") {
      bubble("Hi! I just hatched! What's my name? Right-click me → name, or run: desktop-pet name <name>")
      bubbleTimer.interval = 15000; bubbleTimer.restart()
      notifyProc.command = ["notify-send", "-a", "Desktop Pet", "A " + pet + " hatched!",
        "Give it a name: right-click the pet → name, or run: desktop-pet name <name>"]
      notifyProc.running = true
    } else bubble("Hi! I'm " + petName + "!")
    logEvent("hatched from an egg")
    saveState()
  }
  function newEgg() {
    if (!store.ready) return
    delete store.doc.pets[pet]
    if (pet === "goblin") endHeist(true)
    patches = []
    startEgg()
    saveState()
  }

  function onMonitor(raw) {
    var r = null
    try { r = JSON.parse(raw) } catch (e) {}
    if (!r || !r.ok || !r.monitor || r.monitor === screenName) return
    if (screenName !== "" && mode !== "idle" && mode !== "sleep") return
    moveToScreen(r.monitor)
  }

  function moveToScreen(name) {
    screenName = name
    posX = clamp(posX, 0, Math.max(0, screenW - winW))
    posY = clamp(posY, 0, Math.max(0, screenH - winH))
  }

  // One-time friendly hint when letter-eating needs setup.
  function showHint(reason, terms) {
    if (hintShown) return
    var setup = (pluginDir + "/bin/desktop-pet setup").replace(home, "~")
    var msg = ""
    if (reason === "no-remote-control")
      msg = "I'm hungry for letters, but kitty won't let me in! Run: " + setup
    else if (reason === "unsupported-terminal")
      msg = "I can only nibble kitty terminals (I see " + (terms && terms.length ? terms[0] : "another terminal") + "). Berries it is!"
    if (!msg) return
    hintShown = true
    saveState()
    bubble(msg)
    bubbleTimer.interval = 12000
    bubbleTimer.restart()
    notifyProc.command = ["notify-send", "-a", "Desktop Pet", petName + " wants to eat letters",
      reason === "no-remote-control"
        ? "Letter-eating needs kitty remote control. Run in a terminal:\n" + setup + "\nthen reopen your kitty windows."
        : "Letter-eating works with kitty (and btop running in kitty). Other terminals get berries instead."]
    notifyProc.running = true
  }

  function goSleep() {
    resetActivity()
    mode = "sleep"
    blink = true
    sprite.requestPaint()
  }

  function wakeUp(byClick) {
    mode = "idle"
    blink = false
    napping = false
    if (byClick) {
      wakeUntil = now() + 20 * 60000
      talk("wake", "got woken up by a click while sleeping", true, now() - lastClaudeClick > clickGapMs())
    }
    sprite.requestPaint()
  }

  function resetActivity() {
    moveTimer.stop(); chompTimer.stop(); fireAnim.stop()
    goal = null; arrive = null; task = ""; mouthOpen = false; hopY = 0
    pendingRun = null
    treat.visible = false
    if (mode !== "sleep") mode = "idle"
  }

  function wander() {
    var tx, ty
    if (heist && heist.mode === "hide") { tx = rnd(0, screenW - winW); ty = rnd(screenH * 0.45, screenH - winH) }
    else { tx = clamp(posX + rnd(-450, 450), 0, screenW - winW); ty = clamp(posY + rnd(-220, 220), 0, screenH - winH) }
    walkTo(tx, ty, "wander", function () { mode = "idle" })
  }

  function walkTo(x, y, why, cb) {
    goal = { x: clamp(x, 0, screenW - winW), y: clamp(y, 0, screenH - winH) }
    arrive = cb
    task = why
    mode = "walk"
    dir = goal.x >= posX ? 1 : -1
    moveTimer.restart()
  }

  property real hopPhase: 0
  property int stepCount: 0
  function step() {
    if (!goal) { moveTimer.stop(); return }
    var speed = pet === "slime" ? 6 : pet === "cat" ? 7 : pet === "dragon" ? 8 : 9
    if (heist && carryIcon) speed = Math.max(5, speed - 2)
    speed = speed * (0.5 + 0.5 * k) * 1.3   // keep ~the old 20 fps velocity
    var dx = goal.x - posX, dy = goal.y - posY
    var d = Math.sqrt(dx * dx + dy * dy)
    stepCount++
    if (d <= speed) {
      posX = goal.x; posY = goal.y; hopY = 0; frame = 0
      moveTimer.stop()
      var cb = arrive
      goal = null; arrive = null
      sprite.requestPaint()
      if (cb) cb()
      saveState()   // so a reload brings the pet back where it was
      return
    }
    posX += dx / d * speed
    posY += dy / d * speed
    if (Math.abs(dx) > 2) dir = dx > 0 ? 1 : -1
    hopPhase += (pet === "slime" ? 0.32 : 0.5) * 1.33
    if (pet === "slime") hopY = -Math.abs(Math.sin(hopPhase)) * 14 * k
    else if (pet === "dragon") hopY = (-4 - Math.sin(hopPhase) * 3) * k
    else hopY = -Math.abs(Math.sin(hopPhase)) * 3 * k
    if (stepCount % 4 === 0) { frame = frame ? 0 : 1; sprite.requestPaint() }
  }

  // ---------------------------------------------------------------- eating
  function startMeal() {
    nextFoodTry = now() + 3 * 60000
    if (pet === "goblin" && cfg.goblinSteal && !heist) { startHeist(); return }
    if (!cfg.eat) { giveTreat(15, false); return }
    scanProc.purpose = "eat"
    if (!runHelper(scanProc, ["scan"])) return
    mode = "treat"   // busy while scanning
    task = "scan"
  }

  function startFire() {
    scanProc.purpose = "fire"
    if (!runHelper(scanProc, ["scan"])) return
    mode = "treat"
    task = "scan"
  }

  function mouthPx() {
    var m = Sprites.mouthCell(pet)
    return [artX + m[0] * cellPx, artY + m[1] * cellPx + cellPx / 2]
  }

  function onScan(purpose, raw) {
    var r = null
    try { r = JSON.parse(raw) } catch (e) {}
    mode = "idle"; task = ""
    if (!r || !r.ok) {
      if (r && r.reason) showHint(r.reason, r.terminals)
      if (purpose === "eat") giveTreat(10, false)   // nothing to eat on screen: a berry will do
      return
    }
    if (r.monitor && r.monitor !== screenName) moveToScreen(r.monitor)
    var tgt = { address: r.address, cls: r["class"], x: r.x, y: r.y, w: r.w, h: r.h,
                cw: r.cw, ch: r.ch, ox: r.ox, oy: r.oy, cols: r.cols, rows: r.rows,
                monitor: r.monitor || screenName, font: r.font || "monospace", fontPx: r.fontPx || 12 }
    if (target && target.address !== tgt.address) {
      // keep at most one terminal decorated at a time
      patches = patches.filter(function (p) { return p.addr === tgt.address })
    }
    target = tgt
    targetVisible = true
    var mp = mouthPx()
    var taken = {}
    for (var i = 0; i < patches.length; i++) taken[patches[i].row + ":" + patches[i].col] = true
    for (i = 0; i < r.runs.length; i++) {
      var run = r.runs[i]
      var clash = false
      for (var k = 0; k < run.text.length; k++) if (taken[run.row + ":" + (run.col + k)]) clash = true
      if (clash) continue
      var cellX = tgt.x + tgt.ox + run.col * tgt.cw
      var cellCY = tgt.y + tgt.oy + run.row * tgt.ch + tgt.ch / 2
      var wx = purpose === "fire" ? cellX - fireDist - sprLeft - mp[0] : cellX + 1 - sprLeft - mp[0]
      var wy = cellCY - sprTop - mp[1]
      if (wx < 0 || wy < 0 || wx > screenW - winW || wy > screenH - winH) continue
      pendingRun = run
      walkTo(wx, wy, purpose, function () {
        dir = 1
        if (task === "fire") breatheFire(); else beginChomp()
      })
      return
    }
    if (purpose === "eat") giveTreat(10, false)
  }

  property int chompIdx: 0
  property bool chompPhase: false
  function beginChomp() {
    mode = "eat"
    task = "eat"
    chompIdx = 0
    chompPhase = false
    chompTimer.restart()
  }

  Timer {
    id: chompTimer
    interval: 190
    repeat: true
    onTriggered: root.chompStep()
  }

  function chompStep() {
    var run = pendingRun
    if (!run || !target) { finishMeal(0, ""); return }
    if (!chompPhase) { mouthOpen = true; chompPhase = true; sprite.requestPaint(); return }
    mouthOpen = false
    chompPhase = false
    addPatch(run.col + chompIdx, run.row, "eat", run.text[chompIdx])
    crumbs.burst()
    var ch = run.text[chompIdx] || ""
    var d = diet
    if (/[0-9]/.test(ch)) d.digits++
    else if (/[aeiouAEIOU]/.test(ch)) d.vowels++
    else d.consonants++
    diet = d
    chompIdx++
    lettersEaten++
    if (chompIdx >= run.text.length) { chompTimer.stop(); finishMeal(run.text.length, run.text); return }
    posX = clamp(posX + target.cw, 0, maxX)
    sprite.requestPaint()
  }

  function addPatch(col, row, kind, ch) {
    var list = patches.filter(function (p) { return !(p.addr === target.address && p.col === col && p.row === row) })
    list.push({ addr: target.address, col: col, row: row, kind: kind, ch: ch || "",
                until: now() + rnd(3, 6) * 60000 })
    while (list.length > 60) list.shift()
    patches = list
  }

  function finishMeal(n, word) {
    mode = "idle"; task = ""; pendingRun = null; mouthOpen = false
    sprite.requestPaint()
    if (n <= 0) return
    meals++
    careTick()
    saveSoon()
    lastMealAt = now()
    hunger = clamp(hunger + 5 * n + 4, 0, 100)
    happiness = clamp(happiness + 3, 0, 100)
    hearts.burst()
    var where = target && target.cls === "org.omarchy.btop" ? "btop" : "a terminal"
    var speakProb = cfg.chatty === "low" ? 0.5 : (cfg.chatty === "off" ? 0 : 1)
    talk("meal", "ate the letters \"" + word + "\" from " + where, Math.random() < speakProb, true)
  }

  // ---------------------------------------------------------------- fire
  property real fireT: 0
  function breatheFire() {
    mode = "fire"
    task = "fire"
    mouthOpen = true
    sprite.requestPaint()
    fireAnim.restart()
  }
  SequentialAnimation {
    id: fireAnim
    loops: 3
    NumberAnimation { target: root; property: "fireT"; from: 0; to: 1; duration: 420 }
    onFinished: root.finishFire()
  }
  function finishFire() {
    var run = pendingRun
    fireT = 0
    mouthOpen = false
    if (fetchToast) {
      fetchToast = false; fetchToastDone = true
      ballWin.toasted = true
      mode = "idle"; task = ""
      pickUpBall()
      return
    }
    if (run && target) {
      for (var i = 0; i < run.text.length; i++) addPatch(run.col + i, run.row, "fire", run.text[i])
      happiness = clamp(happiness + 6, 0, 100)
      talk("fire", "breathed fire on \"" + run.text + "\" and turned it red", cfg.chatty !== "low" || Math.random() < 0.4, true)
    }
    mode = "idle"; task = ""; pendingRun = null
    sprite.requestPaint()
  }

  // ---------------------------------------------------------------- treats
  property real treatGain: 15
  function giveTreat(gain, fromUser) {
    if (sleeping && fromUser) wakeUp(false)
    resetActivity()
    treatGain = gain
    mode = "treat"
    task = "treat"
    treat.fromUser = fromUser
    treat.y = 0
    treat.visible = true
    treatDrop.restart()
  }
  function eatTreat() {
    mouthOpen = true
    sprite.requestPaint()
    treatChomp.restart()
  }
  Timer {
    id: treatChomp
    interval: 260
    property int n: 0
    repeat: true
    onTriggered: {
      root.mouthOpen = !root.mouthOpen
      sprite.requestPaint()
      if (++n >= 4) {
        stop(); n = 0
        treat.visible = false
        root.mouthOpen = false
        root.hunger = root.clamp(root.hunger + root.treatGain, 0, 100)
        root.happiness = root.clamp(root.happiness + 5, 0, 100)
        root.lastMealAt = root.now()
        root.meals++
        root.careTick()
        root.saveSoon()
        root.mode = "idle"; root.task = ""
        crumbs.burst(); hearts.burst()
        sprite.requestPaint()
        root.talk("meal", treat.fromUser ? "got a berry treat from my human" : "found a berry to snack on",
                  treat.fromUser || root.cfg.chatty === "high", true)
      }
    }
  }

  // ---------------------------------------------------------------- goblin heist
  function startHeist() {
    dockProc.purpose = "info"
    runHelper(dockProc, ["dock-info"])
  }

  function onDock(purpose, raw) {
    var r = null
    try { r = JSON.parse(raw) } catch (e) {}
    if (!r) return
    if (purpose === "info") {
      dockInstalled = !!r.installed
      if (!r.pinned || r.pinned.length < 2) { if (cfg.eat) { scanProc.purpose = "eat"; runHelper(scanProc, ["scan"]) } return }
      walkTo(screenW / 2 - winW / 2 + rnd(-140, 140), screenH - winH, "heist", function () {
        mode = "heist"
        hopY = -10 * k; sprite.requestPaint()
        rummage.restart()
      })
    } else if (purpose === "steal") {
      carryIcon = r.icon || r.id || "application-x-executable"
      heist = { mode: r.mode || "move", id: r.id, applied: !!r.applied,
                returnAt: now() + (r.mode === "hide" ? rnd(4, 8) : rnd(6, 10)) * 60000 }
      hunger = clamp(hunger + 30, 0, 100)
      happiness = clamp(happiness + 10, 0, 100)
      lastMealAt = now()
      var how = heist.mode === "hide" ? "stole and hid" : "stole and moved"
      talk("heist", how + " the " + r.id + " icon from the dock" + (r.applied ? "" : " (just pretending: the dock is not installed)"), true, true)
      mode = "idle"
      // run off with it
      var tx = heist.mode === "hide" ? rnd(0, screenW - winW) : clamp(posX + (Math.random() < 0.5 ? -1 : 1) * rnd(250, 500), 0, screenW - winW)
      walkTo(tx, heist.mode === "hide" ? rnd(screenH * 0.4, screenH - winH) : screenH - winH, "carry", function () {
        mode = "idle"
        if (heist && heist.mode === "move") { carryIcon = ""; crumbs.burst() }   // drops it in its new spot
        sprite.requestPaint()
      })
    } else if (purpose === "restore") {
      // nothing else to do; the dock was restarted by the helper
    }
  }

  Timer {
    id: rummage
    interval: 350
    property int n: 0
    repeat: true
    onTriggered: {
      root.hopY = (n % 2) ? 0 : -10 * root.k
      root.frame = n % 2
      sprite.requestPaint()
      if (++n >= 5) {
        stop(); n = 0; root.hopY = 0
        dockProc.purpose = "steal"
        if (!root.runHelper(dockProc, ["dock-steal", Math.random() < 0.6 ? "move" : "hide"])) root.mode = "idle"
      }
    }
  }

  function returnIcon() {
    if (!heist) return
    if (!carryIcon) carryIcon = heist.id   // picks the moved icon back up
    walkTo(screenW / 2 - winW / 2, screenH - winH, "return", function () {
      endHeist(false)
      mode = "idle"
      hearts.burst()
      talk("heist", "put the stolen icon back in the dock where it belongs", false, false)
    })
  }

  function endHeist(force) {
    carryIcon = ""
    heist = null
    dockProc.purpose = "restore"
    if (!runHelper(dockProc, ["dock-restore"])) restoreRetry.restart()
  }
  Timer { id: restoreRetry; interval: 1500; onTriggered: { dockProc.purpose = "restore"; if (!root.runHelper(dockProc, ["dock-restore"])) restart() } }

  // ---------------------------------------------------------------- geometry polling
  function onGeom(raw) {
    var r = null
    try { r = JSON.parse(raw) } catch (e) {}
    if (!r || !r.ok || !target) return
    if (!r.exists) {
      var a = target.address
      patches = patches.filter(function (p) { return p.addr !== a })
      target = null; targetVisible = false
      if (mode === "eat" || task === "eat" || task === "fire") resetActivity()
      return
    }
    if (r.w !== target.w || r.h !== target.h) {
      // terminal resized: the grid reflowed, old patches would be wrong
      var addr = target.address
      patches = patches.filter(function (p) { return p.addr !== addr })
      if (mode === "eat" || task === "eat" || task === "fire") resetActivity()
      target = null; targetVisible = false
      return
    }
    if (r.x !== target.x || r.y !== target.y || (r.monitor && r.monitor !== target.monitor)) {
      var t = target; t.x = r.x; t.y = r.y; if (r.monitor) t.monitor = r.monitor; target = t; targetChanged()
    }
    targetVisible = r.visible
  }

  // ---------------------------------------------------------------- interaction
  function petPet() {
    if (egg) { eggTicks = Math.max(eggTicks, 12); return }   // tapping the egg speeds it up
    if (sleeping) { wakeUp(true); hearts.burst(); return }
    careTick()
    saveSoon()
    lastPetAt = now()
    ignoredLogged = false
    happiness = clamp(happiness + 8, 0, 100)
    hearts.burst()
    var useClaude = now() - lastClaudeClick > clickGapMs() && cfg.chatty !== "off"
    if (useClaude) lastClaudeClick = now()
    talk("click", "got petted by my human", true, useClaude)
  }

  function logEvent(text) { talk("event", text, false, false) }

  // trigger, event text, speak (show a bubble), allowClaude
  function talk(trigger, eventText, speak, allowClaude, message) {
    var payload = {
      message: message || "",
      trigger: trigger, event: eventText || "", silent: !speak,
      allowClaude: !!(allowClaude && cfg.brain && speak),
      pet: pet, name: petName, mood: mood(), theme: themeName, stage: stageName, ageDays: Math.floor(ageDays),
      hunger: Math.round(hunger), happiness: Math.round(happiness), energy: Math.round(energy),
      accessory: acc.join(",")
    }
    var q = talkQueue.slice()
    if (q.length > 4) q.shift()
    q.push(payload)
    talkQueue = q
    pumpTalk()
  }

  function pumpTalk() {
    if (talkProc.running || talkQueue.length === 0) return
    var q = talkQueue.slice()
    var p = q.shift()
    talkQueue = q
    talkProc.trigger = p.trigger
    runHelper(talkProc, ["talk", JSON.stringify(p)])
  }

  function onTalk(trigger, raw) {
    var r = null
    try { r = JSON.parse(raw) } catch (e) {}
    if (r && r.text) bubble(r.text)
  }

  function bubble(text) {
    // display-only: plain text, single paragraph, capped
    var t = String(text || "").replace(/[\u0000-\u001f\u007f]/g, " ").replace(/\s+/g, " ").trim()
    if (t.length > 140) t = t.substring(0, 137) + "..."
    bubbleText = t
    bubbleTimer.interval = 6500
    bubbleTimer.restart()
  }

  function healAll() {
    patches = []
    if (mode === "eat" || mode === "fire") resetActivity()
    if (heist || carryIcon) { resetActivity(); endHeist(true) }
  }


  // ---------------------------------------------------------------- fetch
  property bool carryBall: false
  property bool ballThief: false
  PetBall {
    id: ballWin
    pet: root
    onLanded: function (x, y, distance) { root.onBallLanded(x, y, distance) }
    onGrabbed: root.onBallGrabbed()
  }
  Process {
    id: cursorProc
    property string purpose: ""
    stdout: StdioCollector { waitForEnd: true; onStreamFinished: root.onCursor(cursorProc.purpose, text) }
  }
  property real lastThrow: 0
  function fetch() {
    if (!cfg.fetch || egg) return false
    if (sleeping) wakeUp(false)
    cursorProc.purpose = "spawn"
    if (!runHelper(cursorProc, ["cursor"])) spawnBallNearPet()
    return true
  }
  function spawnBallNearPet() {
    ballWin.spawn(clamp(posX + winW / 2 + 60 * dir, 20, screenW - 20), clamp(posY + sprTop - 40, 20, screenH - 40))
  }
  function onCursor(purpose, raw) {
    var r = null
    try { r = JSON.parse(raw) } catch (e) {}
    var ok = r && r.ok && (!r.monitor || r.monitor === screenName || screenName === "")
    if (purpose === "spawn") {
      if (ok) ballWin.spawn(clamp(r.x, 20, screenW - 20), clamp(r.y - 30, 20, screenH - 40))
      else spawnBallNearPet()
    } else if (purpose === "return") {
      var tx = ok ? r.x : screenW / 2, ty = ok ? r.y : screenH / 2
      walkTo(tx - winW / 2, ty - sprTop - spr / 2, "fetch-return", function () { dropBall() })
    }
  }
  function onBallGrabbed() {
    if (task === "fetch" || task === "fetch-return") resetActivity()
  }
  function onBallLanded(x, y, distance) {
    lastThrow = distance
    if (egg || sleeping || menuOpen || (mode !== "idle" && mode !== "walk")) return
    if (mode === "walk" && task !== "wander") return
    var mp = mouthPx()
    walkTo(x - sprLeft - mp[0] + cellPx, screenH - winH, "fetch", function () { reachBall() })
  }
  function reachBall() {
    mode = "idle"
    if (!ballWin.active) return
    if (pet === "dragon" && Math.random() < 0.3) { fetchToast = true; breatheFire(); return }
    pickUpBall()
  }
  property bool fetchToast: false
  function pickUpBall() {
    ballWin.hide()
    carryBall = true
    if (pet === "goblin" && Math.random() < 0.4) {   // finders keepers (for a bit)
      ballThief = true
      bubble("Heh heh, MY ball now!")
      walkTo(posX < screenW / 2 ? screenW - winW : 0, screenH - winH, "fetch-steal", function () { mode = "idle"; ballGiveBack.restart() })
      return
    }
    cursorProc.purpose = "return"
    if (!runHelper(cursorProc, ["cursor"])) onCursor("return", "{}")
  }
  Timer { id: ballGiveBack; interval: 15000; onTriggered: { root.ballThief = false; cursorProc.purpose = "return"; if (!root.runHelper(cursorProc, ["cursor"])) root.onCursor("return", "{}") } }
  function dropBall() {
    mode = "idle"
    if (!carryBall) return
    carryBall = false
    var mp = mouthPx()
    ballWin.place(posX + sprLeft + mp[0] + 6, posY + sprTop + mp[1] - 12)
    var gain = Math.min(15, 3 + lastThrow / 120)
    happiness = clamp(happiness + gain, 0, 100)
    energy = clamp(energy - 2, 0, 100)
    plays++
    if (lastThrow > bestThrow) bestThrow = lastThrow
    careTick()
    saveSoon()
    hearts.burst()
    talk("fetch", "played fetch; the throw went " + Math.round(lastThrow) + " px" + (fetchToastDone ? " and I toasted the ball" : ""),
         Math.random() < (cfg.chatty === "high" ? 0.8 : 0.35), true)
    fetchToastDone = false
  }
  property bool fetchToastDone: false

  // ---------------------------------------------------------------- build buddy
  PetBuddy {
    id: buddy
    enabled: root.cfg.buddy
    onCommandFinished: function (cmd, code, dur) { root.onCommand(cmd, code, dur) }
  }
  property real lastBuddy: 0
  property real lastBuddyFail: 0
  readonly property var testCmds: ["pytest", "cargo test", "npm test", "go test", "make test", "yarn test", "pnpm test", "bun test"]
  function onCommand(cmd, code, dur) {
    if (!cfg.buddy || egg || sleeping || !cmd) return
    var t = now()
    if (t - lastBuddy < 20000 || code === 130) return
    var trig = "", ev = ""
    if (code !== 0) {
      if (t - lastBuddyFail < 60000) return
      lastBuddyFail = t
      trig = "buddy-fail"; ev = "my human's command `" + cmd + "` failed (exit code " + code + ")"
      moodOverride = "sad"; moodTimer.restart(); sprite.requestPaint()
    } else if (testCmds.indexOf(cmd) >= 0) {
      trig = "buddy-test"; ev = "my human's tests (`" + cmd + "`) passed"
      hearts.burst(); celebrate(2, false)
    } else if (cmd === "git push") {
      trig = "buddy-push"; ev = "my human just pushed their code (git push succeeded)"
      evoFx.sparkle(); celebrate(4, true)
    } else if (dur >= 30) {
      trig = "buddy-done"; ev = "my human's `" + cmd + "` finished after " + dur + " seconds"
      celebrate(1, false)
    } else return
    lastBuddy = t
    talk(trig, ev, true, true)
  }
  property int celebrateLeft: 0
  property bool celebrateSpin: false
  function celebrate(n, spin) {
    if (mode !== "idle") return
    celebrateLeft = n * 2; celebrateSpin = spin
    celebrateTimer.restart()
  }
  Timer {
    id: celebrateTimer
    interval: 160
    repeat: true
    onTriggered: {
      root.hopY = (root.celebrateLeft % 2) ? 0 : -12 * root.k
      if (root.celebrateSpin && root.celebrateLeft % 2) root.dir = -root.dir
      if (--root.celebrateLeft <= 0) { stop(); root.hopY = 0 }
    }
  }

  IpcHandler {
    target: "desktoppet"
    function heal(): string { root.healAll(); return "ok" }
    function feed(): string { root.giveTreat(20, true); return "ok" }
    function wake(): string { if (root.sleeping) root.wakeUp(true); else root.wakeUntil = root.now() + 20 * 60000; return "ok" }
    function hungry(): string {
      if (root.sleeping) root.wakeUp(true)
      root.resetActivity(); root.hunger = Math.min(root.hunger, 30); root.lastMealAt = 0; root.nextFoodTry = 0
      root.startMeal(); return "ok"
    }
    function fire(): string {
      if (root.pet !== "dragon") return "only the dragon breathes fire"
      if (root.sleeping) root.wakeUp(true)
      root.resetActivity(); root.startFire(); return "ok"
    }
    function heist(): string {
      if (root.pet !== "goblin") return "only the goblin steals icons"
      if (!root.cfg.goblinSteal) return "goblin-steal is off"
      if (root.heist) { root.heist.returnAt = 0; return "returning the icon" }
      if (root.sleeping) root.wakeUp(true)
      root.resetActivity(); root.startHeist(); return "ok"
    }
    function bubble(text: string): string { root.bubble(text); return "ok" }
    function ping(): string { return "ok" }
    function reload(): string { configFile.reload(); if (root.host && root.host.reload) root.host.reload(); return "ok" }
    function save(): string { root.saveState(); return "ok" }
    function moveTo(x: string, y: string): string {
      if (root.sleeping) root.wakeUp(false)
      root.resetActivity(); root.walkTo(Number(x), Number(y), "wander", function () { root.mode = "idle" }); return "ok"
    }
    function status(): string { return JSON.stringify(root.statusObj()) }
    function evolveSet(stage: string, variant: string): string {
      var st = Number(stage)
      if (!(st >= 1 && st <= 4)) return "stage must be 1-4"
      if (root.egg) return "still an egg"
      if (Sprites.VARIANTS.indexOf(variant) < 0) variant = "classic"
      root.evolve(st, variant); return "ok"
    }
    function newEgg(): string { root.newEgg(); return "ok" }
    function menu(): string { root.openMenu(); return "ok" }
    function fetch(): string { if (root.egg) return "still an egg"; return root.fetch() ? "ok" : "fetch is off" }
    function buddyTest(cmd: string, code: string, dur: string): string { root.lastBuddy = 0; root.lastBuddyFail = 0; root.onCommand(cmd, Number(code), Number(dur)); return "ok" }
  }

  // map the pet window after the overlay so it always stacks above it
  property bool petMapped: false
  Timer { interval: 400; running: true; onTriggered: root.petMapped = true }

  Component.onCompleted: {
    // never leave the dock modified from a previous session
    dockProc.purpose = "restore"
    runHelper(dockProc, ["dock-restore"])
  }
  Component.onDestruction: saveState()

  // ================================================================ windows

  PanelWindow {
    id: overlayWin
    readonly property bool active: root.target !== null && root.targetVisible && root.shownPatches.length > 0
    screen: root.screenByName(root.target ? root.target.monitor : root.screenName)
    anchors { top: true; left: true }
    margins { left: active ? root.target.x : 0; top: active ? root.target.y : 0 }
    implicitWidth: active ? root.target.w : 1
    implicitHeight: active ? root.target.h : 1
    color: "transparent"
    WlrLayershell.namespace: "desktop-pet-overlay"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {}

    Repeater {
      model: overlayWin.active ? root.shownPatches : []
      delegate: Rectangle {
        required property var modelData
        x: root.target.ox + modelData.col * root.target.cw
        y: root.target.oy + modelData.row * root.target.ch
        width: root.target.cw
        height: root.target.ch
        color: root.patchColor
        Text {
          visible: modelData.kind === "fire"
          anchors.fill: parent
          text: modelData.ch
          color: root.fireColor
          font.family: root.target ? root.target.font : "monospace"
          font.pixelSize: root.target ? root.target.fontPx : 12
          font.bold: true
          horizontalAlignment: Text.AlignHCenter
          verticalAlignment: Text.AlignVCenter
        }
      }
    }
  }

  PanelWindow {
    id: petWin
    visible: root.petMapped && root.petScreen !== null
    screen: root.petScreen
    anchors { top: true; left: true }
    margins { left: Math.round(root.posX); top: Math.max(0, Math.round(root.posY + root.hopY)) }
    implicitWidth: root.winW
    implicitHeight: root.winH
    color: "transparent"
    WlrLayershell.namespace: "desktop-pet"
    WlrLayershell.layer: WlrLayer.Top
    WlrLayershell.keyboardFocus: WlrKeyboardFocus.None
    exclusionMode: ExclusionMode.Ignore
    mask: Region {
      item: hitBox
    }

    Item {
      id: hitBox
      x: root.sprLeft + root.artX + 2 * root.cellPx
      y: root.sprTop + root.artY + Sprites.topCell(root.pet, [], root.stage) * root.cellPx
      width: Sprites.GRID_W * root.cellPx - 4 * root.cellPx
      height: root.spr - y + root.sprTop
    }

    Canvas {
      id: sprite
      x: root.sprLeft
      y: root.sprTop + ((root.pet === "slime" && root.frame === 1 && root.mode !== "walk") ? root.cellPx : 0)
      width: root.spr
      height: root.spr
      renderStrategy: Canvas.Immediate
      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var g = root.egg ? Sprites.eggGrid(root.eggFrame) : Sprites.buildGrid(root.pet, {
          frame: root.frame, blink: root.blink || root.sleeping, mouthOpen: root.mouthOpen,
          mood: root.mood(), acc: root.acc, band: root.themeInfo.band || "r",
          stage: root.stage, variant: root.variant })
        var s = root.cellPx
        ctx.translate(root.artX, root.artY)
        var p = root.pal
        for (var y = 0; y < g.length; y++) {
          for (var x = 0; x < g[y].length; x++) {
            var c = g[y][x]
            if (c === ".") continue
            var gx = root.dir < 0 ? (Sprites.GRID_W - 1 - x) : x
            ctx.globalAlpha = c === "*" ? 0.35 : 1
            ctx.fillStyle = p[c] || "#ff00ff"
            ctx.fillRect(gx * s, y * s, s, s)
          }
        }
        ctx.globalAlpha = 1
      }
      Connections {
        target: root
        function onPalChanged() { sprite.requestPaint() }
        function onAccChanged() { sprite.requestPaint() }
        function onPetChanged() { sprite.requestPaint() }
        function onDirChanged() { sprite.requestPaint() }
        function onStageChanged() { sprite.requestPaint() }
        function onVariantChanged() { sprite.requestPaint() }
        function onEggChanged() { sprite.requestPaint() }
      }
    }

    MouseArea {
      anchors.fill: hitBox
      acceptedButtons: Qt.LeftButton | Qt.RightButton
      cursorShape: Qt.PointingHandCursor
      onClicked: function (mouse) {
        var superShift = (mouse.modifiers & Qt.MetaModifier) && (mouse.modifiers & Qt.ShiftModifier)
        if (mouse.button === Qt.RightButton || superShift) root.openMenu()
        else root.petPet()
      }
    }

    // evolution / hatch effect: three white flashes and a ring of sparkles
    Item {
      id: evoFx
      anchors.fill: parent
      property real t: 1
      property real flash: 0
      visible: t < 1
      property bool withFlash: true
      function play() { withFlash = true; evoAnim.restart() }
      function sparkle() { withFlash = false; evoAnim.restart() }
      ParallelAnimation {
        id: evoAnim
        NumberAnimation { target: evoFx; property: "t"; from: 0; to: 1; duration: 1600 }
        SequentialAnimation {
          loops: 3
          NumberAnimation { target: evoFx; property: "flash"; from: 0; to: 0.85; duration: 140 }
          NumberAnimation { target: evoFx; property: "flash"; from: 0.85; to: 0; duration: 220 }
        }
      }
      Rectangle {
        x: sprite.x + root.artX; y: sprite.y + root.artTop
        width: Sprites.GRID_W * root.cellPx; height: root.spr - root.artTop
        radius: width / 3
        color: "white"
        opacity: evoFx.withFlash ? evoFx.flash : 0
      }
      Repeater {
        model: 10
        Rectangle {
          required property int index
          readonly property real ang: index / 10 * Math.PI * 2
          readonly property real rr: (12 + evoFx.t * 46) * Math.max(0.7, root.k)
          width: Math.max(3, Math.round(4 * root.k)); height: width
          color: index % 2 ? root.tc.yellow : root.tc.accent
          x: root.sprLeft + root.spr / 2 + Math.cos(ang) * rr - width / 2
          y: root.sprTop + root.spr * 0.55 + Math.sin(ang) * rr * 0.8 - height / 2
          opacity: 1 - evoFx.t
        }
      }
    }

    // carried ball (fetch)
    Rectangle {
      visible: root.carryBall
      width: Math.max(10, Math.round(14 * root.k)); height: width; radius: width / 2
      x: root.sprLeft + root.mouthPx()[0] - width / 2
      y: sprite.y + root.mouthPx()[1] - height / 2
      color: ballWin.toasted ? "#2b2118" : root.tc.red
      border.width: Math.max(1, Math.round(width / 8)); border.color: Qt.darker(color, 1.8)
    }

    // carried dock icon (goblin)
    Item {
      visible: root.carryIcon !== ""
      readonly property int isz: Math.max(20, Math.round(32 * root.k))
      x: root.sprLeft + root.spr / 2 - isz / 2
      y: sprite.y + root.artTop - isz - 2
      width: isz; height: isz
      Rectangle { anchors.fill: parent; anchors.margins: -2; color: Qt.rgba(0, 0, 0, 0.35); radius: 4; visible: carried.status !== Image.Ready }
      Image {
        id: carried
        anchors.fill: parent
        sourceSize.width: parent.width; sourceSize.height: parent.height
        source: root.carryIcon ? Quickshell.iconPath(root.carryIcon, "application-x-executable") : ""
        smooth: false
      }
    }

    // zzz
    Repeater {
      model: root.sleeping ? 3 : 0
      Text {
        required property int index
        readonly property int st: (root.zstep + index * 2) % 6
        x: root.sprLeft + root.spr - 18 + st * 5
        y: root.sprTop + 18 - st * 9
        opacity: st >= 5 ? 0 : 1
        text: "z"
        font.family: root.uiFont
        font.pixelSize: Math.round((11 + st * 2) * Math.max(0.8, root.k))
        font.bold: true
        color: root.cAccent
        style: Text.Outline
        styleColor: root.cBg
      }
    }

    // hearts
    Item {
      id: hearts
      anchors.fill: parent
      property real t: 1
      visible: t < 1
      function burst() { heartAnim.restart() }
      NumberAnimation { id: heartAnim; target: hearts; property: "t"; from: 0; to: 1; duration: 1100 }
      Repeater {
        model: 3
        Canvas {
          required property int index
          width: 15; height: 12
          x: root.sprLeft + 14 + index * 20 + Math.sin(hearts.t * 6 + index) * 4
          y: root.sprTop + 10 - hearts.t * (34 + index * 8)
          opacity: 1 - hearts.t
          renderStrategy: Canvas.Immediate
          onPaint: {
            var ctx = getContext("2d")
            var rows = [".rr.rr.", "rrrrrrr", "rrrrrrr", ".rrrrr.", "..rrr..", "...r..."]
            ctx.reset()
            ctx.fillStyle = Sprites.mix(root.tc.red, root.tc.magenta, 0.5)
            for (var y = 0; y < rows.length; y++) for (var x = 0; x < 7; x++)
              if (rows[y][x] === "r") ctx.fillRect(x * 2, y * 2, 2, 2)
          }
          Connections { target: root; function onPalChanged() { requestPaint() } }
        }
      }
    }

    // crumbs
    Item {
      id: crumbs
      anchors.fill: parent
      property real t: 1
      visible: t < 1
      function burst() { crumbAnim.restart() }
      NumberAnimation { id: crumbAnim; target: crumbs; property: "t"; from: 0; to: 1; duration: 600 }
      Repeater {
        model: 4
        Rectangle {
          required property int index
          readonly property var mp: root.mouthPx()
          width: Math.max(2, Math.round(4 * root.k)); height: width
          color: index % 2 ? root.pal.a : root.pal.y
          x: root.sprLeft + mp[0] + (index - 1.5) * 6 * crumbs.t
          y: sprite.y + mp[1] + 4 + crumbs.t * crumbs.t * 30 - (index % 2) * 6 * crumbs.t
          opacity: 1 - crumbs.t
        }
      }
    }

    // dragon fire
    Repeater {
      model: root.mode === "fire" ? 9 : 0
      Rectangle {
        required property int index
        readonly property var mp: root.mouthPx()
        readonly property real local: (root.fireT + index / 9) % 1
        width: Math.max(2, (6 - local * 2) * root.k); height: width
        color: local < 0.33 ? root.tc.yellow : (local < 0.66 ? root.tc.orange : root.tc.red)
        x: root.sprLeft + mp[0] + local * (root.fireDist + 4)
        y: sprite.y + mp[1] - 3 + Math.sin(index * 2.1 + root.fireT * 9) * (2 + local * 6)
        opacity: 1 - local * 0.4
      }
    }

    // berry treat
    Canvas {
      id: treat
      visible: false
      property bool fromUser: false
      width: 12; height: 12
      x: root.sprLeft + root.mouthPx()[0] - 2
      renderStrategy: Canvas.Immediate
      onPaint: {
        var ctx = getContext("2d")
        var rows = ["..g...", ".rrr..", "rrwrr.", "rrrrr.", ".rrr.."]
        ctx.reset()
        for (var y = 0; y < rows.length; y++) for (var x = 0; x < 6; x++) {
          var c = rows[y][x]
          if (c === ".") continue
          ctx.fillStyle = c === "g" ? root.tc.green : (c === "w" ? "#ffffff" : root.tc.red)
          ctx.fillRect(x * 2, y * 2, 2, 2)
        }
      }
      NumberAnimation on y { id: treatDrop; running: false; from: 0; to: root.sprTop + root.mouthPx()[1] - 6; duration: 700; easing.type: Easing.OutBounce
        onFinished: root.eatTreat() }
      Connections { target: root; function onPalChanged() { treat.requestPaint() } }
    }

    // speech bubble
    Rectangle {
      id: bubbleBox
      visible: root.bubbleText !== ""
      width: Math.min(root.winW - 6, bubbleLabel.implicitWidth + 16)
      height: bubbleLabel.implicitHeight + 10
      x: Math.round((root.winW - width) / 2)
      y: Math.max(0, sprite.y + root.artTop - height - 6 - (root.carryIcon !== "" ? Math.max(20, Math.round(32 * root.k)) + 2 : 0))
      color: root.cBg
      border.color: root.cAccent
      border.width: 2
      Text {
        id: bubbleLabel
        anchors.centerIn: parent
        width: Math.min(implicitWidth, root.winW - 22)
        text: root.bubbleText
        textFormat: Text.PlainText
        wrapMode: Text.Wrap
        maximumLineCount: 5
        elide: Text.ElideRight
        color: root.cFg
        font.family: root.uiFont
        font.pixelSize: 11
      }
    }
  }

  PetMenu { id: menuWin; pet: root }
}
