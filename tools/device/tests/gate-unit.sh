#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of the login check (tools/device/gate/plasma-fusion-gate.sh) against throw-away HOME
# trees. Test tooling only, not installed. Never touches the caller's HOME, session or systemd:
# every run is `env -i` with a HOME, XDG_RUNTIME_DIR and fake rpm below BASE.
#
#   gate-unit.sh BASE [--real-rpm]
#
# BASE must be a scratch directory on disk (not /tmp); it is emptied first. --real-rpm uses the
# machine's rpm for the timing runs (the other cases always use a fake rpm).
set -u
BASE=${1:?scratch directory}
# The cases change directory, so a relative BASE is made absolute first.
BASE=$(realpath -m -- "$BASE")
REAL_RPM=0
[ "${2:-}" = --real-rpm ] && REAL_RPM=1
HERE=$(cd "$(dirname "$0")" && pwd)
ENGINE=$HERE/../gate/plasma-fusion-gate.sh
REPO=$(cd "$HERE/../../.." && pwd)
LOCKPKG=$REPO/packages/lockscreen/org.plasmafusion.lockshell
case $BASE in /tmp/* | /tmp) echo "use a directory on disk, not /tmp" >&2; exit 2 ;; esac
rm -rf "${BASE:?}"
mkdir -p "$BASE/run" && chmod 700 "$BASE/run"

PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS $*"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $*"; }
check() { # DESCRIPTION COMMAND...
  local d=$1
  shift
  if "$@"; then ok "$d"; else bad "$d"; fi
}

# Fake rpm: answers -q --qf '%{NAME}=%{VERSION}\n' from $BASE/versions.
cat >"$BASE/fake-rpm" <<'EOF'
#!/bin/bash
v=$(dirname "$0")/versions
[ -f "$(dirname "$0")/rpm-hang" ] && sleep 30
shift 3
rc=0
for p in "$@"; do
  line=$(grep -m1 "^$p=" "$v")
  if [ -n "$line" ]; then echo "$line"; else echo "package $p is not installed"; rc=$((rc + 1)); fi
done
exit $rc
EOF
chmod +x "$BASE/fake-rpm"
cat >"$BASE/versions" <<'EOF'
plasma-workspace=6.7.5
kwin=6.7.5
kscreenlocker=6.7.5
libplasma=6.7.5
kdecoration=6.7.5
qt6-qtbase=6.11.2
qt6-qtdeclarative=6.11.2
EOF

H=
FAKE=
TOOL=
RPM=$BASE/fake-rpm
# The compiled decoration as the check looks for it (a test machine may not have it installed).
PLUGINS=$BASE/plugins
mkdir -p "$PLUGINS/org.kde.kdecoration3" && : >"$PLUGINS/org.kde.kdecoration3/org.plasmafusion.decoration.so"
gate() { # MODE... in the current HOME $H
  env -i HOME="$H" PATH=/usr/bin:/bin XDG_RUNTIME_DIR="$BASE/run" XDG_CONFIG_DIRS=/etc/xdg \
    XDG_DATA_DIRS=/usr/local/share:/usr/share LANG="${GATE_LANG:-C.UTF-8}" PF_GATE_RPM="$RPM" QT_PLUGIN_PATH="$PLUGINS" \
    ${FAKE:+PF_GATE_FAKE_VERSIONS="$FAKE"} ${TOOL:+PF_GATE_TOOL="$TOOL"} bash "$ENGINE" "$@"
}
kw() { # FILE GROUP KEY VALUE|--delete, user file of $H
  if [ "$4" = --delete ]; then
    kwriteconfig6 --file "$H/.config/$1" --group "$2" --key "$3" --delete
  else
    kwriteconfig6 --file "$H/.config/$1" --group "$2" --key "$3" -- "$4"
  fi
}
kwd() { kwriteconfig6 --file "$H/.config/kdedefaults/$1" --group "$2" --key "$3" -- "$4"; } # kdedefaults layer
get() { # FILE GROUP KEY: the user file's raw line value, or <absent>
  awk -v g="[$2]" -v k="$3" '/^\[/{c=($0==g)} c && index($0, k"=")==1 {v=substr($0, length(k)+2); f=1} END{print f ? v : "<absent>"}' "$H/.config/$1" 2>/dev/null || echo "<absent>"
}
# Every file|group|key=value under ~/.config, sorted: equal when KConfig reads the same values
# (the check edits files in place, so key order inside a group may differ after a restore).
sums() {
  (cd "$H/.config" && find . -type f | LC_ALL=C sort | while IFS= read -r f; do
    awk -v F="$f" '{ t = $0; sub(/^[ \t]+/, "", t); sub(/[ \t]+$/, "", t) }
      t == "" || t ~ /^#/ { next } t ~ /^\[/ { g = t; next } { sub(/[ \t]*=[ \t]*/, "=", t); print F "|" g "|" t }' "$f"
  done) | LC_ALL=C sort
}
kread() { kreadconfig6 --file "$H/.config/$1" --group "$2" --key "$3"; } # KConfig's own reading
# The value in effect, as the session reads it (user file over ~/.config/kdedefaults).
keff() { XDG_CONFIG_HOME="$H/.config" XDG_CONFIG_DIRS="$H/.config/kdedefaults:/etc/xdg" kreadconfig6 --file "$1" --group "$2" --key "$3"; }

# A HOME configured the way fusion-config.sh leaves it, with the compiled decoration chosen in the
# settings module. $1 directory, $2 variant (Dark/Light)
make_home() {
  H=$1
  local v=${2:-Dark} lnf=org.plasmafusion.dark.desktop
  [ "$v" = Light ] && lnf=org.plasmafusion.light.desktop
  mkdir -p "$H/.config/kdedefaults" "$H/.config/systemd/user/plasma-kwin_wayland.service.d" \
    "$H/.local/share/plasma/shells" "$H/.local/share/aurorae/themes"
  cp -a "$LOCKPKG" "$H/.local/share/plasma/shells/"
  for t in PlasmaFusionDark PlasmaFusionLight PlasmaFusionDark-Left PlasmaFusionLight-Left; do
    mkdir -p "$H/.local/share/aurorae/themes/$t"
    printf '[Desktop Entry]\nName=%s\n' "$t" >"$H/.local/share/aurorae/themes/$t/metadata.desktop"
  done
  printf '[Service]\nEnvironment=PLASMA_DEFAULT_SHELL=org.plasmafusion.lockshell\n' \
    >"$H/.config/systemd/user/plasma-kwin_wayland.service.d/plasma-fusion-lockscreen.conf"
  kw kdeglobals KDE LookAndFeelPackage "$lnf"
  kw kdeglobals General font "Manrope,9.75,-1,5,400,0,0,0,0,0,0,0,0,0,0,1,,0,0"
  kwd kdeglobals General ColorScheme "PlasmaFusion$v"
  kwd kwinrc org.kde.kdecoration2 library org.kde.kwin.aurorae.v2
  kwd kwinrc org.kde.kdecoration2 theme "__aurorae__svg__PlasmaFusion$v"
  kwd kwinrc org.kde.kdecoration2 ButtonsOnLeft M
  kwd kwinrc org.kde.kdecoration2 ButtonsOnRight IAX
  kwd kwinrc TabBox LayoutName org.plasmafusion.switcher
  kw kwinrc org.kde.kdecoration2 library org.plasmafusion.decoration
  kw kwinrc org.kde.kdecoration2 theme ""
  kw kwinrc org.kde.kdecoration2 BorderSizeAuto false
  kw kwinrc Plugins plasmafusion-snapEnabled true
  kw kwinrc Plugins plasmafusion-attachEnabled true
  kw kwinrc Plugins sheetEnabled true
  kw kwinrc Plugins plasmafusion_navigationEnabled true
  kw kwinrc Outline QmlPath kwin/scripts/plasmafusion-snap/contents/outline/outline.qml
  for g in TabBox TabBoxAlternative; do
    kw kwinrc "$g" LayoutName org.plasmafusion.switcher
    kw kwinrc "$g" DesktopMode 0
    kw kwinrc "$g" HighlightWindows false
  done
  kw plasmafusionrc Decoration ButtonStyle RightGlyphs
}
DROPIN_REL=systemd/user/plasma-kwin_wayland.service.d/plasma-fusion-lockscreen.conf

echo "== engine $ENGINE"
bash -n "$ENGINE" || exit 1

# ---------- (a) matching versions: nothing changes ----------
make_home "$BASE/a"
gate deploy >"$BASE/a.deploy.log" 2>&1
check "a: deploy writes the tested record" grep -q '^pkg kwin=6.7.5$' "$H/.local/state/plasma-fusion/gate/tested"
before=$(sums)
gate login
check "a: login exits 0" [ $? = 0 ]
check "a: matching versions change no config file" [ "$(sums)" = "$before" ]
check "a: nothing recorded" [ ! -e "$H/.local/state/plasma-fusion/gate/off" ]
check "a: no notification" [ ! -e "$H/.local/state/plasma-fusion/gate/notify" ]
check "a: log line 'no change'" grep -q 'login: theme=org.plasmafusion.dark.desktop versions=tested lock=tested; no change' "$H/.local/state/plasma-fusion/gate.log"

# ---------- (b) faked KWin / kscreenlocker version ----------
make_home "$BASE/b"
# fusion-config.sh passes its own path; the notification names it as the way back.
TOOL=$H/deploy/tools/device/fusion-config.sh
mkdir -p "${TOOL%/*}" && : >"$TOOL"
gate deploy >/dev/null 2>&1
TOOL=
check "b: deploy records the fusion-config.sh path" grep -qx "tool=$H/deploy/tools/device/fusion-config.sh" "$H/.local/state/plasma-fusion/gate/tested"
orig=$(sums)
FAKE="kwin=6.8.0 kscreenlocker=6.8.0"
gate check >"$BASE/b.check.log"
check "b: check changes nothing" [ "$(sums)" = "$orig" ]
check "b: check reports the fallback" grep -q 'would change: lock screen' "$BASE/b.check.log"
gate login
check "b: login exits 0" [ $? = 0 ]
check "b: drop-in moved aside" [ ! -e "$H/.config/$DROPIN_REL" ]
check "b: drop-in saved" [ -f "$H/.local/state/plasma-fusion/gate/saved/plasma-fusion-lockscreen.conf" ]
check "b: decoration library Aurorae" [ "$(keff kwinrc org.kde.kdecoration2 library)" = org.kde.kwin.aurorae.v2 ]
check "b: decoration theme PlasmaFusionDark" [ "$(keff kwinrc org.kde.kdecoration2 theme)" = __aurorae__svg__PlasmaFusionDark ]
# The Global Theme names the Aurorae theme in kdedefaults: the user's keys go, so the title bars
# follow a light/dark switch startplasma makes after the check (Follow sunset).
check "b: user decoration keys removed (kdedefaults gives the Aurorae theme)" [ "$(get kwinrc org.kde.kdecoration2 library)/$(get kwinrc org.kde.kdecoration2 theme)" = "<absent>/<absent>" ]
check "b: Fusion-only parts untouched (snap on)" [ "$(get kwinrc Plugins plasmafusion-snapEnabled)" = true ]
check "b: navigation effect off (built against KWin's internals)" [ "$(get kwinrc Plugins plasmafusion_navigationEnabled)" = false ]
check "b: notification names the gestures" grep -q "KWin's own edges instead of the tablet gestures" "$H/.local/state/plasma-fusion/gate/notify"
check "b: notification queued" grep -q 'kwin 6.7.5 → 6.8.0, kscreenlocker 6.7.5 → 6.8.0' "$H/.local/state/plasma-fusion/gate/notify"
check "b: notification names the recorded fusion-config.sh" grep -qF "run ~/deploy/tools/device/fusion-config.sh." "$H/.local/state/plasma-fusion/gate/notify"
check "b: status says changed" grep -q '^versions=changed' "$H/.local/state/plasma-fusion/gate/status"
rm -f "$H/.local/state/plasma-fusion/gate/notify"
mid=$(sums)
gate login
check "b: second mismatching login changes nothing" [ "$(sums)" = "$mid" ]
check "b: no second notification for the same versions" [ ! -e "$H/.local/state/plasma-fusion/gate/notify" ]
FAKE=
gate login
check "b: matching login restores every config file" [ "$(sums)" = "$orig" ]
check "b: records cleared" [ ! -e "$H/.local/state/plasma-fusion/gate/off" ]
check "b: saved drop-in removed" [ ! -e "$H/.local/state/plasma-fusion/gate/saved/plasma-fusion-lockscreen.conf" ]

# b2: left circles and light
make_home "$BASE/b2" Light
kw plasmafusionrc Decoration ButtonStyle LeftCircles
gate deploy >/dev/null 2>&1
orig=$(sums)
FAKE="qt6-qtdeclarative=6.12.0"
gate login
check "b2: light left-circles theme" [ "$(get kwinrc org.kde.kdecoration2 theme)" = __aurorae__svg__PlasmaFusionLight-Left ]
check "b2: left-circles button lists" [ "$(get kwinrc org.kde.kdecoration2 ButtonsOnLeft)/$(get kwinrc org.kde.kdecoration2 ButtonsOnRight)" = XIA/_ ]
FAKE=
gate login
check "b2: restored" [ "$(sums)" = "$orig" ]

# b3: fusion-config.sh after the fallback: its Global Theme apply removes the user's decoration keys,
# deploy still brings the compiled decoration back.
make_home "$BASE/b3"
gate deploy >/dev/null 2>&1
FAKE="kwin=6.8.0"
gate login
FAKE=
kw kwinrc org.kde.kdecoration2 library --delete
kw kwinrc org.kde.kdecoration2 theme --delete
mkdir -p "$H/.config/${DROPIN_REL%/*}"
printf '[Service]\nEnvironment=PLASMA_DEFAULT_SHELL=org.plasmafusion.lockshell\n' >"$H/.config/$DROPIN_REL"
gate deploy >"$BASE/b3.deploy.log" 2>&1
check "b3: deploy puts the compiled decoration back" [ "$(get kwinrc org.kde.kdecoration2 library)" = org.plasmafusion.decoration ]
check "b3: deploy empty theme" [ "$(get kwinrc org.kde.kdecoration2 theme)" = "" ]
check "b3: deploy clears the records" [ ! -e "$H/.local/state/plasma-fusion/gate/off" ]

# b4: a changed lock-screen package alone switches only the lock screen
make_home "$BASE/b4"
gate deploy >/dev/null 2>&1
echo "// changed" >>"$H/.local/share/plasma/shells/org.plasmafusion.lockshell/contents/lockscreen/LockScreen.qml"
gate login
check "b4: changed lock-screen files: drop-in aside" [ ! -e "$H/.config/$DROPIN_REL" ]
check "b4: decoration stays compiled" [ "$(get kwinrc org.kde.kdecoration2 library)" = org.plasmafusion.decoration ]
check "b4: notification names the lock-screen files" grep -q 'lock-screen files changed' "$H/.local/state/plasma-fusion/gate/notify"

# b5: the user chose Breeze decorations during the fallback: never overwritten by the restore
make_home "$BASE/b5"
gate deploy >/dev/null 2>&1
FAKE="kwin=6.8.0"
gate login
FAKE=
kw kwinrc org.kde.kdecoration2 library org.kde.breeze
kw kwinrc org.kde.kdecoration2 theme Breeze
gate login
check "b5: user's own decoration kept" [ "$(get kwinrc org.kde.kdecoration2 library)" = org.kde.breeze ]
check "b5: lock screen back" [ -f "$H/.config/$DROPIN_REL" ]

# b6: the compiled decoration is no longer installed when versions match again: stays Aurorae
# (only where it is not installed system-wide, which the check always looks at too)
if [ -e /usr/lib64/qt6/plugins/org.kde.kdecoration3/org.plasmafusion.decoration.so ]; then
  echo "SKIP b6: org.plasmafusion.decoration.so is installed system-wide here"
else
make_home "$BASE/b6"
gate deploy >/dev/null 2>&1
FAKE="kwin=6.8.0"
gate login
FAKE=
mv "$PLUGINS" "$PLUGINS.off"
gate login
mv "$PLUGINS.off" "$PLUGINS"
check "b6: without the plugin the title bars stay Aurorae" [ "$(keff kwinrc org.kde.kdecoration2 library)" = org.kde.kwin.aurorae.v2 ]
check "b6: lock screen back" [ -f "$H/.config/$DROPIN_REL" ]
fi

# b7: a Global Theme that names the compiled decoration in kdedefaults (no user key): the check
# writes the Aurorae theme to the user file and a matching login removes it again.
make_home "$BASE/b7"
kw kwinrc org.kde.kdecoration2 library --delete
kw kwinrc org.kde.kdecoration2 theme --delete
kwd kwinrc org.kde.kdecoration2 library org.plasmafusion.decoration
kwd kwinrc org.kde.kdecoration2 theme ""
gate deploy >/dev/null 2>&1
orig=$(sums)
FAKE="kwin=6.8.0"
gate login
check "b7: user file names the Aurorae theme" [ "$(get kwinrc org.kde.kdecoration2 library)/$(get kwinrc org.kde.kdecoration2 theme)" = org.kde.kwin.aurorae.v2/__aurorae__svg__PlasmaFusionDark ]
FAKE=
gate login
check "b7: matching login: back to the Global Theme's value" [ "$(sums)" = "$orig" ]
check "b7: compiled decoration in effect" [ "$(keff kwinrc org.kde.kdecoration2 library)" = org.plasmafusion.decoration ]

# b8: Follow sunset. Safe mode, then startplasma switches to Light after the check (it writes only
# kdedefaults, Mode::Defaults): the title bars follow; the next matching login restores.
make_home "$BASE/b8"
kw kdeglobals KDE AutomaticLookAndFeel true
gate deploy >/dev/null 2>&1
orig_lib=$(get kwinrc org.kde.kdecoration2 library)
FAKE="kwin=6.8.0"
gate login
FAKE=
kw kdeglobals KDE LookAndFeelPackage org.plasmafusion.light.desktop
kwd kwinrc org.kde.kdecoration2 theme __aurorae__svg__PlasmaFusionLight
check "b8: title bars follow the light theme" [ "$(keff kwinrc org.kde.kdecoration2 theme)" = __aurorae__svg__PlasmaFusionLight ]
gate login
check "b8: matching login: compiled decoration back" [ "$(get kwinrc org.kde.kdecoration2 library)" = "$orig_lib" ]

# b9: safe mode dropped the user's decoration keys (kdedefaults named the Aurorae theme); the user
# then chose Breeze (its apply writes kdedefaults, no user key): a matching login keeps Breeze.
make_home "$BASE/b9"
gate deploy >/dev/null 2>&1
FAKE="kwin=6.8.0"
gate login
FAKE=
kw kdeglobals KDE LookAndFeelPackage org.kde.breeze.desktop
kwd kwinrc org.kde.kdecoration2 library org.kde.breeze
kwd kwinrc org.kde.kdecoration2 theme Breeze
gate login
check "b9: Breeze chosen during safe mode stays" [ "$(keff kwinrc org.kde.kdecoration2 library)" = org.kde.breeze ]
check "b9: decoration record cleared" bash -c '! grep -q "^decoration" "$1" 2>/dev/null' _ "$H/.local/state/plasma-fusion/gate/off"

# ---------- (b10) only the navigation effect depends on the versions ----------
make_home "$BASE/b10"
kw kwinrc org.kde.kdecoration2 library --delete
kw kwinrc org.kde.kdecoration2 theme --delete
rm -f "$H/.config/$DROPIN_REL"
gate deploy >/dev/null 2>&1
orig=$(sums)
FAKE="kwin=6.7.6"
gate login
check "b10: KWin update alone: navigation effect off" [ "$(get kwinrc Plugins plasmafusion_navigationEnabled)" = false ]
check "b10: notification queued" grep -q 'kwin 6.7.5 → 6.7.6' "$H/.local/state/plasma-fusion/gate/notify"
FAKE=
gate login
check "b10: matching login: back on" [ "$(sums)" = "$orig" ]
FAKE="qt6-qtdeclarative=6.12.0"
gate login
check "b10: Qt Quick update: navigation effect off" [ "$(get kwinrc Plugins plasmafusion_navigationEnabled)" = false ]
FAKE=
gate login
check "b10: and back on" [ "$(get kwinrc Plugins plasmafusion_navigationEnabled)" = true ]

# ---------- (c) another Global Theme ----------
make_home "$BASE/c"
gate deploy >/dev/null 2>&1
orig=$(sums)
# What plasma-apply-lookandfeel -a org.kde.breeze.desktop writes: its defaults to kdedefaults, the
# user's keys for them removed, LookAndFeelPackage set. Breeze has no window switcher of its own.
kw kdeglobals KDE LookAndFeelPackage org.kde.breeze.desktop
kwd kwinrc org.kde.kdecoration2 library org.kde.breeze
kwd kwinrc org.kde.kdecoration2 theme Breeze
kw kwinrc org.kde.kdecoration2 library --delete
kw kwinrc org.kde.kdecoration2 theme --delete
gate login
check "c: snap off" [ "$(get kwinrc Plugins plasmafusion-snapEnabled)" = "<absent>" ]
check "c: attach off" [ "$(get kwinrc Plugins plasmafusion-attachEnabled)" = "<absent>" ]
check "c: outline off" [ "$(get kwinrc Outline QmlPath)" = "<absent>" ]
check "c: switcher overrides kdedefaults with KWin's" [ "$(get kwinrc TabBox LayoutName)" = thumbnail_grid ]
check "c: alternative switcher key removed" [ "$(get kwinrc TabBoxAlternative LayoutName)" = "<absent>" ]
check "c: DesktopMode back to default" [ "$(get kwinrc TabBox DesktopMode)" = "<absent>" ]
check "c: lock-screen drop-in aside" [ ! -e "$H/.config/$DROPIN_REL" ]
check "c: sheet effect untouched" [ "$(get kwinrc Plugins sheetEnabled)" = true ]
check "c: navigation effect off" [ "$(get kwinrc Plugins plasmafusion_navigationEnabled)" = false ]
check "c: no notification for a theme switch" [ ! -e "$H/.local/state/plasma-fusion/gate/notify" ]
# The user turns snap layouts on again under Breeze: left on at the next logins.
kw kwinrc Plugins plasmafusion-snapEnabled true
gate login
gate login
check "c: snap turned on again by the user stays on" [ "$(get kwinrc Plugins plasmafusion-snapEnabled)" = true ]
kw kwinrc Plugins plasmafusion-snapEnabled --delete
# Back to Plasma Fusion Dark (its apply writes its defaults again and removes the user keys).
kw kdeglobals KDE LookAndFeelPackage org.plasmafusion.dark.desktop
kwd kwinrc org.kde.kdecoration2 library org.kde.kwin.aurorae.v2
kwd kwinrc org.kde.kdecoration2 theme __aurorae__svg__PlasmaFusionDark
kw kwinrc org.kde.kdecoration2 library org.plasmafusion.decoration
kw kwinrc org.kde.kdecoration2 theme ""
gate login
check "c: Fusion theme again restores everything" [ "$(sums)" = "$orig" ]
[ "$(sums)" = "$orig" ] || diff <(echo "$orig") <(sums)

# ---------- (t) tablet script, keyboard policy and user services under another theme ----------
WANTS=systemd/user/graphical-session.target.wants
make_home "$BASE/t2"
kw kwinrc Plugins plasmafusion-tabletEnabled true
kw kwinrc Wayland InputMethod ""
mkdir -p "$H/.config/$WANTS"
for u in plasma-fusion-powerfx.service plasma-fusion-pen-garage.service; do
  printf '[Unit]\nDescription=test\n[Install]\nWantedBy=graphical-session.target\n' >"$H/.config/systemd/user/$u"
  ln -s "../$u" "$H/.config/$WANTS/$u"
done
gate deploy >/dev/null 2>&1
orig=$(sums)
gate login
check "t: Fusion theme: tablet script stays on" [ "$(get kwinrc Plugins plasmafusion-tabletEnabled)" = true ]
check "t: Fusion theme: powerfx link stays" [ -L "$H/.config/$WANTS/plasma-fusion-powerfx.service" ]
kw kdeglobals KDE LookAndFeelPackage org.kde.breeze.desktop
gate login
check "t: Breeze: tablet script written false" [ "$(get kwinrc Plugins plasmafusion-tabletEnabled)" = false ]
check "t: Breeze: InputMethod key removed (system default returns)" [ "$(get kwinrc Wayland InputMethod)" = "<absent>" ]
check "t: Breeze: powerfx link moved aside" [ ! -e "$H/.config/$WANTS/plasma-fusion-powerfx.service" ] &&
  check "t: Breeze: saved link is the same link" [ "$(readlink "$H/.local/state/plasma-fusion/gate/saved/plasma-fusion-powerfx.service")" = ../plasma-fusion-powerfx.service ]
check "t: Breeze: garage link moved aside" [ ! -L "$H/.config/$WANTS/plasma-fusion-pen-garage.service" ]
check "t: Breeze: unit files kept" [ -f "$H/.config/systemd/user/plasma-fusion-powerfx.service" ]
check "t: Breeze: status lists the held parts" grep -q '^held=.*tablet inputmethod powerfx pengarage' "$H/.local/state/plasma-fusion/gate/status"
# The user enables the power service again under Breeze: it stays.
mkdir -p "$H/.config/$WANTS"
ln -s ../plasma-fusion-powerfx.service "$H/.config/$WANTS/plasma-fusion-powerfx.service"
gate login
gate login
check "t: powerfx enabled again by the user stays" [ -L "$H/.config/$WANTS/plasma-fusion-powerfx.service" ]
rm -f "$H/.config/$WANTS/plasma-fusion-powerfx.service"
kw kdeglobals KDE LookAndFeelPackage org.plasmafusion.dark.desktop
gate login
check "t: Fusion again: keys back" [ "$(sums)" = "$orig" ]
[ "$(sums)" = "$orig" ] || diff <(echo "$orig") <(sums)
check "t: Fusion again: garage link back" [ "$(readlink "$H/.config/$WANTS/plasma-fusion-pen-garage.service")" = ../plasma-fusion-pen-garage.service ]
check "t: Fusion again: powerfx link back (as a removed key comes back)" [ "$(readlink "$H/.config/$WANTS/plasma-fusion-powerfx.service")" = ../plasma-fusion-powerfx.service ]
check "t: Fusion again: no saved links left" [ -z "$(ls -A "$H/.local/state/plasma-fusion/gate/saved" 2>/dev/null)" ]
check "t: Fusion again: nothing held" [ ! -e "$H/.local/state/plasma-fusion/gate/off" ]
# The user's own input method is never touched.
make_home "$BASE/t3"
kw kwinrc Wayland InputMethod /usr/share/applications/fcitx5-wayland-launcher.desktop
gate deploy >/dev/null 2>&1
kw kdeglobals KDE LookAndFeelPackage org.kde.breeze.desktop
gate login
check "t3: another input method stays under Breeze" [ "$(get kwinrc Wayland InputMethod)" = /usr/share/applications/fcitx5-wayland-launcher.desktop ]
# plasma-keyboard written by the policy goes; a removed unit is not linked again.
make_home "$BASE/t4"
kw kwinrc Wayland InputMethod /usr/share/applications/org.kde.plasma.keyboard.desktop
mkdir -p "$H/.config/$WANTS"
printf '[Unit]\n' >"$H/.config/systemd/user/plasma-fusion-powerfx.service"
ln -s ../plasma-fusion-powerfx.service "$H/.config/$WANTS/plasma-fusion-powerfx.service"
gate deploy >/dev/null 2>&1
kw kdeglobals KDE LookAndFeelPackage org.kde.breeze.desktop
gate login
check "t4: plasma-keyboard value removed under Breeze" [ "$(get kwinrc Wayland InputMethod)" = "<absent>" ]
rm -f "$H/.config/systemd/user/plasma-fusion-powerfx.service"
kw kdeglobals KDE LookAndFeelPackage org.plasmafusion.dark.desktop
gate login
check "t4: uninstalled unit: link not put back" [ ! -L "$H/.config/$WANTS/plasma-fusion-powerfx.service" ]
check "t4: InputMethod back as the policy left it" [ "$(get kwinrc Wayland InputMethod)" = /usr/share/applications/org.kde.plasma.keyboard.desktop ]
# A record naming another path is ignored (no file outside the wants link is ever moved).
make_home "$BASE/t5"
gate deploy >/dev/null 2>&1
: >"$H/.config/precious"
printf '# x\npowerfx\ttheme\tlink\t../precious\t-\t-\t-\t-\t-\n' >"$H/.local/state/plasma-fusion/gate/off"
gate login
check "t5: hostile link record ignored" [ -f "$H/.config/precious" ]
check "t5: hostile link record dropped" [ ! -e "$H/.local/state/plasma-fusion/gate/off" ]

# ---------- (i) hand-edited files: KConfig reads what the check meant ----------
make_home "$BASE/i"
gate deploy >/dev/null 2>&1
cat >"$H/.config/kwinrc" <<'EOF'
# kept comment
[Plugins]
plasmafusion-snapEnabled = true

[org.kde.kdecoration2]
BorderSizeAuto=false
library=org.plasmafusion.decoration
theme=

[TabBox]
LayoutName[de]=Deutsch
LayoutName=org.plasmafusion.switcher
DesktopMode=0

[Plugins]
plasmafusion-attachEnabled=true
sheetEnabled=true

[Outline]
QmlPath[$e]=kwin/scripts/plasmafusion-snap/contents/outline/outline.qml
EOF
chmod 600 "$H/.config/kwinrc"
orig=$(sums)
kw kdeglobals KDE LookAndFeelPackage org.kde.breeze.desktop
gate login
check "i: KConfig reads snap off" [ -z "$(kread kwinrc Plugins plasmafusion-snapEnabled)" ]
check "i: KConfig reads attach off, sheet kept" [ "$(kread kwinrc Plugins plasmafusion-attachEnabled)/$(kread kwinrc Plugins sheetEnabled)" = /true ]
check "i: KConfig reads the outline off ([\$e] key)" [ -z "$(kread kwinrc Outline QmlPath)" ]
check "i: KConfig reads KWin's switcher" [ "$(kread kwinrc TabBox LayoutName)" = thumbnail_grid ]
check "i: localised entry and comment kept" bash -c 'grep -qx "LayoutName\[de\]=Deutsch" "$1" && grep -qx "# kept comment" "$1"' _ "$H/.config/kwinrc"
check "i: permissions kept" [ "$(stat -c %a "$H/.config/kwinrc")" = 600 ]
kw kdeglobals KDE LookAndFeelPackage org.plasmafusion.dark.desktop
gate login
check "i: KConfig reads everything back" [ "$(kread kwinrc Plugins plasmafusion-snapEnabled)/$(kread kwinrc Plugins plasmafusion-attachEnabled)/$(kread kwinrc TabBox LayoutName)/$(kread kwinrc TabBox DesktopMode)" = true/true/org.plasmafusion.switcher/0 ]
check "i: outline back" [ "$(kread kwinrc Outline QmlPath)" = kwin/scripts/plasmafusion-snap/contents/outline/outline.qml ]
check "i: same values as before" [ "$(sums | grep -v 'kdeglobals|')" = "$(echo "$orig" | grep -v 'kdeglobals|')" ]
[ "$(sums | grep -v 'kdeglobals|')" = "$(echo "$orig" | grep -v 'kdeglobals|')" ] || diff <(echo "$orig") <(sums)

# (l) locales: the login runs in the user's locale; in tr_TR and et_EE the range [A-Za-z] misses
# ASCII letters, which once made every record unreadable (safe mode at every login).
for L in tr_TR.UTF-8 et_EE.UTF-8 de_DE.UTF-8; do
  if ! locale -a 2>/dev/null | grep -qix "${L%.UTF-8}.utf8"; then echo "SKIP l: locale $L is not installed"; continue; fi
  make_home "$BASE/l-$L"
  gate deploy >/dev/null 2>&1
  before=$(sums)
  GATE_LANG=$L gate login
  check "l: $L matching login changes nothing" [ "$(sums)" = "$before" ]
  check "l: $L log 'no change'" grep -q 'versions=tested lock=tested; no change' "$H/.local/state/plasma-fusion/gate.log"
  FAKE="kwin=6.8.0" GATE_LANG=$L gate login
  check "l: $L faked version seen" grep -q 'kwin 6.7.5 → 6.8.0' "$H/.local/state/plasma-fusion/gate/notify"
  FAKE=
done

# (m) automatic light/dark with a Plasma Fusion theme as one of the two: LookAndFeelPackage may
# still name the other one when the check runs (startplasma picks later), so the parts stay on.
make_home "$BASE/m"
kw kdeglobals KDE AutomaticLookAndFeel true
kw kdeglobals KDE DefaultLightLookAndFeel org.kde.breeze.desktop
kw kdeglobals KDE DefaultDarkLookAndFeel org.plasmafusion.dark.desktop
gate deploy >/dev/null 2>&1
kw kdeglobals KDE LookAndFeelPackage org.kde.breeze.desktop
gate login
check "m: automatic with a Fusion theme: snap stays on" [ "$(get kwinrc Plugins plasmafusion-snapEnabled)" = true ]
check "m: automatic with a Fusion theme: drop-in stays" [ -f "$H/.config/$DROPIN_REL" ]
kw kdeglobals KDE AutomaticLookAndFeel false
gate login
check "m: automatic off: Breeze switches the parts off" [ "$(get kwinrc Plugins plasmafusion-snapEnabled)" = "<absent>" ]

# (w) the in-place writer: KConfig escapes come back byte for byte (awk -v would eat the
# backslash), and a replaced key that is the last line of its group adds no second group header.
make_home "$BASE/w"
gate deploy >/dev/null 2>&1
kw kwinrc Outline QmlPath " /opt/plasmafusion/outline.qml"
line=$(grep '^QmlPath' "$H/.config/kwinrc")
kw kdeglobals KDE LookAndFeelPackage org.kde.breeze.desktop
gate login
kw kdeglobals KDE LookAndFeelPackage org.plasmafusion.dark.desktop
gate login
check "w: escaped value back byte for byte ($line)" [ "$(grep '^QmlPath' "$H/.config/kwinrc")" = "$line" ]
make_home "$BASE/w2"
kw plasmafusionrc Decoration ButtonStyle LeftCircles
gate deploy >/dev/null 2>&1
printf '[org.kde.kdecoration2]\nBorderSizeAuto=false\nlibrary=org.plasmafusion.decoration\n\n[Plugins]\nplasmafusion-snapEnabled=true\n' >"$H/.config/kwinrc"
FAKE="kwin=6.8.0" gate login
check "w2: one [org.kde.kdecoration2] group after replacing its last line" [ "$(grep -c '^\[org.kde.kdecoration2\]' "$H/.config/kwinrc")" = 1 ]
check "w2: KConfig reads the -Left Aurorae theme" [ "$(kread kwinrc org.kde.kdecoration2 theme)" = __aurorae__svg__PlasmaFusionDark-Left ]

# ---------- (p) the Global Theme names the compiled decoration, but the plugin is missing ----------
# (LAYOUT-1: both themes' defaults name org.plasmafusion.decoration.) KWin would fall back to its
# built-in default; the check chooses the matching Aurorae theme without a notification, keeps it
# while the plugin is missing and gives the compiled one back once it is installed again.
make_home "$BASE/p"
gate deploy >/dev/null 2>&1
kw kwinrc org.kde.kdecoration2 library --delete
kw kwinrc org.kde.kdecoration2 theme --delete
kwd kwinrc org.kde.kdecoration2 library org.plasmafusion.decoration
kwd kwinrc org.kde.kdecoration2 theme ""
mv "$PLUGINS/org.kde.kdecoration3/org.plasmafusion.decoration.so" "$BASE/p-plugin.so"
gate login >"$BASE/p.login1.log" 2>&1
check "p: plugin missing: Aurorae title bars" [ "$(keff kwinrc org.kde.kdecoration2 library)" = org.kde.kwin.aurorae.v2 ]
check "p: plugin missing: the matching theme" [ "$(keff kwinrc org.kde.kdecoration2 theme)" = __aurorae__svg__PlasmaFusionDark ]
check "p: plugin missing: no notification" [ ! -e "$H/.local/state/plasma-fusion/gate/notify" ]
mid=$(sums)
gate login >"$BASE/p.login2.log" 2>&1
check "p: still missing: nothing changes" [ "$(sums)" = "$mid" ]
check "p: still missing: the record stays" grep -q '^decoration' "$H/.local/state/plasma-fusion/gate/off"
mv "$BASE/p-plugin.so" "$PLUGINS/org.kde.kdecoration3/org.plasmafusion.decoration.so"
gate login >"$BASE/p.login3.log" 2>&1
check "p: plugin back: the compiled decoration again" [ "$(keff kwinrc org.kde.kdecoration2 library)" = org.plasmafusion.decoration ]
check "p: plugin back: no user decoration keys left" [ "$(get kwinrc org.kde.kdecoration2 library)" = "<absent>" ]
check "p: plugin back: the record is gone" [ -z "$(grep '^decoration' "$H/.local/state/plasma-fusion/gate/off" 2>/dev/null)" ]

# ---------- (e) robustness ----------
make_home "$BASE/e"
gate deploy >/dev/null 2>&1
S=$H/.local/state/plasma-fusion/gate
printf 'garbage\x00\x01\n[[[\npkg $(touch %s/pwned)=1\n' "$BASE" >"$S/tested"
gate login
check "e: corrupt record: exit 0" [ $? = 0 ]
check "e: corrupt record: no command run from it" [ ! -e "$BASE/pwned" ]
check "e: corrupt record: falls back (drop-in aside)" [ ! -e "$H/.config/$DROPIN_REL" ]
check "e: corrupt record: notification says unreadable" grep -q 'its record is unreadable' "$S/notify"
make_home "$BASE/e2"
gate login
check "e2: missing record: exit 0" [ $? = 0 ]
check "e2: missing record: falls back" [ "$(keff kwinrc org.kde.kdecoration2 library)" = org.kde.kwin.aurorae.v2 ]
make_home "$BASE/e3"
gate deploy >/dev/null 2>&1
S=$H/.local/state/plasma-fusion/gate
printf 'lockscreen\tupdate\n\x01\x02 junk\n' >"$S/off"
printf 'junk' >"$S/cache"
before=$(sums)
gate login
check "e3: corrupt records and cache: exit 0" [ $? = 0 ]
check "e3: corrupt records and cache: no config change" [ "$(sums)" = "$before" ]
check "e3: unreadable record lines dropped" [ ! -e "$S/off" ]
: >"$BASE/rpm-hang"
rm -f "$S/cache"
t=${EPOCHREALTIME/[.,]/}
gate login
rc=$?
t=$(((${EPOCHREALTIME/[.,]/} - t) / 1000))
rm -f "$BASE/rpm-hang"
check "e3: hanging rpm: exit 0 ($rc)" [ "$rc" = 0 ]
check "e3: hanging rpm: bounded (${t} ms < 4500)" [ "$t" -lt 4500 ]
check "e3: hanging rpm: falls back" [ ! -e "$H/.config/$DROPIN_REL" ]
make_home "$BASE/e4"
chmod 000 "$H/.config/kwinrc"
gate login
check "e4: unreadable kwinrc: exit 0" [ $? = 0 ]
chmod 644 "$H/.config/kwinrc"
H=$BASE/e5
mkdir -p "$H"
gate login
check "e5: empty HOME: exit 0" [ $? = 0 ]
check "e5: empty HOME: no config written" [ ! -e "$H/.config" ]
env -i PATH=/usr/bin:/bin bash "$ENGINE" login
check "e6: no HOME at all: exit 0" [ $? = 0 ]

# ---------- (e) timing ----------
make_home "$BASE/t"
[ "$REAL_RPM" = 1 ] && RPM=rpm
gate deploy >/dev/null 2>&1
gate login # fills the cache
times=()
for _ in $(seq 1 21); do
  t=${EPOCHREALTIME/[.,]/}
  gate login
  times+=($(((${EPOCHREALTIME/[.,]/} - t) / 1000)))
done
mapfile -t sorted < <(printf '%s\n' "${times[@]}" | sort -n)
echo "timing (match path, drop-in and compiled decoration on, $([ "$RPM" = rpm ] && echo real || echo fake) rpm, cached): median ${sorted[10]} ms, max ${sorted[20]} ms (wall time incl. env -i and bash start)"
check "timing: median under 50 ms" [ "${sorted[10]}" -lt 50 ]
rm -f "$H/.local/state/plasma-fusion/gate/cache"
t=${EPOCHREALTIME/[.,]/}
gate login
echo "timing (first login after an rpm transaction, cache rebuilt): $(((${EPOCHREALTIME/[.,]/} - t) / 1000)) ms"
FAKE="kwin=6.8.0"
t=${EPOCHREALTIME/[.,]/}
gate login
echo "timing (mismatch, switching off): $(((${EPOCHREALTIME/[.,]/} - t) / 1000)) ms"
FAKE=
t=${EPOCHREALTIME/[.,]/}
gate login
echo "timing (restoring): $(((${EPOCHREALTIME/[.,]/} - t) / 1000)) ms"
grep -o '([0-9]* ms)' "$H/.local/state/plasma-fusion/gate.log" | tr -d '()' | sort -n | awk '{a[NR]=$1} END {print "engine-internal time over " NR " runs: median " a[int((NR+1)/2)] " ms, max " a[NR] " ms"}'

echo "== $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
