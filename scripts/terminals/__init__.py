"""Terminal adapters.

A terminal adapter lets the pet see what is on a terminal's screen. Each module
provides:

    NAME
    matches(window) -> bool              is this compositor window one of ours?
    priority(window) -> int              lower = preferred target (e.g. btop first)
    grid_info(window, scale) -> dict | str
        {"cols", "rows", "cw", "ch", "ox", "oy", "font", "fontPx", "handle"} with
        cell size / grid origin in logical px relative to the window, or an
        error string: "no-remote-control" | "unsupported-layout"
    read_cells(window, info) -> [str] | None   screen lines (one per row)

ADAPTERS is tried in order; add new modules here.
"""
from . import kitty

ADAPTERS = [kitty]

# Window classes of terminals we can't read yet (used for a friendly hint).
KNOWN_UNSUPPORTED = ("alacritty", "com.mitchellh.ghostty", "foot", "footclient", "org.wezfurlong.wezterm",
                     "wezterm", "konsole", "org.gnome.ptyxis", "xterm", "st-256color")


def adapter_for(window):
    for a in ADAPTERS:
        if a.matches(window):
            return a
    return None
