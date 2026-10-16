#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit test of the depth features' check (tools/tests/depth/run.sh) with a stand-in session runner
# (--runner): no test host, no session. The runner records the seed it was given and writes what a
# session leaves (checks, scenario.log's status lines, a core dump report): every check passing,
# one feature with a failing check (a red run, as a feature broken on purpose), one feature that
# gives no checks, a session stopped at its time limit after passing checks, a runner that fails,
# a core dump. Checked: the exit status and the summary for each, Quick Look skipped without its
# install, each feature's seed (the HOME tree and tools for every one, the live chips' stand-ins
# and debug rule, Quick Look's install), chosen features only, relative paths, and the setup errors
# (an unknown feature, one given as a pattern, an empty feature list). Test tooling only, not installed.
#
#   run-unit.sh BASE
#
# BASE must be a scratch directory on disk (not /tmp); it is emptied first.
set -euo pipefail
BASE=${1:?scratch directory}
BASE=$(realpath -m -- "$BASE")
case $BASE in /tmp/* | /tmp) echo "use a directory on disk, not /tmp" >&2; exit 2 ;; esac
HERE=$(cd "$(dirname "$0")" && pwd)
rm -rf "${BASE:?}"
mkdir -p "$BASE/stage/.local/share/plasma/plasmoids" "$BASE/ql/bin" "$BASE/ql/share/kio/servicemenus"
echo stand-in >"$BASE/ql/bin/plasma-fusion-quicklook"
printf '[Desktop Entry]\n' >"$BASE/ql/share/kio/servicemenus/plasma-fusion-quicklook.desktop"
chmod 644 "$BASE/ql/share/kio/servicemenus/plasma-fusion-quicklook.desktop"

# The stand-in runner: NAME SCENARIO SEED SIZE TIMEOUT, results in ./vsession-out/NAME/.
cat >"$BASE/runner.sh" <<'EOF'
#!/bin/bash
set -euo pipefail
name=$1 scenario=$2 seed=$3
out=vsession-out/$name
mkdir -p "$out"
feature=${name#*-}
(cd "$seed" && find . -maxdepth 3 \( -path ./pf-tools/'*' -prune -o -print \) | sort) >"$out/seed.txt"
[ -f "$seed/pf-tools/vsession/remote.sh" ] && echo "./pf-tools/vsession/remote.sh" >>"$out/seed.txt"
cp "$seed/.config/pfv-env" "$out/pfv-env" 2>/dev/null || true
echo "$scenario" >"$out/scenario.txt"
{ echo "scenario rc=0"
  if [ "$feature" = "${UNIT_TIMEOUT:-}" ]; then echo "session rc=124"; else echo "session rc=0"; fi; } >"$out/scenario.log"
if [ "$feature" = "${UNIT_DUMP:-}" ]; then echo '[{"exe": "/usr/bin/plasmashell"}]' >"$out/coredumps.json"; fi
[ "$feature" = "${UNIT_EMPTY:-}" ] && exit 0
{ echo "INFO $feature"; echo "PASS $feature: one"; echo "PASS $feature: two"
  [ "$feature" = "${UNIT_FAIL:-}" ] && echo "FAIL $feature: broken on purpose"
  true; } >"$out/checks.txt"
# A runner that fails after a session that looks complete (the fetch of its results failed, say).
[ "$feature" != "${UNIT_RUNNER_FAIL:-}" ] || exit 3
EOF
chmod +x "$BASE/runner.sh"

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); echo "PASS $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
expect() { # DESCRIPTION CONDITION...
  local d=$1; shift
  if "$@"; then pass "$d"; else fail "$d"; fi
}
run() { # CASE ARGS...: the driver; leaves $W (its work directory) and $RC
  local name=$1; shift
  W=$BASE/$name
  RC=0
  bash "$HERE/run.sh" --stage "$BASE/stage" --work "$W" --name unit --runner "$BASE/runner.sh" "$@" >"$BASE/$name.log" 2>&1 || RC=$?
}
result() { python3 -c 'import json, sys; d = json.load(open(sys.argv[1])); print(" ".join(r["feature"] + "=" + r["result"] for r in d["features"]))' "$W/results/summary.json"; }
has() { grep -qxF -- "$2" "$W/results/$1/seed.txt"; }
has_both() { has "$1" "$2" && has "$1" "$3"; }
lacks() { ! grep -qF -- "$2" "$W/results/$1/seed.txt"; }
exit_and() { [ "$RC" = "$1" ] && [ "$(result)" = "$2" ]; }
nothing_run() { [ "$RC" = "$1" ] && [ ! -e "$W/results/placement" ]; }
help_is_usage() { "$HERE/run.sh" --help | grep -q -- "--runner CMD" && ! "$HERE/run.sh" --help | grep -q "import json"; }

run all --quicklook "$BASE/ql"
expect "every feature passing: exit 0" [ "$RC" = 0 ]
expect "  the summary lists the six, each PASS" [ "$(result)" = "placement=PASS snapgroups=PASS workspaces=PASS copytext=PASS quicklook=PASS livechips=PASS" ]
expect "  summary.md has a row per feature" [ "$(grep -c '^| [a-z]* | PASS | 2 | 0 |$' "$W/results/summary.md")" = 6 ]
expect "  each session ran its own scenario" grep -qx "$(cd "$HERE/../../.." && pwd)/packages/kwin/tests/vsession/scenario-snapgroups.sh" "$W/results/snapgroups/scenario.txt"
for f in placement snapgroups workspaces copytext quicklook livechips; do
  expect "  $f's seed has the HOME tree and tools" has_both "$f" ./pf-stage/.local ./pf-tools/vsession/remote.sh
done
expect "  the live chips' seed has their stand-ins" has_both livechips ./pf-chips/fake_status_items.py ./pf-chips/mock_power.py
expect "  and the widget's debug rule" grep -qx 'QT_LOGGING_RULES=org.plasmafusion.livechips.debug=true' "$W/results/livechips/pfv-env"
expect "  Quick Look's seed has its install in ~/.local" has quicklook ./.local/bin/plasma-fusion-quicklook
menu_executable() { [ -x "$W/seeds/quicklook/.local/share/kio/servicemenus/plasma-fusion-quicklook.desktop" ]; }
expect "  and its service menu is executable there (KIO's rule outside the system directories)" menu_executable
expect "  the others have no Quick Look" lacks placement quicklook

run noql
expect "every feature but no --quicklook: exit 2 (Quick Look cannot pass), nothing run" nothing_run 2
run noql-chosen --features placement,livechips
expect "  without quicklook among the features, no --quicklook is needed" exit_and 0 "placement=PASS livechips=PASS"

UNIT_FAIL=workspaces run red --quicklook "$BASE/ql"
expect "a feature broken on purpose: exit 1" [ "$RC" = 1 ]
expect "  the summary marks it FAIL, the rest PASS" [ "$(result)" = "placement=PASS snapgroups=PASS workspaces=FAIL copytext=PASS quicklook=PASS livechips=PASS" ]
expect "  summary.md names the failed check" grep -qF -- "- workspaces: FAIL workspaces: broken on purpose" "$W/results/summary.md"

UNIT_EMPTY=copytext run empty --features copytext,livechips
expect "a feature that gives no checks: exit 1" [ "$RC" = 1 ]
expect "  NO CHECKS for it, only the chosen features run" [ "$(result)" = "copytext=NO CHECKS livechips=PASS" ]
expect "  the others did not run" [ ! -e "$W/results/placement" ]

UNIT_TIMEOUT=placement run timeout --features placement,snapgroups
expect "a session stopped at its time limit after passing checks: exit 1" [ "$RC" = 1 ]
expect "  it is FAIL, the other PASS" [ "$(result)" = "placement=FAIL snapgroups=PASS" ]
expect "  summary.md says why" grep -qF -- "- placement: FAIL the session did not run to the end (scenario rc=0, session rc=124)" "$W/results/summary.md"

UNIT_RUNNER_FAIL=snapgroups run runnerfail --features placement,snapgroups
expect "a session runner that fails: exit 1, that feature FAIL" exit_and 1 "placement=PASS snapgroups=FAIL"

UNIT_DUMP=livechips run dump --features livechips
expect "a core dump from the session: exit 1, FAIL" exit_and 1 "livechips=FAIL"
expect "  summary.md names it" grep -qF -- "- livechips: FAIL 1 core dump(s) from the session" "$W/results/summary.md"

# Relative paths, as the documented command gives them, from the caller's directory.
W=$BASE/relative
RC=0
(cd "$BASE" && bash "$HERE/run.sh" --stage stage --quicklook ql --work relative --name unit --runner ./runner.sh \
  --features quicklook >"$BASE/relative.log" 2>&1) || RC=$?
expect "relative --stage, --quicklook and --runner: exit 0" [ "$RC" = 0 ]
expect "  Quick Look's seed has its install" has quicklook ./.local/bin/plasma-fusion-quicklook

RC=0; bash "$HERE/run.sh" --stage >"$BASE/novalue.log" 2>&1 || RC=$?
expect "an option without its value: exit 2" [ "$RC" = 2 ]
expect "  saying so" grep -qx -- "--stage needs a value" "$BASE/novalue.log"
expect "--help prints the usage only" help_is_usage
# The lanes keep their own results: without --work, the test host's run and a container's land in
# different directories, and the second does not delete the first.
DEF=$(cd "$HERE/../../.." && pwd)/build/tests/depth
rm -rf "$DEF/host" "$DEF/container-localhost_unit_beta"
bash "$HERE/run.sh" --stage "$BASE/stage" --name unit --runner "$BASE/runner.sh" --features placement >"$BASE/lane1.log" 2>&1 || true
bash "$HERE/run.sh" --stage "$BASE/stage" --name unit --runner "$BASE/runner.sh" --features placement \
  --image localhost/unit:beta >"$BASE/lane2.log" 2>&1 || true
both_lanes() { [ -f "$DEF/host/results/summary.json" ] && [ -f "$DEF/container-localhost_unit_beta/results/summary.json" ]; }
expect "  two lanes without --work: each keeps its own summary" both_lanes
rm -rf "$DEF/host" "$DEF/container-localhost_unit_beta"

run unknown --features nosuch
expect "an unknown feature: exit 2" [ "$RC" = 2 ]
run pattern --features '[p]lacement'
expect "  a name that only matches as a pattern ([p]lacement): exit 2, nothing run" nothing_run 2
run pattern2 --features 'place.ent'
expect "  and place.ent: exit 2, nothing run" nothing_run 2
run emptylist --features ""
expect "an empty feature list: exit 2 (nothing tested is no pass)" [ "$RC" = 2 ]

echo "depth run-unit: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
