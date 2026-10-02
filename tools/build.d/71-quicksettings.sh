#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Plasmoid org.plasmafusion.quicksettings (status pill, quick settings pop-up, notification
# list) into $STAGE/.local/share/plasma/plasmoids/, with copies of the shared QML blocks it uses
# (packages/common/*.qml, tools/build-lib/shared-qml.sh) in contents/ui/components (every file of
# the package imports that folder).
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

ID=org.plasmafusion.quicksettings
SRC=$ROOT/packages/plasmoids/$ID
DEST=$STAGE/.local/share/plasma/plasmoids/$ID

python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$SRC/metadata.json"
bash "$ROOT/tools/build-lib/shared-qml.sh" check "$SRC" quicksettings

rm -rf "$DEST"
mkdir -p "$DEST"
cp -r "$SRC/metadata.json" "$SRC/contents" "$DEST/"
bash "$ROOT/tools/build-lib/shared-qml.sh" install "$SRC" "$DEST/contents/ui/components"
find "$DEST" -type d -exec chmod 0755 {} +
find "$DEST" -type f -exec chmod 0644 {} +
echo "quicksettings: $(find "$DEST" -type f | wc -l) files in ${DEST#"$STAGE"/}"
