#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Motion lint (EFFECTS.md 6.2): Fusion animations take their durations from the Motion tokens
# (packages/common/Motion.qml), so Plasma's animation speed and reduced motion reach them.
#
#   tools/checks/motion-lint.sh [--warn] [PATH...]      default PATH: packages/
#
# Findings, one per line as FILE:LINE: RULE message | source:
#   literal-duration   `duration: 150`, `duration: cond ? 600 : 0`, `anim.duration = 150`
#   over-max           a Kirigami unit scaled past Motion.max (`veryLongDuration * 2`)
#   infinite-loop      `loops: Animation.Infinite` (or -1); at most 3 cycles (Motion.loops())
#   no-duration        an *Animation / *Animator with no `duration`: it runs Qt's own 250 ms and
#                      ignores the speed setting (SpringAnimation: physics, no duration at all)
# Allowed: packages/look-and-feel/common/contents/splash/Splash.qml (the splash runs only while
# logging in). Timer `interval:` values are not animations and are not checked. Group
# animations (Sequential, Parallel, Parent), PropertyAction, ScriptAction and FrameAnimation
# carry no duration of their own; custom animation components are checked in their own files.
# Exit status: 1 when anything is found, 0 otherwise; with --warn always 0 (tools/build.sh).
set -euo pipefail
HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
ROOT=$(cd "$HERE/../.." && pwd)
warn=0
if [ "${1:-}" = --warn ]; then warn=1; shift; fi
[ $# -gt 0 ] || set -- "$ROOT/packages"

rc=0
python3 - "$HERE" "$ROOT" "$@" <<'PY' || rc=$?
import re
import sys

sys.path.insert(0, sys.argv[1])
import qmlscan  # noqa: E402

root = sys.argv[2]
paths = sys.argv[3:]
ALLOW = ("packages/look-and-feel/common/contents/splash/Splash.qml",)
# Qt Quick animation types that take a duration (custom components such as Breeze's
# RejectPasswordAnimation are checked in their own files, not at their uses).
TIMED = {"PropertyAnimation", "NumberAnimation", "ColorAnimation", "RotationAnimation", "Vector3dAnimation",
         "SmoothedAnimation", "SpringAnimation", "PauseAnimation", "AnchorAnimation", "PathAnimation",
         "OpacityAnimator", "ScaleAnimator", "RotationAnimator", "XAnimator", "YAnimator", "UniformAnimator"}
UNIT = re.compile(r"\b(?:Kirigami\.)?Units\.(veryShortDuration|shortDuration|longDuration|veryLongDuration)\b")
UNIT_FACTOR = {"veryShortDuration": 0.25, "shortDuration": 0.5, "longDuration": 1.0, "veryLongDuration": 2.0}
NUMBER = re.compile(r"(?<![\w.])(\d+(?:\.\d+)?)(?![\w.])")
# a token scaled by a number (`motion.surface * 1.2`, `2 * motion.hover`) is not a literal
PRODUCT = re.compile(r"(?:[A-Za-z_$][\w.$]*|\))\s*[*/]\s*\d+(?:\.\d+)?|\d+(?:\.\d+)?\s*\*\s*(?=[A-Za-z_$(])")
ASSIGN = re.compile(r"\.duration\s*=\s*(\d)")

findings = []


def check_duration(path, line, value):
    e = qmlscan.expression(value)
    m = UNIT.search(e)
    if m:
        f = UNIT_FACTOR[m.group(1)]
        mult = re.search(re.escape(m.group(0)) + r"\s*\*\s*(\d+(?:\.\d+)?)", e)
        if mult and f * float(mult.group(1)) > 2.0:
            findings.append((path, line, "over-max",
                             f"{m.group(0)} * {mult.group(1)} = {int(200 * f * float(mult.group(1)))} ms at factor 1; "
                             "the longest token is Motion.max (400 ms), use a token"))
        return
    rest = PRODUCT.sub(" ", e)
    nums = NUMBER.findall(rest)
    if nums:
        findings.append((path, line, "literal-duration", f"duration {', '.join(nums)} ms is a literal; use a Motion token"))


for f in qmlscan.qml_files(paths):
    rel = str(f.resolve().relative_to(root)) if str(f.resolve()).startswith(root) else str(f)
    if rel.endswith(ALLOW):
        continue
    text = f.read_text(encoding="utf-8", errors="replace")
    for obj in qmlscan.walk(qmlscan.scan(text)):
        if obj.has("duration"):
            line, value = obj.props["duration"]
            check_duration(rel, line, value)
        elif obj.short in TIMED:
            why = "physics animation, no duration" if obj.short == "SpringAnimation" else "no duration: Qt's default ignores the speed setting"
            findings.append((rel, obj.line, "no-duration", f"{obj.short} with {why}; set a Motion token"))
        if obj.has("loops"):
            line, value = obj.props["loops"]
            v = qmlscan.expression(value)
            if "Infinite" in v or v == "-1":
                findings.append((rel, line, "infinite-loop", "loops forever; at most 3 cycles (Motion.loops(3))"))
    stripped = qmlscan.strip_comments(text).split("\n")
    for n, s in enumerate(stripped, 1):
        if ASSIGN.search(s):
            findings.append((rel, n, "literal-duration", "duration assigned a literal; use a Motion token"))

findings.sort(key=lambda x: (x[0], x[1], x[2]))
for path, line, rule, msg in findings:
    print(f"{path}:{line}: {rule} {msg} | {qmlscan.source_line(root + '/' + path if not path.startswith('/') else path, line)}")
print(f"motion-lint: {len(findings)} finding(s) in {len({x[0] for x in findings})} file(s)", file=sys.stderr)
sys.exit(1 if findings else 0)
PY
if [ "$rc" -gt 1 ]; then echo "motion-lint: the check itself failed (status $rc)" >&2; exit "$rc"; fi
[ "$warn" = 1 ] && exit 0
exit "$rc"
