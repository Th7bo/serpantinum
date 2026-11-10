#!/usr/bin/env python3
# Focus the niri window belonging to an app (used when a notification is clicked).
# Usage: niri_focus_app.py <desktop-entry> <app-name>
import json
import subprocess
import sys


def norm(s):
    return (s or "").lower().removesuffix(".desktop")


def main():
    desktop = norm(sys.argv[1] if len(sys.argv) > 1 else "")
    app = norm(sys.argv[2] if len(sys.argv) > 2 else "")
    keys = {k for k in (desktop, app, desktop.rsplit(".", 1)[-1]) if k}
    if not keys:
        return

    try:
        out = subprocess.run(["niri", "msg", "-j", "windows"], capture_output=True, text=True, timeout=2).stdout
        windows = json.loads(out)
    except (OSError, ValueError, subprocess.TimeoutExpired):
        return

    def rank(w):
        aid = norm(w.get("app_id"))
        if not aid:
            return 0
        if aid in keys:
            return 3
        if aid.rsplit(".", 1)[-1] in keys:
            return 2
        if any(k in aid or aid in k for k in keys if len(k) > 2):
            return 1
        return 0

    best = max(windows, key=rank, default=None)
    if best and rank(best) > 0 and not best.get("is_focused"):
        subprocess.run(["niri", "msg", "action", "focus-window", "--id", str(best["id"])], timeout=2)


if __name__ == "__main__":
    main()
