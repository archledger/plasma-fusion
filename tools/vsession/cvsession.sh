#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Run a tools/vsession scenario inside a Plasma test image (tools/container/test) instead of on the
# ThinkPad: a fresh container per run, the session as user "test", results in ./vsession-out/NAME.
#   cvsession.sh NAME SCENARIO SEED_DIR [WIDTHxHEIGHT] [TIMEOUT]   (PFV_* as for remote.sh)
# PFV_HOME_DIR=DIR keeps the session HOME in DIR on the laptop (seeded from SEED_DIR only when DIR
# is empty), so a later run (another image: an upgrade) continues with it. PFV_PRE='CMD' runs CMD as
# the session user in that HOME before the session starts (where startplasma runs the login check).
# PFV_IMAGE picks the test image (default: the device's Plasma 6.7.5). The container gets the
# laptop's render node (--device /dev/dri: without a GPU KWin paints in software and its screenshot
# plugin crashes) and CAP_SYS_NICE (kwin_wayland has that file capability; without it the exec
# fails). See docs/parts/containers.md.
set -u
NAME=${1:?name}; SCENARIO=${2:?scenario}; SEED=${3:?seed}; SIZE=${4:-1920x1200}; TMO=${5:-600}
IMAGE=${PFV_IMAGE:-localhost/plasma-fusion-test:f44-6.7.5}
REPO=$(cd "$(dirname "$0")/../.." && pwd)
OUTDIR=$(pwd)/vsession-out/$NAME
podman unshare rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"
OPTS=()
for v in PFV_TABLET PFV_ANIM PFV_FONT_PT PFV_LANGUAGE PFV_SHELL PFV_CWD PFV_KDE_PROFILE PFV_XWAYLAND PFV_LOCK; do
  [ -n "${!v:-}" ] && OPTS+=(-e "$v=${!v}")
done
podman run --rm --name "pfv68-$NAME" --shm-size=1g --cap-add=SYS_NICE --device /dev/dri --group-add keep-groups -e LANG=C.UTF-8 \
  -e "PFV_SCALE=${PFV_SCALE:-1}" -e "PFV_OUTPUTS=${PFV_OUTPUTS:-1}" "${OPTS[@]}" \
  -v "$REPO/tools/vsession:/pfv:ro,z" -v "$(realpath "$SCENARIO"):/scenario.sh:ro,z" \
  -v "$(realpath "$SEED"):/seed:ro,z" -v "$OUTDIR:/out:z" \
  ${PFV_HOME_DIR:+-v "$(realpath "$PFV_HOME_DIR"):/persist:z"} -e "PFV_PRE=${PFV_PRE:-}" \
  "$IMAGE" bash -c '
    set -u
    R=/var/tmp/pfv-'"$NAME"'
    if [ -d /persist ]; then
      [ -n "$(ls -A /persist)" ] || cp -a /seed/. /persist/
      chown -R test:test /persist; mkdir -p "$(dirname "$R")"; ln -s /persist "$R/home" 2>/dev/null || { mkdir -p "$R"; ln -s /persist "$R/home"; }
    else
      mkdir -p "$R/home" && cp -a /seed/. "$R/home/"
    fi
    if [ -n "${PFV_PRE:-}" ]; then
      su test -s /bin/bash -c "cd $R/home && HOME=$R/home XDG_CONFIG_HOME=$R/home/.config XDG_DATA_HOME=$R/home/.local/share XDG_STATE_HOME=$R/home/.local/state $PFV_PRE" > /out/pre.log 2>&1; echo "pre rc=$?" >> /out/pre.log
    fi
    cp /pfv/vsession.sh "$R.vsession.sh"; cp /scenario.sh "$R.scenario.sh"; cp /pfv/pfinput.py "$R.pfinput.py"
    chown -R test:test "$R" "$R".*
    env_opts=$(env | grep -E "^PFV_" | grep -vE "^PFV_(PRE|HOME_DIR)=" | tr "\n" " ")
    su test -s /bin/bash -c "cd /var/tmp && env $env_opts PFV_BASE=/var/tmp PFV_NO_GUARD=1 PFINPUT=$R.pfinput.py bash $R.vsession.sh '"$NAME"' $R.scenario.sh '"$SIZE"' '"$TMO"'"
    rc=$?
    cp -a "$R/out/." /out/ 2>/dev/null
    echo "session rc=$rc" >> /out/container.log
    exit $rc'
echo "results in $OUTDIR (rc $?)"
