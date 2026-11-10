#!/usr/bin/env python3
"""Backend for the network manage panel (quickshell/network/NetworkManage.qml).

Usage:
  netmanage.py list                      -> JSON {"wifi": [...], "bt": [...]}
  netmanage.py wifi-up <uuid>
  netmanage.py wifi-down <uuid>
  netmanage.py wifi-forget <uuid>
  netmanage.py wifi-autoconnect <uuid> <yes|no>
  netmanage.py wifi-password <uuid>      -> prints the saved password
  netmanage.py wifi-set-password <uuid> <password>
  netmanage.py bt-connect <mac>
  netmanage.py bt-disconnect <mac>
  netmanage.py bt-trust <mac> <yes|no>
  netmanage.py bt-rename <mac> <name>
  netmanage.py bt-forget <mac>

Actions print nothing on success; on failure they print the tool's error and exit non-zero.
"""
import json
import re
import subprocess
import sys


def run(cmd, timeout=15):
    try:
        p = subprocess.run(cmd, capture_output=True, text=True, timeout=timeout)
        return p.returncode, p.stdout, p.stderr
    except (OSError, subprocess.TimeoutExpired) as e:
        return 1, "", str(e)


def split_terse(line):
    """Split one line of `nmcli -t` output on unescaped colons."""
    fields, cur, esc = [], [], False
    for ch in line:
        if esc:
            cur.append(ch)
            esc = False
        elif ch == "\\":
            esc = True
        elif ch == ":":
            fields.append("".join(cur))
            cur = []
        else:
            cur.append(ch)
    fields.append("".join(cur))
    return fields


def list_wifi():
    _, out, _ = run(["nmcli", "-t", "-f", "SSID,SIGNAL,SECURITY,IN-USE", "dev", "wifi", "list", "--rescan", "no"])
    in_range = {}
    for line in out.splitlines():
        f = split_terse(line)
        if len(f) < 4 or not f[0]:
            continue
        sig = int(f[1]) if f[1].isdigit() else 0
        if f[0] not in in_range or sig > in_range[f[0]]["signal"]:
            in_range[f[0]] = {"signal": sig, "security": f[2] or "Open"}

    _, out, _ = run(["nmcli", "-t", "-f", "NAME,UUID,TYPE,AUTOCONNECT,ACTIVE,TIMESTAMP", "connection", "show"])
    saved = []
    for line in out.splitlines():
        f = split_terse(line)
        if len(f) < 6 or f[2] != "802-11-wireless":
            continue
        name = f[0]
        seen = in_range.get(name)
        saved.append({
            "name": name,
            "uuid": f[1],
            "autoconnect": f[3] == "yes",
            "active": f[4] == "yes",
            "lastUsed": int(f[5]) if f[5].isdigit() else 0,
            "inRange": seen is not None,
            "signal": seen["signal"] if seen else 0,
            "security": seen["security"] if seen else "",
        })
    # Active first, then in range (strongest first), then most recently used.
    saved.sort(key=lambda w: (not w["active"], not w["inRange"], -w["signal"], -w["lastUsed"], w["name"].lower()))
    return saved


def list_bt():
    _, out, _ = run(["bluetoothctl", "devices", "Paired"])
    devices = []
    for line in out.splitlines():
        m = re.match(r"Device ([0-9A-F:]{17}) (.*)", line.strip())
        if not m:
            continue
        mac = m.group(1)
        _, info, _ = run(["bluetoothctl", "info", mac], timeout=5)

        def field(key):
            fm = re.search(r"^\s*" + key + r": (.*)$", info, re.M)
            return fm.group(1).strip() if fm else ""

        battery = re.search(r"Battery Percentage: \S+ \((\d+)\)", info)
        devices.append({
            "mac": mac,
            "name": field("Alias") or field("Name") or m.group(2),
            "icon": field("Icon"),
            "connected": field("Connected") == "yes",
            "trusted": field("Trusted") == "yes",
            "battery": int(battery.group(1)) if battery else -1,
        })
    devices.sort(key=lambda d: (not d["connected"], d["name"].lower()))
    return devices


def bt_path(mac):
    _, out, _ = run(["busctl", "tree", "--list", "org.bluez"], timeout=5)
    suffix = "/dev_" + mac.replace(":", "_")
    for line in out.splitlines():
        if line.strip().endswith(suffix):
            return line.strip()
    return ""


def act(cmd, timeout=30):
    code, out, err = run(cmd, timeout)
    if code != 0:
        print((err or out).strip() or "failed")
        sys.exit(1)


def main():
    a = sys.argv[1:]
    if not a:
        print(__doc__)
        sys.exit(2)
    op = a[0]
    if op == "list":
        print(json.dumps({"wifi": list_wifi(), "bt": list_bt()}))
    elif op == "wifi-up":
        act(["nmcli", "connection", "up", "uuid", a[1]], timeout=45)
    elif op == "wifi-down":
        act(["nmcli", "connection", "down", "uuid", a[1]])
    elif op == "wifi-forget":
        act(["nmcli", "connection", "delete", "uuid", a[1]])
    elif op == "wifi-autoconnect":
        act(["nmcli", "connection", "modify", "uuid", a[1], "connection.autoconnect", a[2]])
    elif op == "wifi-password":
        code, out, err = run(["nmcli", "-s", "-g", "802-11-wireless-security.psk", "connection", "show", "uuid", a[1]])
        if code != 0:
            print(err.strip() or "failed")
            sys.exit(1)
        print(out.strip())
    elif op == "wifi-set-password":
        # psk-flags 0 = NetworkManager stores the password itself. Connections made under KDE are often
        # agent-owned (flags 1), which needs plasma-nm's agent and silently fails under niri.
        act(["nmcli", "connection", "modify", "uuid", a[1],
             "802-11-wireless-security.psk-flags", "0", "802-11-wireless-security.psk", a[2]])
    elif op == "bt-connect":
        act(["bluetoothctl", "connect", a[1]], timeout=30)
    elif op == "bt-disconnect":
        act(["bluetoothctl", "disconnect", a[1]])
    elif op == "bt-trust":
        act(["bluetoothctl", "trust" if a[2] == "yes" else "untrust", a[1]])
    elif op == "bt-rename":
        path = bt_path(a[1])
        if not path:
            print("device not found")
            sys.exit(1)
        act(["busctl", "set-property", "org.bluez", path, "org.bluez.Device1", "Alias", "s", a[2]])
    elif op == "bt-forget":
        act(["bluetoothctl", "remove", a[1]])
    else:
        print("unknown op: " + op)
        sys.exit(2)


if __name__ == "__main__":
    main()
