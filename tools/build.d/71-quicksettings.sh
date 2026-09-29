#!/bin/bash
# Plasmoid org.plasmafusion.quicksettings (status pill, quick settings pop-up, notification
# list) into $STAGE/.local/share/plasma/plasmoids/.
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

ID=org.plasmafusion.quicksettings
SRC=$ROOT/packages/plasmoids/$ID
DEST=$STAGE/.local/share/plasma/plasmoids/$ID

python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$SRC/metadata.json"

rm -rf "$DEST"
mkdir -p "$DEST"
cp -r "$SRC/metadata.json" "$SRC/contents" "$DEST/"
find "$DEST" -type d -exec chmod 0755 {} +
find "$DEST" -type f -exec chmod 0644 {} +
echo "quicksettings: $(find "$DEST" -type f | wc -l) files in ${DEST#"$STAGE"/}"
