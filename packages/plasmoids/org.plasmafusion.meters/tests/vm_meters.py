#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""The system meters in a real Plasma session (test tool; run inside the session as its user).

  vm_meters.py add                 put org.plasmafusion.meters in the top bar, before quick settings
  vm_meters.py remove              take every meters widget out of the panels
  vm_meters.py set KEY VALUE...    write [General] keys of the meters widget (e.g. showNetwork true)
  vm_meters.py dump TAG            the widget's dump (sampling, sensors, texts, accessible names)
  vm_meters.py action ACTION       write debugAction (open, close, dump:TAG)
  vm_meters.py bar                 the top bar's widgets in order
  vm_meters.py cpu SECONDS         plasmashell's CPU time over SECONDS, in percent of one core
  vm_meters.py busy SECONDS [N]    N busy loops (default 2) for SECONDS, in the background
  vm_meters.py scheme dark|light|contrast   a Plasma Fusion colour scheme and Plasma style

The widget logs its dump to the user journal ("meters: dump TAG {...}"); `dump` prints the JSON.
"""

import json
import os
from pathlib import Path
import subprocess
import sys
import time

ID = "org.plasmafusion.meters"


def run(*args, timeout=30, check=True):
    r = subprocess.run(args, text=True, capture_output=True, timeout=timeout)
    if check and r.returncode != 0:
        raise RuntimeError(f"{args!r} rc={r.returncode}: {r.stdout.strip()} {r.stderr.strip()}")
    return (r.stdout + r.stderr).strip()


def shell_pid():
    return run("pgrep", "-u", str(os.getuid()), "-x", "plasmashell").splitlines()[0]


def session_env():
    for entry in Path(f"/proc/{shell_pid()}/environ").read_bytes().split(b"\0"):
        key, sep, value = entry.partition(b"=")
        if sep and key.decode() in {"DBUS_SESSION_BUS_ADDRESS", "XDG_RUNTIME_DIR", "WAYLAND_DISPLAY"}:
            os.environ[key.decode()] = value.decode()


def js(script):
    return run("qdbus-qt6", "org.kde.plasmashell", "/PlasmaShell", "org.kde.PlasmaShell.evaluateScript", script)


def cursor():
    return run("journalctl", "--user", "-n", "0", "--show-cursor", "--no-pager").split("-- cursor: ", 1)[1].strip()


def journal_after(c):
    return run("journalctl", "--user", "--after-cursor", c, "-o", "cat", "--no-pager", timeout=60)


def write_keys(pairs):
    body = "".join(f"w.writeConfig({json.dumps(k)}, {v});\n" for k, v in pairs)
    return js(f'''var n = 0;
panels().forEach(function (p) {{ p.widgets("{ID}").forEach(function (w) {{
    w.currentConfigGroup = ["General"];
{body}    ++n; }}); }});
print(n);''')


def action(value):
    return write_keys([("debugAction", json.dumps(value))])


def dump(tag):
    c = cursor()
    action("dump:" + tag)
    for _ in range(50):
        time.sleep(0.1)
        for line in journal_after(c).splitlines():
            if line.startswith("meters: dump " + tag + " "):
                return json.loads(line.split(" ", 3)[3])
    raise RuntimeError("no dump " + tag)


def bar():
    return js('''var r = [];
panels().forEach(function (p) { if (p.location === "top") {
    r.push(p.widgets().sort(function (a, b) { return a.index - b.index; }).map(function (w) {
        return w.type.replace(/^org\\.(kde\\.plasma|plasmafusion)\\./, ""); }).join(" | ")); } });
print(r.join("\\n"));''')


def add():
    return js(f'''var added = 0;
panels().forEach(function (p) {{
    var qs = p.widgets("org.plasmafusion.quicksettings");
    if (p.screen < 0 || qs.length === 0 || p.widgets("{ID}").length > 0) return;
    var g = qs[0].geometry;
    var w = p.addWidget("{ID}", Math.max(0, g.x - 2), 1, -1, -1);
    if (w) ++added;
}});
print(added);''')


def place():
    return js(f'''var placed = 0;
panels().forEach(function (p) {{
    var qs = p.widgets("org.plasmafusion.quicksettings"), ms = p.widgets("{ID}");
    if (qs.length === 0 || ms.length === 0) return;
    var at = ms[0].index < qs[0].index ? qs[0].index - 1 : qs[0].index;
    if (ms[0].index !== at) ms[0].index = at;
    ++placed;
}});
print(placed);''')


def remove():
    return js(f'''var n = 0;
panels().forEach(function (p) {{ p.widgets("{ID}").forEach(function (w) {{ w.remove(); ++n; }}); }});
print(n);''')


def cpu(seconds):
    """plasmashell's user + system time over `seconds`, in percent of one core."""
    pid = shell_pid()
    tick = os.sysconf("SC_CLK_TCK")

    def ticks():
        fields = Path(f"/proc/{pid}/stat").read_text().rsplit(")", 1)[1].split()
        return int(fields[11]) + int(fields[12])

    t0, c0 = time.monotonic(), ticks()
    time.sleep(seconds)
    t1, c1 = time.monotonic(), ticks()
    return round((c1 - c0) / tick / (t1 - t0) * 100, 3)


def busy(seconds, n):
    code = f"import time\nend = time.monotonic() + {seconds}\nwhile time.monotonic() < end:\n    pass\n"
    for _ in range(n):
        subprocess.Popen([sys.executable, "-c", code], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL,
                         start_new_session=True)


def scheme(which):
    name = {"dark": "PlasmaFusionDark", "light": "PlasmaFusionLight", "contrast": "PlasmaFusionHighContrast"}[which]
    style = "plasma-fusion-light" if which == "light" else "plasma-fusion-dark"
    out = run("plasma-apply-colorscheme", name, check=False)
    out += "\n" + run("plasma-apply-desktoptheme", style, check=False)
    return out


def main(argv):
    session_env()
    cmd = argv[1] if len(argv) > 1 else ""
    if cmd == "add":
        print("added", add())
        time.sleep(1.5)
        print("placed", place())
        time.sleep(1.0)
        print(bar())
    elif cmd == "remove":
        print("removed", remove())
    elif cmd == "set":
        pairs = list(zip(argv[2::2], argv[3::2]))
        print("widgets", write_keys([(k, v if v in ("true", "false") or v.isdigit() else json.dumps(v)) for k, v in pairs]))
    elif cmd == "dump":
        print(json.dumps(dump(argv[2]), indent=1))
    elif cmd == "action":
        print("widgets", action(argv[2]))
    elif cmd == "bar":
        print(bar())
    elif cmd == "cpu":
        print(cpu(float(argv[2])))
    elif cmd == "busy":
        busy(float(argv[2]), int(argv[3]) if len(argv) > 3 else 2)
    elif cmd == "scheme":
        print(scheme(argv[2]))
    else:
        print(__doc__.strip())
        return 2
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
