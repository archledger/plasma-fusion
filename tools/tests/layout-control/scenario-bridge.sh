#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Sourced ONLY by the existing isolated vsession harness. No host/session discovery.
set -euo pipefail

[[ ${PFV:-} == /var/tmp/pfv-layout-control-* &&
   ${HOME:-} == "$PFV/home" &&
   ${XDG_RUNTIME_DIR:-} == "$PFV/run" ]] || {
    echo "Refusing a non-probe HOME/runtime" >&2
    return 64
}

cleanup_helper="$HOME/.local/lib/layout-control/cleanup.py"
finish_probe_session() {
    local owned_pid status
    owned_pid=$(python3 "$cleanup_helper" signal) || return 1
    [[ $owned_pid =~ ^[1-9][0-9]*$ ]] || {
        echo "FAIL: cleanup helper returned no owned child" >&2
        return 1
    }
    if wait "$owned_pid"; then
        status=0
    else
        status=$?
    fi
    python3 "$cleanup_helper" confirm "$status"
}
# Capture once, before the cases; never replace this identity with a later shell owner.
python3 "$cleanup_helper" capture

observations() {
    python3 - "$OUT/plasmashell.log" <<'PY'
import json, sys
latest = {}
with open(sys.argv[1]) as trace:
    for line in trace:
        if not line.endswith("\n") or "layout-probe-observation " not in line:
            continue
        observation = json.loads(line.split("layout-probe-observation ", 1)[1])
        latest[observation["boot"]] = observation
print(json.dumps([{"consumer": key, "observation": value} for key, value in latest.items()]))
PY
}

wait_for_phase() {
    local phase=$1
    for _ in {1..40}; do
        observations >"$OUT/observations-$phase.json"
        if python3 - "$OUT/observations-$phase.json" "$phase" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
assert len(rows) == 2, rows
assert all(row["observation"]["phase"] == sys.argv[2] for row in rows), rows
PY
        then
            return 0
        fi
        sleep 0.1
    done
    echo "FAIL: no confirmed $phase state for both probe widgets" >&2
    return 1
}

reload_probe() {
    local provider="$HOME/.local/share/kwin/scripts/plasmafusion-layout-probe/contents/ui/main.qml"
    local ready=false
    qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.loadDeclarativeScript \
        "$provider" plasmafusion-layout-probe >"$OUT/reload-script-id.txt"
    qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.start
    for _ in {1..40}; do
        if python3 - "$OUT/kwin.log" <<'PY'
import sys
with open(sys.argv[1]) as trace:
    assert sum("layout-probe: initialized " in line for line in trace) == 2
PY
        then
            ready=true
            break
        fi
        sleep 0.1
    done
    [[ $ready == true ]] || { echo "FAIL: reloaded provider not initialized" >&2; return 1; }
    qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut \
        "Plasma Fusion: Layout Probe Wake"
    wait_for_phase online 2>"$OUT/reload-wait.log"
    cp "$OUT/observations-online.json" "$OUT/observations-reloaded.json"
}

refused_backend_probe=$(kreadconfig6 --file "$HOME/.config/kwinrc" \
    --group Script-plasmafusion-layout-probe --key RefusedBackendProbe --default false)
if [[ $refused_backend_probe == true ]]; then
    # Branch before the startup check: this case loads the probe only after the occupier holds
    # the native provider slot. This Bash parent keeps child ownership.
    # shellcheck source=tools/tests/layout-control/refused_scenario.sh
    source "$HOME/.local/lib/layout-control/refused_scenario.sh"
    finish_probe_session
    return 0
fi

loaded=$(qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.isScriptLoaded plasmafusion-layout-probe)
[[ $loaded == true ]] || { echo "FAIL: real declarative probe not loaded" >&2; return 1; }
qdbus org.kde.kglobalaccel >"$OUT/shortcut-components.txt"
qdbus org.kde.kglobalaccel /component/kwin >"$OUT/kwin-shortcut-interface.txt"
qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.shortcutNames \
    >"$OUT/kwin-shortcut-names.txt"

reply_delay_ms=$(kreadconfig6 --file "$HOME/.config/kwinrc" \
    --group Script-plasmafusion-layout-probe --key ReplyDelayMs --default 0)
[[ $reply_delay_ms =~ ^[0-9]+$ ]] || return 64
if [[ $reply_delay_ms != 0 ]]; then
    timeout_provider_ready=false
    for _ in {1..40}; do
        qdbus org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus.ListNames \
            >"$OUT/timeout-bus-names.txt"
        if python3 - "$OUT/timeout-bus-names.txt" "$OUT/timeout-identity-before.txt" <<'PY'
import sys
names = [line.strip() for line in open(sys.argv[1])
         if line.strip().startswith("org.plasmafusion.LayoutProbe.p")]
assert len(names) == 1, names
with open(sys.argv[2], "w") as identity:
    identity.write(names[0])
PY
        then
            timeout_provider_ready=true
            break
        fi
        sleep 0.1
    done
    [[ $timeout_provider_ready == true ]] || return 1
    timeout_identity_before=$(cat "$OUT/timeout-identity-before.txt")
    qdbus org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus.GetNameOwner "$timeout_identity_before" \
        >"$OUT/timeout-owner-before.txt"
fi

two_bar_probe=$(kreadconfig6 --file "$HOME/.config/kwinrc" \
    --group Script-plasmafusion-layout-probe --key TwoBarProbe --default false)
if [[ $two_bar_probe == true ]]; then
    # One probe bar per output. A scripted panel starts on screen 0, so the second one is moved to
    # screen 1. Its consumer can still send its first request for output 0; it refreshes once
    # when it sees its bar's output change, and the two-bar checker allows for that. Neither panel
    # floats: a scripted panel floats by default and moves into its floating position after its
    # control first reports where it is, and a click during that move reached the desktop instead
    # of the control.
    outputs=$(kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | grep -c '^Output:')
    [[ $outputs -ge 2 ]] || { echo "FAIL: the two-bar case needs two outputs" >&2; return 1; }
    evaljs - >"$OUT/widgets-created.txt" <<'JS'
var p=new Panel;
p.location="top";
p.height=40;
p.floating=false;
var a=p.addWidget("org.plasmafusion.layoutprobe");
var q=new Panel;
q.location="top";
q.height=40;
q.floating=false;
q.screen=1;
var b=q.addWidget("org.plasmafusion.layoutprobe");
print(JSON.stringify([a.id,b.id]));
JS
else
    evaljs - >"$OUT/widgets-created.txt" <<'JS'
var p=new Panel;
p.location="top";
p.height=40;
var a=p.addWidget("org.plasmafusion.layoutprobe");
var b=p.addWidget("org.plasmafusion.layoutprobe");
print(JSON.stringify([a.id,b.id]));
JS
fi
wait_for_phase online 2>"$OUT/online-wait.log"
backend_owner=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.GetNameOwner org.kde.KWin)
python3 - "$OUT/observations-online.json" "$backend_owner" "$OUT/identity-name.txt" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
assert len({row["consumer"] for row in rows}) == 2
assert len({row["observation"]["boot"] for row in rows}) == 2
for row in rows:
    observation = row["observation"]
    packet = observation["packet"]
    assert packet["consumer"] == observation["boot"]
    assert packet["capable"] is True, packet
    assert packet["refusal"] == -1, packet
    assert packet["competingProviderRejected"] is True, packet
    assert len(packet["epoch"]) == 32, packet
    assert packet["backendOwner"] == sys.argv[2], packet
    assert packet["identityName"].startswith("org.plasmafusion.LayoutProbe.p"), packet
names = {row["observation"]["packet"]["identityName"] for row in rows}
assert len(names) == 1
with open(sys.argv[3], "w") as identity:
    identity.write(names.pop())
print("PASS: real wake-up, two-widget correlation and native null-output refusal")
PY
identity_name=$(cat "$OUT/identity-name.txt")
identity_owner=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.GetNameOwner "$identity_name")
[[ $identity_owner == "$backend_owner" ]] || return 1

pipeline_probe=$(kreadconfig6 --file "$HOME/.config/kwinrc" \
    --group Script-plasmafusion-layout-probe --key PipelineProbe --default false)
if [[ $pipeline_probe == true ]]; then
    # Branch after the first online exchange and its identity checks; this Bash parent keeps
    # child ownership.
    # shellcheck source=tools/tests/layout-control/pipeline_scenario.sh
    source "$HOME/.local/lib/layout-control/pipeline_scenario.sh"
    finish_probe_session
    return 0
fi

focus_probe=$(kreadconfig6 --file "$HOME/.config/kwinrc" \
    --group Script-plasmafusion-layout-probe --key FocusProbe --default false)
if [[ $focus_probe == true ]]; then
    target_probe=$(kreadconfig6 --file "$HOME/.config/kwinrc" \
        --group Script-plasmafusion-layout-probe --key TargetProbe --default false)
    wait_target_reply() {
        local boot=$1 intent=$2 ready=$3 previous=$4 app=$5
        local complete=false
        for _ in {1..40}; do
            # Non-mutating target receipt: one accepted-state/outbound snapshot, plus native verdict.
            if python3 "$HOME/.local/lib/layout-control/receipts.py" target-reply \
                "$OUT/plasmashell.log" "$OUT/kwin.log" "$boot" "$intent" "$ready" \
                "$previous" "$app" "$OUT" 2>>"$OUT/target-reply-wait.log"
            then
                complete=true
                break
            fi
            sleep 0.1
        done
        [[ $complete == true ]] || {
            echo "FAIL: target reply: no $intent reply, ready $ready, after request $previous" \
                "for ${app/#-/no app} (last check: target-reply-wait.log)" >&2
            return 1
        }
    }
    wait_target_context() {
        local boot=$1 app=$2 ready=false
        for _ in {1..40}; do
            if python3 - "$OUT/plasmashell.log" "$OUT/kwin.log" "$boot" "$app" \
                2>>"$OUT/target-context-wait.log" <<'PY'
import json, sys
observations = [json.loads(line.split("layout-probe-observation ", 1)[1])
                for line in open(sys.argv[1])
                if line.endswith("\n") and "layout-probe-observation " in line]
observation = [row for row in observations if row["boot"] == sys.argv[3]][-1]
assert observation["phase"] == "online"
context = observation["packet"]["targetContext"]
assert context and context["epoch"] == observation["packet"]["epoch"]
native = [json.loads(line.split("layout-probe-focus ", 1)[1])
          for line in open(sys.argv[2])
          if line.endswith("\n") and "layout-probe-focus " in line][-1]
assert native["activeClass"] == native["rememberedClass"] == sys.argv[4]
assert native["activeEligible"] and native["rememberedAlive"]
assert context["generation"] == native["contextGeneration"]
assert context["desktopId"] == native["desktopId"] and context["activityId"] == native["activityId"]
assert context["outputName"] == native["rememberedOutput"]
PY
            then
                ready=true
                break
            fi
            sleep 0.1
        done
        [[ $ready == true ]] || {
            echo "FAIL: target context: no online context remembering $app" \
                "(last check: target-context-wait.log)" >&2
            return 1
        }
    }
    wait_consumer_state() {
        local boot=$1 previous=$2 intent=$3 ready=$4 reason=$5 app=$6 complete=false
        for _ in {1..40}; do
            # Consumer retirement receipt: a newer accepted revision and its exact native verdict.
            if python3 "$HOME/.local/lib/layout-control/receipts.py" consumer-state \
                "$OUT/plasmashell.log" "$OUT/kwin.log" "$boot" "$previous" "$intent" \
                "$ready" "$reason" "$app" "$OUT/consumer-current.json" \
                2>>"$OUT/consumer-state-wait.log"
            then
                complete=true
                break
            fi
            sleep 0.1
        done
        [[ $complete == true ]] || {
            echo "FAIL: consumer state: no state after revision $previous with $intent ready" \
                "$ready, reason ${reason/#-/none}, for ${app/#-/no app}" \
                "(last check: consumer-state-wait.log)" >&2
            return 1
        }
    }
    # Each publication is a shell script call that the shell serves on its main thread, and one can
    # take hundreds of milliseconds; a click sent while the shell served one could lose its button
    # events (docs/DEFERRED.md). As a test-side workaround, a click after a change waits until the
    # provider has observed it, the receiver holds the newest context, and nothing is outstanding.
    wait_target_settled() {
        local boot=$1 minimum=$2 settled=false
        for _ in {1..40}; do
            if python3 "$HOME/.local/lib/layout-control/receipts.py" target-settled \
                "$OUT/plasmashell.log" "$OUT/kwin.log" "$boot" "$minimum" \
                >/dev/null 2>>"$OUT/target-settle-wait.log"
            then
                settled=true
                break
            fi
            sleep 0.1
        done
        [[ $settled == true ]] || {
            echo "FAIL: target settle: the shell did not settle at or after context generation" \
                "$minimum (last check: target-settle-wait.log)" >&2
            return 1
        }
    }
    wait_target_popup() {
        local app=$1 ready=false
        for _ in {1..40}; do
            if python3 - "$OUT/kwin.log" "$OUT/focus-shell-pid.txt" "$app" \
                2>>"$OUT/target-popup-wait.log" <<'PY'
import json, sys
rows = [json.loads(line.split("layout-probe-focus ", 1)[1])
        for line in open(sys.argv[1])
        if line.endswith("\n") and "layout-probe-focus " in line]
native = rows[-1]
assert native["activeAppletPopup"] and not native["activeNormal"]
assert native["activePid"] == int(open(sys.argv[2]).read())
assert native["rememberedClass"] == sys.argv[3] and native["rememberedAlive"]
PY
            then
                ready=true
                break
            fi
            sleep 0.1
        done
        [[ $ready == true ]] || {
            echo "FAIL: target popup: no shell popup active with $app remembered" \
                "(last check: target-popup-wait.log)" >&2
            return 1
        }
    }
    wait_second_app_active() {
        local seen=false
        for _ in {1..40}; do
            if python3 - "$OUT/kwin.log" 2>>"$OUT/target-second-wait.log" <<'PY'
import json, sys
rows = [json.loads(line.split("layout-probe-focus ", 1)[1])
        for line in open(sys.argv[1])
        if line.endswith("\n") and "layout-probe-focus " in line]
assert any(row["activeClass"] == "pf.focus.beta" and row["activeEligible"] for row in rows)
PY
            then
                seen=true
                break
            fi
            sleep 0.1
        done
        [[ $seen == true ]] || {
            echo "FAIL: second app: pf.focus.beta never became the active eligible window" \
                "(last check: target-second-wait.log)" >&2
            return 1
        }
    }
    # The shell lists exactly one probe widget, the owned one that was not removed.
    wait_owned_consumer_removed() {
        local removed=false
        for _ in {1..40}; do
            evaljs - >"$OUT/consumer-widgets-after.json" <<'JS'
var rows=[];
panels().forEach(function(p){p.widgets('org.plasmafusion.layoutprobe').forEach(function(w){
    rows.push({id:w.id,type:w.type});
});});
print(JSON.stringify(rows));
JS
            if python3 - "$OUT/consumer-widgets-after.json" "$OUT/consumer-removed.json" \
                "$OUT/widgets-created.txt" 2>>"$OUT/consumer-removal-wait.log" <<'PY'
import json, sys
rows, removed, owned = [json.load(open(path)) for path in sys.argv[1:]]
assert len(rows) == 1 and rows[0]["id"] in owned
assert rows[0]["id"] != removed["removedId"]
assert rows[0]["type"] == "org.plasmafusion.layoutprobe"
PY
            then
                removed=true
                break
            fi
            sleep 0.1
        done
        [[ $removed == true ]] || {
            echo "FAIL: consumer removal: the shell does not list just the remaining owned" \
                "probe widget (last check: consumer-removal-wait.log)" >&2
            return 1
        }
    }
    qdbus org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus.GetConnectionUnixProcessID org.kde.plasmashell \
        >"$OUT/focus-shell-pid.txt"
    mkfifo "$OUT/focus-client.in"
    exec {focus_input}<>"$OUT/focus-client.in"
    python3 "$HOME/.local/lib/layout-control/heldclient.py" pf.focus.alpha 430x310 \
        <"$OUT/focus-client.in" >"$OUT/focus-client.log" 2>&1 &
    focus_client=$!
    app_seen=false
    for _ in {1..40}; do
        if python3 - "$OUT/kwin.log" 2>>"$OUT/focus-activation-wait.log" <<'PY'
import json, sys
events = [json.loads(line.split("layout-probe-focus ", 1)[1])
          for line in open(sys.argv[1]) if line.endswith("\n") and "layout-probe-focus " in line]
assert any(row["event"] == "activation" and row["activeClass"] == "pf.focus.alpha"
           and row["activeEligible"] and row["rememberedAlive"] for row in events)
PY
        then
            app_seen=true
            break
        fi
        sleep 0.1
    done
    if [[ $app_seen != true ]]; then
        echo "FAIL: controlled app activation not observed" >&2
        return 1
    fi
    python3 - "$OUT/plasmashell.log" "$OUT/focus-control.txt" <<'PY'
import json, sys
latest = {}
for line in open(sys.argv[1]):
    if line.endswith("\n") and "layout-probe-focus-control " in line:
        row = json.loads(line.split("layout-probe-focus-control ", 1)[1])
        latest[row["boot"]] = row
assert len(latest) == 2, latest
control = min(latest.values(), key=lambda row: row["x"])
assert control["screen"] and control["x"] >= 0 and control["y"] >= 0, control
with open(sys.argv[2], "w") as point:
    point.write(f'{control["x"]} {control["y"]} {control["boot"]}\n')
PY
    read -r focus_x focus_y focus_boot <"$OUT/focus-control.txt"
    if [[ $target_probe == true ]]; then
        wait_target_context "$focus_boot" pf.focus.alpha
        keyboard_entry_probe=$(kreadconfig6 --file "$HOME/.config/kwinrc" \
            --group Script-plasmafusion-layout-probe --key KeyboardEntryProbe --default false)
        if [[ $keyboard_entry_probe == true ]]; then
            # Branch before any pointer opens the popup, so the panel has keyboard focus first.
            # The scenario quits the controlled app itself.
            # shellcheck source=tools/tests/layout-control/keyboard_scenario.sh
            source "$HOME/.local/lib/layout-control/keyboard_scenario.sh"
            finish_probe_session
            return 0
        fi
    fi
    pfinput "click $focus_x $focus_y"
    popup_seen=false
    for _ in {1..40}; do
        if python3 - "$OUT/plasmashell.log" "$focus_boot" \
            2>>"$OUT/focus-popup-wait.log" <<'PY'
import json, sys
rows = [json.loads(line.split("layout-probe-popup-focus ", 1)[1])
        for line in open(sys.argv[1])
        if line.endswith("\n") and "layout-probe-popup-focus " in line]
assert any(row["boot"] == sys.argv[2] for row in rows)
PY
        then
            popup_seen=true
            break
        fi
        sleep 0.1
    done
    [[ $popup_seen == true ]] || { echo "FAIL: focus popup not ready" >&2; return 1; }
    if [[ $target_probe == true ]]; then
        wait_target_popup pf.focus.alpha
        python3 - "$OUT/kwin.log" "$focus_boot" <<'PY'
import json, sys
rows = [json.loads(line.split("layout-probe-target ", 1)[1])
        for line in open(sys.argv[1])
        if line.endswith("\n") and "layout-probe-target " in line]
assert not any(row["consumer"] == sys.argv[2] and row["intent"] == "prepare" for row in rows)
print("PASS: opening the popup alone never dispatches a preparation")
PY
    fi
    python3 - "$OUT/plasmashell.log" "$OUT/kwin.log" "$OUT/focus-key-baseline.json" <<'PY'
import json, sys
with open(sys.argv[3], "w") as baseline:
    json.dump({"shellLines": len(open(sys.argv[1]).readlines()),
               "kwinLines": len(open(sys.argv[2]).readlines())}, baseline)
PY
    pfinput "key space"
    queried=false
    for _ in {1..40}; do
        if python3 - "$OUT/plasmashell.log" "$OUT/kwin.log" "$focus_boot" \
            "$OUT/focus-observations-after-key.json" "$OUT/focus-key-baseline.json" \
            2>>"$OUT/focus-query-wait.log" <<'PY'
import json, sys
baseline = json.load(open(sys.argv[5]))
# One shell-log snapshot prevents a newer key from borrowing an older accepted-state snapshot.
shell = open(sys.argv[1]).readlines()
events = []
latest = {}
for index, line in enumerate(shell):
    if not line.endswith("\n"):
        continue
    for kind in ("keyboard-query", "query", "observation"):
        marker = f"layout-probe-{kind} "
        if marker in line:
            row = json.loads(line.split(marker, 1)[1])
            events.append((index, kind, row))
            if kind == "observation":
                latest[row["boot"]] = (index, row)
keys = [(index, row) for index, kind, row in events
        if kind == "keyboard-query" and index >= baseline["shellLines"]]
assert len(keys) == 1
key_index, key = keys[0]
assert key["boot"] == sys.argv[3] and key["activeFocus"] and key["key"] == 32
queries = [(index, row) for index, kind, row in events
           if kind == "query" and row["boot"] == key["boot"] and row["request"] == key["request"]]
assert len(queries) == 1 and key_index < queries[0][0]
accepted_index, selected = latest[key["boot"]]
assert queries[0][0] < accepted_index and selected["phase"] == "online", selected
assert selected["request"] == selected["packet"]["request"] == key["request"], selected
assert selected["packet"]["consumer"] == key["boot"], selected
events = [json.loads(line.split("layout-probe-focus ", 1)[1])
          for index, line in enumerate(open(sys.argv[2]))
          if index >= baseline["kwinLines"] and line.endswith("\n") and "layout-probe-focus " in line]
wake = [row for row in events if row["event"] == "wake"][-1]
assert wake["rememberedClass"] == "pf.focus.alpha" and wake["rememberedAlive"], wake
assert wake["rememberedOutput"] == key["screen"] == wake["activeOutput"], (wake, key)
assert wake["desktopId"] and wake["activityId"], wake
with open(sys.argv[4], "w") as output:
    json.dump([{"consumer": boot, "observation": row} for boot, (_, row) in latest.items()], output)
print("PASS: actual popup keyboard query retains the eligible app and matching output identity")
print(json.dumps(wake))
PY
        then
            queried=true
            break
        fi
        sleep 0.1
    done
    [[ $queried == true ]] || { echo "FAIL: keyboard focus query not confirmed" >&2; return 1; }
    shot focus-keyboard
    if [[ $target_probe == true ]]; then
        target_prepare_request=$(wait_target_reply "$focus_boot" prepare true 1 pf.focus.alpha)
        completion_probe=$(kreadconfig6 --file "$HOME/.config/kwinrc" \
            --group Script-plasmafusion-layout-probe --key CompletionProbe --default false)
        if [[ $completion_probe == true ]]; then
            # Branch while the accepted preparation is still the holder's current request.
            # shellcheck source=tools/tests/layout-control/completion_scenario.sh
            source "$HOME/.local/lib/layout-control/completion_scenario.sh"
            printf 'quit\n' >&"$focus_input"
            wait "$focus_client"
            exec {focus_input}>&-
            finish_probe_session
            return 0
        fi
        two_bar_probe=$(kreadconfig6 --file "$HOME/.config/kwinrc" \
            --group Script-plasmafusion-layout-probe --key TwoBarProbe --default false)
        if [[ $two_bar_probe == true ]]; then
            # Branch while the holder's accepted preparation is still its current request.
            # shellcheck source=tools/tests/layout-control/two_bar_scenario.sh
            source "$HOME/.local/lib/layout-control/two_bar_scenario.sh"
            printf 'quit\n' >&"$focus_input"
            wait "$focus_client"
            exec {focus_input}>&-
            finish_probe_session
            return 0
        fi
        pfinput "key space"
        target_request=$(wait_target_reply "$focus_boot" validate true \
            "$target_prepare_request" pf.focus.alpha)
        echo "PASS: explicit preparation and keyboard validation retain the native application"
        view_loss_probe=$(kreadconfig6 --file "$HOME/.config/kwinrc" \
            --group Script-plasmafusion-layout-probe --key ViewLossProbe --default false)
        if [[ $view_loss_probe == true ]]; then
            # Branch while that validation is still live; this Bash parent keeps child ownership.
            # shellcheck source=tools/tests/layout-control/view_loss_scenario.sh
            source "$HOME/.local/lib/layout-control/view_loss_scenario.sh"
            printf 'quit\n' >&"$focus_input"
            wait "$focus_client"
            exec {focus_input}>&-
            finish_probe_session
            return 0
        fi
        python3 - "$OUT/plasmashell.log" "$focus_boot" >"$OUT/target-control.txt" <<'PY'
import json, sys
rows = [json.loads(line.split("layout-probe-focus-control ", 1)[1])
        for line in open(sys.argv[1])
        if line.endswith("\n") and "layout-probe-focus-control " in line]
control = [row for row in rows if row["boot"] == sys.argv[2]][-1]
assert control["validateX"] >= 0 and control["validateY"] >= 0
print(control["validateX"], control["validateY"])
PY
        read -r validate_x validate_y <"$OUT/target-control.txt"
        generation=$(python3 "$HOME/.local/lib/layout-control/receipts.py" provider-generation \
            "$OUT/kwin.log")
        mkfifo "$OUT/target-second.in"
        exec {target_second_input}<>"$OUT/target-second.in"
        python3 "$HOME/.local/lib/layout-control/heldclient.py" pf.focus.beta 430x310 \
            <"$OUT/target-second.in" >"$OUT/target-second.log" 2>&1 &
        target_second=$!
        wait_second_app_active
        wait_target_settled "$focus_boot" $((generation + 1))
        pfinput "click $validate_x $validate_y"
        target_request=$(wait_target_reply "$focus_boot" validate false "$target_request" -)
        echo "PASS: another eligible app invalidates the old preparation instead of retargeting"
        pfinput "click $focus_x $focus_y"
        wait_target_popup pf.focus.beta
        pfinput "key space"
        target_request=$(wait_target_reply "$focus_boot" prepare true "$target_request" pf.focus.beta)
        generation=$(python3 "$HOME/.local/lib/layout-control/receipts.py" provider-generation \
            "$OUT/kwin.log")
        printf 'quit\n' >&"$target_second_input"
        wait "$target_second"
        exec {target_second_input}>&-
        wait_target_settled "$focus_boot" $((generation + 1))
        pfinput "click $validate_x $validate_y"
        target_request=$(wait_target_reply "$focus_boot" validate false "$target_request" -)
        echo "PASS: closing a freshly prepared target refuses its old handle"
        python3 - "$OUT/kwin.log" >"$OUT/target-alpha-control.txt" <<'PY'
import json, sys
rows = [json.loads(line.split("layout-probe-focus ", 1)[1])
        for line in open(sys.argv[1])
        if line.endswith("\n") and "layout-probe-focus " in line]
alpha = [row for row in rows if row["rememberedClass"] == "pf.focus.alpha"
         and row["rememberedCenter"]][-1]
point = alpha["rememberedCenter"]
assert 0 < point["x"] < 1440 and 0 < point["y"] < 900
print(point["x"], point["y"])
PY
        read -r alpha_x alpha_y <"$OUT/target-alpha-control.txt"
        # The popup kept focus after Beta closed. Re-establish the intended app, not a fallback.
        pfinput "click $alpha_x $alpha_y"
        wait_target_context "$focus_boot" pf.focus.alpha
        pfinput "click $focus_x $focus_y"
        wait_target_popup pf.focus.alpha
        pfinput "key space"
        target_request=$(wait_target_reply "$focus_boot" prepare true "$target_request" pf.focus.alpha)
        [[ $(qdbus org.kde.KWin /KWin org.kde.KWin.currentDesktop) == 1 ]] || return 1
        generation=$(python3 "$HOME/.local/lib/layout-control/receipts.py" provider-generation \
            "$OUT/kwin.log")
        [[ $(qdbus org.kde.KWin /KWin org.kde.KWin.setCurrentDesktop 2) == true ]] || return 1
        [[ $(qdbus org.kde.KWin /KWin org.kde.KWin.setCurrentDesktop 1) == true ]] || return 1
        wait_target_settled "$focus_boot" $((generation + 2))
        pfinput "click $validate_x $validate_y"
        target_request=$(wait_target_reply "$focus_boot" validate false "$target_request" -)
        echo "PASS: leaving and returning to the desktop cannot revive an old preparation"

        python3 - "$OUT/plasmashell.log" "$focus_boot" >"$OUT/consumer-competitor.txt" <<'PY'
import json, sys
latest, controls = {}, {}
for line in open(sys.argv[1]):
    for marker, rows in (("layout-probe-observation ", latest),
                         ("layout-probe-focus-control ", controls)):
        if line.endswith("\n") and marker in line:
            row = json.loads(line.split(marker, 1)[1])
            rows[row["boot"]] = row
boots = set(latest) - {sys.argv[2]}
assert len(boots) == 1
boot = boots.pop()
print(boot, controls[boot]["x"], controls[boot]["y"], latest[boot]["packet"]["revision"])
PY
        read -r competitor_boot competitor_x competitor_y competitor_revision \
            <"$OUT/consumer-competitor.txt"
        # The desktop round trip deliberately cleared the remembered app. Re-establish it first.
        pfinput "click $alpha_x $alpha_y"
        wait_target_context "$competitor_boot" pf.focus.alpha
        pfinput "click $competitor_x $competitor_y"
        wait_target_popup pf.focus.alpha
        pfinput "key space"
        wait_consumer_state "$competitor_boot" "$competitor_revision" prepare false busy -
        cp "$OUT/consumer-current.json" "$OUT/consumer-busy-before.json"

        # Remove only the owned fixture whose native ID and current boot were checked first.
        python3 - "$focus_boot" "$OUT/widgets-created.txt" >"$OUT/consumer-remove.js" <<'PY'
import json, sys
owned = json.load(open(sys.argv[2]))
print("var boot=" + json.dumps(sys.argv[1]) + ",owned=" + json.dumps(owned) + ";")
print("""
var matches=[];
panels().forEach(function(p){p.widgets('org.plasmafusion.layoutprobe').forEach(function(w){
    w.currentConfigGroup=['General'];
    if(owned.indexOf(w.id)>=0 && JSON.parse(w.readConfig('layoutRequest','{}')).consumer===boot)
        matches.push(w);
});});
if(matches.length!==1) throw new Error('owned consumer not unique');
var removedId=matches[0].id;
matches[0].remove();
print(JSON.stringify({removedId:removedId,consumer:boot}));
""")
PY
        evaljs "$OUT/consumer-remove.js" >"$OUT/consumer-removed.json"
        wait_owned_consumer_removed
        competitor_revision=$(python3 - "$OUT/consumer-busy-before.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["packet"]["revision"])
PY
)
        qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut \
            "Plasma Fusion: Layout Probe Wake"
        wait_consumer_state "$competitor_boot" "$competitor_revision" prepare false busy -
        cp "$OUT/consumer-current.json" "$OUT/consumer-busy-after.json"
        python3 - "$OUT/consumer-busy-before.json" "$OUT/consumer-busy-after.json" <<'PY'
import json, sys
before, after = [json.load(open(path)) for path in sys.argv[1:]]
assert before["request"] == after["request"]
assert before["packet"]["targetContext"]["consumerLease"] == after["packet"]["targetContext"]["consumerLease"]
assert after["packet"]["revision"] > before["packet"]["revision"]
print("PASS: real widget removal does not promote the competitor's repeated busy intent")
PY

        pfinput "key esc"
        pfinput "click $alpha_x $alpha_y"
        wait_target_context "$competitor_boot" pf.focus.alpha
        python3 - "$OUT/plasmashell.log" "$competitor_boot" >"$OUT/consumer-new-control.txt" <<'PY'
import json, sys
rows = [json.loads(line.split("layout-probe-focus-control ", 1)[1])
        for line in open(sys.argv[1])
        if line.endswith("\n") and "layout-probe-focus-control " in line]
control = [row for row in rows if row["boot"] == sys.argv[2]][-1]
print(control["x"], control["y"])
PY
        read -r competitor_x competitor_y <"$OUT/consumer-new-control.txt"
        pfinput "click $competitor_x $competitor_y"
        wait_target_popup pf.focus.alpha
        pfinput "key space"
        competitor_revision=$(python3 - "$OUT/consumer-busy-after.json" <<'PY'
import json, sys
print(json.load(open(sys.argv[1]))["packet"]["revision"])
PY
)
        wait_consumer_state "$competitor_boot" "$competitor_revision" prepare true - pf.focus.alpha
        cp "$OUT/consumer-current.json" "$OUT/consumer-explicit-recovery.json"
        python3 - "$OUT/consumer-busy-after.json" "$OUT/consumer-explicit-recovery.json" <<'PY'
import json, sys
before, after = [json.load(open(path)) for path in sys.argv[1:]]
assert after["request"] > before["request"]
assert before["packet"]["targetContext"]["consumerLease"] == after["packet"]["targetContext"]["consumerLease"]
assert after["packet"]["preparation"]["ready"] and after["packet"]["preparation"]["token"]
print("PASS: a new explicit competitor intent succeeds after confirmed holder retirement")
PY
        mixed_lifetime_probe=$(kreadconfig6 --file "$HOME/.config/kwinrc" \
            --group Script-plasmafusion-layout-probe --key MixedLifetimeProbe --default false)
        if [[ $mixed_lifetime_probe == true ]]; then
            # Sourcing preserves this Bash parent's ownership of the shell and controlled app.
            # shellcheck source=tools/tests/layout-control/mixed_scenario.sh
            source "$HOME/.local/lib/layout-control/mixed_scenario.sh"
        fi
        printf 'quit\n' >&"$focus_input"
        wait "$focus_client"
        exec {focus_input}>&-
        printf '%s\n' '{"schema":1,"passed":true,' \
            '"checks":["roundtrip-native","guarded-target"]}' >"$OUT/target-preparation-result.json"
        printf '%s\n' '{"schema":1,"passed":true,' \
            '"checks":["roundtrip-native","guarded-target","consumer-retirement",' \
            '"busy-replay","explicit-recovery"]}' >"$OUT/consumer-retirement-result.json"
        finish_probe_session
        return 0
    fi
    printf 'quit\n' >&"$focus_input"
    wait "$focus_client"
    exec {focus_input}>&-
    removed=false
    for _ in {1..40}; do
        if python3 - "$OUT/kwin.log" 2>>"$OUT/focus-removal-wait.log" <<'PY'
import json, sys
events = [json.loads(line.split("layout-probe-focus ", 1)[1])
          for line in open(sys.argv[1]) if line.endswith("\n") and "layout-probe-focus " in line]
assert any(row["event"] == "removed" and not row["rememberedAlive"]
           and row["rememberedClass"] == "" for row in events)
print("PASS: controlled window removal clears the retained native candidate")
PY
        then
            removed=true
            break
        fi
        sleep 0.1
    done
    [[ $removed == true ]] || { echo "FAIL: removed target remained retained" >&2; return 1; }
    printf '%s\n' '{"schema":1,"passed":true,' \
        '"checks":["roundtrip-native","panel-keyboard-focus"]}' \
        >"$OUT/focus-observation-result.json"
    finish_probe_session
    return 0
fi

if [[ $reply_delay_ms != 0 ]]; then
    python3 - "$OUT/observations-online.json" "$OUT/plasmashell.log" "$OUT/kwin.log" \
        "$OUT/timeout-identity-before.txt" "$OUT/timeout-owner-before.txt" <<'PY'
import json, sys
from pathlib import Path
from xml.etree import ElementTree
rows = json.load(open(sys.argv[1]))
trace = open(sys.argv[2]).readlines()
history = [json.loads(line.split("layout-probe-observation ", 1)[1])
           for line in trace if line.endswith("\n") and "layout-probe-observation " in line]
for row in rows:
    boot = row["consumer"]
    timeline = [entry for entry in history if entry["boot"] == boot]
    unconfirmed = [index for index, entry in enumerate(timeline)
                   if entry["phase"] == "unconfirmed"]
    assert len(unconfirmed) == 1, "query must become unconfirmed once before its late reply"
    first_online = next(index for index, entry in enumerate(timeline) if entry["phase"] == "online")
    assert unconfirmed[0] < first_online
    expired = timeline[unconfirmed[0]]
    assert expired["packet"] is None and expired["accepted"] == 0
    assert expired["request"] == 1
    packet = row["observation"]["packet"]
    assert packet["request"] == expired["request"]
    assert packet["identityName"] == open(sys.argv[4]).read().strip()
    assert packet["backendOwner"] == open(sys.argv[5]).read().strip()
queries = [json.loads(line.split("layout-probe-query ", 1)[1])
           for line in trace if line.endswith("\n") and "layout-probe-query " in line]
schema = Path.home() / (
    ".local/share/plasma/plasmoids/org.plasmafusion.layoutprobe/contents/config/main.xml"
)
expected_deadline = int(ElementTree.parse(schema).find(
    ".//k:entry[@name='queryTimeoutMs']/k:default",
    {"k": "http://www.kde.org/standards/kcfg/1.0"},
).text)
assert {entry["boot"] for entry in queries} == {row["consumer"] for row in rows}
assert all(entry["deadlineMs"] == expected_deadline for entry in queries)
for row in rows:
    assert [entry["request"] for entry in queries if entry["boot"] == row["consumer"]] == [1]
provider = open(sys.argv[3]).read()
assert provider.count("layout-probe: initialized ") == 1
assert provider.count("layout-probe: wake received") == 2
assert provider.count("layout-probe: delayed publication queued") == 1
assert provider.count("layout-probe: delayed publication released") == 1
print("PASS: timeout is unconfirmed, not cancelled/retried; same-provider late state is accepted")
PY
    python3 - "$OUT/observations-online.json" "$OUT/timeout-stale.js" <<'PY'
import json, sys
messages = []
for row in json.load(open(sys.argv[1])):
    packet = dict(row["observation"]["packet"])
    packet["request"] = 0
    packet["revision"] += 10000
    messages.append({"consumer": row["consumer"], "packet": json.dumps(packet)})
with open(sys.argv[2], "w") as injection:
    injection.write("var messages=" + json.dumps(messages) + ";"
        "panels().forEach(function(p){"
        "p.widgets('org.plasmafusion.layoutprobe').forEach(function(w){"
        "w.currentConfigGroup=['General'];var q=JSON.parse(w.readConfig('layoutRequest',''));"
        "messages.forEach(function(m){if(m.consumer===q.consumer){"
        "w.writeConfig('layoutResponse',m.packet);}});});});")
PY
    evaljs "$OUT/timeout-stale.js" >"$OUT/timeout-stale-send.txt"
    for _ in {1..40}; do
        if [[ $(grep -c 'layout-probe-rejected request ' "$OUT/plasmashell.log") == 2 ]]; then
            break
        fi
        sleep 0.1
    done
    observations >"$OUT/observations-after-timeout-stale.json"
    python3 - "$OUT/observations-online.json" "$OUT/observations-after-timeout-stale.json" \
        "$OUT/plasmashell.log" <<'PY'
import json, sys
before = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[1]))}
after = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[2]))}
assert before.keys() == after.keys()
for boot, row in after.items():
    assert row["phase"] == "online" and row["request"] == 1
    assert row["packet"]["request"] == 1 and row["epoch"] == before[boot]["epoch"]
    assert before[boot]["revision"] <= row["revision"] < before[boot]["revision"] + 10000
trace = open(sys.argv[3]).read()
assert trace.count("layout-probe-rejected request ") == 2
accepted = [json.loads(line.split("layout-probe-observation ", 1)[1])
            for line in trace.splitlines() if "layout-probe-observation " in line]
assert all(not entry["packet"] or entry["packet"]["request"] == 1 for entry in accepted)
queries = [line for line in trace.splitlines() if "layout-probe-query " in line]
assert len(queries) == 2
print("PASS: wrong-request high revisions cannot replace the valid late state or trigger retries")
PY
    printf '%s\n' '{"schema":1,"passed":true,' \
        '"checks":["roundtrip-native","query-timeout","late-state"]}' \
        >"$OUT/query-timeout-result.json"
    finish_probe_session
    return 0
fi

drop_retirement_frame=$(kreadconfig6 --file "$HOME/.config/kwinrc" \
    --group Script-plasmafusion-layout-probe --key DropRetirementFrame --default false)
if [[ $drop_retirement_frame == true ]]; then
    cp "$OUT/observations-online.json" "$OUT/observations-initial.json"
    qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript plasmafusion-layout-probe \
        >"$OUT/unload-result.txt"
    identity_held=true
    for _ in {1..40}; do
        identity_held=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus \
            org.freedesktop.DBus.NameHasOwner "$identity_name")
        [[ $identity_held == false ]] && break
        sleep 0.1
    done
    [[ $identity_held == false ]] || { echo "FAIL: quiet retirement kept its alias" >&2; return 1; }
    printf '%s\n' "$identity_held" >"$OUT/retired-identity-owned.txt"
    current_backend=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus \
        org.freedesktop.DBus.GetNameOwner org.kde.KWin)
    [[ $current_backend == "$backend_owner" ]] || return 1
    printf '%s\n' "$current_backend" >"$OUT/silent-backend-owner.txt"
    wait_for_phase unknown 2>"$OUT/silent-loss-wait.log"
    python3 - "$OUT/observations-initial.json" "$OUT/observations-unknown.json" \
        "$OUT/kwin.log" "$OUT/plasmashell.log" <<'PY'
import json, sys
before = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[1]))}
after = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[2]))}
assert before.keys() == after.keys()
for boot, row in after.items():
    assert row["packet"] is None and row["epoch"] == "" and row["revision"] == -1, row
    assert row["request"] > before[boot]["packet"]["request"], row
assert open(sys.argv[3]).read().count("layout-probe: retirement frame deliberately dropped") == 1
frames = [json.loads(line.split("layout-probe-received ", 1)[1])
          for line in open(sys.argv[4]) if "layout-probe-received " in line]
assert not any(frame["status"] == "offline" for frame in frames)
print("PASS: both live receivers invalidate without a retirement frame; KWin remains unchanged")
PY
    reload_probe
    python3 - "$OUT/observations-initial.json" "$OUT/observations-reloaded.json" <<'PY'
import json, sys
before = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[1]))}
after = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[2]))}
assert before.keys() == after.keys()
for boot, row in after.items():
    assert row["epoch"] != before[boot]["epoch"]
    assert row["packet"]["request"] > before[boot]["packet"]["request"]
print("PASS: the same live receivers recover only with a fresh query and new provider epoch")
PY
    printf '%s\n' \
        '{"schema":1,"passed":true,' \
        '"checks":["roundtrip-native","silent-retirement","provider-reload"]}' \
        >"$OUT/silent-retirement-result.json"
    finish_probe_session
    return 0
fi

cp "$OUT/observations-online.json" "$OUT/observations-initial.json"
qdbus org.kde.KWin /Scripting org.kde.kwin.Scripting.unloadScript plasmafusion-layout-probe \
    >"$OUT/unload-result.txt"
wait_for_phase unknown 2>"$OUT/retirement-wait.log"
cp "$OUT/observations-unknown.json" "$OUT/observations-retired.json"
identity_held=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.NameHasOwner "$identity_name")
[[ $identity_held == false ]] || { echo "FAIL: retired alias still owned" >&2; return 1; }
printf '%s\n' "$identity_held" >"$OUT/retired-identity-owned.txt"
retirement_received=false
for _ in {1..40}; do
    if python3 - "$OUT/observations-initial.json" "$OUT/observations-retired.json" \
        "$OUT/plasmashell.log" 2>>"$OUT/offline-delivery-wait.log" <<'PY'
import json, sys
before = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[1]))}
after = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[2]))}
assert before.keys() == after.keys()
for boot, current in after.items():
    assert current["phase"] == "unknown" and current["packet"] is None
    assert current["epoch"] == "" and current["revision"] == -1
    assert current["request"] > before[boot]["packet"]["request"]
frames = [json.loads(line.split("layout-probe-received ", 1)[1])
          for line in open(sys.argv[3])
          if line.endswith("\n") and "layout-probe-received " in line]
offline = {frame["receiverBoot"]: frame for frame in frames if frame["status"] == "offline"}
assert offline.keys() == before.keys()
for boot, frame in offline.items():
    assert frame["consumer"] == boot, "retirement frame reached the wrong live receiver"
    assert frame["epoch"] == before[boot]["epoch"]
    assert frame["request"] == before[boot]["packet"]["request"]
    assert frame["revision"] > before[boot]["revision"]
print("PASS: cached retirement frame reached both live widgets, and withdrawal invalidated state")
PY
    then
        retirement_received=true
        break
    fi
    sleep 0.1
done
[[ $retirement_received == true ]] || { echo "FAIL: missing retirement delivery" >&2; return 1; }
printf '%s\n' '{"schema":1,"passed":true,"checks":["roundtrip-native","retirement"]}' \
    >"$OUT/layout-probe-result.json"
reload_probe
python3 - "$OUT/observations-initial.json" "$OUT/observations-reloaded.json" <<'PY'
import json, sys
before = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[1]))}
after = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[2]))}
assert before.keys() == after.keys()
for key, current in after.items():
    assert current["epoch"] != before[key]["epoch"]
    assert current["packet"]["request"] > before[key]["packet"]["request"]
    assert current["packet"]["capable"] is True
print("PASS: provider reload uses a fresh exchange and new epoch for both live receivers")
PY
printf '%s\n' '{"schema":1,"providerReload":true}' >"$OUT/reload-result.json"

shell_owner=$(qdbus org.freedesktop.DBus /org/freedesktop/DBus \
    org.freedesktop.DBus.GetNameOwner org.kde.plasmashell)
python3 - "$OUT/observations-reloaded.json" "$shell_owner" "$OUT/stale-backend.js" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
messages = []
for row in rows:
    packet = dict(row["observation"]["packet"])
    packet["backendOwner"] = sys.argv[2]
    packet["revision"] += 10000
    messages.append({"consumer": row["consumer"], "packet": json.dumps(packet)})
with open(sys.argv[3], "w") as injection:
    injection.write("var messages=" + json.dumps(messages) + ";"
        "panels().forEach(function(p){p.widgets('org.plasmafusion.layoutprobe').forEach(function(w){"
        "w.currentConfigGroup=['General'];var q=JSON.parse(w.readConfig('layoutRequest',''));"
        "messages.forEach(function(m){if(m.consumer===q.consumer){"
        "w.writeConfig('layoutResponse',m.packet);}});});});")
PY
evaljs "$OUT/stale-backend.js" >"$OUT/stale-backend-send.txt"
for _ in {1..40}; do
    observations >"$OUT/observations-after-stale-backend.json"
    if python3 - "$OUT/observations-after-stale-backend.json" "$OUT/plasmashell.log" "$shell_owner" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
trace = open(sys.argv[2]).read()
assert (all(row["observation"]["packet"]["backendOwner"] == sys.argv[3] for row in rows)
        or trace.count('layout-probe-rejected backend owner ') >= 2)
PY
    then
        break
    fi
    sleep 0.1
done
python3 - "$OUT/observations-reloaded.json" "$OUT/observations-after-stale-backend.json" \
    "$OUT/plasmashell.log" "$shell_owner" <<'PY'
import json, sys
before = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[1]))}
after = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[2]))}
assert before.keys() == after.keys()
for boot, row in after.items():
    old = before[boot]
    assert row["phase"] == "online" and row["epoch"] == old["epoch"]
    assert row["request"] == old["request"]
    assert row["packet"]["backendOwner"] == old["packet"]["backendOwner"]
    assert row["packet"]["identityName"] == old["packet"]["identityName"]
    # A queued legitimate reply may arrive; it must not be the injected high revision.
    assert old["revision"] <= row["revision"] < old["revision"] + 10000
trace = open(sys.argv[3]).read()
assert trace.count('layout-probe-rejected backend owner ') == 2
accepted = [json.loads(line.split("layout-probe-observation ", 1)[1])
            for line in trace.splitlines() if "layout-probe-observation " in line]
assert all(not row["packet"] or row["packet"]["backendOwner"] != sys.argv[4] for row in accepted)
print("PASS: wrong-backend high-revision frames rejected by both receivers")
PY
printf '%s\n' '{"schema":1,"aliasReleased":true,"staleBackendRejected":true}' \
    >"$OUT/identity-fence-result.json"

observations >"$OUT/observations-before-ordering.json"
python3 - "$OUT/observations-before-ordering.json" "$OUT/ordering-burst.js" \
    "$OUT/ordering-inputs.json" <<'PY'
import json, sys
rows = json.load(open(sys.argv[1]))
messages = []
expected = {}
for row in rows:
    packet = row["observation"]["packet"]
    base = packet["revision"]
    assert base < 2147483546, "burst would exceed the protocol's integer bound"
    expected[row["consumer"]] = {
        "low": base + 10, "high": base + 100, "middle": base + 90,
        "epoch": packet["epoch"], "request": packet["request"],
        "backendOwner": packet["backendOwner"], "identityName": packet["identityName"],
    }
    frames = [json.dumps(packet | {"revision": base + offset}) for offset in (10, 100, 90)]
    messages.append({"consumer": row["consumer"], "packets": frames})
with open(sys.argv[3], "w") as inputs:
    json.dump(expected, inputs)
with open(sys.argv[2], "w") as injection:
    injection.write("var messages=" + json.dumps(messages) + ";var written=0;"
        "panels().forEach(function(p){"
        "p.widgets('org.plasmafusion.layoutprobe').forEach(function(w){"
        "w.currentConfigGroup=['General'];var q=JSON.parse(w.readConfig('layoutRequest',''));"
        "messages.forEach(function(m){if(m.consumer===q.consumer){"
        "m.packets.forEach(function(packet){"
        "w.writeConfig('layoutResponse',packet);++written;});}});});});print(written);")
PY
evaljs "$OUT/ordering-burst.js" >"$OUT/ordering-burst-send.txt"
[[ $(cat "$OUT/ordering-burst-send.txt") == 6 ]] || return 1
python3 - "$OUT/ordering-inputs.json" "$OUT/plasmashell.log" <<'PY'
import json, sys
expected = json.load(open(sys.argv[1]))
lines = open(sys.argv[2]).readlines()
for boot, spec in expected.items():
    revisions = {spec[key] for key in ("low", "high", "middle")}
    received = {}
    accepted = []
    for index, line in enumerate(lines):
        if not line.endswith("\n"):
            continue
        if "layout-probe-received " in line:
            packet = json.loads(line.split("layout-probe-received ", 1)[1])
            if packet["receiverBoot"] == boot and packet["revision"] in revisions:
                assert packet["consumer"] == boot and packet["epoch"] == spec["epoch"]
                assert packet["request"] == spec["request"]
                received[packet["revision"]] = index
        if "layout-probe-observation " in line:
            row = json.loads(line.split("layout-probe-observation ", 1)[1])
            if row["boot"] == boot and row["packet"] and row["revision"] in revisions:
                accepted.append(index)
    assert received.keys() == revisions, "burst packets did not all reach the live receiver"
    assert not accepted or min(accepted) > max(received.values()), \
        "burst did not queue while verification was in flight"
print("PASS: all six burst frames reached the intended receivers before verification completed")
PY
ordered=false
for _ in {1..40}; do
    observations >"$OUT/observations-after-ordering.json"
    if python3 - "$OUT/ordering-inputs.json" "$OUT/observations-after-ordering.json" \
        2>>"$OUT/ordering-wait.log" <<'PY'
import json, sys
expected = json.load(open(sys.argv[1]))
after = {row["consumer"]: row["observation"] for row in json.load(open(sys.argv[2]))}
assert after.keys() == expected.keys()
for boot, row in after.items():
    spec = expected[boot]
    assert row["phase"] == "online" and row["revision"] == spec["high"], row
    assert row["packet"]["consumer"] == boot and row["epoch"] == spec["epoch"]
    assert row["packet"]["request"] == spec["request"]
    assert row["packet"]["backendOwner"] == spec["backendOwner"]
    assert row["packet"]["identityName"] == spec["identityName"]
PY
    then
        ordered=true
        break
    fi
    sleep 0.1
done
[[ $ordered == true ]] || { echo "FAIL: newer pending state was lost" >&2; return 1; }
printf '%s\n' '{"schema":1,"passed":true,' \
    '"checks":["roundtrip-native","same-provider-ordering"]}' >"$OUT/reply-ordering-result.json"
echo "PASS: same-provider ordering plus prior transport/lifetime checks; full G0 remains open"
finish_probe_session
