#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Seed HOME for a private session that tests the notification applet copy (test tooling, not
# installed).
#
#   make-seed.sh STAGE_DIR SEED_DIR VSESSION_NAME MODE
#
# STAGE_DIR is a `cmake --install` stage of packages/notifications-cpp (DESTDIR). stock seeds no
# plugin, so plasmashell loads the installed applet. Every other mode puts the plugin under
# SEED/pf-plugins/plasma/applets, and QT_PLUGIN_PATH (SEED/.config/pfv-env) puts it in front of
# the stock plugin; nothing is installed system-wide. copy is the control that runs the built copy
# as stock does; the modes of the banner keyboard triage (scen-notifications.sh names them) run it
# with the applet's debug category switched on, where the triage reports its steps.
# PFV_BASE (default /var/tmp, as tools/vsession/remote.sh) is where the session HOME lives on the
# test device; QT_PLUGIN_PATH must name it literally.
set -euo pipefail
STAGE=${1:?stage dir}
SEED=${2:?seed dir}
NAME=${3:?vsession name}
MODE=${4:?stock, copy or a mode of the banner keyboard triage}
case $MODE in
    stock | copy | full | lock-idle | lock-focused | activate | buttons | timer | eligible) ;;
    *)
        echo "usage: $0 STAGE_DIR SEED_DIR VSESSION_NAME stock|copy|full|lock-idle|lock-focused|activate|buttons|timer|eligible" >&2
        exit 64
        ;;
esac
HERE=$(cd "$(dirname "$0")" && pwd)

mapfile -t plugins < <(find "$STAGE" -type f -name org.kde.plasma.notifications.so \
    -path '*/plasma-fusion/qt6/plugins/plasma/applets/*')
if [[ ${#plugins[@]} != 1 ]]; then
    echo "expected one staged plugin under plasma-fusion/qt6/plugins/plasma/applets, found ${#plugins[@]}" >&2
    exit 2
fi

# Only a seed is removed and written again. A directory that holds none (pf-notif) is left alone,
# whatever the argument says.
if [[ -e "$SEED" && ! -d "$SEED/pf-notif" ]]; then
    echo "refusing to replace $SEED: it holds no seed (no pf-notif inside)" >&2
    exit 2
fi
rm -rf "$SEED"
mkdir -p "$SEED/.config" "$SEED/pf-notif"
cp "$HERE/sender.py" "$SEED/pf-notif/sender.py"
if [[ "$MODE" != stock ]]; then
    mkdir -p "$SEED/pf-plugins/plasma/applets"
    cp "${plugins[0]}" "$SEED/pf-plugins/plasma/applets/"
    sha256sum "${plugins[0]}" | cut -c1-64 >"$SEED/pf-notif/plugin.sha256"
    printf 'QT_PLUGIN_PATH=%s/pfv-%s/home/pf-plugins\n' "${PFV_BASE:-/var/tmp}" "$NAME" >"$SEED/.config/pfv-env"
    printf 'QT_LOGGING_RULES=org.kde.plasma.notifications.debug=true\n' >>"$SEED/.config/pfv-env"
fi
printf '%s\n' "$MODE" >"$SEED/pf-notif/mode"
echo "seed: $SEED ($MODE)"
