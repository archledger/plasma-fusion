#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test tooling (not installed). Seed HOME for a virtual session (tools/vsession/remote.sh) that
# tests the settings module without installing it:
#
#   tests/make-seed.sh STAGE KCM_ROOT SEED NAME [dark|light] [DECO_PLUGIN_DIR]
#
#   STAGE     tools/build.sh output (a HOME tree with every Plasma Fusion part)
#   KCM_ROOT  the unpacked RPM (build-rpm.sh OUTDIR/root)
#   SEED      seed directory to (re)create
#   NAME      the vsession name it will run as (paths in .config/pfv-env are absolute: the
#             session HOME is $PFV_BASE/pfv-NAME/home, PFV_BASE defaulting to /var/tmp as in
#             tools/vsession/vsession.sh)
#   DECO_PLUGIN_DIR  optional: a Qt plugin directory holding org.kde.kdecoration3/<plugin>.so
#
# The session gets QT_PLUGIN_PATH with the module (and the decoration, if given) and
# XDG_DATA_DIRS with the module's data (desktop file, icon).
set -euo pipefail
STAGE=${1:?stage}; KCM=${2:?kcm root}; SEED=${3:?seed}; NAME=${4:?vsession name}; VARIANT=${5:-dark}; DECO=${6:-}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
H=${PFV_BASE:-/var/tmp}/pfv-$NAME/home
rm -rf "$SEED"
mkdir -p "$SEED/.config" "$SEED/pf-kcm"
cp -a "$STAGE" "$SEED/pf-stage"
cp -a "$ROOT/tools" "$SEED/pf-tools"
cp -a "$KCM/." "$SEED/pf-kcm/"
cp -a "$HERE" "$SEED/pf-kcm-tests"
plugins=$H/pf-kcm/usr/lib64/qt6/plugins
if [ -n "$DECO" ]; then
  cp -a "$DECO" "$SEED/pf-deco"
  plugins=$plugins:$H/pf-deco
fi
{
  echo "QT_PLUGIN_PATH=$plugins"
  echo "XDG_DATA_DIRS=$H/pf-kcm/usr/share:/usr/local/share:/usr/share"
} >"$SEED/.config/pfv-env"
echo "VARIANT=$VARIANT" >"$SEED/pf-params.sh"
echo "seed: $SEED ($VARIANT, plugins $plugins)"
