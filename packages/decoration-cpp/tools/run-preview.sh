#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Laptop side: run tests/pfdeco-preview (built by tools/build-remote.sh) on the test device, offscreen,
# under a private D-Bus session, for the dark and light Plasma Fusion colour schemes, over the Main /
# MainLight board renders. Results (PNG scenes + preview-<scheme>.log with PASS/FAIL lines) land in
# OUT_DIR (default build/cx/out/preview). Scratch config lives in ~/.local/state/plasma-fusion/
# decoration-cpp/preview-config-* (PF_REMOTE overrides the directory below HOME, as for build-remote.sh);
# the user's own configuration is never read or written.
#
# PF_SCALES (default 1,1.3333333,1.325) picks the scales; PF_SSH_OPTS as for build-remote.sh. The
# tool runs with LANG=en_US.UTF-8 (the tooltip check expects the English board text).
#
#   packages/decoration-cpp/tools/run-preview.sh [OUT_DIR]
set -euo pipefail
PKG=$(cd "$(dirname "$0")/.." && pwd)
ROOT=$(cd "$PKG/../.." && pwd)
HOST=${PF_HOST:-thinkpad-fedora}
OUT=${1:-$ROOT/build/cx/out/preview}
REMOTE=${PF_REMOTE:-.local/state/plasma-fusion/decoration-cpp}
RENDERS=${PF_RENDERS:-/mnt/archledger-gp/artifacts/plasma-fusion/2026-09-29-design-source/renders}
SCALES=${PF_SCALES:-1,1.3333333,1.325}
read -r -a SSH_OPTS <<<"${PF_SSH_OPTS:--o ConnectTimeout=40}"
RSYNC_E="ssh ${SSH_OPTS[*]}"

ssh -o BatchMode=yes "${SSH_OPTS[@]}" "$HOST" "mkdir -p ~/$REMOTE/fonts ~/$REMOTE/schemes ~/$REMOTE/backdrops"
rsync -a -e "$RSYNC_E" "$ROOT/fonts/manrope/static/" "$HOST:$REMOTE/fonts/"
rsync -a -e "$RSYNC_E" "$ROOT/packages/color-schemes/PlasmaFusionDark.colors" "$ROOT/packages/color-schemes/PlasmaFusionLight.colors" "$HOST:$REMOTE/schemes/"
rsync -a -e "$RSYNC_E" "$RENDERS/desktop-dark-1.png" "$RENDERS/desktop-light-1.png" "$HOST:$REMOTE/backdrops/"

set +e
ssh -o BatchMode=yes "${SSH_OPTS[@]}" "$HOST" "REMOTE=$REMOTE SCALES=$SCALES bash -s" <<'REMOTE_SCRIPT'
set -euo pipefail
R=$HOME/$REMOTE
rm -rf "$R/preview"
mkdir -p "$R/preview"
rc=0
for v in dark:Dark:desktop-dark-1:#1b2031:Light light:Light:desktop-light-1:#ffffff:Dark; do
  IFS=: read -r name scheme backdrop client other <<<"$v"
  cfg=$R/preview-config-$name
  rm -rf "$cfg" "$R/preview-cache-$name"
  mkdir -p "$cfg" "$R/preview-cache-$name"
  cp "$R/schemes/PlasmaFusion$scheme.colors" "$cfg/kdeglobals"
  env -u DISPLAY -u WAYLAND_DISPLAY -u XAUTHORITY -u DBUS_SESSION_BUS_ADDRESS -u LANGUAGE -u LC_ALL -u LC_MESSAGES \
    LANG=en_US.UTF-8 XDG_CONFIG_HOME="$cfg" XDG_CACHE_HOME="$R/preview-cache-$name" QT_QPA_PLATFORM=offscreen \
    timeout 300 nice -n 10 dbus-run-session -- "$R/build/bin/pfdeco-preview" \
      --decoration-plugin "$R/build/bin/org.plasmafusion.decoration.so" --out "$R/preview" --name "$name" \
      --scheme "$R/schemes/PlasmaFusion$scheme.colors" --other-scheme "$R/schemes/PlasmaFusion$other.colors" --fonts "$R/fonts" \
      --backdrop "$R/backdrops/$backdrop.png" --client "$client" --scales "$SCALES" >"$R/preview/preview-$name.log" 2>&1 || rc=1
done
grep -h -E "^(PASS|FAIL|ALL|title font|plugin id|fake)" "$R"/preview/preview-*.log
exit $rc
REMOTE_SCRIPT
status=$?
set -e
mkdir -p "$OUT"
rsync -a --delete -e "$RSYNC_E" "$HOST:$REMOTE/preview/" "$OUT/"
echo "results in $OUT"
exit $status
