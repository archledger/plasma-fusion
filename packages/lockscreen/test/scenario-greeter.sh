# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test tooling (not installed): tools/vsession scenario that runs the real kscreenlocker_greet
# (--testing) in a private virtual session, the package selected only through
# PLASMA_DEFAULT_SHELL, and screenshots the idle and prompt states.
#
# Seed = a full build plus this folder's mock_services.py and an env file:
#   STAGE=SEED tools/build.sh
#   mkdir -p SEED/pf-rlk && cp packages/lockscreen/test/mock_services.py SEED/pf-rlk/
#   printf 'PF_SCHEME=dark\nPF_LC=en_GB.UTF-8\n' >SEED/pf-rlk/env      # or light / en_US.UTF-8
#   printf '[Layout]\nLayoutList=us\nUse=true\n' >SEED/.config/kxkbrc  # KWin reads it at start
#   tools/vsession/remote.sh NAME packages/lockscreen/test/scenario-greeter.sh SEED 1440x900 200
#
# PF_SCHEME (dark|light) and PF_LC (locale for LC_TIME) come from the seed file pf-rlk/env.
# No password is typed or submitted; each greeter run is killed after at most ~25 s.
. "$HOME/pf-rlk/env"
log() { echo "[$(date +%T)] $*"; }
if [ "$PF_SCHEME" = light ]; then
  SCHEME=PlasmaFusionLight; ICONS=PlasmaFusion; STYLE=plasma-fusion-light
else
  SCHEME=PlasmaFusionDark; ICONS=PlasmaFusion-Dark; STYLE=plasma-fusion-dark
fi
plasma-apply-colorscheme "$SCHEME" >"$OUT/apply.log" 2>&1
kwriteconfig6 --file kdeglobals --group Icons --key Theme "$ICONS"
kwriteconfig6 --file plasmarc --group Theme --key name "$STYLE"
kwriteconfig6 --file kscreenlockerrc --group Greeter --key WallpaperPlugin org.kde.image
kwriteconfig6 --file kscreenlockerrc --group Greeter --group Wallpaper --group org.kde.image --group General --key Image "file://$HOME/.local/share/wallpapers/PlasmaFusion/"
log "config written ($SCHEME, $ICONS, $STYLE, LC_TIME=$PF_LC)"

# Test-only driver (private HOME only): the same package under another id whose root shows
# the prompt after 5 s, as a key press would.
T=$HOME/.local/share/plasma/shells/org.plasmafusion.lockshelltest
rm -rf "$T"; cp -r "$HOME/.local/share/plasma/shells/org.plasmafusion.lockshell" "$T"
sed -i 's/"Id": "org.plasmafusion.lockshell"/"Id": "org.plasmafusion.lockshelltest"/' "$T/metadata.json"
python3 - "$T/contents/lockscreen/LockScreen.qml" <<'EOF'
import sys
p = sys.argv[1]; s = open(p).read()
drv = '''
    Timer {
        interval: 5000
        running: true
        onTriggered: {
            const find = item => {
                if (item.objectName === "lockScreenRoot") return item;
                for (let i = 0; i < item.children.length; ++i) {
                    const r = find(item.children[i]);
                    if (r) return r;
                }
                return null;
            };
            const r = find(root);
            if (r) { r.uiVisible = true; console.warn("PFTEST: prompt shown"); }
        }
    }
}
'''
i = s.rstrip().rfind("}")
open(p, "w").write(s[:i].rstrip() + "\n" + drv)
EOF

python3 "$HOME/pf-rlk/mock_services.py" mpris inhibit >"$OUT/mock.log" 2>&1 &
MOCK=$!
sleep 1

notify() { # app icon desktop summary body
  notify-send -a "$1" -i "$2" --hint="string:desktop-entry:$3" "$4" "$5"
}

greeter() { # name shell
  env PLASMA_DEFAULT_SHELL="$2" LC_TIME="$PF_LC" QT_FORCE_STDERR_LOGGING=1 \
    /usr/libexec/kscreenlocker_greet --testing >"$OUT/greeter-$1.log" 2>&1 &
  GPID=$!
}

# 1. idle (the real package, chosen by PLASMA_DEFAULT_SHELL alone)
greeter idle org.plasmafusion.lockshell
sleep 5
notify Calendar office-calendar org.kde.merkuro.calendar "Team sync" "Event starting in 10 min"
sleep 0.3
for i in 1 2 3; do notify Mail internet-mail org.kde.kmail2 "Message $i" "Private body"; sleep 0.2; done
sleep 4
shot "idle-$PF_SCHEME"
log "idle shot"
kill "$GPID" 2>/dev/null; sleep 1; kill -9 "$GPID" 2>/dev/null
sleep 1

# 2. prompt (driver copy): the real PAM stack starts when the prompt shows; nothing is typed.
greeter prompt org.plasmafusion.lockshelltest
sleep 4
notify Calendar office-calendar org.kde.merkuro.calendar "Team sync" "Event starting in 10 min"
sleep 0.3
for i in 1 2 3; do notify Mail internet-mail org.kde.kmail2 "Message $i" "Private body"; sleep 0.2; done
sleep 4
shot "prompt-$PF_SCHEME"
log "prompt shot"
kill "$GPID" 2>/dev/null; sleep 1; kill -9 "$GPID" 2>/dev/null
kill "$MOCK" 2>/dev/null
if kill -0 "$GPID" 2>/dev/null; then log "greeter still running"; else log "no greeter left"; fi
grep -h -i "qml\|warn\|error\|PFTEST\|lockscreen" "$OUT"/greeter-*.log | grep -v "^$" | head -60 >"$OUT/greeter-warnings.txt"
