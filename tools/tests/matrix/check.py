#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Adaptive test matrix: judge the sessions of run.sh (laptop side).
#
#   check.py RESULTS_DIR [ID...]      (default: every configuration directory in RESULTS_DIR)
#
# Per configuration (RESULTS_DIR/ID: config.txt, state-*.json from mx.py, logs, coredumps.json)
# it writes ID/checks.json, and RESULTS_DIR/summary.{md,json} for all. Checks (ADAPTIVE.md 11):
#   session, install, coredumps, steps       the session ran to the end, fusion-config.sh passed,
#                                            no core dump of this session, every step recorded
#   widgets-in-screen, widgets-clear-of-panels, widgets-apart
#                                            desktop widgets inside their screen and Plasma's
#                                            available area, clear of every panel window of that
#                                            output and of each other (every step)
#   applets-in-panel, panels-in-output       panel applets inside their panel and apart; panel
#                                            windows inside an output (every step)
#   popup-opened, popups-closed, notification
#                                            the launcher, quick settings and clock pop-ups open
#                                            inside their screen; none is left open afterwards; the
#                                            notification appears inside a screen
#   bars-per-screen                          two outputs: each has its own top bar (decision 8)
#   lid, hotplug, rotate, screen2, font, anim, tablet, lnfswitch, manyapps
#                                            the configuration's own checks (body.sh flags)
#   touch-targets                            tablet configurations: every PFTARGET the widgets
#                                            printed is at least 44 x 44 px (48 at a screen edge)
#                                            and 8 px from its neighbours; NOT RUN while no widget
#                                            prints any (debugDumpTargets, docs/parts/testing.md)
# Exit status: 0 no FAIL, 1 a FAIL, 2 a configuration without results.
import glob, json, os, re, sys

TOL = 1.0      # logical px of rounding allowed at edges
TARGET, EDGE_TARGET, GAP = 44, 48, 8
BASE_STEPS = ["01-desktop", "02b-dock-after-leave", "03-launcher", "04-quicksettings", "05-clock-popup",
              "06-dolphin", "07-konsole", "09-snap-flyout", "10-notification", "99-end"]
POPUP_STEPS = {"03-launcher": "launcher", "04-quicksettings": "quick settings", "05-clock-popup": "clock"}


def R(d):
    return (float(d["x"]), float(d["y"]), float(d["w"]), float(d["h"]))


def inside(a, b, tol=TOL):
    return a[0] >= b[0] - tol and a[1] >= b[1] - tol and a[0] + a[2] <= b[0] + b[2] + tol and a[1] + a[3] <= b[1] + b[3] + tol


def overlap(a, b):
    w = min(a[0] + a[2], b[0] + b[2]) - max(a[0], b[0])
    h = min(a[1] + a[3], b[1] + b[3]) - max(a[1], b[1])
    return w > TOL and h > TOL


def gap(a, b):
    dx = max(b[0] - (a[0] + a[2]), a[0] - (b[0] + b[2]), 0)
    dy = max(b[1] - (a[1] + a[3]), a[1] - (b[1] + b[3]), 0)
    return max(dx, dy) if (dx == 0 or dy == 0) else (dx * dx + dy * dy) ** 0.5


def fmt(r):
    return "%g,%g %gx%g" % r


def shell(w):
    return w["cls"] in ("plasmashell", "org.kde.plasmashell")


class Checker:
    def __init__(self, d, cid):
        self.d, self.id, self.res = d, cid, []
        row = open(os.path.join(d, "config.txt")).read().split() if os.path.exists(os.path.join(d, "config.txt")) else []
        self.size, self.scale, self.outs = (row[1], row[2], int(row[3])) if len(row) > 3 else ("?", "?", 1)
        self.flags = [] if len(row) < 5 or row[4] == "-" else row[4].split(",")
        self.what = " ".join(row[5:]) if len(row) > 5 else ""
        self.states = {}
        for f in sorted(glob.glob(os.path.join(d, "state-*.json"))):
            try:
                self.states[os.path.basename(f)[6:-5]] = json.load(open(f))
            except ValueError as e:
                self.add("steps", "FAIL", "%s unreadable: %s" % (os.path.basename(f), e))

    def add(self, check, result, detail="", step=""):
        self.res.append({"check": check, "step": step, "result": result, "detail": detail})

    def flag(self, name):
        for f in self.flags:
            if f == name or f.startswith(name + "="):
                return f.split("=", 1)[1] if "=" in f else True
        return None

    def text(self, name):
        p = os.path.join(self.d, name)
        return open(p, errors="replace").read() if os.path.exists(p) else ""

    # ---- whole session
    def session(self):
        log = self.text("scenario.log")
        if not log:
            self.add("session", "FAIL", "no scenario.log (the session did not run; see remote-%s.log)" % self.id)
            return False
        ok = "scenario rc=0" in log and re.search(r"^session rc=0$", log, re.M)
        self.add("session", "PASS" if ok else "FAIL", "" if ok else " / ".join(
            l for l in log.splitlines() if "rc=" in l or "time limit" in l)[-300:])
        fc = self.text("fusion-config.log")
        self.add("install", "PASS" if "fusion-config rc=0" in fc else "FAIL",
                 "" if "fusion-config rc=0" in fc else (fc.strip().splitlines() or ["no log"])[-1][:200])
        try:
            dumps = json.load(open(os.path.join(self.d, "coredumps.json")))
            self.add("coredumps", "PASS" if not dumps else "FAIL",
                     ", ".join("%s %s" % (x.get("exe"), x.get("signal")) for x in dumps))
        except (OSError, ValueError):
            self.add("coredumps", "FAIL", "no coredumps.json (the driver could not ask the host)")
        want = list(BASE_STEPS)
        if self.flag("hotplug"):
            want.append("00-login-one-output")
        if self.flag("screen2"):
            want.append("11-launcher-on-screen2")
        if self.flag("rotate"):
            want += ["12-portrait", "12b-portrait-launcher", "13-landscape-again"]
        if self.flag("manyapps"):
            want.append("14-many-apps")
        if self.flag("lnfswitch"):
            want += ["15-light", "16-dark-again"]
        missing = [s for s in want if s not in self.states]
        self.add("steps", "PASS" if not missing else "FAIL", "missing: " + ", ".join(missing) if missing else
                 "%d steps" % len(self.states))
        return True

    # ---- geometry helpers
    def outputs(self, st):
        return {o["name"]: o for o in st.get("kwin", {}).get("outputs", [])}

    def screen_output(self, st, screen):
        for name, sid in st.get("screen_ids", {}).items():
            if sid == screen and name in self.outputs(st):
                return self.outputs(st)[name]
        return None

    def panel_windows(self, st):
        return [w for w in st.get("kwin", {}).get("windows", []) if w.get("dock") and shell(w)]

    def popups(self, st):
        return [w for w in st.get("kwin", {}).get("windows", []) if shell(w) and not w.get("dock") and
                not w.get("desktop") and not w.get("notification") and not w.get("tooltip") and not w.get("hidden")
                and w["geo"]["w"] > 1 and w["geo"]["h"] > 1]

    def output_of(self, st, r):
        for o in self.outputs(st).values():
            if inside(r, R(o["geo"])):
                return o
        return None

    # ---- per step
    def layout(self, step, st):
        pl = st.get("plasma", {})
        if pl.get("error"):
            self.add("layout", "FAIL", "desktop scripting failed: " + pl["error"][:200], step)
            return
        bad_in, bad_clear, bad_apart = [], [], []
        panels = self.panel_windows(st)
        for dk in pl.get("desktops", []):
            o = self.screen_output(st, dk["screen"])
            if o is None:
                if dk["widgets"]:
                    bad_in.append("desktop %s (screen %s) has %d widgets but no output" % (dk["id"], dk["screen"], len(dk["widgets"])))
                continue
            og = R(o["geo"])
            av = st.get("avail", {}).get(o["name"])
            rects = []
            for w in dk["widgets"]:
                r = (og[0] + w["x"], og[1] + w["y"], w["w"], w["h"])
                rects.append((w["type"], r))
                if not inside(r, og):
                    bad_in.append("%s %s outside %s %s" % (w["type"], fmt(r), o["name"], fmt(og)))
                if av and not inside(r, R(av)):
                    bad_clear.append("%s %s outside the available area %s" % (w["type"], fmt(r), fmt(R(av))))
                for p in panels:
                    if overlap(r, R(p["geo"])):
                        bad_clear.append("%s %s under the panel %s" % (w["type"], fmt(r), fmt(R(p["geo"]))))
            for i in range(len(rects)):
                for j in range(i + 1, len(rects)):
                    if overlap(rects[i][1], rects[j][1]):
                        bad_apart.append("%s %s and %s %s" % (rects[i][0], fmt(rects[i][1]), rects[j][0], fmt(rects[j][1])))
        self.add("widgets-in-screen", "FAIL" if bad_in else "PASS", "; ".join(bad_in), step)
        self.add("widgets-clear-of-panels", "FAIL" if bad_clear else "PASS", "; ".join(bad_clear), step)
        self.add("widgets-apart", "FAIL" if bad_apart else "PASS", "; ".join(bad_apart), step)
        bad = []
        for p in pl.get("panels", []):
            vertical = p["location"] in ("left", "right")
            thick, length = p["height"], p["length"]
            spans = []
            for w in p["widgets"]:
                along, across = (w["y"], w["h"]) if vertical else (w["x"], w["w"])
                if w["w"] <= 0 or w["h"] <= 0:
                    continue  # hidden applet (tray items folded away)
                if along < -TOL or along + across > length + TOL:
                    bad.append("%s in the %s panel at %g..%g of %g" % (w["type"], p["location"], along, along + across, length))
                cross = w["x"] if vertical else w["y"]
                size = w["w"] if vertical else w["h"]
                if cross < -TOL or cross + size > thick + TOL:
                    bad.append("%s in the %s panel %g px thick at %g..%g" % (w["type"], p["location"], thick, cross, cross + size))
                if w["type"] != "org.kde.plasma.panelspacer":  # invisible filler; applets may sit on it
                    spans.append((along, along + across, w["type"]))
            spans.sort()
            for a, b in zip(spans, spans[1:]):
                if b[0] < a[1] - TOL:
                    bad.append("%s and %s overlap in the %s panel (%g > %g)" % (a[2], b[2], p["location"], a[1], b[0]))
        self.add("applets-in-panel", "FAIL" if bad else "PASS", "; ".join(bad), step)
        bad = [fmt(R(p["geo"])) for p in panels if not self.output_of(st, R(p["geo"]))]
        self.add("panels-in-output", "FAIL" if bad else "PASS", "panel windows outside every output: " + ", ".join(bad) if bad else "", step)

    def step_checks(self):
        for step, st in sorted(self.states.items()):
            self.layout(step, st)
            if step in POPUP_STEPS or step in ("11-launcher-on-screen2", "12b-portrait-launcher"):
                pops = self.popups(st)
                if not pops:
                    self.add("popup-opened", "FAIL", "no %s pop-up window" % POPUP_STEPS.get(step, "launcher"), step)
                else:
                    out = [fmt(R(w["geo"])) for w in pops if not self.output_of(st, R(w["geo"]))]
                    self.add("popup-opened", "FAIL" if out else "PASS",
                             ("outside every output: " + ", ".join(out)) if out else
                             ", ".join("%s on %s" % (fmt(R(w["geo"])), w.get("output")) for w in pops), step)
            if step in ("02b-dock-after-leave", "06-dolphin", "99-end"):
                pops = self.popups(st)
                self.add("popups-closed", "FAIL" if pops else "PASS",
                         ", ".join("%s %s" % (w["caption"] or w["cls"], fmt(R(w["geo"]))) for w in pops), step)
            if step == "10-notification":
                notes = [w for w in st.get("kwin", {}).get("windows", []) if w.get("notification")]
                bad = [fmt(R(w["geo"])) for w in notes if not self.output_of(st, R(w["geo"]))]
                self.add("notification", "FAIL" if not notes or bad else "PASS",
                         "no notification window" if not notes else ("outside: " + ", ".join(bad) if bad else ""), step)

    # ---- configuration flags
    def config_checks(self):
        s1 = self.states.get("01-desktop")
        if s1 is None:
            return
        outs = self.outputs(s1)
        if self.outs > 1 and not self.flag("lid"):
            missing = []
            for name, o in outs.items():
                og = R(o["geo"])
                tops = [p for p in self.panel_windows(s1) if abs(p["geo"]["y"] - og[1]) <= TOL and
                        inside(R(p["geo"]), og) and p["geo"]["h"] < og[3] / 4]
                if not tops:
                    missing.append(name)
            self.add("bars-per-screen", "FAIL" if missing else "PASS",
                     "no top bar on " + ", ".join(missing) if missing else "%d outputs" % len(outs), "01-desktop")
        if self.flag("lid"):
            ok = len(outs) == 1 and len(self.panel_windows(s1)) >= 2
            self.add("lid", "PASS" if ok else "FAIL", "%d outputs, %d panel windows on them" % (
                len(outs), len(self.panel_windows(s1))), "01-desktop")
        if self.flag("hotplug"):
            s0 = self.states.get("00-login-one-output", {})
            n0 = len(self.outputs(s0)) if s0 else 0
            ok = n0 == 1 and len(outs) == 2
            self.add("hotplug", "PASS" if ok else "FAIL", "outputs at login %d, after the hot-plug %d" % (n0, len(outs)))
        if self.flag("screen2"):
            st = self.states.get("11-launcher-on-screen2")
            names = list(self.outputs(s1))
            pops = self.popups(st) if st else []
            on2 = [w for w in pops if len(names) > 1 and w.get("output") == names[1]]
            self.add("screen2", "PASS" if on2 else "FAIL", "pop-ups on %s" % ", ".join(
                w.get("output", "?") for w in pops) if pops else "no pop-up", "11-launcher-on-screen2")
        if self.flag("rotate"):
            sp, sb = self.states.get("12-portrait"), self.states.get("13-landscape-again")
            o = list(self.outputs(sp).values())[0]["geo"] if sp and self.outputs(sp) else None
            self.add("rotate", "PASS" if o and o["h"] > o["w"] else "FAIL",
                     "portrait output %s" % (fmt(R(o)) if o else "missing"), "12-portrait")
            if sb:
                def wid(st):
                    return {(w["type"], w["id"]): (w["x"], w["y"], w["w"], w["h"]) for d in st["plasma"].get("desktops", [])
                            for w in d["widgets"]}
                a, b = wid(s1), wid(sb)
                moved = ["%s %s -> %s" % (k[0], fmt(a[k]), fmt(b.get(k, (0, 0, 0, 0)))) for k in a
                         if k not in b or max(abs(x - y) for x, y in zip(a[k], b[k])) > TOL]
                self.add("rotate", "FAIL" if moved else "PASS",
                         ("widgets moved after rotating back: " + "; ".join(moved)) if moved else "widgets back in place",
                         "13-landscape-again")
        v = self.flag("font")
        if v:
            st = s1.get("settings", {})
            bad = [k for k in ("font", "menuFont", "toolBarFont") if ",%s," % v not in (st.get("kdeglobals/General/" + k) or "")]
            self.add("font", "FAIL" if bad else "PASS", "not %s pt: %s" % (v, ", ".join(bad)) if bad else "%s pt" % v)
        v = self.flag("anim")
        if v:
            got = s1.get("settings", {}).get("kdeglobals/KDE/AnimationDurationFactor")
            self.add("anim", "PASS" if got == v else "FAIL", "AnimationDurationFactor=%s" % got)
        if self.flag("tablet"):
            self.add("tablet", "PASS" if s1.get("tablet_mode") is True else "FAIL", "tabletMode=%s" % s1.get("tablet_mode"))
        if self.flag("lnfswitch"):
            before = self.states.get("10-notification", {}).get("settings", {})
            skip = ("kdeglobals/KDE/LookAndFeelPackage", "kdeglobals/General/ColorScheme", "kwinrc/org.kde.kdecoration2/theme")
            for step in ("15-light", "16-dark-again"):
                after = self.states.get(step, {}).get("settings", {})
                diff = ["%s: %s -> %s" % (k, before.get(k), after.get(k)) for k in before if k not in skip and before.get(k) != after.get(k)]
                self.add("lnfswitch", "FAIL" if diff else "PASS", "; ".join(diff) or "fonts, cursor and buttons kept (%s)" %
                         after.get("kdeglobals/KDE/LookAndFeelPackage"), step)
        if self.flag("manyapps"):
            st = self.states.get("14-many-apps")
            if st:
                o = list(self.outputs(st).values())[0]
                docks = [p for p in self.panel_windows(st) if p["geo"]["y"] > o["geo"]["y"] + o["geo"]["h"] / 2]
                bad = [fmt(R(p["geo"])) for p in docks if not inside(R(p["geo"]), R(o["geo"]))]
                self.add("manyapps", "FAIL" if bad or not docks else "PASS",
                         ("dock outside the screen: " + ", ".join(bad)) if bad else
                         ("no dock" if not docks else "dock " + ", ".join(fmt(R(p["geo"])) for p in docks)), "14-many-apps")

    # ---- touch targets
    def targets(self):
        if not self.flag("targets"):
            return
        lines = []
        for f in sorted(glob.glob(os.path.join(self.d, "plasmashell*.log"))):
            lines += [l for l in open(f, errors="replace") if "PFTARGET " in l]
        if not lines:
            self.add("touch-targets", "NOT RUN", "no widget printed PFTARGET lines (debugDumpTargets not implemented yet)")
            return
        st = self.states.get("01-desktop", {})
        wins = [w for w in st.get("kwin", {}).get("windows", []) if shell(w)]
        per_win, bad, n, unplaced = {}, [], 0, 0
        for l in lines:
            m = re.search(r"PFTARGET (\S+) (\d+)x(\d+) (-?[\d.]+) (-?[\d.]+) ([\d.]+) ([\d.]+) ?(.*)$", l.strip())
            if not m:
                continue
            n += 1
            tag, ww, wh = m.group(1), int(m.group(2)), int(m.group(3))
            r = tuple(float(m.group(i)) for i in (4, 5, 6, 7))
            label = m.group(8).strip() or "?"
            key = (tag, ww, wh, r, label)
            per_win.setdefault((tag, ww, wh), set()).add(key)
        for (tag, ww, wh), items in per_win.items():
            items = sorted(items, key=lambda k: k[3])
            win = [w for w in wins if abs(w["geo"]["w"] - ww) <= TOL and abs(w["geo"]["h"] - wh) <= TOL]
            og = None
            if len(win) == 1:
                og = R(win[0]["geo"])
            for _, _, _, r, label in items:
                edge = False
                if og:
                    g = (og[0] + r[0], og[1] + r[1], r[2], r[3])
                    o = self.output_of(st, g)
                    if o:
                        ob = R(o["geo"])
                        edge = g[0] <= ob[0] + 2 or g[1] <= ob[1] + 2 or g[0] + g[2] >= ob[0] + ob[2] - 2 or g[1] + g[3] >= ob[1] + ob[3] - 2
                else:
                    unplaced += 1
                need = EDGE_TARGET if edge else TARGET
                if min(r[2], r[3]) < need - 0.5:
                    bad.append("%s %s %s %gx%g < %d%s" % (tag, label, fmt(r), r[2], r[3], need, " (edge)" if edge else ""))
            for i in range(len(items)):
                for j in range(i + 1, len(items)):
                    a, b = items[i][3], items[j][3]
                    if inside(a, b, 0) or inside(b, a, 0):
                        continue  # nested (a button inside a delegate)
                    if overlap(a, b) or gap(a, b) < GAP - 0.5:
                        bad.append("%s %s and %s %.0f px apart" % (tag, items[i][4], items[j][4], gap(a, b)))
        self.add("touch-targets", "FAIL" if bad else "PASS", ("; ".join(bad[:40]) + (" (+%d)" % (len(bad) - 40) if len(bad) > 40 else ""))
                 if bad else "%d targets in %d windows%s" % (n, len(per_win), ", %d without a window match (edge rule skipped)" % unplaced if unplaced else ""))

    def run(self):
        if self.session():
            self.step_checks()
            self.config_checks()
            self.targets()
        json.dump({"id": self.id, "size": self.size, "scale": self.scale, "outputs": self.outs, "flags": self.flags,
                   "what": self.what, "checks": self.res}, open(os.path.join(self.d, "checks.json"), "w"), indent=1)
        return self.res


def main(argv):
    if len(argv) < 2:
        raise SystemExit("usage: check.py RESULTS_DIR [ID...]")
    res_dir = argv[1]
    ids = argv[2:] or sorted(d for d in os.listdir(res_dir) if os.path.isdir(os.path.join(res_dir, d)))
    rows, summary, missing = [], [], []
    for cid in ids:
        d = os.path.join(res_dir, cid)
        if not os.path.isdir(d):
            missing.append(cid)
            continue
        c = Checker(d, cid)
        res = c.run()
        fails = [r for r in res if r["result"] == "FAIL"]
        notrun = [r for r in res if r["result"] == "NOT RUN"]
        verdict = "FAIL" if fails else "PASS"
        # one line per failing check (steps folded)
        folded = {}
        for r in fails:
            folded.setdefault(r["check"], []).append(r)
        text = "; ".join("%s (%s): %s" % (k, ", ".join(sorted({x["step"] or "-" for x in v})), v[0]["detail"][:160])
                         for k, v in folded.items())
        rows.append("| %s | %s @%s x%d %s | %s | %d | %d | %d | %s |" % (
            cid, c.size, c.scale, c.outs, ",".join(c.flags) or "-", verdict,
            sum(1 for r in res if r["result"] == "PASS"), len(fails), len(notrun), text.replace("|", "/") or "-"))
        summary.append({"id": cid, "verdict": verdict, "pass": sum(1 for r in res if r["result"] == "PASS"),
                        "fail": len(fails), "notrun": len(notrun), "failures": sorted(folded)})
    head = ["| config | output | result | pass | fail | not run | failures (check (steps): first detail) |",
            "|---|---|---|---|---|---|---|"]
    out = "\n".join(head + rows)
    out += "\n\nNot encoded: the separator and icon sharpness probe (pixel-grid pass, ADAPTIVE fix 11; " \
           "compare the screenshots), M27 (tools/device/tests, the login check).\n"
    if missing:
        out += "No results: %s\n" % ", ".join(missing)
    print(out)
    open(os.path.join(res_dir, "summary.md"), "w").write(out)
    json.dump({"configs": summary, "missing": missing}, open(os.path.join(res_dir, "summary.json"), "w"), indent=1)
    if missing:
        return 2
    return 1 if any(s["verdict"] == "FAIL" for s in summary) else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
