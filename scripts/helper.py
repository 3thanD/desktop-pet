#!/usr/bin/env python3
"""desktop-pet helper. Run with `python3 -I helper.py <cmd> ...`.

Commands (all print one JSON object on stdout):
  scan [--prefer ADDR]  pick a target terminal (btop first, else a visible kitty
                        window on the active workspace), read its screen through
                        kitty remote control, and return geometry + letter runs.
  geom ADDR             cheap geometry/visibility check for a window address.
  monitor               name of the focused monitor.
  cursor                pointer position on the focused monitor.
  dock-info             pinned dock icons (with icon names) and dock status.
  dock-steal MODE       goblin heist: MODE is "move" or "hide". Backs up the
                        pinned list first, edits it, restarts the dock.
  dock-restore          put the original pinned list back and restart the dock.
  talk JSON             log a pet event and/or produce a speech line (Claude via
                        the claude CLI with no tools, or canned fallback).
  skills-list           every valid skill recipe (built-in, user, pending) + errors.
  skills-approve ID     move a pending (pitched) skill to the user skills and enable it.
  skills-reject ID      drop a pending skill.
  skills-pitch [--auto] JSON   ask Claude, in character, for one new skill (queued,
                        never enabled). --auto: at most one a day.
  wall-swap DOODLE W H COLORS SECONDS   journaled temporary wallpaper swap.
  wall-restore          put the journaled original wallpaper back.
  restore-all           dock-restore + wall-restore (load, heal, off, crash).
  cursor-stream SECONDS pointer position as JSON lines, ~8 per second.
  sound NAME            play a tiny synthesized skill sound (if enabled).
"""
import json
import os
import random
import re
import shutil
import subprocess
import sys
import time

# Our sibling modules (python -I does not add the script dir to sys.path).
# No .pyc files: writing into the plugin dir would make the shell reload it.
sys.dont_write_bytecode = True
sys.path.insert(0, os.path.dirname(os.path.realpath(__file__)))

import adapters  # noqa: E402  compositor adapters (Hyprland today)
import skills  # noqa: E402  skill recipes, pitch queue, wallpaper journal
import terminals  # noqa: E402  terminal adapters (kitty today)
from util import run, find_claude  # noqa: E402

HOME = os.path.expanduser("~")
STATE_DIR = os.path.join(HOME, ".local/state/desktop-pet")
PINNED = os.path.join(HOME, ".cache/nwg-dock-pinned")
PINNED_BACKUP = os.path.join(STATE_DIR, "nwg-dock-pinned.orig")
HEIST_FLAG = os.path.join(STATE_DIR, "dock-heist.json")
ALNUM = re.compile(r"[A-Za-z0-9]+")


def out(obj):
    sys.stdout.write(json.dumps(obj, separators=(",", ":")))
    sys.stdout.write("\n")


def rects_intersect(a, b):
    ax, ay, aw, ah = a
    bx, by, bw, bh = b
    return ax < bx + bw and bx < ax + aw and ay < by + bh and by < ay + ah


def rect(w):
    return (w["x"], w["y"], w["w"], w["h"])


def is_covered(target, peers, overlay_open):
    """True when another window (or a scratchpad) is drawn over the target."""
    if overlay_open:
        return True
    for c in peers:
        if c["id"] == target["id"] or not rects_intersect(rect(target), rect(c)):
            continue
        if c["fullscreen"]:
            return True
        if c["floating"] and not target["floating"]:
            return True
        if c["floating"] and target["floating"] and c["focus_rank"] < target["focus_rank"]:
            return True
    return False


def workspace_view(comp):
    """(focused monitor, windows on its visible workspace) or (None, [])."""
    mon = comp.focused_monitor()
    wins = comp.list_windows()
    if not mon or wins is None:
        return None, []
    return mon, [w for w in wins if w["workspace"] == mon["workspace"]]


def find_runs(lines, cols, rows, limit=40):
    runs = []
    for r, line in enumerate(lines[:rows]):
        line = line[:cols]
        for m in ALNUM.finditer(line):
            s, e = m.start(), m.end()
            if e - s < 2:
                continue
            n = random.randint(2, min(5, e - s))
            st = random.randint(s, e - n)
            runs.append({"row": r, "col": st, "text": line[st:st + n]})
    random.shuffle(runs)
    return runs[:limit]


def compositor():
    comp = adapters.detect()
    if comp is None:
        out({"ok": False, "reason": "unsupported-compositor", "message": adapters.unsupported_message()})
    return comp


def cmd_scan(prefer):
    comp = compositor()
    if not comp:
        return
    mon, peers = workspace_view(comp)
    if not mon:
        return out({"ok": False, "reason": "no-compositor-data"})
    cands, other_terms, no_rc = [], [], 0
    for w in peers:
        term = terminals.adapter_for(w)
        if term is None:
            if w["app"].lower() in terminals.KNOWN_UNSUPPORTED:
                other_terms.append(w["app"])
            continue
        if is_covered(w, peers, mon["overlay_open"]):
            continue
        score = -1 if (prefer and w["id"] == prefer) else term.priority(w)
        cands.append((score, random.random(), w, term))
    cands.sort(key=lambda t: (t[0], t[1]))
    for _, _, w, term in cands:
        info = term.grid_info(w, mon["scale"])
        if info == "no-remote-control":
            no_rc += 1
            continue
        if not isinstance(info, dict):
            continue
        lines = term.read_cells(w, info)
        if lines is None:
            no_rc += 1
            continue
        runs = find_runs(lines, info["cols"], info["rows"])
        if not runs:
            continue
        return out({
            "ok": True, "address": w["id"], "class": w["app"], "pid": w["pid"], "terminal": term.NAME,
            "monitor": mon["name"], "scale": mon["scale"],
            "x": w["x"] - mon["x"], "y": w["y"] - mon["y"], "w": w["w"], "h": w["h"],
            "cols": info["cols"], "rows": info["rows"], "cw": info["cw"], "ch": info["ch"],
            "ox": info["ox"], "oy": info["oy"], "font": info["font"], "fontPx": info["fontPx"],
            "runs": runs,
        })
    if no_rc:
        reason = "no-remote-control"
    elif other_terms and not cands:
        reason = "unsupported-terminal"
    else:
        reason = "no-terminal"
    out({"ok": False, "reason": reason, "monitor": mon["name"], "terminals": other_terms[:3]})


def cmd_geom(addr):
    comp = compositor()
    if not comp:
        return
    wins = comp.list_windows()
    if wins is None:
        return out({"ok": False})
    w = next((w for w in wins if w["id"] == addr), None)
    if w is None:
        return out({"ok": True, "exists": False, "visible": False})
    mon, peers = workspace_view(comp)
    on_ws = bool(mon) and any(p["id"] == addr for p in peers)
    covered = on_ws and is_covered(w, peers, mon["overlay_open"])
    out({"ok": True, "exists": True, "visible": bool(on_ws and not covered),
         "monitor": mon["name"] if mon else "",
         "x": w["x"] - (mon["x"] if mon else 0), "y": w["y"] - (mon["y"] if mon else 0),
         "w": w["w"], "h": w["h"]})


def cmd_cursor():
    comp = compositor()
    if not comp:
        return
    pos, mon = comp.cursor_pos(), comp.focused_monitor()
    if not pos or not mon:
        return out({"ok": False})
    out({"ok": True, "x": pos[0] - mon["x"], "y": pos[1] - mon["y"], "monitor": mon["name"]})


def cmd_monitor():
    comp = compositor()
    if not comp:
        return
    m = comp.focused_monitor()
    out({"ok": bool(m), "monitor": (m or {}).get("name", "")})


# ------------------------------------------------------------------ dock

def read_pinned():
    try:
        with open(PINNED) as f:
            return [l.strip() for l in f if l.strip()]
    except FileNotFoundError:
        return []


def write_pinned(items):
    tmp = PINNED + ".desktop-pet.tmp"
    with open(tmp, "w") as f:
        f.write("\n".join(items) + "\n")
    os.replace(tmp, PINNED)


def desktop_icon(app_id):
    dirs = [os.path.join(HOME, ".local/share/applications"), "/usr/local/share/applications",
            "/usr/share/applications"]
    for d in dirs:
        p = os.path.join(d, app_id + ".desktop")
        if os.path.exists(p):
            try:
                with open(p, errors="replace") as f:
                    for line in f:
                        if line.startswith("Icon="):
                            return line[5:].strip()
            except Exception:
                pass
    return app_id


DOCK_ARGS = os.path.join(STATE_DIR, "dock-args.json")
DOCK_LOCK = os.path.join(STATE_DIR, "dock.lock")


class dock_lock:
    """Serialize dock operations (the pet and the CLI may both touch the dock)."""
    def __enter__(self):
        import fcntl
        os.makedirs(STATE_DIR, exist_ok=True)
        self.f = open(DOCK_LOCK, "w")
        fcntl.flock(self.f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        self.f.close()


def dock_pids():
    code, txt = run(["pgrep", "-x", "nwg-dock-hyprla"])  # comm is truncated to 15 chars
    pids = [int(p) for p in txt.split()] if code == 0 else []
    if not pids:
        code, txt = run(["pgrep", "-f", "^(/usr/bin/)?nwg-dock-hyprland"])
        pids = [int(p) for p in txt.split()] if code == 0 else []
    return pids


def autostart_args():
    """nwg-dock-hyprland command line from the Hyprland autostart config."""
    import shlex
    cfg = os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config")
    for name in ("hypr/autostart.lua", "hypr/autostart.conf", "hypr/hyprland.conf"):
        try:
            text = open(os.path.join(cfg, name), errors="replace").read()
        except OSError:
            continue
        for line in text.splitlines():
            if line.strip().startswith(("--", "#")) or "nwg-dock-hyprland" not in line:
                continue
            m = re.search(r'"(nwg-dock-hyprland[^"]*)"', line) or re.search(r"(nwg-dock-hyprland.*)$", line)
            if m:
                try:
                    return shlex.split(m.group(1))
                except ValueError:
                    pass
    return None


def dock_args():
    """Exact args of the running dock (saved for later), else saved, else autostart."""
    for pid in dock_pids():
        try:
            with open("/proc/%d/cmdline" % pid, "rb") as f:
                args = [a.decode() for a in f.read().split(b"\0") if a]
            if args:
                save_json(DOCK_ARGS, {"args": args})
                return args
        except Exception:
            pass
    saved = load_json(DOCK_ARGS, {}).get("args")
    return saved or autostart_args()


def launch_dock(args):
    launcher = ["uwsm-app", "--"] if shutil.which("uwsm-app") else []
    for attempt in (launcher + args, args):
        subprocess.Popen(attempt, stdin=subprocess.DEVNULL, stdout=subprocess.DEVNULL,
                         stderr=subprocess.DEVNULL, start_new_session=True)
        for _ in range(30):
            time.sleep(0.1)
            if dock_pids():
                return True
    return False


def restart_dock(was_running=None):
    """Restart nwg-dock-hyprland with its exact flags so it rereads the pinned
    list. Never leaves it dead: relaunches even if it had died meanwhile."""
    running = dock_pids()
    args = dock_args()
    if not args:
        return False
    if not running and was_running is False:
        return False   # the user doesn't run the dock; just leave the file changed
    for pid in running:
        try:
            os.kill(pid, 15)
        except Exception:
            pass
    for _ in range(30):
        if not dock_pids():
            break
        time.sleep(0.1)
    return launch_dock(args)


# Journal: written BEFORE the pinned list is touched, removed after restoring.
# If the pet crashes or reloads mid-heist, the next load / heal / off restores it.
JOURNAL = os.path.join(STATE_DIR, "dock-journal.json")


def journal():
    j = load_json(JOURNAL, {})
    if not j and os.path.exists(HEIST_FLAG) and os.path.exists(PINNED_BACKUP):   # pre-0.1 layout
        try:
            j = {"original": [l.strip() for l in open(PINNED_BACKUP) if l.strip()]}
        except OSError:
            j = {}
    return j if isinstance(j.get("original"), list) else {}


def cmd_dock_info():
    installed = shutil.which("nwg-dock-hyprland") is not None
    items = read_pinned()
    out({"ok": True, "installed": installed, "running": bool(dock_pids()),
         "heist": bool(journal()),
         "pinned": [{"id": i, "icon": desktop_icon(i)} for i in items]})


def cmd_dock_steal(mode):
    installed = shutil.which("nwg-dock-hyprland") is not None
    with dock_lock():
        if journal():
            restore_locked()   # never stack heists
        items = read_pinned()
        if not installed or len(items) < 2 or not os.path.exists(PINNED):
            pick = random.choice(items) if items else "org.gnome.Nautilus"
            return out({"ok": True, "applied": False,
                        "reason": "dock not installed" if not installed else "too few pinned icons",
                        "id": pick, "icon": desktop_icon(pick)})
        was_running = bool(dock_pids())
        idx = random.randrange(len(items))
        pick = items[idx]
        rest = items[:idx] + items[idx + 1:]
        if mode == "hide":
            new = rest
        else:
            new = rest[:]
            new.insert(random.choice([i for i in range(len(items)) if i != idx]), pick)
            if new == items:
                new = rest + [pick] if items[-1] != pick else [pick] + rest
        save_json(JOURNAL, {"original": items, "mode": mode, "id": pick, "since": time.time(),
                            "dockWasRunning": was_running})
        shutil.copy2(PINNED, PINNED_BACKUP)   # extra plain-text backup
        write_pinned(new)
        restarted = restart_dock(was_running)
    out({"ok": True, "applied": True, "mode": mode, "id": pick, "icon": desktop_icon(pick),
         "restarted": restarted})


def restore_locked():
    j = journal()
    if not j:
        return False, False
    write_pinned(j["original"])
    restarted = restart_dock(j.get("dockWasRunning", True))
    for f in (JOURNAL, HEIST_FLAG):
        try:
            os.remove(f)
        except FileNotFoundError:
            pass
    return True, restarted


def cmd_dock_restore():
    with dock_lock():
        restored, restarted = restore_locked()
    out({"ok": True, "restored": restored, "restarted": restarted})


# ------------------------------------------------------------------ brain (Claude)

CONFIG_PATH = os.path.join(HOME, ".config/desktop-pet/config.json")
MEMORY_PATH = os.path.join(STATE_DIR, "memory.json")
STATE_PATH = os.path.join(STATE_DIR, "state.json")
AUTO_CAP = {"off": 0, "low": 8, "normal": 16, "high": 30}   # automatic Claude calls per hour

PERSONAS = {
    "slime": "You are a bubbly, clingy little slime. You adore your human, wobble when excited, "
             "speak in short gushy sentences and get a bit needy when ignored.",
    "cat": "You are an aloof, sarcastic little cat. You act unimpressed by everything, are dry and witty, "
           "and only grudgingly admit you like your human.",
    "dragon": "You are a dramatic, grandiose baby dragon. You speak as if you were an ancient, mighty wyrm, "
              "even though you are tiny, and you are very proud of your fire breath.",
    "goblin": "You are a mischievous, scheming little goblin. You brag about the dock icons you steal, "
              "plot harmless pranks and cackle a lot, but you always give the icons back.",
}

CANNED = {
    "slime": {
        "click": ["Hehe, that tickles!", "More pats please!", "*happy wobble*", "I love you sooo much!"],
        "meal": ["Nom nom! Crunchy letters!", "Yummy, tasted like {word}!", "*blorp* so good!"],
        "wake": ["Mmh... five more minutes...", "Oh! Hi! I was dreaming of you!"],
        "auto": ["*jiggles*", "Are you still there? Hi!", "I'm a happy little blob.", "Pet me pet me!"],
        "say": ["*wobbles excitedly*", "Yes! Whatever you say!", "Ooh, tell me more!"],
        "fire": ["Hot hot hot!"], "heist": ["Oops?"],
    },
    "cat": {
        "click": ["...fine. You may continue.", "Don't make it weird.", "*tolerates you*", "Mrrp. Acceptable."],
        "meal": ["{word}? Bland. Needs salt.", "I've had better letters.", "*crunch* adequate."],
        "wake": ["Did you just wake me? Bold.", "I was not asleep. I was thinking."],
        "auto": ["*stares at your cursor*", "I knocked a pixel off your screen.", "Feed me. Or don't. Whatever."],
        "say": ["Mhm. Fascinating.", "Is that so.", "*slow blink*"],
        "fire": ["Not my department."], "heist": ["Not my department."],
    },
    "dragon": {
        "click": ["You dare touch the mighty dragon? ...do it again.", "Bow before me! Also, thanks.", "*proud snort*"],
        "meal": ["I have devoured \"{word}\"! Tremble!", "Your letters fuel my eternal flame!", "A worthy feast."],
        "wake": ["WHO DISTURBS MY SLUMBER?", "The ancient one awakens... yawn."],
        "auto": ["Behold my magnificence!", "One day I shall be enormous.", "I sense letters nearby..."],
        "say": ["Your words please the dragon.", "Hah! Mortal, you amuse me."],
        "fire": ["BURN! Your text is now gloriously red!", "Witness my flame!", "Toasted. Perfectly."],
        "heist": ["Hoard it all!"],
    },
    "goblin": {
        "click": ["Hands off the loot!", "Heh heh, you didn't see nothin'.", "*cackles*"],
        "meal": ["Snack stolen, snack eaten.", "Mine now. Nom."],
        "wake": ["I wasn't sleeping, I was SCHEMING.", "Wha-? Who's there? My loot!"],
        "auto": ["Nice dock you got there...", "Heh heh heh.", "I'm planning something. Don't worry about it."],
        "say": ["Heh, a deal? I'm listening.", "Whatever you say, boss. *crosses fingers*"],
        "fire": ["Ooh, shiny."],
        "heist": ["Yoink! That icon's mine now!", "Heh heh, finders keepers!", "Fine, fine, you can have it back."],
    },
}


GENERIC = {
    "fetch": ["Again! Again!", "Got it!", "*drops the ball at your feet*"],
    "evolve": ["I feel... different. Bigger!", "Look at me now!", "Whoa, I evolved!"],
    "buddy-fail": ["Ouch, that one failed.", "Oof. Try again?", "*winces*"],
    "buddy-test": ["Tests passed! Woo!", "All green!", "*happy dance*"],
    "buddy-push": ["Pushed! Victory!", "Ship it!", "*victory dance*"],
    "buddy-done": ["Done! That took a while.", "Finished!", "*hop* all done!"],
}


def load_json(path, default):
    try:
        with open(path) as f:
            v = json.load(f)
        return v if isinstance(v, type(default)) else default
    except Exception:
        return default


def save_json(path, obj):
    os.makedirs(os.path.dirname(path), exist_ok=True)
    tmp = path + ".tmp"
    with open(tmp, "w") as f:
        json.dump(obj, f, indent=1)
    os.replace(tmp, path)


ANSI = re.compile(r"\x1b\[[0-9;?]*[ -/]*[@-~]|\x1b\][^\x07]*\x07")


def clean_text(text, cap=120):
    # Display text only: strip escapes, markdown and control chars, one line, capped.
    t = ANSI.sub("", text or "")
    t = re.sub(r"[\x00-\x1f\x7f]", " ", t)
    t = re.sub(r"[_`#>|]+|\*\*", "", t)
    t = re.sub(r"\s+", " ", t).strip().strip('"').strip()
    if len(t) > cap:
        cut = t[:cap - 1]
        if " " in cut[cap // 2:]:
            cut = cut[:cut.rfind(" ")]
        t = cut.rstrip(",;: ") + "…"
    return t


def canned(pet, trigger, word=""):
    lines = CANNED.get(pet, CANNED["slime"])
    pool = lines.get(trigger) or GENERIC.get(trigger) or lines.get("auto")
    line = random.choice(pool)
    return line.replace("{word}", word or "letters")


def time_of_day(h):
    if 5 <= h < 12:
        return "morning"
    if 12 <= h < 17:
        return "afternoon"
    if 17 <= h < 23:
        return "evening"
    return "night"


def build_prompt(p, cfg, mem, user_msg="", history=None):
    pet = p.get("pet") or cfg.get("pet") or "slime"
    names = cfg.get("names") or {}
    name = p.get("name") or names.get(pet) or ""
    personas = cfg.get("persona") or {}
    persona = personas.get(pet) if isinstance(personas, dict) else None
    persona = persona or PERSONAS.get(pet, PERSONAS["slime"])
    who = name if name else "an as-yet unnamed little " + pet + " (you would love a name)"
    stage = p.get("stage") or ""
    system = (
        "You are " + who + ", a tiny pixel-art desktop pet (" + (stage + " " if stage else "") + pet + ") living on your human's Linux desktop. "
        + persona +
        " Always stay in character. Reply with exactly ONE short line of plain text, at most 100 characters. "
        "No markdown, no lists, no quotes around the line, no stage directions longer than three words, no hashtags. "
        "You cannot do anything except talk; never offer to run commands or open things."
    )
    now = time.localtime()
    lines = [
        "Right now: %s (%02d:%02d), Omarchy theme: %s." % (time_of_day(now.tm_hour), now.tm_hour, now.tm_min, p.get("theme", "?")),
        "Your stats out of 100: hunger fullness %s, happiness %s, energy %s. Mood: %s. Age: %s days." % (
            p.get("hunger", "?"), p.get("happiness", "?"), p.get("energy", "?"), p.get("mood", "?"), p.get("ageDays", "?")),
    ]
    if p.get("accessory"):
        lines.append("You are wearing: %s." % p["accessory"])
    ev = mem.get("events", [])[-8:]
    if ev:
        lines.append("Recent events (oldest first):")
        for e in ev:
            ago = int((time.time() - e.get("t", time.time())) / 60)
            lines.append("- %s (%d min ago)" % (e.get("text", ""), ago))
    said = mem.get("lines", [])[-5:]
    if said:
        lines.append("Things you said recently (don't repeat them): " + " | ".join(s.get("text", "") for s in said))
    if p.get("context"):
        lines.append("Extra desktop context the user opted in to share: " + p["context"])
    trig = p.get("trigger", "auto")
    if user_msg:
        if history:
            lines.append("Conversation so far:")
            for h in history[-8:]:
                lines.append("%s: %s" % ("Human" if h.get("who") == "user" else name, h.get("text", "")))
        lines.append("Your human says to you: " + user_msg)
        lines.append("Reply to them in character.")
    else:
        what = {
            "meal": "You just finished eating. React to it.",
            "click": "Your human just petted you (clicked on you). React.",
            "wake": "Your human just woke you up. React.",
            "fire": "You just breathed fire at some terminal text. React.",
            "heist": "React to what you just did with the dock icon.",
            "fetch": "You just brought the ball back after a game of fetch. React.",
            "evolve": "You just evolved into a new form! React with excitement, in character.",
            "buddy-fail": "Your human's terminal command failed. Commiserate briefly, in character.",
            "buddy-test": "Your human's tests just passed. Cheer, in character.",
            "buddy-push": "Your human just pushed their code. Celebrate, in character.",
            "buddy-done": "A long-running command of your human's just finished. Announce it, in character.",
        }.get(trig, "Say something spontaneous to your human, inspired by your mood or recent events.")
        if p.get("event"):
            what = "This just happened: " + p["event"] + ". " + what
        lines.append(what)
    return system, "\n".join(lines)


def ask_claude(system, prompt):
    exe = find_claude()
    if not exe:
        return None
    cmd = [exe, "-p", "--model", "haiku", "--system-prompt", system, "--tools", "",
           "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}', "--no-session-persistence",
           "--setting-sources", "", prompt]
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=30, cwd=STATE_DIR,
                           stdin=subprocess.DEVNULL)
    except Exception:
        return None
    if r.returncode != 0:
        return None
    t = clean_text(r.stdout)
    return t or None


def active_context():
    comp = adapters.detect()
    aw = (comp.active_window() if comp else None) or {}
    t, c = aw.get("title", ""), aw.get("app", "")
    return ("focused window: %s - %s" % (c, t))[:160] if (t or c) else ""


def cmd_talk(raw):
    """Payload JSON: trigger, event, silent, allowClaude, pet, name, mood, stats, theme,
    accessory, message (user text), history (chat). Prints {"text", "source"}."""
    try:
        p = json.loads(raw)
    except Exception:
        p = {}
    os.makedirs(STATE_DIR, exist_ok=True)
    cfg = load_json(CONFIG_PATH, {})
    mem = load_json(MEMORY_PATH, {})
    mem.setdefault("events", [])
    mem.setdefault("lines", [])
    mem.setdefault("auto", [])
    now = time.time()
    trig = p.get("trigger", "auto")
    pet = p.get("pet") or cfg.get("pet") or "slime"
    msg = clean_text(p.get("message", ""), 400)
    if p.get("event"):
        mem["events"].append({"t": now, "text": clean_text(p["event"], 160)})
    if msg:
        mem["events"].append({"t": now, "text": "my human said: " + msg})
    mem["events"] = mem["events"][-20:]
    if p.get("silent"):
        save_json(MEMORY_PATH, mem)
        return out({"text": "", "source": "silent"})

    word = ""
    m = re.search(r'"([^"]+)"', p.get("event", ""))
    if m:
        word = m.group(1)
    text, source = None, "canned"
    brain_on = cfg.get("brain", True) is not False
    user_initiated = trig in ("say", "chat")
    allow = brain_on and (user_initiated or p.get("allowClaude"))
    if allow and not user_initiated:
        level = cfg.get("chatty", "low")
        mem["auto"] = [t for t in mem["auto"] if now - t < 3600]
        if len(mem["auto"]) >= AUTO_CAP.get(level, 8):
            allow = False
    if allow:
        if cfg.get("brainContext") is True:
            p["context"] = active_context()
        system, prompt = build_prompt(p, cfg, mem, msg, p.get("history"))
        text = ask_claude(system, prompt)
        if text:
            source = "claude"
            if not user_initiated:
                mem["auto"].append(now)
    if not text:
        text = canned(pet, trig if trig != "chat" else "say", word)
    mem["lines"].append({"t": now, "text": text})
    mem["lines"] = mem["lines"][-20:]
    save_json(MEMORY_PATH, mem)
    out({"text": text, "source": source})


# ------------------------------------------------------------------ skills

def cmd_cursor_stream(seconds):
    comp = compositor()
    if not comp:
        return
    end = time.time() + max(0.5, min(12.0, seconds))
    last = None
    while time.time() < end:
        pos, mon = comp.cursor_pos(), comp.focused_monitor()
        if pos and mon:
            cur = (pos[0] - mon["x"], pos[1] - mon["y"], mon["name"])
            if cur != last:
                out({"x": cur[0], "y": cur[1], "monitor": cur[2]})
                sys.stdout.flush()
                last = cur
        time.sleep(0.12)


def cmd_skills_pitch(args):
    auto = "--auto" in args
    rest = [a for a in args if a != "--auto"]
    try:
        ctx = json.loads(rest[0]) if rest else {}
    except Exception:
        ctx = {}
    cfg = load_json(CONFIG_PATH, {})
    pet = ctx.get("pet") or cfg.get("pet") or "slime"
    ctx["pet"] = pet
    if not ctx.get("name"):
        ctx["name"] = (cfg.get("names") or {}).get(pet, "")
    personas = cfg.get("persona") if isinstance(cfg.get("persona"), dict) else {}
    persona = personas.get(pet) or PERSONAS.get(pet, PERSONAS["slime"])
    out(skills.pitch(ctx, persona, auto=auto))


def cmd_restore_all():
    with dock_lock():
        d, _ = restore_locked()
    w = skills.wall_restore()
    out({"ok": True, "dock": d, "wallpaper": w})


def main(argv):
    if not argv:
        print(__doc__)
        return 2
    cmd = argv[0]
    if cmd == "scan":
        prefer = argv[2] if len(argv) > 2 and argv[1] == "--prefer" else ""
        cmd_scan(prefer)
    elif cmd == "monitor":
        cmd_monitor()
    elif cmd == "cursor":
        cmd_cursor()
    elif cmd == "geom" and len(argv) > 1:
        cmd_geom(argv[1])
    elif cmd == "dock-info":
        cmd_dock_info()
    elif cmd == "dock-steal":
        cmd_dock_steal(argv[1] if len(argv) > 1 else "move")
    elif cmd == "dock-restore":
        cmd_dock_restore()
    elif cmd == "talk":
        cmd_talk(argv[1] if len(argv) > 1 else sys.stdin.read())
    elif cmd == "skills-list":
        out(skills.list_for_qml())
    elif cmd in ("skills-approve", "skills-reject") and len(argv) > 1:
        ok, msg = (skills.approve if cmd == "skills-approve" else skills.reject)(argv[1])
        out({"ok": ok, "id": msg if ok else argv[1], "message": "" if ok else msg})
    elif cmd == "skills-pitch":
        cmd_skills_pitch(argv[1:])
    elif cmd == "wall-swap" and len(argv) > 5:
        try:
            colors = json.loads(argv[4])
        except Exception:
            colors = {}
        out(skills.wall_swap(argv[1], int(float(argv[2])), int(float(argv[3])), colors if isinstance(colors, dict) else {}, float(argv[5])))
    elif cmd == "wall-restore":
        out({"ok": True, "restored": skills.wall_restore()})
    elif cmd == "restore-all":
        cmd_restore_all()
    elif cmd == "cursor-stream":
        cmd_cursor_stream(float(argv[1]) if len(argv) > 1 else 5)
    elif cmd == "sound" and len(argv) > 1:
        out(skills.play_sound(argv[1]))
    else:
        print(__doc__)
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
