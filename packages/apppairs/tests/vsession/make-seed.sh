#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Seed HOME for the saved app pairs session (scenario-apppairs.sh; test tooling, not installed).
#
#   make-seed.sh STAGE_HOME NAV_STAGE SEED_DIR VSESSION_NAME
#
# STAGE_HOME is a tools/build.sh output (all parts), copied to SEED/pf-stage and applied inside the
# session with tools/device/fusion-config.sh --install; the repository's tools/ go to SEED/pf-tools.
# NAV_STAGE is a DESTDIR install of packages/navigation-cpp built against the test device's KWin
# (cmake --install, as tools/container-build.sh stages it): its effect package goes to the session's
# ~/.local/share/kwin/effects (KWin prefers it to a system package's) and its QML module to
# SEED/pf-qml, which QML_IMPORT_PATH (SEED/.config/pfv-env) puts before the system's; nothing is
# installed system-wide. PFV_BASE (default /var/tmp, as tools/vsession/remote.sh) is where the
# session HOME lives on the test device; QML_IMPORT_PATH must name it literally.
set -euo pipefail
STAGE=${1:?stage home}; NAV=${2:?navigation stage}; SEED=${3:?seed dir}; NAME=${4:?vsession name}
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../../.." && pwd)
effect=$(find "$NAV" -type d -path '*/kwin/effects/plasmafusion_navigation' | head -n 1)
module=$(find "$NAV" -type d -path '*/qml/org/plasmafusion/navigation' | head -n 1)
[ -n "$effect" ] && [ -n "$module" ] || { echo "make-seed: no navigation effect or module in $NAV" >&2; exit 1; }
rm -rf "$SEED"
mkdir -p "$SEED/.config" "$SEED/.local/share/kwin/effects" "$SEED/pf-qml/org/plasmafusion"
rsync -a "$STAGE/" "$SEED/pf-stage/"
rsync -a --exclude __pycache__ "$ROOT/tools/" "$SEED/pf-tools/"
rsync -a "$effect/" "$SEED/.local/share/kwin/effects/plasmafusion_navigation/"
rsync -a "$module/" "$SEED/pf-qml/org/plasmafusion/navigation/"
printf 'QML_IMPORT_PATH=%s/pfv-%s/home/pf-qml\n' "${PFV_BASE:-/var/tmp}" "$NAME" >"$SEED/.config/pfv-env"
echo "seed: $SEED"
