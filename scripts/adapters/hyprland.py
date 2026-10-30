"""Hyprland compositor adapter (hyprctl JSON). See adapters/__init__.py for the interface."""
import json

from util import run

NAME = "hyprland"


def _hypr(what):
    code, txt = run(["hyprctl", "-j", what])
    if code != 0:
        return None
    try:
        return json.loads(txt)
    except Exception:
        return None


def available():
    return _hypr("version") is not None


def _monitor(m):
    scale = float(m.get("scale") or 1) or 1.0
    w, h = m.get("width") or 0, m.get("height") or 0
    if int(m.get("transform", 0)) % 2 == 1:
        w, h = h, w
    return {
        "name": m.get("name", ""), "x": m.get("x", 0), "y": m.get("y", 0),
        "w": round(w / scale), "h": round(h / scale), "scale": scale,
        "focused": bool(m.get("focused")),
        "workspace": (m.get("activeWorkspace") or {}).get("id"),
        "overlay_open": (m.get("specialWorkspace") or {}).get("id", 0) != 0,
    }


def monitors():
    return [_monitor(m) for m in (_hypr("monitors") or [])]


def focused_monitor():
    mons = monitors()
    return next((m for m in mons if m["focused"]), mons[0] if mons else None)


def list_windows():
    clients = _hypr("clients")
    if clients is None:
        return None
    wins = []
    for c in clients:
        if not c.get("mapped") or c.get("hidden"):
            continue
        wins.append({
            "id": c.get("address", ""), "app": c.get("class") or "", "title": c.get("title") or "",
            "pid": int(c.get("pid") or 0),
            "x": c["at"][0], "y": c["at"][1], "w": c["size"][0], "h": c["size"][1],
            "workspace": (c.get("workspace") or {}).get("id"),
            "floating": bool(c.get("floating")), "fullscreen": bool(c.get("fullscreen")),
            "focus_rank": c.get("focusHistoryID", 99),
        })
    return wins


def active_window():
    aw = _hypr("activewindow") or {}
    if not aw:
        return None
    return {"app": aw.get("class") or "", "title": aw.get("title") or ""}


def cursor_pos():
    """Pointer position in global logical px, or None."""
    code, txt = run(["hyprctl", "-j", "cursorpos"])
    try:
        d = json.loads(txt) if code == 0 else None
        return (d["x"], d["y"]) if d else None
    except Exception:
        return None
