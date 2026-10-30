"""Small shared helpers for the desktop-pet scripts."""
import subprocess


def run(cmd, timeout=3):
    """Run a command, return (returncode, stdout); never raises."""
    try:
        r = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout
    except Exception:
        return 1, ""
