#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Summary of an icon-position test run (tools/tests/icons/run.sh): reads RESULTS/{1,2,3}/checks.jsonl,
# compares each step's screenshot of the icon area with the baseline screenshot (Pillow, when
# installed), prints a table and writes RESULTS/summary.{json,md}.
#
#   report.py RESULTS_DIR [--strict]
#
# Results per step (per event): PASS (the positions entry is byte-identical to the one before the
# step and every file keeps its baseline cell), REWRITTEN (Plasma saved the entry again during the
# step, every file keeps its cell and the icons look the same), FAIL (a file changed cell, the icons
# look different, a card moved, a pop-up stayed open or a core dump appeared). The column "entry =
# baseline" compares with the baseline entry itself.
# Exit status: 0 no FAIL (with --strict: every step PASS), 1 otherwise, 2 the setup failed (pattern
# not reached, or a step without a result).
import json, os, sys

res_dir = sys.argv[1]
strict = "--strict" in sys.argv[2:]
rows, setup = [], []
for sess in ("1", "2", "3"):
    path = os.path.join(res_dir, sess, "checks.jsonl")
    if os.path.exists(path):
        rows += [dict(json.loads(line), session=sess) for line in open(path) if line.strip()]
    steps = os.path.join(res_dir, sess, "steps.log")
    if os.path.exists(steps):
        setup += [line.strip() for line in open(steps) if "SETUP FAIL" in line]
    elif sess == "1":
        setup.append("session 1 left no steps.log")
pattern = os.path.join(res_dir, "1", "pattern.json")
if os.path.exists(pattern) and open(pattern).read().strip() not in ("", "[]"):
    setup.append("pattern not reached: " + open(pattern).read().strip())
# Every step of the three scenarios must have a result: a session that failed to start or a check
# that crashed must not shrink the table to the steps that passed.
EXPECTED = {"1": ["02-plasmashell-restart", "03-kwin-reconfigure", "04-scale-back", "05-rotation-back",
                  "06-dock-dodge", "07-dock-autohide-back"],
            "2": ["08-second-session"],
            "3": ["09-second-output-at-login", "10-first-output-disabled", "11-first-output-enabled",
                  "12-second-output-removed"]}
have = {(r["session"], r["step"]) for r in rows}
missing = [s + "/" + step for s, steps in EXPECTED.items() for step in steps if (s, step) not in have]
if missing:
    setup.append("no result for step(s) %s (see remote-N.log and N/steps.log)" % ", ".join(missing))
upgrade = None
if os.path.exists(os.path.join(res_dir, "1", "upgrade.json")):
    upgrade = json.load(open(os.path.join(res_dir, "1", "upgrade.json")))
elif os.path.exists(os.path.join(res_dir, "upgrade-expected")):
    setup.append("the upgrade path ran without a result (1/upgrade.json missing)")
folderview = ""
if os.path.exists(os.path.join(res_dir, "1", "folderview.txt")):
    folderview = open(os.path.join(res_dir, "1", "folderview.txt")).read().strip().split("=")[-1]
late = []
if os.path.exists(os.path.join(res_dir, "coredumps.json")):
    late = json.load(open(os.path.join(res_dir, "coredumps.json")))

# Icon area of the baseline, in logical px relative to the output that shows the icons: the first
# 12 columns (clear of the cards) and every row of the grid.
try:
    from PIL import Image, ImageChops
except ImportError:
    Image = None
base_state = os.path.join(res_dir, "1", "state-base.json")
grid_file = os.path.join(res_dir, "1", "grid.json")
area, base_outs = None, []
if Image and os.path.exists(base_state) and os.path.exists(grid_file):
    g = json.load(open(grid_file))
    area = (g["x"], g["y"], g["x"] + min(12, g["ncol"]) * g["cw"], g["y"] + g["per"] * g["ch"])
    bs = json.load(open(base_state))
    base_outs = [(o["name"], o["geo"], o["scale"]) for o in bs["kwin"]["outputs"]]


def crop(png, outputs, on):
    """The icon area of the output `on` in a full-screen screenshot of all outputs."""
    if not (area and on and os.path.exists(png)):
        return None
    geo = {n: (gg, sc) for n, gg, sc in outputs}
    if on not in geo:
        return None
    gg, sc = geo[on]
    minx = min(v[0]["x"] for v in geo.values())
    miny = min(v[0]["y"] for v in geo.values())
    ox, oy = (gg["x"] - minx) * sc, (gg["y"] - miny) * sc
    box = tuple(int(round(v)) for v in (ox + area[0] * sc, oy + area[1] * sc, ox + area[2] * sc, oy + area[3] * sc))
    im = Image.open(png).convert("RGB")
    if box[2] > im.size[0] or box[3] > im.size[1]:
        return None
    return im.crop(box)


base_img = crop(os.path.join(res_dir, "1", "01-base.png"), base_outs, base_outs[0][0]) if base_outs else None


def looks(r):
    """Pixels of the icon area that differ from the baseline screenshot (None: not comparable)."""
    if base_img is None:
        return None
    img = crop(os.path.join(res_dir, r["session"], r["step"] + ".png"), r["outputs"], r.get("icons_on"))
    if img is None or img.size != base_img.size:
        return None
    diff = ImageChops.difference(base_img, img).convert("L").point(lambda v: 255 if v > 40 else 0)
    hist = diff.histogram()
    return sum(hist) - hist[0]


def yn(v):
    return "yes" if v else "NO"


lines = ["| step | entry = baseline (bytes) | rewritten at this step | header (stripes, per stripe) | same cells | "
         "icons look the same | icons on | cards / ItemGeometries | pop-ups left | core dumps | result |",
         "|---|---|---|---|---|---|---|---|---|---|---|"]
for r in rows:
    px = looks(r)
    r["screen_diff_px"] = px
    if px is not None and px > 50 and r["result"] != "FAIL":
        r["result"], r["pass"] = "FAIL", False
    pops = ", ".join("%s %r" % (p["cls"], p["caption"]) for p in r["popups"]) or "none"
    dumps = ", ".join("%s %s" % (d["exe"], d["signal"]) for d in r["coredumps"]) or "none"
    moved = "" if r["positions_same_cells"] else " (%s)" % "; ".join(
        "%s %s->%s" % (m["file"].split("/")[-1], m["base"], m["now"]) for m in r["moved"][:4])
    head = r["header"]["now"] or ["-", "-"]
    lines.append("| %s | %s | %s | %s,%s (base %s,%s) | %s%s | %s | %s | %s / %s | %s | %s | %s |" % (
        r["step"], yn(r["positions_bytes_equal"]), "yes" if r.get("rewritten") else "no", head[0], head[1],
        r["header"]["base"][0], r["header"]["base"][1], yn(r["positions_same_cells"]), moved,
        "n/a" if px is None else ("yes" if px <= 50 else "NO (%d px)" % px), r.get("icons_on") or "-",
        yn(r["cards_equal"]), yn(r["itemgeom_equal"]), pops, dumps, r["result"]))
text = "\n".join(lines)
if folderview:
    text += "\n\nFolder View: %s" % ("from the build's layout (M1)" if folderview == "layout"
                                    else "written by the test (the build's layout has none)")
if upgrade:
    text += "\n\nUpgrade from the previous build: %s%s (desktop %s -> %s)" % (
        upgrade["result"], (": " + "; ".join(upgrade["problems"])) if upgrade["problems"] else
        " (panels, dock pins and cards kept)", upgrade["desktop_before"], upgrade["desktop_after"])
if setup:
    text += "\n\nSetup problems:\n" + "\n".join("- " + s for s in setup)
text += "\n\nCore dumps of the test sessions (journal, whole run): %s" % (
    ", ".join("%s %s pid %s" % (d["exe"], d["signal"], d["pid"]) for d in late) or "none")
counts = {k: sum(1 for r in rows if r["result"] == k) for k in ("PASS", "REWRITTEN", "FAIL")}
text += "\nSteps: %d PASS, %d REWRITTEN, %d FAIL of %d" % (counts["PASS"], counts["REWRITTEN"], counts["FAIL"], len(rows))
print(text)
keys = ("step", "result", "positions_bytes_equal", "rewritten", "positions_same_cells", "header", "icons_on",
        "screen_diff_px", "cards_equal", "itemgeom_equal", "lastResolution", "resolutions")
summary = {"steps": [{k: r.get(k) for k in keys} | {"popups": len(r["popups"]), "coredumps": len(r["coredumps"])}
                     for r in rows], "setup_problems": setup, "coredumps": late, "counts": counts, "total": len(rows),
           "folderview": folderview, "upgrade": upgrade}
json.dump(summary, open(os.path.join(res_dir, "summary.json"), "w"), indent=1)
open(os.path.join(res_dir, "summary.md"), "w").write(text + "\n")
if setup or not rows:
    sys.exit(2)
bad = counts["FAIL"] or late or (strict and counts["REWRITTEN"]) or (upgrade and not upgrade["pass"])
sys.exit(1 if bad else 0)
