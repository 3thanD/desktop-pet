"""Pet skills: recipe discovery, validation, the pitch queue, and the two
journaled desktop changes skills may make (the wallpaper swap here; the dock
lives in helper.py).

A skill is a declarative JSON recipe (docs/skill.schema.json, docs/SKILLS.md):
a trigger plus a few steps built ONLY from a fixed list of approved actions that
the QML engine implements. Recipes never contain commands, paths outside the
user skills dir, URLs or anything executable; this module rejects anything that
does not match the schema exactly, plus a few extra semantic checks.

  built-in   <plugin>/skills/<pet>/<id>.json          on by default
  user       ~/.config/desktop-pet/skills/<id>.json   off until enabled
  pending    ~/.local/state/desktop-pet/skills/pending/<id>.json   pitched by the
             pet through Claude; never runs except a one-off preview, until approved
"""
import json
import os
import random
import re
import shutil
import struct
import subprocess
import time
import zlib

from util import run, find_claude

HOME = os.path.expanduser("~")
REPO_DIR = os.path.dirname(os.path.dirname(os.path.realpath(__file__)))
BUILTIN_DIR = os.path.join(REPO_DIR, "skills")
SCHEMA_PATH = os.path.join(REPO_DIR, "docs", "skill.schema.json")
CONFIG_PATH = os.path.join(HOME, ".config/desktop-pet/config.json")
USER_DIR = os.path.join(HOME, ".config/desktop-pet/skills")
STATE_DIR = os.path.join(HOME, ".local/state/desktop-pet")
SK_STATE = os.path.join(STATE_DIR, "skills")
PENDING_DIR = os.path.join(SK_STATE, "pending")
PITCH_LOG = os.path.join(SK_STATE, "pitches.json")
DOODLE_DIR = os.path.join(SK_STATE, "doodles")
SOUND_DIR = os.path.join(SK_STATE, "sounds")
WALL_JOURNAL = os.path.join(STATE_DIR, "wall-journal.json")
WALL_LOCK = os.path.join(STATE_DIR, "wall.lock")
BG_LINK = os.path.join(HOME, ".local/state/omarchy/current/background")

MAX_RECIPE_BYTES = 16 * 1024
MAX_PNG_BYTES = 256 * 1024
MAX_PNG_SIDE = 1024
MAX_PENDING = 5
AUTO_PITCH_GAP = 24 * 3600        # automatic pitches: at most one a day
MANUAL_PITCH_CAP = 6              # `skills pitch`: at most 6 a day
MAX_RUN_SECONDS = 120             # hard cap the engine enforces on every run / effect
PETS = ("slime", "cat", "dragon", "goblin")
BUILTIN_DOODLES = ("goblin-was-here", "slime-was-here", "heart", "crown", "paw", "skull-and-coins")


# ------------------------------------------------------------------ small io

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
        f.write("\n")
    os.replace(tmp, path)


class file_lock:
    def __init__(self, path):
        self.path = path

    def __enter__(self):
        import fcntl
        os.makedirs(os.path.dirname(self.path), exist_ok=True)
        self.f = open(self.path, "w")
        fcntl.flock(self.f, fcntl.LOCK_EX)
        return self

    def __exit__(self, *exc):
        self.f.close()


# ------------------------------------------------------------------ schema validation
# A small JSON-Schema interpreter for exactly the keywords skill.schema.json uses
# (type, const, enum, properties, required, additionalProperties, pattern,
# minLength/maxLength, minimum/maximum, items, minItems/maxItems, oneOf, $ref).
# Unknown keywords in the schema are an error, so the two can't drift apart.

_SCHEMA = None
KNOWN_KW = {"$schema", "$id", "title", "description", "type", "const", "enum", "properties", "required",
            "additionalProperties", "pattern", "minLength", "maxLength", "minimum", "maximum", "items",
            "minItems", "maxItems", "oneOf", "$ref", "$defs"}


def schema():
    global _SCHEMA
    if _SCHEMA is None:
        with open(SCHEMA_PATH) as f:
            _SCHEMA = json.load(f)
    return _SCHEMA


def _resolve(ref):
    if not ref.startswith("#/"):
        raise ValueError("unsupported $ref " + ref)
    node = schema()
    for part in ref[2:].split("/"):
        node = node[part]
    return node


def _type_ok(t, v):
    if t == "object":
        return isinstance(v, dict)
    if t == "array":
        return isinstance(v, list)
    if t == "string":
        return isinstance(v, str)
    if t == "boolean":
        return isinstance(v, bool)
    if t == "integer":
        return isinstance(v, int) and not isinstance(v, bool)
    if t == "number":
        return isinstance(v, (int, float)) and not isinstance(v, bool) and v == v and abs(v) != float("inf")
    raise ValueError("unsupported type " + t)


def validate(node, v, where="recipe"):
    """Return a list of error strings (empty = valid)."""
    bad = set(node) - KNOWN_KW
    if bad:
        raise ValueError("schema uses unsupported keywords: %s" % ", ".join(sorted(bad)))
    errs = []
    if "$ref" in node:
        errs += validate(_resolve(node["$ref"]), v, where)
    if "oneOf" in node:
        # steps: pick the branch by its "action" const for a readable error
        if isinstance(v, dict) and "action" in v:
            branches = [_resolve(b["$ref"]) if "$ref" in b else b for b in node["oneOf"]]
            names = [b.get("properties", {}).get("action", {}).get("const") for b in branches]
            if v["action"] not in names:
                return errs + ["%s: unknown action %r (allowed: %s)" % (where, v["action"], ", ".join(n for n in names if n))]
            errs += validate(branches[names.index(v["action"])], v, where)
        else:
            ok = [b for b in node["oneOf"] if not validate(b, v, where)]
            if len(ok) != 1:
                errs.append("%s: must be a step object with an \"action\"" % where)
    if "type" in node and not _type_ok(node["type"], v):
        return errs + ["%s: must be of type %s" % (where, node["type"])]
    if "const" in node and v != node["const"]:
        errs.append("%s: must be %r" % (where, node["const"]))
    if "enum" in node and v not in node["enum"]:
        errs.append("%s: %r is not one of %s" % (where, v, ", ".join(map(str, node["enum"]))))
    if isinstance(v, str):
        if "minLength" in node and len(v) < node["minLength"]:
            errs.append("%s: too short" % where)
        if "maxLength" in node and len(v) > node["maxLength"]:
            errs.append("%s: longer than %d characters" % (where, node["maxLength"]))
        if "pattern" in node and not re.search(node["pattern"], v):
            errs.append("%s: %r does not match %s" % (where, v[:40], node["pattern"]))
    if isinstance(v, (int, float)) and not isinstance(v, bool):
        if "minimum" in node and v < node["minimum"]:
            errs.append("%s: %s is below the minimum %s" % (where, v, node["minimum"]))
        if "maximum" in node and v > node["maximum"]:
            errs.append("%s: %s is above the maximum %s" % (where, v, node["maximum"]))
    if isinstance(v, list):
        if "minItems" in node and len(v) < node["minItems"]:
            errs.append("%s: needs at least %d items" % (where, node["minItems"]))
        if "maxItems" in node and len(v) > node["maxItems"]:
            errs.append("%s: at most %d items" % (where, node["maxItems"]))
        if "items" in node:
            for i, it in enumerate(v[:100]):
                errs += validate(node["items"], it, "%s[%d]" % (where, i))
    if isinstance(v, dict):
        props = node.get("properties", {})
        for k in node.get("required", []):
            if k not in v:
                errs.append("%s: missing %r" % (where, k))
        if node.get("additionalProperties") is False:
            for k in v:
                if k not in props:
                    errs.append("%s: unknown field %r" % (where, str(k)[:40]))
        for k, sub in props.items():
            if k in v:
                errs += validate(sub, v[k], where + "." + k)
    return errs


# Strings in a recipe are display text or enum-like names. Anything that looks
# like a command, a path or a URL is rejected outright (defense in depth: no
# field is ever executed, but a recipe that tries is not one we want to run).
PLACEHOLDERS = re.compile(r"\{(name|icon)\}")
BAD_CHARS = re.compile(r"[`$\\<>|;{}\x00-\x1f\x7f]")
BAD_BITS = re.compile(r"://|\.\./|\.\.\\|~/|/(bin|usr|etc|home|tmp|dev|proc|sys|var|root|run)\b|&&|\|\||"
                      r"\b(sudo|bash|zsh|eval|exec|curl|wget|chmod|chown|python3?|perl|rm\s+-|mkfs|dd\s+if)\b",
                      re.I)


def _strings(v, where="recipe"):
    if isinstance(v, str):
        yield where, v
    elif isinstance(v, dict):
        for k, x in v.items():
            yield from _strings(k, where + ".<key>")
            yield from _strings(x, where + "." + str(k)[:20])
    elif isinstance(v, list):
        for i, x in enumerate(v):
            yield from _strings(x, "%s[%d]" % (where, i))


def safety_errors(recipe):
    errs = []
    for where, s in _strings(recipe):
        t = PLACEHOLDERS.sub("", s)
        if BAD_CHARS.search(t) or BAD_BITS.search(t):
            errs.append("%s: looks like a command, path or URL (%r); recipes are display text only" % (where, s[:40]))
    return errs


def png_errors(name):
    """A user doodle: NAME.png directly inside the user skills dir, small PNG."""
    if name in BUILTIN_DOODLES:
        return []
    if not name.endswith(".png"):
        return ["unknown built-in doodle %r (built-ins: %s)" % (name, ", ".join(BUILTIN_DOODLES))]
    path = os.path.join(USER_DIR, name)
    real = os.path.realpath(path)
    if os.path.dirname(real) != os.path.realpath(USER_DIR) or os.path.basename(real) != name:
        return ["doodle %r must be a file directly inside %s (no links or paths)" % (name, USER_DIR)]
    try:
        st = os.stat(real)
        if st.st_size > MAX_PNG_BYTES:
            return ["doodle %r is %d KB; the limit is %d KB" % (name, st.st_size // 1024, MAX_PNG_BYTES // 1024)]
        with open(real, "rb") as f:
            head = f.read(24)
    except OSError:
        return ["doodle %r not found in %s" % (name, USER_DIR)]
    if head[:8] != b"\x89PNG\r\n\x1a\n" or head[12:16] != b"IHDR":
        return ["doodle %r is not a PNG image" % name]
    w, h = struct.unpack(">II", head[16:24])
    if not (0 < w <= MAX_PNG_SIDE and 0 < h <= MAX_PNG_SIDE):
        return ["doodle %r is %dx%d; the limit is %dx%d" % (name, w, h, MAX_PNG_SIDE, MAX_PNG_SIDE)]
    return []


def check_recipe(recipe):
    """Full validation. Returns a list of errors (empty = the recipe may run)."""
    if not isinstance(recipe, dict):
        return ["a recipe must be a JSON object"]
    try:
        errs = validate(schema(), recipe)
    except (ValueError, KeyError, OSError) as e:
        return ["schema problem: %s" % e]
    errs += safety_errors(recipe)
    if errs:
        return errs
    total = 0.0
    for i, st in enumerate(recipe["steps"]):
        a = st["action"]
        if a in ("doodle", "wallpaper"):
            errs += ["recipe.steps[%d]: %s" % (i, e) for e in png_errors(st.get("image") or st.get("doodle"))]
        if a in ("animate", "wait", "clones", "shake"):
            total += float(st.get("duration", 1))
        if a == "move" and st.get("follow"):
            total += float(st["follow"])
        if a == "glyph" and st["source"] == "text" and not st.get("text"):
            errs.append("recipe.steps[%d]: glyph with source \"text\" needs a text" % i)
    if total > MAX_RUN_SECONDS:
        errs.append("recipe: the steps add up to %ds; a skill may run at most %ds" % (total, MAX_RUN_SECONDS))
    return errs


def load_recipe_file(path):
    """(recipe, errors). Rejects oversized files before parsing."""
    try:
        st = os.stat(path)
    except OSError as e:
        return None, ["cannot read: %s" % e.strerror]
    if st.st_size > MAX_RECIPE_BYTES:
        return None, ["file is %d KB; recipes are limited to %d KB" % (st.st_size // 1024, MAX_RECIPE_BYTES // 1024)]
    try:
        with open(path, encoding="utf-8") as f:
            data = json.load(f)
    except (ValueError, UnicodeDecodeError) as e:
        return None, ["not valid JSON: %s" % str(e)[:80]]
    except OSError as e:
        return None, ["cannot read: %s" % e.strerror]
    errs = check_recipe(data)
    return (None if errs else data), errs


# ------------------------------------------------------------------ discovery

def load_config():
    c = load_json(CONFIG_PATH, {})
    return c if isinstance(c, dict) else {}


def is_enabled(cfg, sid, origin):
    m = cfg.get("skills") if isinstance(cfg.get("skills"), dict) else {}
    if sid in m:
        return m[sid] is True
    return origin == "builtin"


def _json_files(d):
    try:
        return sorted(os.path.join(d, f) for f in os.listdir(d) if f.endswith(".json"))
    except OSError:
        return []


def discover():
    """All skills: [{id, origin, file, recipe}], pending [{id, pitch, at, recipe}], errors."""
    skills, errors, seen = [], [], set()
    for pet in PETS:
        for path in _json_files(os.path.join(BUILTIN_DIR, pet)):
            r, errs = load_recipe_file(path)
            if errs:
                errors.append({"file": os.path.relpath(path, REPO_DIR), "origin": "builtin", "errors": errs[:6]})
                continue
            seen.add(r["id"])
            skills.append({"id": r["id"], "origin": "builtin", "file": path, "recipe": r})
    for path in _json_files(USER_DIR):
        r, errs = load_recipe_file(path)
        if not errs and r["id"] in seen:
            errs = ["id %r is already used by another skill" % r["id"]]
        if errs:
            errors.append({"file": path, "origin": "user", "errors": errs[:6]})
            continue
        seen.add(r["id"])
        skills.append({"id": r["id"], "origin": "user", "file": path, "recipe": r})
    pending = []
    for path in _json_files(PENDING_DIR):
        p = load_json(path, {})
        r = p.get("recipe")
        errs = check_recipe(r) if r is not None else ["no recipe"]
        if errs:
            errors.append({"file": path, "origin": "pending", "errors": errs[:6]})
            continue
        pending.append({"id": r["id"], "pitch": str(p.get("pitch", ""))[:160], "at": p.get("at", 0),
                        "pet": p.get("pet", r["pet"]), "file": path, "recipe": r})
    pending.sort(key=lambda p: p["at"])
    return skills, pending, errors


def list_for_qml():
    cfg = load_config()
    skills, pending, errors = discover()
    return {"ok": True,
            "skills": [{"id": s["id"], "origin": s["origin"], "enabled": is_enabled(cfg, s["id"], s["origin"]),
                        "recipe": s["recipe"]} for s in skills],
            "pending": [{"id": p["id"], "pitch": p["pitch"], "pet": p["pet"], "recipe": p["recipe"]} for p in pending],
            "errors": errors}


def find_pending(sid):
    for p in discover()[1]:
        if p["id"] == sid:
            return p
    return None


def set_enabled(sid, on):
    cfg = load_config()
    m = cfg.get("skills") if isinstance(cfg.get("skills"), dict) else {}
    m[sid] = bool(on)
    cfg["skills"] = m
    save_json(CONFIG_PATH, cfg)


def approve(sid):
    p = find_pending(sid)
    if not p:
        return False, "no pending skill %r" % sid
    taken = {s["id"] for s in discover()[0]}
    r = dict(p["recipe"])
    if r["id"] in taken:
        return False, "a skill called %r already exists" % r["id"]
    os.makedirs(USER_DIR, exist_ok=True)
    save_json(os.path.join(USER_DIR, r["id"] + ".json"), r)
    os.remove(p["file"])
    set_enabled(r["id"], True)
    return True, r["id"]


def reject(sid):
    p = find_pending(sid)
    if not p:
        return False, "no pending skill %r" % sid
    os.remove(p["file"])
    return True, sid


def remove(sid):
    """Delete a user skill (built-ins can only be disabled)."""
    for s in discover()[0]:
        if s["id"] == sid:
            if s["origin"] == "builtin":
                return False, "%r is built in; use: desktop-pet skills disable %s" % (sid, sid)
            os.remove(s["file"])
            cfg = load_config()
            if isinstance(cfg.get("skills"), dict) and sid in cfg["skills"]:
                del cfg["skills"][sid]
                save_json(CONFIG_PATH, cfg)
            return True, sid
    p = find_pending(sid)
    if p:
        os.remove(p["file"])
        return True, sid
    # also clean up a recipe that failed validation (shown under "errors")
    for path in _json_files(USER_DIR):
        if os.path.basename(path) == sid + ".json":
            os.remove(path)
            return True, sid
    return False, "no user skill %r" % sid


# ------------------------------------------------------------------ describing a recipe

TRIGGER_TEXT = {
    "idle": "now and then while it is idle",
    "walk": "when it starts a stroll",
    "happy": "when its happiness is at least {min}",
    "neglected": "when nobody has petted it for {min} minutes",
    "petted": "when you pet it",
    "command-ok": "when a terminal command succeeds (build buddy)",
    "milestone": "every {min} coins in its hoard",
    "manual": "only when you run it (desktop-pet skills run ID)",
}


def describe_step(st):
    a = st["action"]
    if a == "move":
        if st["to"] == "cursor" and st.get("follow"):
            return "sits beside your mouse pointer and follows it for %gs (never blocks clicks)" % st["follow"]
        return "walks to the %s" % {"random": "somewhere nearby", "home": "where it started"}.get(st["to"], st["to"])
    if a == "hop":
        return "hops %d time%s" % (st["count"], "" if st["count"] == 1 else "s")
    if a == "path":
        return "walks a little %s %s" % (st.get("size", "medium"), st["shape"])
    if a == "animate":
        return "plays its %s animation (%gs)" % (st["frames"], st.get("duration", 1))
    if a == "bubble":
        return "says: \"%s\"" % st["text"]
    if a == "wait":
        return "waits %gs" % st["duration"]
    if a == "particles":
        return "a small burst of %s around itself" % st["kind"]
    if a == "trail":
        return "leaves %s behind as it walks for %gs (each fades after %gs)" % (st["kind"], st.get("duration", 10), st.get("fade", 8))
    if a == "tint":
        return "a soft %s tint %s for %gs" % (st["color"], "over the screen" if st.get("area") == "screen" else "around itself", st.get("duration", 2))
    if a == "shake":
        return "a %s screen-shake drawn on an overlay for %gs (no real window moves)" % (st.get("intensity", "gentle"), st.get("duration", 1))
    if a == "glyph":
        if st["source"] == "terminal":
            return "swats ONE letter off a btop/kitty window; it falls and %s (the hole heals in a few minutes)" % (
                "shatters into pixels" if st.get("shatter", True) else "fades")
        return "drops a \"%s\" that falls with physics" % st.get("text", "?")
    if a == "doodle":
        return "shows a small \"%s\" doodle %s for %gs" % (st["image"], {"pet": "next to itself", "corner": "in a corner", "center": "in the middle"}.get(st.get("where", "pet")), st.get("duration", 5))
    if a == "sound":
        return "plays a tiny \"%s\" sound (only if skill sounds are on)" % st["name"]
    if a == "dock":
        r = st.get("ransom")
        extra = (" until you pet it %d time%s (ransom note)" % (r["count"], "" if r["count"] == 1 else "s")) if r else ""
        return "%s one dock icon%s; it comes back by itself after %gs at the latest" % (
            "hides" if st["mode"] == "hide" else "moves", extra, st.get("duration", 60))
    if a == "wallpaper":
        return "swaps your wallpaper for a \"%s\" doodle; the original comes back after %gs" % (st["doodle"], st.get("duration", 20))
    if a == "clones":
        return "splits into %d mini copies for %gs, then they merge back" % (st["count"], st.get("duration", 30))
    if a == "hoard":
        return "adds %d coin%s to its tiny coin pile" % (st.get("add", 1), "" if st.get("add", 1) == 1 else "s")
    return a


def describe(recipe):
    t = recipe["trigger"]
    when = TRIGGER_TEXT[t["on"]].format(min=int(t.get("min", 0)) if t.get("min") is not None else "?")
    if t.get("chance") is not None and t["on"] != "manual":
        when += " (chance %g%% %s)" % (t["chance"] * 100, "per minute" if t["on"] in ("idle", "happy", "neglected") else "each time")
    lines = ["when: " + when + "; at most every %g min" % recipe["cooldown"]
             + (", %d a day" % recipe["maxPerDay"] if recipe.get("maxPerDay") else "")]
    lines += ["  %d. %s" % (i + 1, describe_step(s)) for i, s in enumerate(recipe["steps"])]
    touches = []
    for s in recipe["steps"]:
        a = s["action"]
        if a == "dock":
            touches.append("a dock icon (journaled, restored on heal/off/crash)")
        elif a == "wallpaper":
            touches.append("your wallpaper (journaled, restored on heal/off/crash)")
        elif a == "glyph" and s["source"] == "terminal":
            touches.append("one letter of terminal text (an overlay patch, the text itself is untouched)")
        elif a == "sound":
            touches.append("sound (if enabled)")
    lines.append("touches: " + (", ".join(dict.fromkeys(touches)) if touches else "nothing outside its own overlays"))
    lines.append("everything reverts by itself within %ds; `desktop-pet heal` undoes it at once" % MAX_RUN_SECONDS)
    return lines


# ------------------------------------------------------------------ pitching (Claude)

def pitch_log():
    j = load_json(PITCH_LOG, {})
    j.setdefault("auto", [])
    j.setdefault("manual", [])
    return j


def pitch_allowed(auto):
    now = time.time()
    j = pitch_log()
    if len(discover()[1]) >= MAX_PENDING:
        return False, "the pitch queue is full (%d waiting); review them first: desktop-pet skills review" % MAX_PENDING
    if auto:
        last = max([t for t in j["auto"] + j["manual"]] or [0])
        if now - last < AUTO_PITCH_GAP:
            return False, "already pitched today"
    else:
        recent = [t for t in j["manual"] if now - t < 86400]
        if len(recent) >= MANUAL_PITCH_CAP:
            return False, "that's %d pitches today; your pet needs to think up new ideas (try tomorrow)" % MANUAL_PITCH_CAP
    return True, ""


def _record_pitch(auto):
    j = pitch_log()
    now = time.time()
    key = "auto" if auto else "manual"
    j[key] = [t for t in j[key] if now - t < 7 * 86400] + [now]
    save_json(PITCH_LOG, j)


def _compact_schema():
    return json.dumps(schema(), separators=(",", ":"))


EXAMPLE = {
    "format": "desktop-pet-skill/1", "id": "happy-twirl", "name": "Happy twirl", "pet": "slime",
    "description": "Twirls in a little heart shape and sparkles.",
    "trigger": {"on": "petted", "chance": 0.3}, "cooldown": 30, "maxPerDay": 4,
    "steps": [{"action": "bubble", "text": "Wheee!"}, {"action": "path", "shape": "heart", "size": "small"},
              {"action": "particles", "kind": "sparkles", "count": 10, "color": "accent"}],
}


def build_pitch_prompt(ctx, persona, existing):
    pet = ctx.get("pet", "slime")
    name = ctx.get("name") or ("a little " + pet)
    system = (
        "You are " + name + ", a tiny pixel-art desktop pet (" + pet + ") on your human's Linux desktop. " + persona +
        " You are inventing ONE new harmless trick (a 'skill') for yourself and pitching it to your human. "
        "A skill is a JSON recipe that must validate against this JSON Schema exactly:\n" + _compact_schema() +
        "\nRules: use ONLY the actions in the schema; no unknown fields; plain display text only (no commands, "
        "paths, URLs, code, $, backticks, semicolons or braces); it must be cute, entertaining and impermanent. "
        "Prefer small, playful effects (particles, paths, hops, bubbles, trails, doodles). Set \"pet\" to \"" + pet + "\". "
        "Use cooldown >= 30 and maxPerDay <= 4. Pick a new id that is not one of: " + ", ".join(existing) + ".\n"
        "Example recipe: " + json.dumps(EXAMPLE, separators=(",", ":")) + "\n"
        "Output ONLY one JSON object of the form {\"pitch\": \"<one short in-character line, max 100 chars, "
        "asking your human to let you learn it>\", \"recipe\": {...}} with nothing before or after it."
    )
    user = ("Your stats: happiness %s, energy %s, mood %s, stage %s. Pitch your new trick now." %
            (ctx.get("happiness", "?"), ctx.get("energy", "?"), ctx.get("mood", "?"), ctx.get("stage", "?")))
    return system, user


def extract_json(text):
    t = (text or "").strip()
    t = re.sub(r"^```(?:json)?\s*|\s*```$", "", t)
    s, e = t.find("{"), t.rfind("}")
    if s < 0 or e <= s:
        return None
    try:
        return json.loads(t[s:e + 1])
    except ValueError:
        return None


def ask_claude_raw(system, prompt, timeout=90):
    exe = find_claude()
    if not exe:
        return None
    cmd = [exe, "-p", "--model", "haiku", "--system-prompt", system, "--tools", "",
           "--strict-mcp-config", "--mcp-config", '{"mcpServers":{}}', "--no-session-persistence",
           "--setting-sources", "", prompt]
    try:
        os.makedirs(STATE_DIR, exist_ok=True)
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout, cwd=STATE_DIR, stdin=subprocess.DEVNULL)
    except Exception:
        return None
    return r.stdout[:20000] if r.returncode == 0 else None


def sanitize_pitched(recipe, pet):
    """Pitched recipes are tamed before validation: forced to this pet, slow cooldowns."""
    if not isinstance(recipe, dict):
        return recipe
    recipe["pet"] = pet
    recipe["format"] = "desktop-pet-skill/1"
    if isinstance(recipe.get("cooldown"), (int, float)):
        recipe["cooldown"] = max(30, min(1440, recipe["cooldown"]))
    if not isinstance(recipe.get("maxPerDay"), int) or recipe["maxPerDay"] > 4:
        recipe["maxPerDay"] = 4
    if isinstance(recipe.get("id"), str):
        sid = re.sub(r"[^a-z0-9-]", "-", recipe["id"].lower()).strip("-")[:28] or "trick"
        taken = {s["id"] for s in discover()[0]} | {p["id"] for p in discover()[1]}
        base, n = sid, 2
        while sid in taken:
            sid = "%s-%d" % (base[:28], n)
            n += 1
        recipe["id"] = sid
    return recipe


def pitch(ctx, persona, auto=False, ask=ask_claude_raw):
    """Ask Claude (in character) for one new skill. Never enables anything:
    a valid recipe goes into the pending queue for `desktop-pet skills review`."""
    cfg = load_config()
    if cfg.get("brain", True) is False:
        return {"ok": False, "reason": "the brain is off (desktop-pet brain on)"}
    if not find_claude():
        return {"ok": False, "reason": "the Claude Code CLI was not found"}
    allowed, why = pitch_allowed(auto)
    if not allowed:
        return {"ok": False, "reason": why}
    pet = ctx.get("pet") if ctx.get("pet") in PETS else "slime"
    existing = sorted({s["id"] for s in discover()[0]} | {p["id"] for p in discover()[1]})
    system, user = build_pitch_prompt(ctx, persona, existing)
    _record_pitch(auto)          # counts even if it fails: protects the user's usage
    errs = ["no reply"]
    for attempt in range(2):     # one repair round with the validator's errors
        raw = ask(system, user)
        obj = extract_json(raw)
        if not isinstance(obj, dict) or not isinstance(obj.get("recipe"), dict):
            errs = ["the reply was not a JSON object with a recipe"]
        else:
            recipe = sanitize_pitched(obj["recipe"], pet)
            errs = check_recipe(recipe)
            line = re.sub(r"\s+", " ", re.sub(r"[\x00-\x1f\x7f`$\\<>|;{}]", " ", str(obj.get("pitch", "")))).strip()[:120]
            if not errs:
                os.makedirs(PENDING_DIR, exist_ok=True)
                save_json(os.path.join(PENDING_DIR, recipe["id"] + ".json"),
                          {"pitch": line or "I learned a new trick! Can I keep it?", "pet": pet, "at": time.time(),
                           "recipe": recipe})
                return {"ok": True, "id": recipe["id"], "pitch": line, "name": recipe["name"]}
        user = ("Your previous answer was rejected: " + "; ".join(errs[:6]) +
                ". Output ONLY the corrected JSON object {\"pitch\": ..., \"recipe\": {...}}.")
    return {"ok": False, "reason": "the pitched recipe was invalid: " + "; ".join(errs[:4])}


# ------------------------------------------------------------------ PNG doodles (pure python)

FONT = {  # 5x7
    "A": ["01110", "10001", "10001", "11111", "10001", "10001", "10001"],
    "B": ["11110", "10001", "10001", "11110", "10001", "10001", "11110"],
    "C": ["01111", "10000", "10000", "10000", "10000", "10000", "01111"],
    "D": ["11110", "10001", "10001", "10001", "10001", "10001", "11110"],
    "E": ["11111", "10000", "10000", "11110", "10000", "10000", "11111"],
    "G": ["01111", "10000", "10000", "10011", "10001", "10001", "01111"],
    "H": ["10001", "10001", "10001", "11111", "10001", "10001", "10001"],
    "I": ["11111", "00100", "00100", "00100", "00100", "00100", "11111"],
    "L": ["10000", "10000", "10000", "10000", "10000", "10000", "11111"],
    "M": ["10001", "11011", "10101", "10101", "10001", "10001", "10001"],
    "N": ["10001", "11001", "10101", "10011", "10001", "10001", "10001"],
    "O": ["01110", "10001", "10001", "10001", "10001", "10001", "01110"],
    "R": ["11110", "10001", "10001", "11110", "10100", "10010", "10001"],
    "S": ["01111", "10000", "10000", "01110", "00001", "00001", "11110"],
    "T": ["11111", "00100", "00100", "00100", "00100", "00100", "00100"],
    "W": ["10001", "10001", "10001", "10101", "10101", "11011", "10001"],
    "!": ["00100", "00100", "00100", "00100", "00100", "00000", "00100"],
    " ": ["00000"] * 7,
}
GOBLIN_ART = ["......oooo......", ".....occcco.....", "....occcccco....", "oo.obbbbbbbbo.oo",
              "obbobbbbbbbbobbo", ".obbbyebbyebbbo.", "..obbbbBBbbbbo..", "..obbbmmmmbbbo..",
              "...obbbbbbbbo...", "..occcccccccco..", ".obccccccccccbo.", "..occcyyyyccco..",
              "...occcccccco...", "...obbo..obbo...", "...ooo....ooo..."]
SLIME_ART = ["......oooo......", "....oohhhboo....", "...ohhbbbbbbo...", "..ohbbbbbbbbbo..",
             "..obbbbbbbbbbo..", ".obbbbbbbbbbbbo.", ".obbwebbbbwebbo.", ".obbeebbbbeebbo.",
             ".obpbbbbbbbbpbo.", ".obbbbbmmbbbbbo.", ".oBbbbbbbbbbbBo.", "..oBBBBBBBBBBo..",
             "...oooooooooo..."]


def _hex(c, fb):
    m = re.fullmatch(r"#?([0-9a-fA-F]{6})", str(c or ""))
    h = m.group(1) if m else fb.lstrip("#")
    return bytes(int(h[i:i + 2], 16) for i in (0, 2, 4))


def _mix(a, b, t):
    return bytes(int(a[i] + (b[i] - a[i]) * t) for i in range(3))


class Canvas:
    def __init__(self, w, h, bg):
        self.w, self.h = w, h
        self.rows = [bytearray(bg * w) for _ in range(h)]

    def rect(self, x, y, w, h, c):
        x0, y0, x1, y1 = max(0, int(x)), max(0, int(y)), min(self.w, int(x + w)), min(self.h, int(y + h))
        if x1 <= x0 or y1 <= y0:
            return
        seg = c * (x1 - x0)
        for yy in range(y0, y1):
            self.rows[yy][x0 * 3:x1 * 3] = seg

    def png(self):
        raw = b"".join(b"\x00" + bytes(r) for r in self.rows)
        def chunk(t, d):
            return struct.pack(">I", len(d)) + t + d + struct.pack(">I", zlib.crc32(t + d) & 0xffffffff)
        return (b"\x89PNG\r\n\x1a\n" + chunk(b"IHDR", struct.pack(">IIBBBBB", self.w, self.h, 8, 2, 0, 0, 0))
                + chunk(b"IDAT", zlib.compress(raw, 6)) + chunk(b"IEND", b""))


def _text(cv, s, x, y, px, c, shadow=None):
    for i, ch in enumerate(s):
        g = FONT.get(ch, FONT[" "])
        for r, row in enumerate(g):
            for k, bit in enumerate(row):
                if bit == "1":
                    if shadow:
                        cv.rect(x + (i * 6 + k) * px + px // 2, y + r * px + px // 2, px, px, shadow)
                    cv.rect(x + (i * 6 + k) * px, y + r * px, px, px, c)


def _art(cv, rows, x, y, px, pal):
    for r, row in enumerate(rows):
        for k, ch in enumerate(row):
            if ch != "." and ch in pal:
                cv.rect(x + k * px, y + r * px, px, px, pal[ch])


def make_wall_doodle(name, w, h, colors):
    """A full-screen 'goblin was here' style pixel doodle in the theme's colors."""
    w, h = max(320, min(7680, int(w))), max(240, min(4320, int(h)))
    bg = _hex(colors.get("background"), "#1a1b26")
    fg = _hex(colors.get("foreground"), "#c0caf5")
    green = _hex(colors.get("green"), "#8cc570")
    yellow = _hex(colors.get("yellow"), "#e5c07b")
    accent = _hex(colors.get("accent"), "#7aa2f7")
    red = _hex(colors.get("red"), "#e05561")
    brown = _mix(_hex(colors.get("orange"), "#e8945a"), b"\x00\x00\x00", 0.45)
    cv = Canvas(w, h, bg)
    rnd = random.Random(w * 7 + h)
    px = max(2, w // 240)
    # paper-texture specks
    speck = _mix(bg, fg, 0.06)
    for _ in range(w * h // 9000):
        cv.rect(rnd.randrange(w) // px * px, rnd.randrange(h) // px * px, px, px, speck)
    slime = name.startswith("slime")
    words = "SLIME WAS HERE" if slime else "GOBLIN WAS HERE"
    tpx = max(3, int(w * 0.62 / (len(words) * 6)))
    tw = len(words) * 6 * tpx
    ty = int(h * 0.56)
    _text(cv, words, (w - tw) // 2, ty, tpx, green if not slime else accent, shadow=_mix(bg, b"\x00\x00\x00", 0.5))
    small = "HEH HEH HEH!" if not slime else "BLORP!"
    spx = max(2, tpx // 2)
    _text(cv, small, (w - len(small) * 6 * spx) // 2 + tw // 5, ty + 9 * tpx, spx, yellow)
    # the artist
    apx = max(3, int(h * 0.30 / 16))
    art = SLIME_ART if slime else GOBLIN_ART
    pal = {"o": _mix(green if not slime else accent, b"\x00\x00\x00", 0.7), "b": green if not slime else accent,
           "B": _mix(green if not slime else accent, b"\x00\x00\x00", 0.25), "h": _mix(accent, b"\xff\xff\xff", 0.3),
           "c": brown, "y": yellow, "e": b"\x10\x10\x18", "w": b"\xff\xff\xff",
           "m": _mix(green, b"\x00\x00\x00", 0.6), "p": _mix(red, b"\xff\xff\xff", 0.3)}
    ax = (w - 16 * apx) // 2
    ay = ty - 17 * apx
    _art(cv, art, ax, ay, apx, pal)
    # scribbles: random-walk crayon lines and stars around the edges
    for col in (accent, red, yellow, fg):
        x, y = rnd.randrange(w), rnd.randrange(h)
        for _ in range(140):
            dx, dy = rnd.choice(((1, 0), (-1, 0), (0, 1), (0, -1), (1, 1), (-1, 1)))
            for _ in range(rnd.randint(2, 6)):
                x = max(0, min(w - 1, x + dx * px))
                y = max(0, min(h - 1, y + dy * px))
                if abs(x - w / 2) > w * 0.36 or abs(y - h / 2) > h * 0.36:
                    cv.rect(x, y, px * 2, px * 2, col)
    for _ in range(22):
        sx, sy = rnd.randrange(w), rnd.randrange(h)
        if abs(sx - w / 2) < w * 0.34 and abs(sy - h / 2) < h * 0.34:
            continue
        s = px * rnd.randint(2, 4)
        cv.rect(sx - s, sy, s * 3, s, yellow)
        cv.rect(sx, sy - s, s, s * 3, yellow)
    # an arrow pointing at the artist
    for i in range(10):
        cv.rect(ax - (12 - i) * apx, ay + 6 * apx + i * apx // 3, apx, apx, red)
    cv.rect(ax - 3 * apx, ay + 8 * apx, apx, apx * 2, red)
    cv.rect(ax - 5 * apx, ay + 9 * apx, apx * 2, apx, red)
    return cv.png()


# ------------------------------------------------------------------ wallpaper heist (journaled)

def _omarchy():
    return shutil.which("omarchy")


def _bg_set(path):
    exe = _omarchy()
    if not exe:
        return False
    code, _ = run([exe, "theme", "bg", "set", path], timeout=15)
    return code == 0


def wall_journal():
    j = load_json(WALL_JOURNAL, {})
    return j if j.get("original") else {}


def _restore_locked():
    j = wall_journal()
    if not j:
        return False
    cur = os.path.realpath(BG_LINK) if os.path.lexists(BG_LINK) else ""
    doodle = os.path.realpath(j.get("doodle", "")) if j.get("doodle") else ""
    restored = False
    if (not cur or cur == doodle) and os.path.exists(j["original"]):
        restored = _bg_set(j["original"])
        raw = j.get("originalLink", "")
        # omarchy stores the resolved path; put the exact original link text back
        # (so `omarchy theme bg next` keeps its place) when it names the same file
        if restored and raw and os.path.realpath(raw if os.path.isabs(raw) else os.path.join(os.path.dirname(BG_LINK), raw)) == os.path.realpath(j["original"]):
            try:
                if os.readlink(BG_LINK) != raw:
                    tmp = BG_LINK + ".desktop-pet.tmp"
                    if os.path.lexists(tmp):
                        os.remove(tmp)
                    os.symlink(raw, tmp)
                    os.replace(tmp, BG_LINK)
            except OSError:
                pass
    # else: the user picked another wallpaper meanwhile; leave theirs alone
    try:
        os.remove(WALL_JOURNAL)
    except FileNotFoundError:
        pass
    if doodle and doodle.startswith(os.path.realpath(DOODLE_DIR) + os.sep):
        try:
            os.remove(doodle)
        except OSError:
            pass
    return restored


def wall_restore():
    with file_lock(WALL_LOCK):
        return _restore_locked()


def wall_swap(doodle, w, h, colors, seconds):
    """Swap the wallpaper for a doodle. The journal is written BEFORE the swap,
    so heal / off / a reload / a crash always puts the original back."""
    seconds = max(5, min(MAX_RUN_SECONDS, float(seconds)))
    with file_lock(WALL_LOCK):
        if wall_journal():
            _restore_locked()   # never stack swaps
        if not os.path.islink(BG_LINK) or not _omarchy():
            return {"ok": True, "applied": False, "reason": "no Omarchy wallpaper to swap"}
        original = os.path.realpath(BG_LINK)
        if not os.path.isfile(original):
            return {"ok": True, "applied": False, "reason": "current wallpaper not found"}
        if doodle in BUILTIN_DOODLES:
            os.makedirs(DOODLE_DIR, exist_ok=True)
            path = os.path.join(DOODLE_DIR, "%s-%d.png" % (doodle, int(time.time())))
            with open(path + ".tmp", "wb") as f:
                f.write(make_wall_doodle(doodle, w, h, colors))
            os.replace(path + ".tmp", path)
        else:
            if png_errors(doodle):
                return {"ok": False, "reason": "; ".join(png_errors(doodle))}
            path = os.path.join(USER_DIR, doodle)
        save_json(WALL_JOURNAL, {"original": original, "originalLink": os.readlink(BG_LINK), "doodle": path,
                                 "since": time.time(), "until": time.time() + seconds})
        if not _bg_set(path):
            _restore_locked()
            return {"ok": True, "applied": False, "reason": "omarchy theme bg set failed"}
    return {"ok": True, "applied": True, "seconds": seconds}


# ------------------------------------------------------------------ sounds (off by default)

def _synth(name):
    import math
    rate = 22050
    notes = {"blip": [(880, .07)], "pop": [(520, .04), (1040, .05)], "chime": [(1047, .12), (1319, .12), (1568, .2)],
             "coin": [(988, .07), (1319, .22)], "roar": [(110, .5)], "purr": [(70, .6)]}[name]
    out = bytearray()
    for f, d in notes:
        n = int(rate * d)
        for i in range(n):
            t = i / rate
            env = min(1, i / 200) * max(0, 1 - i / n)
            if name in ("roar", "purr"):
                v = (math.sin(2 * math.pi * f * t) + 0.5 * math.sin(2 * math.pi * f * 2.03 * t)) * (0.6 + 0.4 * math.sin(2 * math.pi * 23 * t))
            else:
                v = 1 if math.sin(2 * math.pi * f * t) > 0 else -1
            out += struct.pack("<h", int(v * env * 5000))
    hdr = b"RIFF" + struct.pack("<I", 36 + len(out)) + b"WAVEfmt " + struct.pack("<IHHIIHH", 16, 1, 1, rate, rate * 2, 2, 16)
    return hdr + b"data" + struct.pack("<I", len(out)) + bytes(out)


def play_sound(name):
    if load_config().get("skillSound") is not True:
        return {"ok": True, "played": False, "reason": "skill sounds are off"}
    if name not in ("blip", "chime", "coin", "roar", "pop", "purr"):
        return {"ok": False}
    path = os.path.join(SOUND_DIR, name + ".wav")
    if not os.path.exists(path):
        os.makedirs(SOUND_DIR, exist_ok=True)
        with open(path, "wb") as f:
            f.write(_synth(name))
    for player in ("pw-play", "paplay", "aplay"):
        exe = shutil.which(player)
        if exe:
            subprocess.Popen([exe, path] + (["-q"] if player == "aplay" else []), stdin=subprocess.DEVNULL,
                             stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL, start_new_session=True)
            return {"ok": True, "played": True}
    return {"ok": True, "played": False, "reason": "no audio player"}
