#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The optional KWin backport's session check (packaging/patches/kwin, docs/parts/ci.md
# "kwin-backport"): the placement memory's session scenarios in two Plasma test containers
# (tools/vsession/cvsession.sh), one with Fedora's KWin and one with the rebuilt packages, and one
# summary. On the backport a late tile-sized commit must leave the memory alone; on stock KWin that
# check is informational, so the stock lane shows that the scenarios themselves still work there.
#
#   run.sh --rpms DIR [--stage DIR] [--image IMAGE] [--work DIR] [--no-gpu] [--coredumps]
#
#   --rpms DIR     packaging/patches/kwin/build.sh's output (the RPMs and SHA256SUMS)
#   --stage DIR    built HOME tree (tools/build.sh output; default <repo>/stage/home)
#   --image IMAGE  the stock test image (default localhost/plasma-fusion-test:f44-6.7.5). When it is
#                  missing it is built: the build image IMAGE-build from tools/container/Containerfile
#                  with the Plasma version of --rpms and Fedora's current Qt, then
#                  tools/container/test/build.sh. The backport image IMAGE-pf1 is built afresh from it
#                  and --rpms on every run (tools/container/test/backport.Containerfile).
#   --work DIR     seeds, image logs, session output and results (default <repo>/build/tests/kwin-backport)
#   --no-gpu       sessions without the host's render node (cvsession.sh PFV_DRI=0, so without
#                  screenshots): GitHub's runners have none
#   --coredumps    every core dump the host's journal recorded during the sessions fails the run
#                  (results/coredumps.json, coredumpctl): only on a machine that runs nothing else,
#                  such as a CI runner
#
# Results: WORK/results/<lane>-<scenario>/ (checks.txt, scenario.log, the session's logs),
# images.txt (each lane image's kwin package), image-*.log, summary.md and summary.json; the rules
# are verdict.py's. Exit status: 0 every run passed, 1 one did not (an image that did not build
# fails its lane's runs), 2 setup error.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
# shellcheck source=tools/tests/lib/common.sh
source "$HERE/../lib/common.sh"

# scenario|path (from the repository root)|size|timeout|property|session variables: property means
# the scenario reports whether KWin has Window.requestedGeometry, which must match the lane; the
# variables (PFV_*, space-separated) go to cvsession.sh. The placement scenario runs with Xwayland
# so its X11 step (a window maximized and closed through Xwayland) is not skipped.
SCENARIOS=(
  "pending|packages/kwin/tests/vsession/scenario-placement-pending.sh|1440x900|360|property|"
  "placement|packages/kwin/tests/vsession/scenario-placement.sh|1440x900|420||PFV_XWAYLAND=1"
)
RPMS=''; STAGE=$ROOT/stage/home; IMAGE=localhost/plasma-fusion-test:f44-6.7.5
WORK=$ROOT/build/tests/kwin-backport; DRI=1; DUMPS=()
while [ $# -gt 0 ]; do
  case "$1" in
    --rpms|--stage|--image|--work)
      [ $# -ge 2 ] || { echo "$1 needs a value" >&2; exit 2; } ;;
  esac
  case "$1" in
    --rpms) RPMS=$2; shift 2 ;;
    --stage) STAGE=$2; shift 2 ;;
    --image) IMAGE=$2; shift 2 ;;
    --work) WORK=$2; shift 2 ;;
    --no-gpu) DRI=0; shift ;;
    --coredumps) DUMPS=(--coredumps); shift ;;
    -h|--help) sed -n '2,/^set -euo pipefail$/p' "$0" | sed '$d'; exit 0 ;;
    *) echo "unknown option $1" >&2; exit 2 ;;
  esac
done
[ -n "$RPMS" ] || { echo "--rpms DIR is required (packaging/patches/kwin/build.sh's output)" >&2; exit 2; }
RPMS=$(realpath -e -- "$RPMS") && [ -f "$RPMS/SHA256SUMS" ] || { echo "no SHA256SUMS in $RPMS" >&2; exit 2; }
(cd "$RPMS" && sha256sum --quiet -c SHA256SUMS) || { echo "the RPMs in $RPMS do not match SHA256SUMS" >&2; exit 2; }
# The build's kwin package, named as rpmbuild names its file: NAME-VERSION-RELEASE.ARCH.rpm.
mapfile -t built < <(cd "$RPMS" && find . -maxdepth 1 -name 'kwin-[0-9]*.rpm' ! -name '*.src.rpm' -printf '%f\n')
[ ${#built[@]} = 1 ] || { echo "expected one kwin binary package in $RPMS, found ${#built[@]}" >&2; exit 2; }
WANT=${built[0]%.rpm}
[[ $WANT =~ ^kwin-([0-9.]+)-[0-9]+\.fc[0-9]+\.pf1\.[a-z0-9_]+$ ]] || { echo "not a backport build: $WANT" >&2; exit 2; }
VERSION=${BASH_REMATCH[1]}
STAGE=$(realpath -m -- "$STAGE")
[ -d "$STAGE/.local/share/plasma" ] || { echo "no built HOME tree at $STAGE (run tools/build.sh)" >&2; exit 2; }
BACKPORT=$IMAGE-pf1
mkdir -p "$WORK" || exit 2
WORK=$(cd "$WORK" && pwd)
RES=$WORK/results
# One run per work tree, and no container session of the same name (cvsession.sh: pfv68-NAME).
exec {worklock}>"$WORK/.run.lock"
flock -n "$worklock" || { echo "another run uses $WORK (choose another --work)" >&2; exit 2; }
running=$(podman ps --format '{{.Names}}') || { echo "podman did not answer" >&2; exit 2; }
if grep -q '^pfv68-kb-' <<<"$running"; then
  echo "a kwin-backport container session is running (pfv68-kb-*)" >&2
  exit 2
fi
# cvsession.sh hands the results back to this user; a tree left by an older cvsession.sh can still
# be owned by subordinate ids, which only podman's user namespace can remove.
clean_tree() {
  rm -rf -- "$@" 2>/dev/null && return 0
  podman unshare rm -rf -- "$@" 2>/dev/null
  local d
  for d in "$@"; do
    [ ! -e "$d" ] || { echo "cannot remove $d" >&2; return 1; }
  done
}
clean_tree "$RES" "$WORK/vsession-out" "$WORK/seed" "$WORK/backport-ctx" || exit 2
mkdir -p "$RES"
make_seed "$STAGE" "$ROOT/tools" "$WORK/seed" || { echo "the seed failed" >&2; exit 2; }

# ---- the images
image_ok=1
if ! podman image exists "$IMAGE"; then
  base=$IMAGE-build
  echo "== building $base and $IMAGE (Plasma $VERSION, Fedora's current Qt)"
  # tools/container/test/build.sh assembles its context below <repo>/build.
  mkdir -p "$ROOT/build"
  if ! podman build --build-arg "PLASMA=$VERSION*" --build-arg QT=6 -t "$base" "$ROOT/tools/container" \
      >"$RES/image-build.log" 2>&1 ||
    ! "$ROOT/tools/container/test/build.sh" "$base" "$IMAGE" >"$RES/image-test.log" 2>&1; then
    echo "the stock test image did not build (results/image-build.log, image-test.log)"
    image_ok=0
  fi
fi
# Never an earlier run's backport image: when this build fails, its lane fails.
podman rmi -f "$BACKPORT" >/dev/null 2>&1 || true
if [ "$image_ok" = 1 ]; then
  echo "== building $BACKPORT from $IMAGE and $RPMS"
  mkdir -p "$WORK/backport-ctx/rpms"
  cp -- "$RPMS"/*.rpm "$RPMS/SHA256SUMS" "$WORK/backport-ctx/rpms/"
  podman build --build-arg "BASE=$IMAGE" -t "$BACKPORT" -f "$ROOT/tools/container/test/backport.Containerfile" \
    "$WORK/backport-ctx" >"$RES/image-backport.log" 2>&1 ||
    echo "the backport image did not build: the README's install command failed (results/image-backport.log)"
fi
: >"$RES/images.txt"
for lane in stock backport; do
  img=$IMAGE; [ "$lane" = stock ] || img=$BACKPORT
  if podman image exists "$img"; then
    printf '%s %s\n' "$lane" "$(podman run --rm --network=none "$img" rpm -q kwin || true)" >>"$RES/images.txt"
    podman run --rm --network=none "$img" rpm -q kwin kwin-common kwin-libs kwin-devel >"$RES/packages-$lane.txt" 2>&1 || true
  fi
done
cat "$RES/images.txt"

# ---- the sessions, one after the other
cd "$WORK"
T0=$(date +%s)
runs=()
for lane in stock backport; do
  img=$IMAGE; [ "$lane" = stock ] || img=$BACKPORT
  for row in "${SCENARIOS[@]}"; do
    IFS='|' read -r id scenario size tmo prop vars <<<"$row"
    read -r -a session_env <<<"$vars"
    runs+=("$lane:$id${prop:+:$prop}")
    n=kb-$lane-$id
    mkdir -p "$RES/$lane-$id"
    if ! podman image exists "$img"; then
      echo "no image $img" >"$RES/$lane-$id/runner-failed"
      continue
    fi
    echo "== $lane-$id ($(date +%T)): $scenario"
    ran=0
    env PFV_IMAGE="$img" PFV_DRI="$DRI" "${session_env[@]}" bash "$ROOT/tools/vsession/cvsession.sh" "$n" \
      "$ROOT/$scenario" "$WORK/seed" "$size" "$tmo" >"$RES/cvsession-$lane-$id.log" 2>&1 || ran=$?
    if [ -d "vsession-out/$n" ]; then
      rm -rf "${RES:?}/$lane-$id"; mv "vsession-out/$n" "$RES/$lane-$id"
      # Results are regular files: the held client's command FIFOs stay behind, and an upload that
      # opened one for reading would wait for a writer that never comes.
      find "$RES/$lane-$id" \( -type p -o -type s \) -delete
    fi
    [ "$ran" = 0 ] || echo "$ran" >"$RES/$lane-$id/runner-failed"
    echo "   $lane-$id done ($(date +%T))"
  done
done

if [ ${#DUMPS[@]} -gt 0 ]; then
  # coredumpctl exits 1 both for an empty list and for a journal it cannot read: only its own
  # "No coredumps found." means none (anything else leaves no report, which fails).
  dumps_rc=0
  dumps_err=$(coredumpctl --no-pager --since "@$T0" --json=short list 2>&1 >"$RES/coredumps.raw") || dumps_rc=$?
  if [ "$dumps_rc" = 0 ]; then
    mv "$RES/coredumps.raw" "$RES/coredumps.json"
  elif [ "$dumps_rc" = 1 ] && [ "$dumps_err" = "No coredumps found." ] && [ ! -s "$RES/coredumps.raw" ]; then
    echo '[]' >"$RES/coredumps.json"
  else
    printf 'coredumpctl failed (%s): %s\n' "$dumps_rc" "$dumps_err" | tee "$RES/coredumps.error"
  fi
  rm -f "$RES/coredumps.raw"
fi
rc=0
python3 -I "$HERE/verdict.py" "${DUMPS[@]}" "$RES" "$WANT" "${runs[@]}" || rc=$?
echo "results: $RES (summary.md, summary.json, <lane>-<scenario>/checks.txt)"
exit "$rc"
