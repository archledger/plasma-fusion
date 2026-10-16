#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit test of the depth features' check (tools/tests/depth/run.sh) with a stand-in session runner
# (--runner): no test host, no session. The runner records the seed it was given and writes the
# checks a scenario would: every check passing, one feature with a failing check (a red run, as a
# feature broken on purpose), one feature that gives no checks. Checked: the exit status and the
# summary for each, Quick Look skipped without its install, each feature's seed (the HOME tree and
# tools for every one, the live chips' stand-ins and debug rule, Quick Look's install), and a run
# of chosen features only. Test tooling only, not installed.
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

# The stand-in runner: NAME SCENARIO SEED SIZE TIMEOUT, results in ./vsession-out/NAME/.
cat >"$BASE/runner.sh" <<'EOF'
#!/bin/bash
set -eu
name=$1 scenario=$2 seed=$3
out=vsession-out/$name
mkdir -p "$out"
feature=${name#*-}
(cd "$seed" && find . -maxdepth 3 \( -path ./pf-tools/'*' -prune -o -print \) | sort) >"$out/seed.txt"
[ -f "$seed/pf-tools/vsession/remote.sh" ] && echo "./pf-tools/vsession/remote.sh" >>"$out/seed.txt"
cp "$seed/.config/pfv-env" "$out/pfv-env" 2>/dev/null || true
echo "$scenario" >"$out/scenario.txt"
[ "$feature" = "${UNIT_EMPTY:-}" ] && exit 0
{ echo "INFO $feature"; echo "PASS $feature: one"; echo "PASS $feature: two"
  [ "$feature" = "${UNIT_FAIL:-}" ] && echo "FAIL $feature: broken on purpose"
  true; } >"$out/checks.txt"
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
expect "  the others have no Quick Look" lacks placement quicklook

run noql
expect "without --quicklook: exit 0" [ "$RC" = 0 ]
expect "  Quick Look is SKIPPED, the others PASS" [ "$(result)" = "placement=PASS snapgroups=PASS workspaces=PASS copytext=PASS quicklook=SKIPPED livechips=PASS" ]

UNIT_FAIL=workspaces run red --quicklook "$BASE/ql"
expect "a feature broken on purpose: exit 1" [ "$RC" = 1 ]
expect "  the summary marks it FAIL, the rest PASS" [ "$(result)" = "placement=PASS snapgroups=PASS workspaces=FAIL copytext=PASS quicklook=PASS livechips=PASS" ]
expect "  summary.md names the failed check" grep -qF -- "- workspaces: FAIL workspaces: broken on purpose" "$W/results/summary.md"

UNIT_EMPTY=copytext run empty --features copytext,livechips
expect "a feature that gives no checks: exit 1" [ "$RC" = 1 ]
expect "  NO CHECKS for it, only the chosen features run" [ "$(result)" = "copytext=NO CHECKS livechips=PASS" ]
expect "  the others did not run" [ ! -e "$W/results/placement" ]

run unknown --features nosuch
expect "an unknown feature: exit 2" [ "$RC" = 2 ]

echo "depth run-unit: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
