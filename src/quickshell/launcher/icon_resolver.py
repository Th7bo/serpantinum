#!/usr/bin/env python3
# Maps desktop-entry icon names to real files, so the launcher can load icons
# by path instead of through the image://icon provider (renders blank here).
import configparser
import json
import os
import re
import sys

home = os.path.expanduser("~")
data_dirs = [os.path.join(home, ".local/share")] + \
    os.environ.get("XDG_DATA_DIRS", "/usr/local/share:/usr/share").split(":")
icon_bases = [os.path.join(home, ".icons")] + [os.path.join(d, "icons") for d in data_dirs]
EXTS = (".svg", ".png", ".xpm")


def current_theme():
    cfg = os.path.join(home, ".config/qt6ct/qt6ct.conf")
    try:
        with open(cfg) as f:
            for line in f:
                if line.startswith("icon_theme="):
                    return line.split("=", 1)[1].strip()
    except OSError:
        pass
    return "hicolor"


def theme_chain(name, chain):
    if not name or name in chain:
        return
    chain.append(name)
    for base in icon_bases:
        idx = os.path.join(base, name, "index.theme")
        if os.path.isfile(idx):
            cp = configparser.ConfigParser(interpolation=None, strict=False)
            try:
                cp.read(idx)
            except configparser.Error:
                return
            for parent in cp.get("Icon Theme", "Inherits", fallback="").split(","):
                theme_chain(parent.strip(), chain)
            return


def wanted_icons():
    names = set()
    for d in data_dirs:
        apps = os.path.join(d, "applications")
        for root, _, files in os.walk(apps):
            for fn in files:
                if not fn.endswith(".desktop"):
                    continue
                try:
                    with open(os.path.join(root, fn), errors="ignore") as f:
                        for line in f:
                            if line.startswith("Icon="):
                                ic = line[5:].strip()
                                if ic and not ic.startswith("/"):
                                    names.add(ic)
                                break
                except OSError:
                    pass
    return names


def score(path):
    if path.endswith(".svg"):
        return 10000
    m = re.search(r"/(\d+)x\d+(?:@\d+)?/", path)
    return int(m.group(1)) if m else 1


def main():
    out = sys.argv[1]
    names = wanted_icons()
    chain = []
    theme_chain(current_theme(), chain)
    if "hicolor" not in chain:
        chain.append("hicolor")

    result = {}
    for theme in chain:
        found = {}
        for base in icon_bases:
            tdir = os.path.join(base, theme)
            for root, _, files in os.walk(tdir, followlinks=True):
                for fn in files:
                    stem, ext = os.path.splitext(fn)
                    if ext in EXTS and stem in names and stem not in result:
                        p = os.path.join(root, fn)
                        if stem not in found or score(p) > score(found[stem]):
                            found[stem] = p
        result.update(found)

    for name in names - result.keys():
        for d in data_dirs:
            for ext in EXTS:
                p = os.path.join(d, "pixmaps", name + ext)
                if os.path.isfile(p):
                    result[name] = p
                    break
            if name in result:
                break

    os.makedirs(os.path.dirname(out), exist_ok=True)
    tmp = out + ".tmp"
    with open(tmp, "w") as f:
        json.dump(result, f)
    os.replace(tmp, out)


if __name__ == "__main__":
    main()
