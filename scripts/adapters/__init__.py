"""Compositor adapters.

Core code never talks to a compositor directly; it calls `detect()` and uses the
returned module, which must provide:

    NAME                    str, e.g. "hyprland"
    available() -> bool     the compositor is running and reachable
    monitors() -> [Monitor] all outputs (see below), [] on failure
    focused_monitor() -> Monitor | None
    list_windows() -> [Window] | None    None on failure
    active_window() -> {"app": str, "title": str} | None
    cursor_pos() -> (x, y) | None          global logical px

Monitor: {"name", "x", "y", "w", "h", "scale", "focused", "workspace", "overlay_open"}
    x/y/w/h are logical (layout) pixels, workspace is the visible workspace id,
    overlay_open is True when something like a scratchpad covers the workspace.
Window: {"id", "app", "title", "pid", "x", "y", "w", "h", "workspace",
         "floating", "fullscreen", "focus_rank"}
    x/y/w/h are logical, global layout pixels; focus_rank 0 = most recently focused.

To add a compositor, copy template.py to <name>.py, implement it, and add a
detection rule to detect() below.
"""
import os

from . import hyprland


def detect():
    """Return the adapter module for the running compositor, or None."""
    if os.environ.get("HYPRLAND_INSTANCE_SIGNATURE") and hyprland.available():
        return hyprland
    # Future adapters (see template.py):
    #   SWAYSOCK            -> sway
    #   NIRI_SOCKET         -> niri
    #   KDE_FULL_SESSION    -> kde (KWin scripting)
    return None


def unsupported_message():
    desk = os.environ.get("XDG_CURRENT_DESKTOP") or "this desktop"
    return "desktop-pet supports Hyprland only for now (detected: %s)" % desk
