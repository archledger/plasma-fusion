#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Run in a private 1440x900 RPM-seeded copy scenario. Reopen the real KCM on each start.
set -euo pipefail
[[ -n ${PFV:-} && ${XDG_RUNTIME_DIR:-} == "$PFV/run" && -f "$HOME/pf-notif/rpm" ]]
[[ $(cat "$HOME/pf-notif/mode") == copy ]]

check_log=$OUT/checks.txt
: >"$check_log"
accel() { gdbus call --session --timeout 4 --dest org.kde.kglobalaccel "$@"; }
action="['plasmashell', 'focus notification banner', 'plasmashell', 'Focus notification banner']"
key=$((0x04000000 | 0x08000000 | 0x10000000 | 0x01000017))
copy_path=/usr/lib64/libexec/plasma-fusion/qt6/plugins/plasma/applets/org.kde.plasma.notifications.so
stock_path=/usr/lib64/qt6/plugins/plasma/applets/org.kde.plasma.notifications.so

evaljs - >"$OUT/panel.txt" <<'JS'
panels().forEach(p => p.remove());
const panel = new Panel;
panel.location = "top";
print("NOTIFICATIONS_APPLET " + panel.addWidget("org.kde.plasma.notifications").id);
JS
grep -q '^NOTIFICATIONS_APPLET ' "$OUT/panel.txt"
wait_for_name org.freedesktop.Notifications
accel --object-path /kglobalaccel --method org.kde.KGlobalAccel.setForeignShortcutKeys \
    "$action" "[([$key, 0, 0, 0],)]" >"$OUT/bind.txt"
accel --object-path /kglobalaccel --method org.kde.KGlobalAccel.shortcutKeys "$action" >>"$OUT/bind.txt"
grep -Fq "$key" "$OUT/bind.txt"

page() {
    local name=$1 want=$2 pid shell_pid
    shell_pid=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus.GetConnectionUnixProcessID org.kde.plasmashell)
    [[ $shell_pid =~ ^[0-9]+$ ]]
    awk '/\/org\.kde\.plasma\.notifications\.so( \(deleted\))?$/ {
        sub(/^([^[:space:]]+[[:space:]]+){5}/, "")
        print
    }' "/proc/$shell_pid/maps" | sort -u >"$OUT/$name.maps"
    [[ $(cat "$OUT/$name.maps") == "$want" ]]

    QT_LINUX_ACCESSIBILITY_ALWAYS_ON=1 kcmshell6 kcm_keys >"$OUT/kcm-$name.log" 2>&1 &
    pid=$!
    python3 "$HOME/pf-notif/shortcut-page.py" "$pid" search >"$OUT/search-$name.txt" 2>&1
    # The centered KCM on this fixture places its single search result here. The Qt Wayland
    # accessibility delegate can be read but did not activate or report usable screen bounds.
    shot "filtered-$name"
    pfinput 'click 475 305'
    if ! python3 "$HOME/pf-notif/shortcut-page.py" "$pid" bound >"$OUT/page-$name.txt" 2>&1; then
        shot "failed-$name"
        printf 'FAIL Shortcuts %s\n' "$name" >>"$check_log"
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        return 1
    fi
    shot "$name"
    printf 'PASS Shortcuts %s: %s\n' "$name" "$(cat "$OUT/page-$name.txt")" >>"$check_log"
    kill "$pid" 2>/dev/null || true
    wait "$pid" 2>/dev/null || true
}

observe() {
    local script name id row
    script=$(mktemp "$PFV/observe-XXXXXXXX.js")
    name=${script##*/}
    printf 'console.info("%s " + (%s));\n' "$name" "$1" >"$script"
    id=$(busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting loadScript ss \
        "$script" "$name" | awk '{print $2}')
    [[ $id =~ ^[0-9]+$ ]] || return 1
    busctl --user call org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script run >/dev/null || return 1
    for _ in {1..25}; do
        if row=$(grep -Fm1 "$name " "$OUT/kwin.log"); then
            busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting unloadScript s "$name" >/dev/null
            rm -- "$script"
            printf '%s\n' "${row#*"$name "}"
            return 0
        fi
        sleep .1
    done
    return 1
}

wait_observed() {
    local value needle=$1
    shift
    for _ in {1..25}; do
        value=$(observe "$1") || return 1
        [[ $value == "$needle" ]] && return 0
        sleep .2
    done
    printf 'Expected %s, got %s\n' "$needle" "$value" >&2
    return 1
}

chord() {
    local phase=$1 expected=$2 before id after
    local active='workspace.activeWindow?.caption ?? "none"'
    local banners='workspace.windowList().filter(w => w.resourceClass == "org.kde.plasmashell" &&
        w.caption == "plasmashell").length'
    printf 'Dispatch test\n' >"$HOME/focus-target.txt"
    kwrite "$HOME/focus-target.txt" >"$OUT/kwrite-$phase.log" 2>&1 &
    wait_observed true "($active).startsWith('focus-target.txt')"
    before=$(observe "$active")
    id=$(gdbus call --session --timeout 4 --dest org.freedesktop.Notifications \
        --object-path /org/freedesktop/Notifications \
        --method org.freedesktop.Notifications.Notify 'Focus probe' 0 '' \
        'Focus test banner' 'The saved key should only work with the copy.' '[]' '{}' 0)
    wait_observed 1 "$banners"
    pfinput 'key meta+ctrl+alt+pagedown'
    if [[ $expected == inert ]]; then
        sleep .4
        after=$(observe "$active")
        [[ $after == "$before" && $(observe "$banners") == 1 ]]
    else
        wait_observed plasmashell "$active"
        pfinput 'key escape'
        wait_observed 0 "$banners"
    fi
    printf 'PASS saved key %s under %s\n' "$expected" "$phase" >>"$check_log"
    if [[ $expected == inert ]]; then
        [[ $id =~ ^\(uint32\ ([0-9]+),\)$ ]]
        gdbus call --session --timeout 4 --dest org.freedesktop.Notifications \
            --object-path /org/freedesktop/Notifications \
            --method org.freedesktop.Notifications.CloseNotification "${BASH_REMATCH[1]}" >/dev/null
    fi
    [[ $(observe '(() => { const w = workspace.windowList().find(w => w.caption.startsWith("focus-target.txt"));
        if (!w) return false; w.closeWindow(); return true; })()') == true ]]
    wait_observed false 'workspace.windowList().some(w => w.caption.startsWith("focus-target.txt"))'
}

page copy "$copy_path"
export PF_GATE_FAKE_VERSIONS=plasma-workspace=0.0.0
pfv_restart_shell
wait_for_name org.freedesktop.Notifications
page stock "$stock_path"
chord stock inert
unset PF_GATE_FAKE_VERSIONS
pfv_restart_shell
wait_for_name org.freedesktop.Notifications
page reenabled "$copy_path"
chord reenabled effective
