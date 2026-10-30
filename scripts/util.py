"""Small shared helpers for the desktop-pet scripts."""
import os
import shutil
import subprocess

HOME = os.path.expanduser("~")
CLAUDE_CANDIDATES = [  # fallbacks when `claude` is not on PATH
    os.path.join(HOME, ".local/bin/claude"),
    os.path.join(HOME, ".claude/local/claude"),
    os.path.join(HOME, ".local/share/mise/shims/claude"),
    os.path.join(HOME, ".local/share/mise/installs/claude/latest/claude"),
    os.path.join(HOME, ".npm-global/bin/claude"),
    os.path.join(HOME, ".local/share/npm/bin/claude"),
    os.path.join(HOME, ".bun/bin/claude"),
]


def run(cmd, timeout=3):
    """Run a command, return (returncode, stdout); never raises."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout
    except Exception:
        return 1, ""


def find_claude():
    p = shutil.which("claude")
    if p:
        return p
    for p in CLAUDE_CANDIDATES:
        if os.path.isfile(p) and os.access(p, os.X_OK):
            return p
    return None
