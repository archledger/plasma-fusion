#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The depth features' check (docs/parts/testing.md "Depth features"): the session scenarios of
# the features that set Plasma Fusion apart, against one built HOME tree, in one run with one
# summary. Run it before a Plasma update is let onto the test machines (the plasma-watch issue)
# and before a release tag (docs/RELEASING.md). The features and their scenarios:
#
#   placement   window placement memory     packages/kwin/tests/vsession/scenario-placement.sh
#   snapgroups  snap groups                 packages/kwin/tests/vsession/scenario-snapgroups.sh
#   workspaces  dynamic workspaces          packages/kwin/tests/vsession/scenario-workspaces.sh
#   copytext    copy text from the screen   packages/copytext/tests/vsession/scenario-copytext.sh
#   quicklook   Quick Look                  packages/quicklook-cpp/tests/vsession/scenario-quicklook.sh
#   livechips   live chips                  packages/plasmoids/org.plasmafusion.livechips/tests/vsession/scenario-livechips.sh
#
#   run.sh [--stage DIR] [--quicklook DIR] [--features LIST|all] [--name PREFIX] [--work DIR]
#          [--image IMAGE] [--runner CMD] [--list]
#
#   --stage DIR      built HOME tree (tools/build.sh output; default <repo>/stage/home)
#   --quicklook DIR  Quick Look installed below a prefix (cmake --install BUILD --prefix DIR: bin/,
#                    share/), copied into the quicklook session's ~/.local; without it quicklook is
#                    SKIPPED (a compiled part: tools/build.sh does not build it)
#   --features LIST  feature names, comma-separated (default all)
#   --name PREFIX    session name prefix (default depth; sessions PREFIX-<feature>)
#   --work DIR       seeds, raw session output and results (default <repo>/build/tests/depth)
#   --image IMAGE    run each session in a Plasma test container on this machine instead of the
#                    test host (tools/vsession/cvsession.sh with PFV_IMAGE=IMAGE): the beta lane
#                    (docs/parts/containers.md)
#   --runner CMD     run each session with CMD NAME SCENARIO SEED SIZE TIMEOUT (it leaves its
#                    results in ./vsession-out/NAME/, as remote.sh does) and without the test-host
#                    checks: for the driver's own test (run-unit.sh)
#   --list           print the features and exit
#
# Each session runs in one session slot of build/lead/vslot.sh (tools/tests/lib/common.sh), one
# after the other, on the test host and in a container alike. Results: WORK/results/<feature>/
# (checks.txt, scenario.log, screenshots, logs, coredumps.json), WORK/results/summary.md and
# summary.json. A feature passes when its session ran to the end (scenario rc=0 and session rc=0
# in scenario.log: not stopped at its time limit), every check passed (at least one), and no core
# dump came from its session (on the test host coredumps.json must say so; elsewhere a
# coredumps.json the session left counts). Exit status: 0 every feature run passed, 1 one did not,
# 2 setup error (also an empty --features list).
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
# shellcheck source=tools/tests/lib/common.sh
source "$HERE/../lib/common.sh"

# feature|scenario (from the repository root)|size|timeout (each scenario's own Run: line)
FEATURES=(
  "placement|packages/kwin/tests/vsession/scenario-placement.sh|1440x900|300"
  "snapgroups|packages/kwin/tests/vsession/scenario-snapgroups.sh|1440x900|420"
  "workspaces|packages/kwin/tests/vsession/scenario-workspaces.sh|1440x900|420"
  "copytext|packages/copytext/tests/vsession/scenario-copytext.sh|1440x900|300"
  "quicklook|packages/quicklook-cpp/tests/vsession/scenario-quicklook.sh|1440x900|420"
  "livechips|packages/plasmoids/org.plasmafusion.livechips/tests/vsession/scenario-livechips.sh|1440x900|360"
)
STAGE=$ROOT/stage/home; QUICKLOOK=''; WANT=all; NAME=depth; WORK=$ROOT/build/tests/depth; IMAGE=''; RUNNER=''
while [ $# -gt 0 ]; do
  case "$1" in
    --stage) STAGE=$2; shift 2 ;;
    --quicklook) QUICKLOOK=$2; shift 2 ;;
    --features) WANT=$2; shift 2 ;;
    --name) NAME=$2; shift 2 ;;
    --work) WORK=$2; shift 2 ;;
    --image) IMAGE=$2; shift 2 ;;
    --runner) RUNNER=$2; shift 2 ;;
    --list) printf '%s\n' "${FEATURES[@]}" | cut -d'|' -f1,2 | tr '|' ' '; exit 0 ;;
    -h|--help) sed -n '2,/^set -u/p' "$0" | sed '$d'; exit 0 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
# Paths as given from the caller's directory: the runs below work in WORK.
STAGE=$(realpath -m -- "$STAGE")
[ -z "$QUICKLOOK" ] || QUICKLOOK=$(realpath -m -- "$QUICKLOOK")
[ -z "$RUNNER" ] || [ ! -e "$RUNNER" ] || RUNNER=$(realpath -- "$RUNNER")
[ -d "$STAGE/.local/share/plasma" ] || { echo "no built HOME tree at $STAGE (run tools/build.sh)" >&2; exit 2; }
[ -z "$QUICKLOOK" ] || [ -d "$QUICKLOOK/bin" ] || { echo "no Quick Look install at $QUICKLOOK (no bin/)" >&2; exit 2; }
[[ "$NAME" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || { echo "bad session name $NAME" >&2; exit 2; }
IDS=()
for f in "${FEATURES[@]}"; do IDS+=("${f%%|*}"); done
if [ "$WANT" != all ]; then
  want=(); IFS=, read -r -a want <<<"$WANT" || true
  [ ${#want[@]} -gt 0 ] || { echo "no features chosen (--features is empty)" >&2; exit 2; }
  for id in "${want[@]}"; do
    printf '%s\n' "${IDS[@]}" | grep -qx "$id" || { echo "unknown feature $id (--list)" >&2; exit 2; }
  done
  IDS=("${want[@]}")
fi
mkdir -p "$WORK" || exit 2
WORK=$(cd "$WORK" && pwd)
RES=$WORK/results
rm -rf "$RES" "$WORK/vsession-out" "$WORK/seeds"; mkdir -p "$RES" "$WORK/seeds"
cd "$WORK" || exit 2

# The seed of one feature: the HOME tree at ~/pf-stage and tools/ at ~/pf-tools (make_seed), and
# what the feature's scenario needs besides.
make_feature_seed() {  # FEATURE SEED
  local id=$1 s=$2
  make_seed "$STAGE" "$ROOT/tools" "$s" || return 1
  case $id in
    livechips)
      # The chips' stand-ins (status items, PowerDevil for Keep awake) and the widget's debug
      # output, which the scenario reads.
      mkdir -p "$s/pf-chips" "$s/.config"
      cp "$ROOT/packages/plasmoids/org.plasmafusion.livechips/tests/fake_status_items.py" \
        "$ROOT/packages/plasmoids/org.plasmafusion.quicksettings/tests/mock_power.py" "$s/pf-chips/" || return 1
      printf 'QT_LOGGING_RULES=org.plasmafusion.livechips.debug=true\n' >"$s/.config/pfv-env"
      ;;
    quicklook)
      mkdir -p "$s/.local"
      cp -a "$QUICKLOOK"/. "$s/.local/" || return 1
      ;;
  esac
}

SLOT=()
if [ -z "$RUNNER" ]; then
  # A session slot for every lane (a container's session is a GPU session too).
  slot_prefix one || exit 2
fi
if [ -z "$RUNNER" ] && [ -z "$IMAGE" ]; then
  T0=$(hssh 'date +%s') || { echo "host $HOST not reachable" >&2; exit 2; }
  names=(); for id in "${IDS[@]}"; do names+=("$NAME-$id"); done
  if session_in_use "${names[@]}"; then
    echo "a session named $NAME-<feature> is running on $HOST (or the host did not answer); choose another --name" >&2
    exit 2
  fi
  { echo "start: $(host_state)"; slot_note; } | tee "$RES/host.txt"
  host_packages >"$RES/packages.txt" || true
  trap 'echo "interrupted; cleaning up"; host_cleanup "${names[@]}"; exit 130' INT TERM
fi

run_feature() {  # ID
  local id=$1 row scenario size tmo n seed
  row=$(printf '%s\n' "${FEATURES[@]}" | awk -F'|' -v id="$id" '$1 == id')
  IFS='|' read -r _ scenario size tmo <<<"$row"
  n=$NAME-$id
  seed=$WORK/seeds/$id
  mkdir -p "$RES/$id"
  if [ "$id" = quicklook ] && [ -z "$QUICKLOOK" ]; then
    echo "== $id: SKIPPED (no --quicklook install)"
    echo "SKIPPED" >"$RES/$id/skipped"
    return 0
  fi
  make_feature_seed "$id" "$seed" || { echo "   $id: the seed failed" | tee "$RES/$id/error"; return 0; }
  echo "== $id ($(date +%T)): $scenario"
  local ran=0
  if [ -n "$RUNNER" ]; then
    "$RUNNER" "$n" "$ROOT/$scenario" "$seed" "$size" "$tmo" >"$RES/remote-$id.log" 2>&1 || ran=$?
  elif [ -n "$IMAGE" ]; then
    run_remote "$RES/remote-$id.log" "$n" "${SLOT[@]}" env PFV_IMAGE="$IMAGE" \
      bash "$ROOT/tools/vsession/cvsession.sh" "$n" "$ROOT/$scenario" "$seed" "$size" "$tmo" || ran=$?
  else
    run_remote "$RES/remote-$id.log" "$n" "${SLOT[@]}" \
      bash "$ROOT/tools/vsession/remote.sh" "$n" "$ROOT/$scenario" "$seed" "$size" "$tmo" || ran=$?
  fi
  if [ -d "vsession-out/$n" ]; then
    rm -rf "${RES:?}/$id"; mv "vsession-out/$n" "$RES/$id"
  fi
  mkdir -p "$RES/$id"
  if [ "$ran" != 0 ]; then
    echo "   $id: the session runner failed with $ran (see $RES/remote-$id.log)"
    echo "$ran" >"$RES/$id/runner-failed"
  fi
  if [ -z "$RUNNER" ] && [ -z "$IMAGE" ]; then
    host_cleanup "$n" || true
    # No report (the host could not be asked) counts as a failure in the summary.
    host_coredumps "$T0" "/var/tmp/pfv-$n/run" >"$RES/$id/coredumps.json" || rm -f "$RES/$id/coredumps.json"
  fi
  echo "   $id done ($(date +%T))"
}
for id in "${IDS[@]}"; do
  run_feature "$id"
done
trap - INT TERM
if [ -z "$RUNNER" ] && [ -z "$IMAGE" ]; then
  echo "end: $(host_state)" | tee -a "$RES/host.txt"
fi

# The summary: per feature its PASS and FAIL lines (checks.txt), the session's status
# (scenario.log) and its core dumps (coredumps.json); a feature without any check counts as a
# failure (the session did not get as far as its checks).
rc=0
python3 - "$RES" "${IMAGE:-test host}" "$([ -z "$RUNNER" ] && [ -z "$IMAGE" ] && echo host || echo other)" "${IDS[@]}" <<'PY' || rc=$?
import json, os, sys
res, lane, kind, ids = sys.argv[1], sys.argv[2], sys.argv[3], sys.argv[4:]
rows, bad = [], 0
for i in ids:
    d = os.path.join(res, i)
    if os.path.exists(os.path.join(d, "skipped")):
        rows.append({"feature": i, "result": "SKIPPED", "pass": 0, "fail": 0, "failed": []})
        continue
    lines = []
    if os.path.exists(os.path.join(d, "checks.txt")):
        lines = open(os.path.join(d, "checks.txt"), errors="replace").read().splitlines()
    passed = [l for l in lines if l.startswith("PASS")]
    failed = [l for l in lines if l.startswith("FAIL")]
    # The session ran to the end: the scenario's and the session's status lines say 0.
    log = ""
    if os.path.exists(os.path.join(d, "scenario.log")):
        log = open(os.path.join(d, "scenario.log"), errors="replace").read()
    status = [l for l in log.splitlines() if l.startswith("scenario rc=") or l.startswith("session rc=")]
    ended = "scenario rc=0" in status and "session rc=0" in status
    if os.path.exists(os.path.join(d, "runner-failed")):
        failed.append("FAIL the session runner failed (status %s)" % open(os.path.join(d, "runner-failed")).read().strip())
    elif not ended:
        failed.append("FAIL the session did not run to the end (%s)" % (", ".join(status) or "no status in scenario.log"))
    # Core dumps of its session: on the test host the report must be there.
    dumps_path = os.path.join(d, "coredumps.json")
    try:
        dumps = json.load(open(dumps_path)) if os.path.exists(dumps_path) else ([] if kind != "host" else None)
    except ValueError:
        dumps = None
    if dumps is None:
        failed.append("FAIL no core dump report for the session")
    elif dumps:
        failed.append("FAIL %d core dump(s) from the session" % len(dumps))
    result = "PASS" if passed and not failed else "FAIL" if failed else "NO CHECKS"
    bad += result != "PASS"
    rows.append({"feature": i, "result": result, "pass": len(passed), "fail": len(failed), "failed": failed[:10]})
json.dump({"lane": lane, "features": rows, "ok": bad == 0}, open(os.path.join(res, "summary.json"), "w"), indent=1)
with open(os.path.join(res, "summary.md"), "w") as f:
    f.write("# Depth features (%s)\n\n| Feature | Result | PASS | FAIL |\n|---|---|---|---|\n" % lane)
    for r in rows:
        f.write("| %s | %s | %d | %d |\n" % (r["feature"], r["result"], r["pass"], r["fail"]))
    for r in rows:
        for l in r["failed"]:
            f.write("\n- %s: %s" % (r["feature"], l))
    f.write("\n")
for r in rows:
    print("%-11s %-9s %3d PASS %3d FAIL" % (r["feature"], r["result"], r["pass"], r["fail"]))
sys.exit(0 if bad == 0 else 1)
PY
echo "results: $RES (summary.md, summary.json, <feature>/checks.txt and screenshots)"
exit "$rc"
