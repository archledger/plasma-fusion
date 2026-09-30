#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Offscreen load test of the shared QML blocks (BASE-1 acceptance): stages Probe.qml with the
# blocks it uses (tools/build-lib/shared-qml.sh), then runs it with Qt's offscreen platform on a
# private D-Bus bus (no KWin: FusionTablet must fall back to Kirigami) at the display scales
# 1, 1.25, 4/3, 1.325 and 1.5, at animation factors 1 and 0 (and 0.5 and 2 at scale 1), in the
# dark and light Plasma Fusion schemes and with a user accent, and checks the values it prints.
#
#   packages/common/tests/offscreen.sh OUTDIR
#
# Needs qml (Qt 6), Kirigami with qqc2-desktop-style, plasma-workspace's QML modules, Pillow.
# Writes only below OUTDIR (screenshots OUTDIR/*-tiles.png, *-backdrop.png; logs OUTDIR/*.log).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
OUT=$(mkdir -p "${1:?usage: offscreen.sh OUTDIR}" && cd "$1" && pwd)
QML=${QML:-/usr/lib64/qt6/bin/qml}
rm -rf "$OUT/ui" "$OUT/cfg" "$OUT/wall" "$OUT/cache"
mkdir -p "$OUT/ui" "$OUT/cfg" "$OUT/wall" "$OUT/cache"

bash "$ROOT/tools/build-lib/shared-qml.sh" install "$HERE" "$OUT/ui"
install -m 0644 "$HERE/Probe.qml" "$OUT/ui/Probe.qml"

# A wallpaper package: light images in three sizes, dark images in two.
python3 - "$OUT/wall" <<'PY'
import os, sys
from PIL import Image, ImageDraw
base = sys.argv[1]
def make(sub, w, h, top, bottom):
    d = os.path.join(base, "contents", sub)
    os.makedirs(d, exist_ok=True)
    im = Image.new("RGB", (w // 8, h // 8))
    dr = ImageDraw.Draw(im)
    for y in range(im.height):
        t = y / max(1, im.height - 1)
        dr.line([(0, y), (im.width, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    dr.ellipse([im.width * 0.6, im.height * 0.25, im.width * 0.8, im.height * 0.55], fill=(242, 166, 90))
    im.resize((w, h)).save(os.path.join(d, f"{w}x{h}.png"))
make("images", 1280, 800, (200, 210, 235), (120, 140, 200))
make("images", 1920, 1200, (220, 225, 240), (90, 120, 200))
make("images", 3840, 1600, (230, 200, 200), (150, 90, 90))
make("images_dark", 1920, 1200, (20, 26, 46), (59, 86, 160))
make("images_dark", 1080, 1920, (60, 20, 20), (20, 20, 20))
open(os.path.join(base, "metadata.json"), "w").write('{"KPlugin": {"Id": "ProbeWallpaper", "Name": "Probe"}}\n')
PY

# kdeglobals per case: a Plasma Fusion scheme (optionally with an accent written the way Plasma
# applies one: DecorationFocus and DecorationHover of every group), a factor, Breeze icons.
config() {  # NAME SCHEME FACTOR [ACCENT_RGB]
  local d=$OUT/cfg/$1
  mkdir -p "$d"
  python3 - "$ROOT/packages/color-schemes/$2.colors" "$d/kdeglobals" "$3" "${4:-}" <<'PY'
import sys
src, dst, factor, accent = sys.argv[1:5]
out = []
for line in open(src, encoding="utf-8"):
    if accent and line.startswith(("DecorationFocus=", "DecorationHover=")):
        line = line.split("=")[0] + "=" + accent + "\n"
    out.append(line)
out.append("\n[KDE]\nAnimationDurationFactor=%s\n\n[Icons]\nTheme=breeze\n" % factor)
open(dst, "w", encoding="utf-8").write("".join(out))
PY
}

run() {  # LABEL SCALE CONFIG [ENV=VALUE...]
  local label=$1 scale=$2 cfg=$3; shift 3
  env -u DISPLAY -u WAYLAND_DISPLAY -u DBUS_SESSION_BUS_ADDRESS -u KDE_KIRIGAMI_TABLET_MODE \
    dbus-run-session -- env QT_QPA_PLATFORM=offscreen QT_SCALE_FACTOR="$scale" QT_FORCE_STDERR_LOGGING=1 \
    QT_QUICK_CONTROLS_STYLE=org.kde.desktop QML_DISABLE_DISK_CACHE=1 \
    XDG_CONFIG_HOME="$OUT/cfg/$cfg" XDG_CACHE_HOME="$OUT/cache" "$@" \
    timeout 60 "$QML" "$OUT/ui/Probe.qml" -- "file://$OUT/wall" "$OUT" "$label" >"$OUT/$label.log" 2>&1 || true
}

config dark1 PlasmaFusionDark 1
config dark0 PlasmaFusionDark 0
config dark05 PlasmaFusionDark 0.5
config dark2 PlasmaFusionDark 2
config light1 PlasmaFusionLight 1
config teal1 PlasmaFusionDark 1 60,196,176
config amberlight1 PlasmaFusionLight 1 242,166,90

for s in 1 1.25 1.3333333 1.325 1.5; do
  run "s$s-f1" "$s" dark1
  run "s$s-f0" "$s" dark0
done
run s1-f05 1 dark05
run s1-f2 1 dark2
run s1-light 1 light1
run s1-teal 1 teal1
run s1-amberlight 1 amberlight1
run s1.3333333-tabletenv 1.3333333 dark1 KDE_KIRIGAMI_TABLET_MODE=1

python3 - "$OUT" <<'PY'
import json, pathlib, re, sys
out = pathlib.Path(sys.argv[1])
TOK1 = dict(press=0, pressScale=80, hover=100, toggle=150, popupIn=200, popupOut=150, surface=250, pulse=500,
            max=400, lockPrompt=300, loops3=3, loops9=3)
TOK0 = {k: 0 for k in TOK1}
TOK05 = dict(press=0, pressScale=40, hover=50, toggle=75, popupIn=100, popupOut=75, surface=125, pulse=250,
             max=200, lockPrompt=150, loops3=3, loops9=3)
TOK2 = dict(press=0, pressScale=160, hover=200, toggle=300, popupIn=400, popupOut=300, surface=500, pulse=1000,
            max=800, lockPrompt=600, loops3=3, loops9=3)
# Names the Fusion icon theme draws as tiles (generators/icons/names.py; "google-chrome-canary"
# through the dash fallback) and names it never will (a made-up app, an icon file).
TILES = {"firefox": False, "org.kde.kcalc": False, "org.example.NoSuchApp": True, "google-chrome-canary": False,
         "org.kde.konsole": False, "vlc": False, "/opt/example/icon.png": True, "": False}
BLOCK = re.compile(r"/ui/(Motion|FusionTablet|FusionAccent|FusionIconTile|FusionBackdrop|FusionMetrics|Probe)\.qml:\d+")
fails = []
rows = []

def expect(label, what, got, want):
    if got != want:
        fails.append(f"{label}: {what} is {got!r}, expected {want!r}")

for log in sorted(out.glob("s*.log")):
    label = log.stem
    text = log.read_text(errors="replace")
    for line in text.splitlines():
        if BLOCK.search(line):
            fails.append(f"{label}: QML message from a block: {line.strip()}")
    m = re.search(r"PROBE (\{.*\})", text)
    if not m:
        fails.append(f"{label}: no PROBE line (see {log.name})")
        continue
    p = json.loads(m.group(1))
    scale = float(label.split("-")[0][1:])
    expect(label, "dpr", round(p["dpr"], 4), round(scale, 4))
    factor = label.rsplit("-", 1)[-1]
    want = {"f0": TOK0, "f05": TOK05, "f2": TOK2}.get(factor, TOK1)
    expect(label, "tokens", p["tokens"], want)
    expect(label, "reduced", p["reduced"], factor == "f0")
    expect(label, "tabletFromKWin", p["tabletFromKWin"], False)
    tabletenv = "tabletenv" in label
    expect(label, "tablet", p["tablet"], tabletenv)
    expect(label, "metricsTablet", p["metricsTablet"], tabletenv)
    if tabletenv:
        expect(label, "metricsTouch", p["metricsTouch"], True)
    if "light" in label:
        expect(label, "dark", p["dark"], False)
        want_accent, want_text = ("#f2a65a", "#141827") if "amber" in label else ("#2f6fdf", "#ffffff")
        expect(label, "accent", p["accent"], want_accent)
        expect(label, "accentText", p["accentText"], want_text)
        expect(label, "schemeAccent", p["schemeAccent"], "amber" not in label)
    elif "teal" in label:
        expect(label, "accent", p["accent"], "#3cc4b0")
        expect(label, "focusRing", p["focusRing"], "#3cc4b0")
        expect(label, "accentText", p["accentText"], "#141827")
        expect(label, "schemeAccent", p["schemeAccent"], False)
    else:
        expect(label, "dark", p["dark"], True)
        expect(label, "accent", p["accent"], "#5b9dff")
        expect(label, "accentText", p["accentText"], "#141827")
        expect(label, "fill", p["fill"], "#2f6fdf")
        expect(label, "fillText", p["fillText"], "#ffffff")
        expect(label, "focusRing", p["focusRing"], "#8ab8ff")
        expect(label, "soft", p["soft"], "#475b9dff")
        expect(label, "schemeAccent", p["schemeAccent"], True)
    for name, foreign, glyph in p["tiles"]:
        expect(label, f"tile {name!r} foreign", foreign, TILES[name])
        dpr = p["dpr"]
        want_glyph = round(48 * 42 / 64 * dpr) / dpr if foreign else 48
        expect(label, f"tile {name!r} glyph size", round(glyph, 4), round(want_glyph, 4))
    expect(label, "backdropReady", p["backdropReady"], True)
    expect(label, "backdropSolid", p["backdropSolid"], False)
    expect(label, "backdropFile", p["backdropFile"].rsplit("/contents/", 1)[-1], "images_dark/1920x1200.png")
    expect(label, "backdropTint", p["backdropTint"], "#8c0c0f1c")
    expect(label, "solidTint", p["solidTint"], "#f0ecf0f8")
    expect(label, "solidReady", p["solidReady"], False)  # Glass = Solid loads no picture
    for png in (f"{label}-tiles.png", f"{label}-backdrop.png"):
        if not (out / png).is_file():
            fails.append(f"{label}: {png} was not saved")
    rows.append(f"{label}: dpr {p['dpr']:.4f} unit {p['factorUnit']} tokens {p['tokens']['hover']}/{p['tokens']['toggle']}/"
                f"{p['tokens']['popupIn']}/{p['tokens']['popupOut']}/{p['tokens']['surface']}/{p['tokens']['max']} "
                f"accent {p['accent']} tablet {p['tablet']} backdrop {p['backdropFile'].rsplit('/', 2)[-2:]}")
print("\n".join(rows))
if fails:
    print("\n".join("FAIL " + f for f in fails))
    sys.exit(1)
print(f"offscreen: {len(rows)} runs, all checks passed")
PY
