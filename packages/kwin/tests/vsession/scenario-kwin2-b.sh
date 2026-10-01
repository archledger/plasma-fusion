# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# KWIN-2 private-session scenario B (test tooling; ADAPTIVE M23, owner decision 8): a second
# output that appears after login gets its top bar. The session has two virtual outputs; the
# second is disabled before Plasma Fusion is installed and enabled afterwards (the hot-plug).
exec 2>&1
export OUT
set -x
CHK=$OUT/checks.txt
KLOG=$OUT/kwin.log
PLOG=$OUT/plasmashell.log
pass() { echo "PASS $*" >>"$CHK"; }
fail() { echo "FAIL $*" >>"$CHK"; }
info() { echo "INFO $*" >>"$CHK"; }
outputs() { kscreen-doctor -o 2>/dev/null | sed 's/\x1b\[[0-9;]*m//g' | awk '/^Output:/{print $3, $4, $5, $6}'; }
bars() { # prints "screen:location:height ..." for every panel
  evaljs - <<'JS' | tr '\n' ' '
var ps = panels(), out = [];
for (var i = 0; i < ps.length; ++i) { out.push(ps[i].screen + ":" + ps[i].location + ":" + ps[i].height + ":" + ps[i].widgetIds.length); }
print("screens " + screenCount + " panels " + out.join(" "));
JS
}
outputs >"$OUT/outputs-0.txt"
O2=$(awk 'NR==2{print $1}' "$OUT/outputs-0.txt")
info "outputs at start: $(tr '\n' ';' <"$OUT/outputs-0.txt"); second: $O2"
kscreen-doctor "output.$O2.disable" >>"$OUT/kscreen-doctor.log" 2>&1
sleep 4
outputs >"$OUT/outputs-1.txt"
info "after disabling $O2: $(tr '\n' ';' <"$OUT/outputs-1.txt")"
bash "$HOME/pf-tools/device/fusion-config.sh" --install "$HOME/pf-stage" >"$OUT/fc.log" 2>&1
info "fusion-config rc=$?"
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardShown true
kwriteconfig6 --file plasmafusionrc --group Tablet --key GestureCardVersion 99
pfv_restart_shell 12
qdbus org.kde.KWin /KWin reconfigure; sleep 3
B0=$(bars); info "one output: $B0"
shot m23-0-one-output
N0=$(grep -ac 'plasmafusion-snap: top bars' "$KLOG")
kscreen-doctor "output.$O2.enable" >>"$OUT/kscreen-doctor.log" 2>&1
sleep 8
outputs >"$OUT/outputs-2.txt"
info "after enabling $O2: $(tr '\n' ';' <"$OUT/outputs-2.txt")"
B1=$(bars); info "two outputs: $B1"
shot m23-1-two-outputs
grep -a 'plasmafusion-snap:' "$KLOG" | tail -4 >>"$CHK"
python3 - "$B0" "$B1" >>"$CHK" <<'PY'
import sys
def tops(s):
    return sorted(p.split(":")[0] for p in s.split("panels", 1)[1].split() if p.split(":")[1] == "top")
a, b = tops(sys.argv[1]), tops(sys.argv[2])
print(("PASS" if len(a) == 1 and len(b) == 2 and len(set(b)) == 2 else "FAIL") + f" M23: top bars on screens {a} before and {b} after the second output appeared")
PY
[ "$(grep -ac 'plasmafusion-snap: top bars' "$KLOG")" -gt "$N0" ] && pass "M23: the snap script ran the top-bar check after the output appeared" || fail "M23: no top-bar check in KWin's log"
# again (idempotent): off and on once more must not add a third bar
kscreen-doctor "output.$O2.disable" >>"$OUT/kscreen-doctor.log" 2>&1
sleep 6
B2=$(bars); info "second output off again: $B2"
kscreen-doctor "output.$O2.enable" >>"$OUT/kscreen-doctor.log" 2>&1
sleep 8
B3=$(bars); info "second output on again: $B3"
python3 - "$B3" >>"$CHK" <<'PY'
import sys
t = [p for p in sys.argv[1].split("panels", 1)[1].split() if p.split(":")[1] == "top"]
print(("PASS" if len(t) == 2 else "FAIL") + f" M23: still one top bar per screen after a second hot-plug: {t}")
PY
shot m23-2-again
grep -a 'plasmafusion-snap:' "$KLOG" | tail -3 >>"$CHK"
grep -aE 'plasmafusion-snap' "$KLOG" | grep -aiE 'error|TypeError|ReferenceError|Unable to assign|is not defined' | head -10 >"$OUT/warnings.txt"
info "snap script warnings: $(wc -l <"$OUT/warnings.txt")"
[ "$(grep -ac 'KCrash: Application' "$KLOG")" = 0 ] && pass "KWin did not crash" || fail "KWin crashed"
[ "$(grep -c 'KCrash: Application' "$PLOG")" = 0 ] && pass "plasmashell did not crash" || fail "plasmashell crashed"
echo "scenario done" >>"$CHK"
