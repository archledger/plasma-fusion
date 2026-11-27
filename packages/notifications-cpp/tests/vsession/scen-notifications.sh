#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Notification applet in a private session (tools/vsession; test tooling, not installed). The seed
# names the mode (make-seed.sh): stock runs Plasma's installed applet, copy runs the built copy,
# which the seed puts in front of it through QT_PLUGIN_PATH. Both must behave the same, and that is
# what this scenario checks. Each check is a PASS or FAIL line in $OUT/checks.txt; the scenario
# returns non-zero when one failed. Never run it against a logged-in desktop.
exec 2>&1
set -euo pipefail

# Only inside the harness (tools/vsession), which sources this file in a private session: a
# session bus of its own, and a HOME that holds a seed. Never on a desktop someone is using.
[[ -n "${PFV:-}" && -d "$PFV" && -f "$HOME/pf-notif/mode" ]] || {
    echo "this scenario runs only inside tools/vsession" >&2
    exit 64
}
mode=$(cat "$HOME/pf-notif/mode")
[[ "$mode" == stock || "$mode" == copy ]]

expect() { # LABEL ACTUAL EXPECTED
    if [ "$2" = "$3" ]; then
        echo "PASS $1" >>"$OUT/checks.txt"
    else
        echo "FAIL $1: got '$2', expected '$3'" >>"$OUT/checks.txt"
    fi
}

wait_text() { # PATTERN FILE: at most 6 s
    local pattern=$1 file=$2
    for _ in {1..40}; do
        if grep -Eq -- "$pattern" "$file"; then return 0; fi
        sleep .15
    done
    printf 'No match for %s in %s\n' "$pattern" "$file"
    return 1
}

write_request() {
    printf '%s\n' "$1" >"$HOME/pf-notif-request.next"
    mv "$HOME/pf-notif-request.next" "$HOME/pf-notif-request.json"
}

SENT_ID=
send() { # LABEL [EXTRA JSON MEMBERS]
    local label=$1 extra=${2:-} line
    write_request "{\"op\":\"send\",\"label\":\"$label\",\"replaces\":0$extra}"
    wait_text "\"event\": \"sent\", \"label\": \"$label\"" "$OUT/sender.log"
    line=$(grep -F "\"event\": \"sent\", \"label\": \"$label\"" "$OUT/sender.log" | tail -n 1)
    SENT_ID=$(sed -n 's/.*"id": *\([0-9][0-9]*\).*/\1/p' <<<"$line")
    [[ "$SENT_ID" =~ ^[1-9][0-9]*$ ]]
}

close_notification() {
    write_request "{\"op\":\"close\",\"id\":$1}"
    wait_text "\"event\": \"closed\", \"id\": $1" "$OUT/sender.log"
}

# A document to type in, so that there is an ordinary window in the session.
printf 'previous focus A\n' >"$HOME/pf-notif-app.txt"
kwrite "$HOME/pf-notif-app.txt" >"$OUT/kwrite.log" 2>&1 &
sleep 3

# A fresh session has no panel, and with it no notification applet: add one.
wait_for_name org.kde.plasmashell
evaljs - >"$OUT/panel.txt" <<'JS'
panels().forEach(p => p.remove());
const panel = new Panel;
panel.location = "top";
print("NOTIFICATIONS_APPLET " + panel.addWidget("org.kde.plasma.notifications").id);
JS
grep -q '^NOTIFICATIONS_APPLET ' "$OUT/panel.txt"
wait_for_name org.freedesktop.Notifications

# Which applet plasmashell runs.
pid=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.GetConnectionUnixProcessID org.kde.plasmashell)
expect "the notification server is plasmashell's" \
    "$(qdbus org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.GetConnectionUnixProcessID org.freedesktop.Notifications)" "$pid"
applet_maps=$(awk '$NF ~ /\/org\.kde\.plasma\.notifications\.so$/ {print $NF}' "/proc/$pid/maps" | sort -u)
# Exactly one applet is mapped, and it is the installed one: a file under /usr that belongs to a
# package of plasma-workspace (on Fedora 44, plasma-workspace-libs), not the staged copy nor a
# copy put anywhere else. (An empty map is one blank line, which a count of the lines that are
# not the copy would take for the installed applet.)
stock_applet_mapped() {
    local path count=0 owner
    [[ -n "$applet_maps" ]] || return 1
    while IFS= read -r path; do
        [[ -n "$path" ]] || continue
        [[ "$path" == /usr/* ]] || return 1
        owner=$(rpm -q --qf '%{NAME}' -f "$path" 2>/dev/null || true)
        [[ -z "$owner" || "$owner" == plasma-workspace* ]] || return 1
        count=$((count + 1))
    done <<<"$applet_maps"
    [ "$count" = 1 ]
}

if [[ "$mode" == stock ]]; then
    expect "the installed applet is mapped, not a copy" \
        "$(stock_applet_mapped && echo yes || echo no)" yes
else
    expect "the copy is mapped" "$applet_maps" "$HOME/pf-plugins/plasma/applets/org.kde.plasma.notifications.so"
    expect "the mapped copy is the built one" "$(sha256sum "$applet_maps" | cut -c1-64)" "$(cat "$HOME/pf-notif/plugin.sha256")"
fi
printf '%s\n' "$applet_maps" >"$OUT/mapped-applet.txt"
rpm -q kwin plasma-workspace >"$OUT/packages.txt" 2>/dev/null || true

python3 "$HOME/pf-notif/sender.py" "$HOME/pf-notif-request.json" >"$OUT/sender.log" 2>&1 &
sender=$!
wait_text '"event": "ready"' "$OUT/sender.log"

# A banner without actions that times out tells the application it expired. (One with actions is
# only marked expired, and the application is told nothing.)
send timed-out ',"timeout":2000,"actions":[]'
wait_text "\"event\": \"closed\", \"id\": $SENT_ID, \"reason\": 1" "$OUT/sender.log"
expect "a banner without actions that times out tells the application" \
    "$(grep -c "\"event\": \"closed\", \"id\": $SENT_ID, \"reason\": 1" "$OUT/sender.log" || true)" 1

# A click on a banner with a default action runs that action once and closes it.
send clicked ',"actions":["default","Open"]'
sleep 1.5
shot 01-banner
pfinput 'click 200 125'
wait_text "\"event\": \"action\", \"id\": $SENT_ID, \"key\": \"default\"" "$OUT/sender.log"
wait_text "\"event\": \"closed\", \"id\": $SENT_ID, \"reason\": 3" "$OUT/sender.log"
expect "the default action ran once" "$(grep -c "\"event\": \"action\", \"id\": $SENT_ID," "$OUT/sender.log" || true)" 1

# Closing a notification tells the application.
send closed-by-call
sleep 1.5
close_notification "$SENT_ID"
expect "a closed notification tells the application" \
    "$(grep -c "\"event\": \"closed\", \"id\": $SENT_ID, \"reason\": 3" "$OUT/sender.log" || true)" 1

expect "no script error in the shell log" \
    "$(grep -c -E 'TypeError|ReferenceError|is not a function|Unable to assign' "$OUT/plasmashell.log" || true)" 0

write_request '{"op":"stop"}'
wait "$sender" || true
cat "$OUT/checks.txt"
if grep -q '^FAIL' "$OUT/checks.txt"; then
    return 1
fi
return 0
