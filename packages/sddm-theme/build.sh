#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Stage Plasma Fusion's SDDM theme (packages/sddm-theme/) into a theme directory that sddm-greeter
# runs: `sddm-greeter --test --theme OUT/plasmafusion`. Reproducible: the same tree twice gives
# byte-identical output.
#
#   packages/sddm-theme/build.sh OUT [BACKGROUND]
#
# BACKGROUND is the wallpaper file the theme shows (default:
# /usr/share/plasma-fusion/backgrounds/dusk-ridge-dark-login.png, the Login board's treatment -
# one of tools/system/greeter-apply.sh's three). packaging/install-tree.sh takes the directory as
# its --sddm argument and installs it as share/sddm/themes/plasmafusion.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
OUT=${1:?usage: build.sh OUT [BACKGROUND]}
BACKGROUND=${2:-/usr/share/plasma-fusion/backgrounds/dusk-ridge-dark-login.png}
DEST=$OUT/plasmafusion

rm -rf "$DEST"
mkdir -p "$DEST"

# The theme's files: the QML, the palette and the metadata SDDM reads (docs/THEMING.md).
cp "$HERE/Main.qml" "$HERE/palette.js" "$HERE/LoginCard.qml" "$HERE/UserSwitcher.qml" \
   "$HERE/SessionPill.qml" "$HERE/PowerBar.qml" "$HERE/CircularImage.qml" \
   "$HERE/metadata.desktop" "$DEST/"
python3 -c 'import sys, pathlib; s = pathlib.Path(sys.argv[1]).read_text(); pathlib.Path(sys.argv[2]).write_text(s.replace(sys.argv[3], sys.argv[4]))' "$HERE/theme.conf.in" "$DEST/theme.conf" "@BACKGROUND@" "$BACKGROUND"
cp "$HERE/../../design/previews/Login.webp" "$DEST/preview.webp"

# A stable order and mode, so two builds are byte-identical.
find "$DEST" -type f -exec touch -d '2026-01-01 00:00:00 UTC' {} +
chmod 0644 "$DEST"/*
echo "sddm theme: $DEST"
