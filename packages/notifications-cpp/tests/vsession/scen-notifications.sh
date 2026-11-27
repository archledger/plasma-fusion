#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Notification applet in a private session (tools/vsession; test tooling, not installed). The seed
# names the mode (make-seed.sh):
#
#   stock, copy   The control. stock runs Plasma's installed applet, copy the built copy put in
#                 front of it through QT_PLUGIN_PATH. Both run the same checks of stock behaviour,
#                 so a difference between them is the copy's doing. Neither moves focus for the
#                 test chord: the action does not exist in stock, and is unassigned in copy.
#   full          The banner keyboard triage end to end (SPEC-notification-triage.md).
#   lock-idle     With the screen locked while no banner is focused.
#   lock-focused  With the screen locked while a banner is focused. Both need a lock-capable
#                 session (PFV_LOCK=1). Never type a password into that lock screen.
#   activate      Enter on the focused banner does what a click does.
#   buttons       Escape and Return on the controls inside the banner, and the reply field.
#   timer         The banner's timeout is paused while it is focused.
#   eligible      Which banners the shortcut takes, and three cases of its focus.
#
# In the triage modes the test chord is bound to "Focus notification banner" and the applet's
# debug category is on: each step is a line in the shell log, banner triage "<step>". Every check
# is a PASS or FAIL line in $OUT/checks.txt, and the scenario returns non-zero when one failed. A
# step that must succeed stops its mode when it fails, since the checks after it could mean
# nothing. Never run it against a logged-in desktop.
exec 2>&1
set -euo pipefail

# Only inside the harness (tools/vsession), which sources this file in a private session: a
# session bus of its own, and a HOME that holds a seed. Never on a desktop someone is using.
[[ -n "${PFV:-}" && -d "$PFV" && -f "$HOME/pf-notif/mode" ]] || {
    echo "this scenario runs only inside tools/vsession" >&2
    exit 64
}
mode=$(cat "$HOME/pf-notif/mode")
triage_mode() { [[ "$mode" != stock && "$mode" != copy ]]; }

PASS=0 FAILED=0
expect() { # LABEL ACTUAL EXPECTED
    if [[ "$2" == "$3" ]]; then
        PASS=$((PASS + 1))
        echo "PASS $1" >>"$OUT/checks.txt"
    else
        FAILED=$((FAILED + 1))
        echo "FAIL $1: got '$2', expected '$3'" >>"$OUT/checks.txt"
    fi
}
need() { # LABEL COMMAND...: the step must succeed, or the mode stops here
    local label=$1
    shift
    if "$@"; then
        PASS=$((PASS + 1))
        echo "PASS $label" >>"$OUT/checks.txt"
    else
        FAILED=$((FAILED + 1))
        echo "FAIL $label" >>"$OUT/checks.txt"
        return 1
    fi
}

# Each wait reads a file, never a pipe: a grep that stops at its match can close the pipe while
# the writer is still writing, and pipefail would then turn a match into a failure.
wait_text() { # PATTERN FILE [AFTER LINE]: at most 6 s
    local pattern=$1 file=$2 after=${3:-0}
    for _ in {1..40}; do
        if [ "$after" = 0 ]; then
            grep -Eq -- "$pattern" "$file" && return 0
        else
            tail -n +"$((after + 1))" "$file" >"$PFV/since.txt" 2>/dev/null
            grep -Eq -- "$pattern" "$PFV/since.txt" && return 0
        fi
        sleep .15
    done
    return 1
}

# The test applications: instances of sender.py, each with a request file and a log of its own.
# send, replace, close and the receipts work on the selected one. The first serves the whole mode;
# a mode that needs an application to leave the bus starts a second (start_second_sender).
sender_request=$HOME/pf-notif-request.json
sender_log=$OUT/sender.log
use_sender() { # 1 or 2
    if [ "$1" = 1 ]; then
        sender_request=$HOME/pf-notif-request.json sender_log=$OUT/sender.log
    else
        sender_request=$HOME/pf-notif-request-2.json sender_log=$OUT/sender-2.log
    fi
}
write_request() {
    printf '%s\n' "$1" >"$sender_request.next"
    mv "$sender_request.next" "$sender_request"
}

SENT_ID=
send() { # LABEL [EXTRA JSON MEMBERS OF THE REQUEST]
    local label=$1 extra=${2:-} line
    write_request "{\"op\":\"send\",\"label\":\"$label\",\"replaces\":0$extra}"
    wait_text "\"event\": \"sent\", \"label\": \"$label\"" "$sender_log" || return 1
    line=$(grep -F "\"event\": \"sent\", \"label\": \"$label\"" "$sender_log" | tail -n 1)
    SENT_ID=$(sed -n 's/.*"id": *\([0-9][0-9]*\).*/\1/p' <<<"$line")
    [[ "$SENT_ID" =~ ^[1-9][0-9]*$ ]]
}
replace() { # LABEL ID OF THE NOTIFICATION REPLACED [EXTRA]
    local label=$1 id=$2 extra=${3:-} line
    write_request "{\"op\":\"send\",\"label\":\"$label\",\"replaces\":$id$extra}"
    wait_text "\"event\": \"sent\", \"label\": \"$label\"" "$sender_log" || return 1
    line=$(grep -F "\"event\": \"sent\", \"label\": \"$label\"" "$sender_log" | tail -n 1)
    SENT_ID=$(sed -n 's/.*"id": *\([0-9][0-9]*\).*/\1/p' <<<"$line")
}
close_notification() {
    write_request "{\"op\":\"close\",\"id\":$1}"
    wait_text "\"event\": \"closed\", \"id\": $1" "$sender_log"
}
receipts() { # ID: what the test application was told about a notification
    grep -E "\"event\": \"(action|closed|replied)\", \"id\": $1(,|\})" "$sender_log" || true
}
receipt_count() { receipts "$1" | grep -c . || true; }
second_sender=
start_second_sender() { # starts it and selects it; it has no request yet
    rm -f "$HOME/pf-notif-request-2.json"
    python3 "$HOME/pf-notif/sender.py" "$HOME/pf-notif-request-2.json" >"$OUT/sender-2.log" 2>&1 &
    second_sender=$!
    use_sender 2
    wait_text '"event": "ready"' "$sender_log"
}
# Stops the selected test application and waits for it (at most 10 s); kills it if it is still running.
sender_stopped=
stop_sender() {
    local pid=$sender
    [ "$sender_log" != "$OUT/sender-2.log" ] || pid=$second_sender
    write_request '{"op":"stop"}'
    for _ in {1..40}; do
        kill -0 "$pid" 2>/dev/null || break
        sleep .25
    done
    if kill -0 "$pid" 2>/dev/null; then
        kill "$pid" 2>/dev/null || true
        wait "$pid" 2>/dev/null || true
        sender_stopped="no (killed)"
        return 1
    fi
    wait "$pid" 2>/dev/null || true
    sender_stopped=yes
}
# A script error in plasmashell's log: the kinds Qt Quick reports, wherever the file was loaded
# from, and the lines it prints for a file in the applet's resources.
no_script_error() {
    ! grep -q -E 'TypeError|ReferenceError|is not a function|Unable to assign|qrc:.*:[0-9]+: [A-Za-z]*Error' "$OUT/plasmashell.log"
}

# What KWin's script engine sees. Each observation runs a small script that logs one line.
observe() { # JS EXPRESSION: its value
    local nonce id line
    nonce=$RANDOM$RANDOM$RANDOM
    printf 'console.info("PF_NOTIF %s " + (%s));\n' "$nonce" "$1" >"$PFV/observe-$nonce.js"
    id=$(busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting loadScript ss "$PFV/observe-$nonce.js" "observe-$nonce" | awk '{print $2}')
    [[ "$id" =~ ^[0-9]+$ ]] || return 1
    busctl --user call org.kde.KWin "/Scripting/Script$id" org.kde.kwin.Script run >/dev/null || return 1
    wait_text "PF_NOTIF $nonce " "$OUT/kwin.log" || return 1
    line=$(grep -F "PF_NOTIF $nonce " "$OUT/kwin.log" | tail -n 1)
    busctl --user call org.kde.KWin /Scripting org.kde.kwin.Scripting unloadScript s "observe-$nonce" >/dev/null 2>&1 || true
    printf '%s\n' "${line#*PF_NOTIF $nonce }"
}
active() { # EXPECTED FRAGMENT [LABEL]: the caption or the class of the active window contains it
    local expected=$1 label=${2:-} got
    got=$(observe '(workspace.activeWindow ? workspace.activeWindow.caption + "|" + workspace.activeWindow.resourceClass : "none")') || return 1
    printf '%s: %s\n' "${label:-the active window}" "$got" >>"$OUT/active-windows.txt"
    [[ "$got" == *"$expected"* ]]
}
window_count() { # CAPTION
    observe 'workspace.windowList().filter(w => w.caption.indexOf("'"$1"'") === 0 && !w.popupWindow).length'
}
wait_window_count() { # CAPTION NUMBER: at most 6 s
    for _ in {1..40}; do
        [ "$(window_count "$1")" = "$2" ] && return 0
        sleep .15
    done
    return 1
}
activate_window_by_caption() { # CAPTION: KWin makes it the active window, as a click into it would
    observe '(() => { const w = workspace.windowList().find(w => w.caption.indexOf("'"$1"'") === 0 && !w.popupWindow); if (!w) return "none"; workspace.activeWindow = w; return "ok"; })()'
}
close_window_by_caption() { # CAPTION: KWin asks the application to close it
    observe '(() => { const w = workspace.windowList().find(w => w.caption.indexOf("'"$1"'") === 0 && !w.popupWindow); if (!w) return "none"; w.closeWindow(); return "ok"; })()'
}
# The focus ring as the picture shows it (ring.py, the standard library only): the focus colour
# on the frame of the banner's window, one pixel in from each of its four sides, and on none of the
# window's content. The applet reports the window's place and size, its padding and the focus
# colour when the ring appears; the screenshot must already be taken.
ring_check() { # SHOT-NAME
    local geometry
    geometry=$(grep -E 'banner triage "ring-geometry [-0-9 ]+#[0-9a-f]{6}"$' "$OUT/plasmashell.log" | tail -n 1 | sed 's/^.*"ring-geometry //; s/"$//')
    expect "the applet reports where the banner is drawn" "$([ -n "$geometry" ] && echo reported || echo none)" reported
    [ -n "$geometry" ] || return 1
    expect "the focus ring is on the banner's frame and on none of its content" \
        "$(python3 "$HOME/pf-notif/ring.py" "$OUT/$1.png" $geometry)" "on the frame, none in the content"
}
shown_banners() { # A banner is a window of plasmashell with the caption "plasmashell".
    observe 'workspace.windowList().filter(w => w.resourceClass == "org.kde.plasmashell" && w.caption == "plasmashell").length'
}

log_lines() { wc -l <"$OUT/plasmashell.log"; }
triage_count() { grep -c -- "banner triage \"$1" "$OUT/plasmashell.log" || true; }
triage() { # PATTERN (without its closing quote) [AFTER LINE]: a triage step that matches it
    wait_text "banner triage \"$1" "$OUT/plasmashell.log" "${2:-0}"
}
triage_since() { triage "$2" "$1" && echo yes || echo no; } # AFTER LINE, PATTERN

focus_key='key meta+ctrl+alt+pagedown'
focus_action="['plasmashell', 'focus notification banner', 'plasmashell', 'Focus notification banner']"
# How KWin names a banner that is the active window: its caption and its class. A panel is a
# window of plasmashell too, so the class alone would take any of them for the banner.
banner_window='plasmashell|org.kde.plasmashell'
accel() { gdbus call --session --timeout 4 --dest org.kde.kglobalaccel "$@"; }
focus_action_listed() {
    for _ in {1..40}; do
        accel --object-path /component/plasmashell --method org.kde.kglobalaccel.Component.shortcutNames >"$OUT/actions.txt" 2>&1 || true
        grep -Fq 'focus notification banner' "$OUT/actions.txt" && return 0
        sleep .2
    done
    return 1
}
# Binds the test chord (Meta+Ctrl+Alt+PageDown) to the action, as a user would in System Settings.
bind_focus_key() {
    local key
    key=$((0x04000000 | 0x08000000 | 0x10000000 | 0x01000017))
    accel --object-path /kglobalaccel --method org.kde.KGlobalAccel.setForeignShortcutKeys "$focus_action" "[([$key, 0, 0, 0],)]" >"$OUT/binding.txt" 2>&1
    accel --object-path /kglobalaccel --method org.kde.KGlobalAccel.shortcutKeys "$focus_action" >"$OUT/binding.txt" 2>&1
    grep -Fq "$key" "$OUT/binding.txt"
}
# Tab until an item whose type matches PATTERN has the keyboard focus (at most eight presses);
# the applet reports the type of the item where each Tab lands.
focus_with() { # KEY TYPE PATTERN: presses KEY until the focus report matches (at most eight presses)
    local key=$1 wanted=$2 from
    for _ in {1..8}; do
        from=$(log_lines)
        pfinput "$key"
        wait_text 'banner triage "focus-within ' "$OUT/plasmashell.log" "$from" || break
        if triage "focus-within inside=true $wanted" "$from"; then return 0; fi
    done
    return 1
}
tab_to() { focus_with 'key tab' "$1"; }
# The button of an action of the banner. The banner's own buttons (close, configure) are of the
# stock type; an action's button is declared where the actions are, which makes it a type of its
# own, with a second numbered part in its name.
tab_to_action_button() { tab_to 'ToolButton_QMLTYPE_[0-9]+_QML_[0-9]+'; }
tab_to_reply_field() { tab_to 'TextField'; }
tab_back_to_close() { focus_with 'key shift+tab' 'ToolButton_QMLTYPE_[0-9]+"'; }
take_banner() { # [AFTER LINE IS RETURNED IN from]: the shortcut gives the last banner sent (SENT_ID) keyboard focus
    from=$(log_lines)
    pfinput "$focus_key"
    triage "focus-granted $SENT_ID\"" "$from"
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
if ! grep -q '^NOTIFICATIONS_APPLET ' "$OUT/panel.txt"; then
    echo "FAIL the panel got the notification applet" >>"$OUT/checks.txt"
    FAILED=1
fi
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
    expect "the installed applet is mapped, not a copy" "$(stock_applet_mapped && echo yes || echo no)" yes
else
    expect "the copy is mapped" "$applet_maps" "$HOME/pf-plugins/plasma/applets/org.kde.plasma.notifications.so"
    expect "the mapped copy is the built one" "$(sha256sum "$applet_maps" | cut -c1-64)" "$(cat "$HOME/pf-notif/plugin.sha256")"
fi
printf '%s\n' "$applet_maps" >"$OUT/mapped-applet.txt"
rpm -q kwin plasma-workspace >"$OUT/packages.txt" 2>/dev/null || true

python3 "$HOME/pf-notif/sender.py" "$HOME/pf-notif-request.json" >"$OUT/sender.log" 2>&1 &
sender=$!
wait_text '"event": "ready"' "$OUT/sender.log"

if triage_mode; then
    need "\"Focus notification banner\" is listed with the applet's shortcuts" focus_action_listed || true
    need "the test chord is bound to it" bind_focus_key || true
fi

control_mode() {
    local listed keys
    # The focus action: absent from the installed applet, unassigned in the copy.
    if focus_action_listed; then listed=listed; else listed=absent; fi
    if [[ "$mode" == stock ]]; then
        expect "the installed applet has no \"Focus notification banner\" action" "$listed" absent
    else
        expect "the copy lists \"Focus notification banner\" with the applet's shortcuts" "$listed" listed
        keys=$(accel --object-path /kglobalaccel --method org.kde.KGlobalAccel.defaultShortcutKeys "$focus_action" 2>&1)
        # gdbus prints an empty array of shortcuts as "(@a(ai) [],)"; an error would print something else.
        expect "  and it ships unassigned" "$(head -n 1 <<<"$keys")" '(@a(ai) [],)'
    fi

    # A banner without actions that times out tells the application it expired. (One with actions is
    # only marked expired, and the application is told nothing.)
    need "a banner without actions is sent" send timed-out ',"timeout":2000,"actions":[]' || return 1
    timed_out=$SENT_ID
    need "a banner without actions that times out tells the application it expired" \
        wait_text "\"event\": \"closed\", \"id\": $timed_out, \"reason\": 1" "$sender_log" || return 1
    expect "  once" "$(receipt_count "$timed_out")" 1

    # The test chord moves no focus: nothing is bound to it.
    need "a banner with a default action is sent" send unbound ',"actions":["default","Open"]' || return 1
    unbound=$SENT_ID
    sleep 1.5
    need "its arrival moves no focus" active pf-notif-app.txt after-arrival || return 1
    pfinput "$focus_key"
    sleep 1
    expect "the test chord moves no focus" "$(active pf-notif-app.txt after-the-chord && echo yes || echo no)" yes
    expect "  and asks for no banner" "$(triage_count 'focus-requested')" 0
    need "  and the application closes it" close_notification "$unbound" || return 1

    # A click on a banner with a default action runs that action once and closes it. It is the
    # only banner, so the click is on it.
    need "another is sent" send clicked ',"actions":["default","Open"]' || return 1
    clicked=$SENT_ID
    sleep 1.5
    shot 01-banner
    pfinput 'click 200 125'
    need "the click runs the default action" wait_text "\"event\": \"action\", \"id\": $clicked, \"key\": \"default\"" "$sender_log" || return 1
    need "  and closes the notification" wait_text "\"event\": \"closed\", \"id\": $clicked, \"reason\": 3" "$sender_log" || return 1
    expect "  once each" "$(receipt_count "$clicked")" 2

    # Closing a notification tells the application.
    need "a banner is sent to be closed" send closed-by-call || return 1
    by_call=$SENT_ID
    sleep 1.5
    need "the application closes it" close_notification "$by_call" || return 1
    expect "a closed notification tells the application" "$(receipt_count "$by_call")" 1
}

mode_full() {
    # With no banner the shortcut does nothing.
    expect "no banner is shown at first" "$(shown_banners)" 0
    pfinput "$focus_key"
    need "with no banner the shortcut is ignored" triage 'shortcut-ignored-no-banner' || return 1
    expect "  and no banner is asked for" "$(triage_count 'focus-requested')" 0
    need "  and KWrite stays active" active pf-notif-app.txt chord-without-banner || return 1

    # Arrival moves no focus.
    need "a banner is sent" send original ',"actions":["default","Open"]' || return 1
    original=$SENT_ID
    sleep 1.5
    need "the arrival of a banner moves no focus" active pf-notif-app.txt after-arrival || return 1
    shot 01-banner
    expect "one banner is shown" "$(shown_banners)" 1

    # The shortcut gives it keyboard focus; Escape dismisses it through its own expiry.
    need "the shortcut gives the banner keyboard focus" take_banner || return 1
    need "  and KWrite is no longer the active window" active "$banner_window" focused-banner || return 1
    # The compositor draws the ring a moment after the focus arrives.
    sleep .3
    shot 02-focused
    ring_check 02-focused
    pfinput 'key escape'
    need "Escape dismisses the focused banner" triage "dismissed-by-escape $original\"" "$from" || return 1
    sleep .6
    need "  and KWrite is active again" active pf-notif-app.txt restored-after-escape || return 1
    shot 03-returned
    expect "  the banner is gone" "$(shown_banners)" 0
    expect "  and the application is told nothing (a banner with actions is only marked expired)" "$(receipt_count "$original")" 0

    # A replacement while focused gives the previous window its focus back.
    need "a banner is sent" send replace-me ',"actions":["default","Open"]' || return 1
    replaced=$SENT_ID
    sleep 1
    need "the shortcut takes it" take_banner || return 1
    granted=$(log_lines)
    need "the application replaces it under the same id" replace replacement "$replaced" ',"actions":["default","Open"]' || return 1
    need "a replacement ends the interaction" triage 'ended replaced' "$granted" || return 1
    need "  and asks for the previous window" triage 'focus-restore-requested' "$granted" || return 1
    sleep .6
    need "  and KWrite is active again" active pf-notif-app.txt after-replacement || return 1
    expect "  and does not take the replacement banner" "$(triage_since "$granted" "focus-granted $replaced\"")" no
    pfinput 'key escape'
    sleep .5
    expect "a later Escape in KWrite dismisses nothing" "$(triage_count 'dismissed-by-escape')" 1
    expect "  and the application is told nothing" "$(receipt_count "$replaced")" 0
    need "the application closes the replacement" close_notification "$replaced" || return 1

    # A replacement that keeps the summary and the text is a replacement too.
    need "a banner is sent" send kept ',"actions":["default","Open"]' || return 1
    kept=$SENT_ID
    sleep 1.5
    need "the shortcut takes it" take_banner || return 1
    granted=$(log_lines)
    need "the application replaces it with the same summary and text" replace kept-again "$kept" ',"timeout":30000' || return 1
    need "a replacement that keeps the summary ends the interaction" triage 'ended replaced' "$granted" || return 1
    need "  and asks for the previous window" triage 'focus-restore-requested' "$granted" || return 1
    sleep .6
    need "  and KWrite is active again" active pf-notif-app.txt after-same-summary || return 1
    need "  and the application closes it" close_notification "$kept" || return 1

    # The user moves the focus away: the interaction ends and nothing is dismissed.
    sleep .8
    pfinput 'click 600 400'
    sleep .4
    need "a banner is sent" send focus-loss ',"actions":["default","Open"]' || return 1
    lost=$SENT_ID
    sleep 1
    need "the shortcut takes it" take_banner || return 1
    pfinput 'click 600 400'
    need "a click into KWrite ends the interaction" triage 'ended lost' "$from" || return 1
    need "  and KWrite is active" active pf-notif-app.txt deliberate-switch || return 1
    pfinput 'key escape'
    sleep .5
    expect "a later Escape in KWrite dismisses nothing" "$(triage_count 'dismissed-by-escape')" 1
    expect "  the banner is still shown" "$(shown_banners)" 1
    need "  and the application can still close it" close_notification "$lost" || return 1

    # An application with two windows is one row in the task manager: the window that had the
    # keyboard focus is still the one that gets it back.
    printf 'previous focus B\n' >"$HOME/pf-notif-app-b.txt"
    kwrite "$HOME/pf-notif-app-b.txt" >"$OUT/kwrite-b.log" 2>&1 &
    sleep 3
    pfinput 'move 700 700' 'click 600 400'
    need "the second document's window is active" active pf-notif-app-b.txt second-document || return 1
    need "a banner is sent" send grouped ',"actions":["default","Open"]' || return 1
    grouped=$SENT_ID
    sleep 1.5
    need "the shortcut takes it" take_banner || return 1
    granted=$(log_lines)
    need "the application replaces it under the same id" replace replaced "$grouped" ',"actions":["default","Open"]' || return 1
    need "a replacement ends the interaction" triage 'ended replaced' "$granted" || return 1
    need "  and asks for the previous window" triage 'focus-restore-requested' "$granted" || return 1
    sleep .6
    need "  and that document is active again" active pf-notif-app-b.txt after-grouped || return 1
    need "  and the application closes it" close_notification "$grouped" || return 1
}

mode_lock_idle() {
    local before
    [[ ${PFV_LOCK:-0} == 1 ]] || { expect "a lock-capable session (PFV_LOCK=1)" no yes; return 1; }
    # That the chord dispatches in this session at all: with no banner, the applet says so.
    from=$(log_lines)
    pfinput "$focus_key"
    need "before the lock the chord reaches the applet" triage 'shortcut-ignored-no-banner' "$from" || return 1
    need "  and KWrite stays active" active pf-notif-app.txt before-lock-chord || return 1
    need "a banner is sent" send lock-idle ',"actions":["default","Open"]' || return 1
    sleep 1.5
    need "before the lock KWrite is active" active pf-notif-app.txt before-lock || return 1
    pfv_lock
    need "the screen is locked" grep -qx true <<<"$(qdbus org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.GetActive)" || return 1
    sleep .6
    before=$(triage_count 'triage-available')
    pfinput "$focus_key"
    sleep 1.2
    expect "locked with no banner focused: the shortcut is not dispatched" "$(triage_count 'triage-available')" "$before"
    expect "  and no banner is asked for" "$(triage_count 'focus-requested')" 0
    pfinput 'key escape'
    sleep 1.2
    expect "  and a later Escape dismisses nothing" "$(triage_count 'dismissed-by-escape')" 0
    shot 02-locked
}

mode_lock_focused() {
    [[ ${PFV_LOCK:-0} == 1 ]] || { expect "a lock-capable session (PFV_LOCK=1)" no yes; return 1; }
    need "a banner is sent" send lock-focused ',"actions":["default","Open"]' || return 1
    sleep 1.5
    need "the shortcut gives the banner keyboard focus" take_banner || return 1
    pfv_lock
    need "the screen is locked" grep -qx true <<<"$(qdbus org.freedesktop.ScreenSaver /ScreenSaver org.freedesktop.ScreenSaver.GetActive)" || return 1
    need "locking ends the interaction" triage 'ended lost' "$from" || return 1
    pfinput 'key escape'
    sleep 1.2
    expect "a later Escape dismisses nothing" "$(triage_count 'dismissed-by-escape')" 0
    shot 02-locked
}

mode_activate() {
    # Enter does what a click does: for each shape of banner, what a click tells the application
    # and what Enter tells it are the same.
    local clicked entered plain held
    need "a banner with a default action is sent" send click-default ',"actions":["default","Open"]' || return 1
    clicked=$SENT_ID
    sleep 1.5
    pfinput 'click 200 125'
    need "a click on it runs the default action and closes it" \
        wait_text "\"event\": \"closed\", \"id\": $clicked, \"reason\": 3" "$sender_log" || return 1
    need "another is sent" send enter-default ',"actions":["default","Open"]' || return 1
    entered=$SENT_ID
    sleep 1.5
    need "the shortcut gives it keyboard focus" take_banner || return 1
    pfinput 'key return'
    need "Enter runs the default action" triage "activated-by-enter $entered\"" "$from" || return 1
    need "  and closes the notification" \
        wait_text "\"event\": \"closed\", \"id\": $entered, \"reason\": 3" "$sender_log" || return 1
    need "  and KWrite is active again" active pf-notif-app.txt after-enter-default || return 1
    shot 01-after-enter
    expect "Enter tells the application what a click does" "$(receipts "$entered" | sed "s/\"id\": $entered/\"id\": N/" | sort)" "$(receipts "$clicked" | sed "s/\"id\": $clicked/\"id\": N/" | sort)"
    expect "  in two receipts, once each" "$(receipt_count "$entered")" 2

    # No default action and no window of the application: nothing, and the banner stays.
    need "a banner without a default action is sent" send enter-plain ',"actions":["open","Open"],"entry":""' || return 1
    plain=$SENT_ID
    sleep 1.5
    need "the shortcut gives it keyboard focus" take_banner || return 1
    pfinput 'key return'
    sleep 1
    expect "Enter without a default action activates nothing" "$(triage_count 'activated-by-enter')" 1
    expect "  the application is told nothing" "$(receipt_count "$plain")" 0
    expect "  the banner is still shown" "$(shown_banners)" 1
    need "  and still has keyboard focus" active "$banner_window" still-focused || return 1
    pfinput 'key escape'
    need "  and Escape still dismisses it" triage "dismissed-by-escape $plain\"" "$from" || return 1

    # No default action, with a window of the application open. What stock does for a click here
    # is its own; Enter must leave the application and the banner in the same state.
    need "a banner without a default action is sent" send click-fallback ',"actions":["open","Open"]' || return 1
    clicked=$SENT_ID
    sleep 1.5
    pfinput 'click 200 125'
    sleep 1
    expect "a click on it tells the application nothing" "$(receipt_count "$clicked")" 0
    expect "  and leaves it shown" "$(shown_banners)" 1
    need "another is sent" send enter-fallback ',"actions":["open","Open"]' || return 1
    entered=$SENT_ID
    sleep 1.5
    need "the shortcut takes it" take_banner || return 1
    pfinput 'key return'
    sleep 1.5
    expect "Enter tells the application what a click does" "$(receipt_count "$entered")" "$(receipt_count "$clicked")"
    expect "  and leaves both banners, as the click left its" "$(shown_banners)" 2
    pfinput 'key escape'
    need "  Escape dismisses it" triage "dismissed-by-escape $entered\"" "$from" || return 1
    sleep .6
    need "  with KWrite active again" active pf-notif-app.txt after-fallback || return 1
    # The banner that was clicked stays shown; it is closed so that the next count starts clean.
    need "  and the application closes the banner that was clicked" close_notification "$clicked" || return 1

    # A held Return activates once. What the held key types afterwards lands in KWrite, as with
    # any focus change, so the document is saved before the session ends.
    need "a banner with a default action is sent" send held ',"actions":["default","Open"]' || return 1
    held=$SENT_ID
    sleep 1.5
    need "the shortcut takes it" take_banner || return 1
    pfinput 'keydown return' 'sleep 1.2' 'keyup return'
    need "a held Return activates" triage "activated-by-enter $held\"" "$from" || return 1
    # The activation reaches the application once the key is released and the compositor has
    # given the activation token, so the receipt is waited for, not timed.
    need "  and the application is told" wait_text "\"event\": \"action\", \"id\": $held, \"key\": \"default\"" "$sender_log" || return 1
    need "  and the notification is closed for it" wait_text "\"event\": \"closed\", \"id\": $held, \"reason\": 3" "$sender_log" || return 1
    expect "  once" "$(grep -c "\"event\": \"action\", \"id\": $held," "$sender_log" || true)" 1
    need "  and KWrite is active again" active pf-notif-app.txt after-held || return 1
    pfinput 'key ctrl+s'
    sleep 1
    need "the test document is saved, so the session can end quietly" active pf-notif-app.txt after-save || return 1

    # A resident banner stays after its default action, and keeps the keyboard focus. A held
    # Return acts once while it stays (the case above cannot show that: its banner closes with the
    # first activation), each separate press acts again, and Escape still dismisses.
    need "a resident banner with a default action is sent" send staying ',"actions":["default","Open"],"hints":{"resident":true}' || return 1
    staying=$SENT_ID
    sleep 1.5
    need "the shortcut takes it" take_banner || return 1
    granted=$(log_lines)
    pfinput 'keydown return' 'sleep 1.2' 'keyup return'
    need "a held Return runs the default action" triage "activated-by-enter $staying\"" "$granted" || return 1
    need "  and the application is told" wait_text "\"event\": \"action\", \"id\": $staying, \"key\": \"default\"" "$sender_log" || return 1
    sleep 1
    expect "  the resident banner stays" "$(shown_banners)" 1
    need "  and keeps the keyboard focus" active "$banner_window" still-focused || return 1
    expect "  and is told once, the banner staying" "$(grep -c "\"event\": \"action\", \"id\": $staying," "$sender_log" || true)" 1
    from=$(log_lines)
    pfinput 'key return'
    need "a second, separate Enter acts again" triage "activated-by-enter $staying\"" "$from" || return 1
    sleep 2
    expect "  so the application is told twice" "$(grep -c "\"event\": \"action\", \"id\": $staying," "$sender_log" || true)" 2
    # Rule 7 names two keys: Return and Enter. The keypad's Enter is the other one.
    from=$(log_lines)
    pfinput 'key kp_enter'
    need "the keypad's Enter acts as well" triage "activated-by-enter $staying\"" "$from" || return 1
    sleep 2
    expect "  so the application is told three times" "$(grep -c "\"event\": \"action\", \"id\": $staying," "$sender_log" || true)" 3
    expect "  and the notification is not closed" "$(grep -c "\"event\": \"closed\", \"id\": $staying" "$sender_log" || true)" 0
    from=$(log_lines)
    pfinput 'key escape'
    need "  and Escape still dismisses it" triage "dismissed-by-escape $staying\"" "$from" || return 1
    sleep .6
    need "  with KWrite active again" active pf-notif-app.txt after-resident || return 1
}

mode_buttons() {
    local buttoned actioned replied typing return_buttoned return_replied granted
    # Tab moves the keyboard focus inside the banner and nothing is invoked; Escape from there
    # dismisses.
    need "a banner with one action is sent" send buttoned ',"actions":["open","Open"],"entry":""' || return 1
    buttoned=$SENT_ID
    sleep 1.5
    need "the shortcut gives it keyboard focus" take_banner || return 1
    # Counted from after the grant: the grant itself reports the focus in the banner's content.
    granted=$(log_lines)
    pfinput 'key tab'
    need "Tab moves the keyboard focus to a control inside the banner" triage 'focus-within inside=true' "$granted" || return 1
    expect "  to a control, not back to the content" "$(triage_since "$granted" 'focus-within inside=true MouseEventListener')" no
    need "  and the banner stays the active window" active "$banner_window" after-tab || return 1
    expect "  and invokes nothing" "$(receipt_count "$buttoned")" 0
    shot 01-after-tab
    pfinput 'key escape'
    need "Escape from a control of the banner dismisses it" triage "dismissed-by-escape $buttoned\"" "$from" || return 1
    sleep .6
    need "  and KWrite is active again" active pf-notif-app.txt after-escape-from-control || return 1
    expect "  the application is told nothing" "$(receipt_count "$buttoned")" 0

    # Space on the action's button is that button's own click: the action, once. (Return is not
    # the button's key in stock either: on a focused button of a banner it does nothing.)
    need "a banner with an action is sent" send actioned ',"actions":["act","Open"],"entry":""' || return 1
    actioned=$SENT_ID
    sleep 1.5
    need "the shortcut gives it keyboard focus" take_banner || return 1
    need "Tab reaches the action's button" tab_to_action_button || return 1
    pfinput 'key space'
    need "Space on the button invokes the action" wait_text "\"event\": \"action\", \"id\": $actioned, \"key\": \"act\"" "$sender_log" || return 1
    need "  and the notification is closed for it" wait_text "\"event\": \"closed\", \"id\": $actioned, \"reason\": 3" "$sender_log" || return 1

    # Return on a focused control is not taken as Enter on the banner. With a default action the
    # banner would act on Enter, so a banner with one is used: neither its action's button nor the
    # banner itself acts on Return, and the same button acts on Space.
    need "a banner with a default action and an action button is sent" send return-buttoned ',"actions":["default","Open","act","Act"],"entry":""' || return 1
    return_buttoned=$SENT_ID
    sleep 1.5
    need "the shortcut gives it keyboard focus" take_banner || return 1
    need "Tab reaches the action's button" tab_to_action_button || return 1
    granted=$(log_lines)
    pfinput 'key return'
    sleep 1
    expect "Return on the focused button invokes nothing" "$(receipt_count "$return_buttoned")" 0
    expect "  and is not taken as Enter on the banner" "$(triage_since "$granted" 'activated-by-enter')" no
    need "  and the banner is still the active window" active "$banner_window" after-return || return 1
    expect "  and still shown" "$(shown_banners)" 1
    pfinput 'key space'
    need "Space on the same button invokes the action" wait_text "\"event\": \"action\", \"id\": $return_buttoned, \"key\": \"act\"" "$sender_log" || return 1
    need "  and closes the notification" wait_text "\"event\": \"closed\", \"id\": $return_buttoned, \"reason\": 3" "$sender_log" || return 1

    # In the reply field of a banner that also has a default action, Return is the field's own: it
    # sends the reply, and is not taken as Enter on the banner.
    need "a banner with a default action and a reply action is sent" send return-replied ',"actions":["default","Open","inline-reply","Reply"],"entry":""' || return 1
    return_replied=$SENT_ID
    sleep 1.5
    need "the shortcut gives it keyboard focus" take_banner || return 1
    need "Tab reaches the reply field, which starts the reply" tab_to_reply_field || return 1
    pfinput 'type draft'
    granted=$(log_lines)
    pfinput 'key return'
    need "Return in the reply field sends the reply" wait_text "\"event\": \"replied\", \"id\": $return_replied, \"text\": \"draft\"" "$sender_log" || return 1
    expect "  and is not taken as Enter on the banner" "$(triage_since "$granted" 'activated-by-enter')" no
    sleep .5
    expect "  and the default action is not invoked" "$(grep -c "\"event\": \"action\", \"id\": $return_replied," "$sender_log" || true)" 0

    # With the reply open, Escape is the reply field's own only while the keyboard focus is in
    # it: from the banner's close button it dismisses, as from any button.
    need "a banner with a reply action is sent" send replying-close ',"actions":["inline-reply","Reply"],"entry":""' || return 1
    replying_close=$SENT_ID
    sleep 1.5
    need "the shortcut gives it keyboard focus" take_banner || return 1
    need "Tab reaches the reply field, which starts the reply" tab_to_reply_field || return 1
    pfinput 'type draft'
    sleep .3
    need "Shift+Tab goes back to the banner's close button" tab_back_to_close || return 1
    from=$(log_lines)
    pfinput 'key escape'
    need "Escape from the close button dismisses it, the reply open or not" triage "dismissed-by-escape $replying_close\"" "$from" || return 1
    sleep .6
    need "  and KWrite is active again" active pf-notif-app.txt after-escape-from-close || return 1
    expect "  the application is told nothing" "$(receipt_count "$replying_close")" 0

    # The reply field: Escape keeps its text, and the reply can still be sent.
    need "a banner with a reply action is sent" send replied ',"actions":["inline-reply","Reply"],"entry":""' || return 1
    replied=$SENT_ID
    sleep 1.5
    need "the shortcut gives it keyboard focus" take_banner || return 1
    # A banner whose only action is a reply shows the field itself: Tab reaches it and that starts the reply.
    need "Tab reaches the reply field, which starts the reply" tab_to_reply_field || return 1
    pfinput 'type draft'
    sleep .5
    before=$(triage_count 'dismissed-by-escape')
    pfinput 'key escape'
    sleep .8
    expect "Escape in the reply field dismisses nothing" "$(triage_count 'dismissed-by-escape')" "$before"
    expect "  and the banner stays" "$(shown_banners)" 1
    shot 02-after-escape-in-reply
    pfinput 'key return'
    need "the reply is sent with the text Escape left in place" wait_text "\"event\": \"replied\", \"id\": $replied, \"text\": \"draft\"" "$sender_log" || return 1

    # A replacement while a reply is being typed keeps the keyboard in the reply field: the
    # previous window is not asked for, and what is typed next arrives in the reply.
    need "a banner with a reply action is sent" send typing ',"actions":["inline-reply","Reply"],"entry":""' || return 1
    typing=$SENT_ID
    sleep 1.5
    need "the shortcut gives it keyboard focus" take_banner || return 1
    need "Tab reaches the reply field, which starts the reply" tab_to_reply_field || return 1
    pfinput 'type draft'
    sleep .5
    granted=$(log_lines)
    need "the application replaces it under the same id, the reply open" replace typing-replaced "$typing" ',"actions":["inline-reply","Reply"],"entry":""' || return 1
    need "the replacement ends the interaction" triage 'ended replaced' "$granted" || return 1
    expect "  and does not ask for the previous window" "$(triage_since "$granted" 'focus-restore-requested')" no
    need "  and the banner stays the active window" active "$banner_window" typing-on || return 1
    pfinput 'type z'
    pfinput 'key return'
    need "what is typed after the replacement arrives in the reply, which is then sent" \
        wait_text "\"event\": \"replied\", \"id\": $typing, \"text\": \"draftz\"" "$sender_log" || return 1
}

mode_timer() {
    local before
    # Three seconds: shorter than the pause it is about to get.
    need "a banner with a three-second timeout is sent" send timed ',"timeout":3000' || return 1
    timed=$SENT_ID
    sleep 1
    need "the shortcut gives it keyboard focus" take_banner || return 1
    sleep 4
    need "four seconds later the banner still has keyboard focus" active "$banner_window" still-focused || return 1
    expect "  and is still shown" "$(shown_banners)" 1
    before=$(triage_count 'focus-requested')
    pfinput "$focus_key"
    sleep 1
    expect "the shortcut again asks for no second focus" "$(triage_count 'focus-requested')" "$before"
    # The pointer must not rest on the banner: stock resumes the timeout when the pointer leaves
    # in small steps, but this harness moves it in one jump, and that does not deliver the leave.
    pfinput 'move 700 700'
    pfinput 'click 600 400'
    need "a click into KWrite ends the interaction" triage 'ended lost' "$from" || return 1
    need "  and KWrite is active" active pf-notif-app.txt after-the-click || return 1
    for _ in {1..60}; do
        [ "$(shown_banners)" = 0 ] && break
        sleep .25
    done
    expect "the timeout resumes and the banner expires" "$(shown_banners)" 0
    expect "  and the application is told nothing" "$(receipt_count "$timed")" 0
}

mode_eligible() {
    local critical resident replying older newer again first_taken second_taken granted leaving pointed late before
        plain critical_plain closed_focused orphan
    # Critical and resident banners are taken, and dismissed by Escape.
    need "a critical banner is sent" send critical ',"actions":["default","Open"],"entry":"","hints":{"urgency":2}' || return 1
    critical=$SENT_ID
    sleep 1.5
    need "the shortcut takes it" take_banner || return 1
    pfinput 'key escape'
    need "  and Escape dismisses it" triage "dismissed-by-escape $critical\"" "$from" || return 1
    expect "  the application is told nothing" "$(receipt_count "$critical")" 0
    sleep .6

    need "a resident banner is sent" send resident ',"actions":["default","Open"],"entry":"","hints":{"resident":true}' || return 1
    resident=$SENT_ID
    sleep 1.5
    need "the shortcut takes it" take_banner || return 1
    pfinput 'key escape'
    need "  and Escape dismisses it" triage "dismissed-by-escape $resident\"" "$from" || return 1
    sleep .6
    expect "  and it is gone" "$(shown_banners)" 0
    expect "  the application is told nothing" "$(receipt_count "$resident")" 0

    # Escape on a banner without actions tells the application "expired", once, as its own
    # timeout would; on one with actions it is told nothing (above).
    need "a banner without actions is sent" send plain ',"actions":[],"entry":"","timeout":30000' || return 1
    plain=$SENT_ID
    sleep 1.5
    need "the shortcut takes it" take_banner || return 1
    pfinput 'key escape'
    need "  and Escape dismisses it" triage "dismissed-by-escape $plain\"" "$from" || return 1
    need "  and the application is told it expired" wait_text "\"event\": \"closed\", \"id\": $plain, \"reason\": 1" "$sender_log" || return 1
    sleep .6
    expect "  once" "$(receipt_count "$plain")" 1
    need "  and KWrite is active again" active pf-notif-app.txt after-plain || return 1

    # A critical banner has no timeout: it is told "expired" as well (decision 14).
    need "a critical banner without actions is sent" send critical-plain ',"actions":[],"entry":"","hints":{"urgency":2}' || return 1
    critical_plain=$SENT_ID
    sleep 1.5
    need "the shortcut takes it" take_banner || return 1
    pfinput 'key escape'
    need "  and Escape dismisses it" triage "dismissed-by-escape $critical_plain\"" "$from" || return 1
    need "  and the application is told it expired" wait_text "\"event\": \"closed\", \"id\": $critical_plain, \"reason\": 1" "$sender_log" || return 1
    sleep .6
    expect "  once" "$(receipt_count "$critical_plain")" 1
    need "  and KWrite is active again" active pf-notif-app.txt after-critical-plain || return 1

    # A job popup is not a notification banner.
    write_request '{"op":"job","label":"job"}'
    need "a job popup is made" wait_text '"event": "job"' "$sender_log" || return 1
    sleep 1.5
    expect "  and shown" "$(shown_banners)" 1
    from=$(log_lines)
    pfinput "$focus_key"
    need "the shortcut does not take a job popup" triage 'shortcut-ignored-no-banner' "$from" || return 1
    need "  and KWrite stays active" active pf-notif-app.txt job-popup || return 1
    write_request '{"op":"job-end","label":"job"}'
    need "the job popup is ended" wait_text '"event": "job-ended"' "$sender_log" || return 1

    # A banner that is handling a reply is not taken either.
    need "a banner with a reply action is sent" send replying ',"actions":["inline-reply","Reply"],"entry":""' || return 1
    replying=$SENT_ID
    sleep 1.5
    need "the shortcut gives it keyboard focus" take_banner || return 1
    need "Tab reaches the reply field, which starts the reply" tab_to_reply_field || return 1
    pfinput 'click 600 400'
    need "a click into KWrite ends the interaction" triage 'ended lost' "$from" || return 1
    expect "the banner with its reply open is still shown" "$(shown_banners)" 1
    pfinput "$focus_key"
    need "the shortcut does not take a banner whose reply is open" triage 'shortcut-ignored-no-banner' "$from" || return 1
    need "  and KWrite stays active" active pf-notif-app.txt reply-open || return 1
    need "  and the application closes it" close_notification "$replying" || return 1

    # Two banners, the older one on top: the shortcut names the newer.
    need "an older banner is sent" send older ',"actions":["default","Open"]' || return 1
    older=$SENT_ID
    need "  and a newer one" send newer ',"actions":["default","Open"]' || return 1
    newer=$SENT_ID
    sleep 1.5
    expect "both are shown" "$(shown_banners)" 2
    shot 01-two-banners
    need "the shortcut names the newer banner" take_banner || return 1
    pfinput 'key escape'
    need "  and Escape dismisses that one" triage "dismissed-by-escape $newer\"" "$from" || return 1
    sleep .6
    expect "  leaving the older one" "$(shown_banners)" 1
    need "  which the application closes" close_notification "$older" || return 1

    # The shortcut again while a banner is focused changes nothing: the recorded window is still
    # the one to return to.
    need "a banner is sent" send again ',"actions":["default","Open"]' || return 1
    again=$SENT_ID
    sleep 1.5
    need "the shortcut takes it" take_banner || return 1
    before=$(triage_count 'focus-requested')
    pfinput "$focus_key"
    sleep 1
    expect "the shortcut again asks for no second focus" "$(triage_count 'focus-requested')" "$before"
    need "the application replaces it under the same id" replace replaced "$again" ',"actions":["default","Open"]' || return 1
    need "  and a replacement still asks for KWrite" triage 'focus-restore-requested' "$from" || return 1
    sleep .6
    need "  which is active" active pf-notif-app.txt after-replacement || return 1
    need "  and the application closes it" close_notification "$again" || return 1

    # An application that leaves the bus is no replacement: KDE then clears the actions of its
    # notification. The banner stays taken, and Escape still dismisses it.
    need "a second application is started" start_second_sender || return 1
    need "it sends a banner with a default action" send leaving ',"actions":["default","Open"]' || return 1
    leaving=$SENT_ID
    sleep 1.5
    need "the shortcut takes it" take_banner || return 1
    granted=$(log_lines)
    need "  and the application leaves the bus" stop_sender || return 1
    sleep 1
    expect "the application leaving the bus is no replacement" "$(triage_since "$granted" 'ended replaced')" no
    expect "  and asks for no window" "$(triage_since "$granted" 'focus-restore-requested')" no
    need "  and the banner is still the active window" active "$banner_window" after-leaving || return 1
    pfinput 'key escape'
    need "  and Escape still dismisses it" triage "dismissed-by-escape $leaving\"" "$from" || return 1
    sleep .6
    need "  with KWrite active again" active pf-notif-app.txt after-leaving-escape || return 1
    use_sender 1

    # The shortcut takes a newer banner while an older one is still taken: the window from before
    # the first press stays the one to return to.
    need "a banner is sent" send first-taken ',"actions":["default","Open"]' || return 1
    first_taken=$SENT_ID
    sleep 1.5
    need "with KWrite active before it is taken" active pf-notif-app.txt before-hand-over || return 1
    need "the shortcut takes it" take_banner || return 1
    need "  and a newer banner is sent" send second-taken ',"actions":["default","Open"]' || return 1
    second_taken=$SENT_ID
    sleep 1.5
    need "the shortcut takes the newer one" take_banner || return 1
    granted=$(log_lines)
    need "the application replaces the newer one under its id" replace second-replaced "$second_taken" ',"actions":["default","Open"]' || return 1
    need "a replacement of the newer banner still asks for KWrite" triage 'focus-restore-requested' "$granted" || return 1
    sleep .6
    need "  which is active again" active pf-notif-app.txt after-hand-over || return 1
    need "  and the application closes the newer one" close_notification "$second_taken" || return 1
    need "  and the older one" close_notification "$first_taken" || return 1

    # The window recorded before the shortcut is gone when the interaction ends: nothing is asked
    # for, and the banner stays the active window and takes no key (rule 9).
    printf 'previous focus B\n' >"$HOME/pf-notif-app-b.txt"
    kwrite "$HOME/pf-notif-app-b.txt" >"$OUT/kwrite-b.log" 2>&1 &
    sleep 3
    [ "$(activate_window_by_caption pf-notif-app-b.txt)" = ok ] || return 1
    sleep .8
    need "the second document's window is active" active pf-notif-app-b.txt second-document || return 1
    need "a banner is sent" send orphan ',"actions":["default","Open"]' || return 1
    orphan=$SENT_ID
    sleep 1.5
    need "the shortcut takes it" take_banner || return 1
    granted=$(log_lines)
    need "  and the application that had the keyboard focus closes its window" close_window_by_caption pf-notif-app-b.txt || return 1
    need "  and the window is gone" wait_window_count pf-notif-app-b.txt 0 || return 1
    need "the application replaces the banner" replace orphan-replaced "$orphan" ',"actions":["default","Open"]' || return 1
    need "  and nothing is asked for, the recorded window being gone" triage 'focus-restore-skipped' "$granted" || return 1
    need "  and the banner stays the active window" active "$banner_window" nothing-to-restore || return 1
    before=$(triage_count 'dismissed-by-escape')
    pfinput 'key escape'
    sleep .8
    expect "  and it takes no key: Escape dismisses nothing" "$(triage_count 'dismissed-by-escape')" "$before"
    need "  and the application can still close it" close_notification "$orphan" || return 1

    # The banner is the active window already, with the pointer on it: the keyboard focus arrives
    # at once.
    need "a banner without a default action is sent" send pointed ',"actions":["open","Open"],"entry":""' || return 1
    pointed=$SENT_ID
    sleep 1.5
    pfinput 'move 200 125' 'click 200 125'
    sleep .6
    need "the banner is the active window with the pointer on it" active "$banner_window" pointer-on-banner || return 1
    need "and the shortcut gives it keyboard focus at once" take_banner || return 1
    pfinput 'key escape'
    need "  and Escape dismisses it" triage "dismissed-by-escape $pointed\"" "$from" || return 1
    sleep .6
    need "  with KWrite active again" active pf-notif-app.txt after-pointed || return 1

    # The pointer leaves the corner where the banners appear, and KWrite is active.
    pfinput 'move 600 400' 'click 600 400'
    sleep .4
    # The banner is closed while it has the keyboard focus: nothing is restored, nothing dismissed.
    need "a banner is sent" send closed-focused ',"actions":["default","Open"]' || return 1
    closed_focused=$SENT_ID
    sleep 1.5
    need "the shortcut takes it" take_banner || return 1
    before=$(triage_count 'focus-restore-requested')
    need "the application closes it" close_notification "$closed_focused" || return 1
    sleep 1.5
    expect "a banner closed while focused restores nothing" "$(triage_count 'focus-restore-requested')" "$before"
    expect "  and dismisses nothing: the close is what the application is told" "$(receipt_count "$closed_focused")" 1
    expect "  and no banner is shown" "$(shown_banners)" 0
    need "  and KWrite is active" active pf-notif-app.txt closed-focused || return 1

    # The banner is closed right after the request, before or after the grant as the run goes:
    # the chord asked for it, and nothing is restored or dismissed either way.
    need "a banner is sent" send late ',"actions":["default","Open"]' || return 1
    late=$SENT_ID
    sleep 1.5
    need "KWrite is active" active pf-notif-app.txt before-late || return 1
    from=$(log_lines)
    before=$(triage_count 'focus-restore-requested')
    pfinput "$focus_key"
    need "the application closes it at once" close_notification "$late" || return 1
    need "  and the chord had asked for it" triage "focus-requested $late\"" "$from" || return 1
    sleep 1.5
    expect "a banner closed right after the request restores nothing" "$(triage_count 'focus-restore-requested')" "$before"
    expect "  and dismisses nothing: the close is what the application is told" "$(receipt_count "$late")" 1
    expect "  and no banner is shown" "$(shown_banners)" 0
    need "  and KWrite is active" active pf-notif-app.txt late || return 1
}

case $mode in
    stock | copy) control_mode || true ;;
    full) mode_full || true ;;
    lock-idle) mode_lock_idle || true ;;
    lock-focused) mode_lock_focused || true ;;
    activate) mode_activate || true ;;
    buttons) mode_buttons || true ;;
    timer) mode_timer || true ;;
    eligible) mode_eligible || true ;;
esac

# Every mode, the control ones too: a script error in the shell log is the copy's doing.
expect "no script error in the shell log" "$(no_script_error && echo none || echo some)" none

stop_sender
expect "the test application ends on request" "$sender_stopped" yes
cat "$OUT/checks.txt"
echo "checks: $PASS passed, $FAILED failed"
[ "$FAILED" = 0 ]
