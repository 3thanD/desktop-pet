"""kitty terminal adapter: kitty's local remote control (socket-only, in the
user's private runtime dir). See terminals/__init__.py for the interface."""
import json
import os
import shutil

from util import run

NAME = "kitty"
RUNTIME = os.environ.get("XDG_RUNTIME_DIR") or "/run/user/%d" % os.getuid()
HOME = os.path.expanduser("~")
# Omarchy launches btop as its own kitty process with this class.
BTOP_APPS = ("org.omarchy.btop",)


def matches(window):
    return bool(shutil.which("kitty")) and (window["app"] == "kitty" or window["app"] in BTOP_APPS)


def priority(window):
    return 0 if (window["app"] in BTOP_APPS or "btop" in window["title"].lower()) else 1


def socket_for(pid):
    """Omarchy's kitty.conf listens on omarchy-kitty-<pid>; `desktop-pet setup`
    adds kitty-<pid> when nothing else is configured."""
    for name in ("omarchy-kitty-%d" % pid, "kitty-%d" % pid):
        p = os.path.join(RUNTIME, name)
        if os.path.exists(p):
            return p
    try:
        for name in os.listdir(RUNTIME):
            if "kitty" in name and name.endswith("-%d" % pid):
                return os.path.join(RUNTIME, name)
    except OSError:
        pass
    return None


def _kitty(sock, *args):
    return run(["kitty", "@", "--to", "unix:" + sock, *args], timeout=4)


def _active_window(sock):
    """(window_id, cols, rows, tab_count) of the active window, or None (splits)."""
    code, txt = _kitty(sock, "ls")
    if code != 0:
        return None
    try:
        data = json.loads(txt)
    except Exception:
        return None
    if not data:
        return None
    osw = next((o for o in data if o.get("is_focused")), data[0])
    tabs = osw.get("tabs") or []
    if not tabs:
        return None
    tab = next((t for t in tabs if t.get("is_active")), tabs[0])
    wins = tab.get("windows", [])
    if len(wins) != 1:
        return None
    w = wins[0]
    return w["id"], int(w["columns"]), int(w["lines"]), len(tabs)


def settings():
    """font_family, font_size (pt) and window_padding_width (pt) from kitty's
    config chain (system defaults, then the user's file and its includes)."""
    found = {"font_family": "monospace", "font_size": 11.0, "window_padding_width": 0.0}
    seen = set()

    def parse(path, depth=0):
        path = os.path.expanduser(os.path.expandvars(path))
        if depth > 4 or path in seen or not os.path.isfile(path):
            return
        seen.add(path)
        try:
            lines = open(path, errors="replace").read().splitlines()
        except OSError:
            return
        for line in lines:
            line = line.strip()
            if not line or line.startswith("#"):
                continue
            key, _, val = line.partition(" ")
            val = val.strip()
            if key == "include":
                inc = val if os.path.isabs(os.path.expanduser(val)) else os.path.join(os.path.dirname(path), val)
                parse(inc, depth + 1)
            elif key == "font_family" and val:
                found["font_family"] = val
            elif key in ("font_size", "window_padding_width"):
                try:
                    found[key] = float(val.split()[0])
                except (ValueError, IndexError):
                    pass

    parse("/etc/xdg/kitty/kitty.conf")
    parse(os.path.join(os.environ.get("XDG_CONFIG_HOME") or os.path.join(HOME, ".config"), "kitty/kitty.conf"))
    return found


def grid_geometry(width, height, cols, rows, tabs, scale, pad_pt):
    """Cell size and grid origin in logical px. kitty lays the grid out in
    physical pixels with whole-pixel cells and (placement_strategy center, the
    default) splits the leftover space evenly around it."""
    pw, ph = round(width * scale), round(height * scale)
    pad = round(pad_pt * 96 / 72 * scale)
    cw = max(1, (pw - 2 * pad) // cols)
    ch = max(1, (ph - 2 * pad) // (rows + (1 if tabs > 1 else 0)))
    tabbar = ch if tabs > 1 else 0
    ox = (pw - cols * cw) // 2
    oy = (ph - tabbar - rows * ch) // 2
    return cw / scale, ch / scale, ox / scale, oy / scale


def grid_info(window, scale):
    sock = socket_for(window["pid"])
    if not sock:
        return "no-remote-control"
    aw = _active_window(sock)
    if not aw:
        return "unsupported-layout"
    wid, cols, rows, tabs = aw
    ks = settings()
    cw, ch, ox, oy = grid_geometry(window["w"], window["h"], cols, rows, tabs, scale, ks["window_padding_width"])
    return {"cols": cols, "rows": rows, "cw": cw, "ch": ch, "ox": ox, "oy": oy,
            "font": ks["font_family"], "fontPx": round(ks["font_size"] * 96 / 72, 2),
            "handle": {"sock": sock, "wid": wid}}


def read_cells(window, info):
    h = info["handle"]
    code, text = _kitty(h["sock"], "get-text", "--match", "id:%d" % h["wid"])
    if code != 0:
        return None
    return text.split("\n")
