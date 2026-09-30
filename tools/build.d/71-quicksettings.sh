#!/bin/bash
# Plasmoid org.plasmafusion.quicksettings (status pill, quick settings pop-up, notification
# list) into $STAGE/.local/share/plasma/plasmoids/, with a copy of packages/common/FusionMetrics.qml
# in contents/ui/components (every file of the package imports that folder).
set -euo pipefail
: "${ROOT:?}" "${STAGE:?}"

ID=org.plasmafusion.quicksettings
SRC=$ROOT/packages/plasmoids/$ID
DEST=$STAGE/.local/share/plasma/plasmoids/$ID

python3 -c 'import json, sys; json.load(open(sys.argv[1]))' "$SRC/metadata.json"
[ -z "$(find "$SRC" -name FusionMetrics.qml)" ] || { echo "quicksettings: the package has its own FusionMetrics.qml" >&2; exit 1; }

rm -rf "$DEST"
mkdir -p "$DEST"
cp -r "$SRC/metadata.json" "$SRC/contents" "$DEST/"
install -m 0644 "$ROOT/packages/common/FusionMetrics.qml" "$DEST/contents/ui/components/FusionMetrics.qml"
find "$DEST" -type d -exec chmod 0755 {} +
find "$DEST" -type f -exec chmod 0644 {} +
echo "quicksettings: $(find "$DEST" -type f | wc -l) files in ${DEST#"$STAGE"/}"
