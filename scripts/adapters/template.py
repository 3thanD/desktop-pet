"""Template for a new compositor adapter (sway, niri, KDE, ...).

Copy to adapters/<name>.py, implement every function, then add a detection
rule in adapters/__init__.py:detect(). Return shapes are documented there.
Hints:
  sway:  `swaymsg -t get_outputs` / `get_tree` (rect, focused, pid, app_id)
  niri:  `niri msg --json outputs` / `windows` / `focused-output`
  KDE:   KWin scripting over D-Bus (no per-window geometry from the CLI)
Coordinates must be logical pixels in the compositor's global layout space.
"""

NAME = "template"


def available():
    return False


def monitors():
    return []


def focused_monitor():
    return None


def list_windows():
    return None


def active_window():
    return None


def cursor_pos():
    return None
