#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test tooling (not installed). Build every part into SEED_DIR/pf-stage (the tree
# fusion-config.sh --install copies into the session HOME), plus the device scripts and the
# test helpers in SEED_DIR/pf-tools, and a gtk-3.0/gtk.css with a rule of its own (the install
# must keep it and add only the Plasma Fusion import).
#
#   generators/look-and-feel/tests/make-seed.sh SEED_DIR
#   tools/vsession/remote.sh lf-a generators/look-and-feel/tests/scenario-full.sh SEED_DIR 1440x900 240
#   tools/vsession/remote.sh lf-a generators/look-and-feel/tests/scenario-relogin.sh - 1440x900 240
set -euo pipefail
SEED=${1:?seed dir}
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
HERE=$(cd "$(dirname "$0")" && pwd)
rm -rf "$SEED"
mkdir -p "$SEED/pf-tools" "$SEED/pf-stage" "$SEED/.config/gtk-3.0"
STAGE=$SEED/pf-stage PF_WALLPAPER_SIZES=${PF_WALLPAPER_SIZES:-quick} bash "$ROOT/tools/build.sh" >/dev/null
cp "$ROOT"/tools/device/fusion-config.sh "$ROOT"/tools/device/fusion-restore.sh \
   "$ROOT"/tools/device/lockscreen-enable.sh "$ROOT"/tools/device/lockscreen-disable.sh "$SEED/pf-tools/"
cp "$HERE"/merge-kdedefaults.py "$HERE"/dump-layout.js "$HERE"/session-common.sh "$SEED/pf-tools/"
printf "@import 'colors.css';\n\n/* a rule of the user's own */\nwindow { border-radius: 3px; }\n" >"$SEED/.config/gtk-3.0/gtk.css"
echo "seed: $SEED"
