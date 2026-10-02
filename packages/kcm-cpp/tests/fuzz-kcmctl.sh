#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# ctest driver (tests/CMakeLists.txt, test kcmctl-fuzz): random rounds for the settings module from
# bash's generator seeded with PF_FUZZ_SEED (default 1), so the same seed repeats the same rounds;
# PF_FUZZ_COUNT rounds (default 25). Each round
#   - writes kdeglobals, kwinrc, plasmafusionrc and baloofilerc with valid, odd and broken values
#     for the keys the module reads (or leaves a key, a group or a file out), and sometimes adds the
#     high-contrast scheme and the previous-desktop theme the module looks for;
#   - runs kcmctl with random commands: set (valid and invalid values), get, dump, load, save,
#     defaults, the module's actions;
#   - checks that kcmctl exits normally and that every integer property it reports is in range.
# The programs the module starts (plasma-apply-lookandfeel, plasma-apply-colorscheme, systemctl)
# are stand-ins that exit with a random status: kcmctl runs with PATH holding only them. As in
# run-kcmctl.sh it runs in a scratch HOME, on a private D-Bus session without service activation
# (session-bus.conf) and without display variables, so nothing reaches a real session. Under
# tools/sanitizers/run.sh a memory error or undefined behaviour stops kcmctl and fails the round.
#
#   fuzz-kcmctl.sh KCMCTL PLUGIN_DIR WORKDIR
set -euo pipefail
here=$(cd "$(dirname "$0")" && pwd)
kcmctl=$1 plugins=$2 work=$3
seed=${PF_FUZZ_SEED:-1} rounds=${PF_FUZZ_COUNT:-25}
RANDOM=$seed

rm -rf "$work"
mkdir -p "$work/home" "$work/config" "$work/data" "$work/cache" "$work/state" "$work/runtime" "$work/bin" "$work/logs"
chmod 700 "$work/runtime"
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
export HOME=$work/home XDG_CONFIG_HOME=$work/config XDG_DATA_HOME=$work/data XDG_CACHE_HOME=$work/cache
export XDG_STATE_HOME=$work/state XDG_RUNTIME_DIR=$work/runtime
export QT_PLUGIN_PATH=$plugins QT_QPA_PLATFORM=offscreen
export PF_STUB_DIR=$work/bin

# Stand-ins for the programs the module runs (bash builtins only: PATH holds nothing else).
for tool in plasma-apply-lookandfeel plasma-apply-colorscheme systemctl; do
  cat >"$work/bin/$tool" <<'EOF'
#!/bin/bash
printf '%s\n' "$(<"$PF_STUB_DIR/output")"
exit "$(<"$PF_STUB_DIR/status")"
EOF
  chmod +x "$work/bin/$tool"
done

# REPLY = one of the arguments (no subshell, so the generator's sequence stays the same).
pick() {
  local i=$((RANDOM % $# + 1))
  REPLY=${!i}
}
long=$(printf '%0400d' 0)
# REPLY = one of the arguments, or (one time in three) an odd value.
value() {
  if ((RANDOM % 3 == 0)); then
    pick '' ' ' Unknown -1 2147483648 nan 1e308 0x10 '#zzz' 1,2 300,-20,7 '[General]' 'a=b' \
      $'\xc3\xa9\xe2\x80\xae' "$long"
  else
    pick "$@"
  fi
}
# A key line KEY=VALUE, left out one time in six.
entry() {
  if ((RANDOM % 6 != 0)); then
    value "${@:2}"
    printf '%s=%s\n' "$1" "$REPLY"
  fi
}
# One time in four, a broken or unusual line.
garbage() {
  if ((RANDOM % 4 == 0)); then
    # shellcheck disable=SC2016 # [$i] is KConfig's mark for an immutable key or group
    pick '[Unclosed' '=novalue' 'NoEquals' 'Key[$i]=locked' '[KDE][$i]' '[]' 'Key[de]=localized' \
      $'Bytes=\x01\x02\x7f\xff' "Long$long=x" ' Spaces = around '
    printf '%s\n' "$REPLY"
  fi
}
# FILE written from the lines on stdin, or (one time in eight) removed.
write() {
  if ((RANDOM % 8 == 0)); then
    rm -f "$1"
    cat >/dev/null
  else
    cat >"$1"
  fi
}

write_config() {
  local c=$work/config
  {
    garbage
    echo '[KDE]'
    entry LookAndFeelPackage org.plasmafusion.dark.desktop org.plasmafusion.light.desktop org.kde.breezedark.desktop
    entry AutomaticLookAndFeel true false
    entry DefaultLightLookAndFeel org.plasmafusion.light.desktop org.kde.breeze.desktop
    entry DefaultDarkLookAndFeel org.plasmafusion.dark.desktop org.kde.breezedark.desktop
    entry AnimationDurationFactor 0 0.5 1 2
    entry DndBehavior AlwaysAsk MoveIfSameDevice
    garbage
    echo '[General]'
    entry AccentColor 47,111,223 '#2f6fdf' 255,255,255 0,0,0,0
    entry LastUsedCustomAccentColor 47,111,223 200,40,40
    entry accentColorFromWallpaper true false
    entry ColorScheme PlasmaFusionDark PlasmaFusionLight PlasmaFusionHighContrast BreezeDark
    echo '[Colors:Window]'
    entry BackgroundNormal 27,32,49 240,242,247 '#ffffff'
    garbage
  } | write "$c/kdeglobals"
  {
    echo '[org.kde.kdecoration2]'
    entry library org.plasmafusion.decoration org.kde.kwin.aurorae.v2 org.kde.breeze
    entry theme __aurorae__svg__PlasmaFusionDark __aurorae__svg__PlasmaFusionLight-Left __aurorae__svg__PlasmaFusionDark-Left
    entry ButtonsOnLeft M MS ''
    entry ButtonsOnRight IAX HIAX ''
    garbage
    echo '[Effect-overview]'
    entry BorderActivate 7 9 7,9 3
    echo '[Input]'
    entry TabletMode auto on off
    echo '[Script-plasmafusion-tablet]'
    entry WindowMode fullscreen windowed
    entry DockHiding overApps none
    entry EdgeLeft true false
    entry EdgeRight true false
    echo '[Plugins]'
    entry blurEnabled true false
    entry plasmafusion-snapEnabled true false
    garbage
  } | write "$c/kwinrc"
  {
    echo '[Decoration]'
    entry ButtonStyle RightGlyphs LeftCircles ShowOnHover
    entry SnapLayoutsOnHover true false
    echo '[Effects]'
    entry Glass Full Reduced Solid solid
    echo '[TopBar]'
    entry EveryScreen true false
    entry SolidNextToWindows true false
    garbage
    echo '[Power]'
    entry LighterOnCritical true false
    entry Tier critical low full
    entry UserGlass Full Solid
    entry UserDockMagnify true false
    echo '[Motion]'
    entry PreviousAnimationDurationFactor 1 0.5
    garbage
  } | write "$c/plasmafusionrc"
  {
    echo '[General]'
    entry 'only basic indexing' true false
  } | write "$c/baloofilerc"

  # What the module looks for in the data directories: the high-contrast scheme and the
  # previous-desktop theme (restorePreviousDesktop needs it).
  rm -rf "$work/data/color-schemes" "$work/data/plasma"
  if ((RANDOM % 2 == 0)); then
    mkdir -p "$work/data/color-schemes"
    printf '[General]\nName=Plasma Fusion High Contrast\n' >"$work/data/color-schemes/PlasmaFusionHighContrast.colors"
  fi
  if ((RANDOM % 2 == 0)); then
    mkdir -p "$work/data/plasma/look-and-feel/org.plasmafusion.previous.desktop"
    echo '{"KPlugin": {"Id": "org.plasmafusion.previous.desktop"}}' >"$work/data/plasma/look-and-feel/org.plasmafusion.previous.desktop/metadata.json"
  fi

  # How the stand-ins answer this round.
  pick 0 0 0 1 2
  echo "$REPLY" >"$work/bin/status"
  pick '' 'Applied.' 'error: no such package' "$long"
  printf '%s' "$REPLY" >"$work/bin/output"
}

ints=(style buttonStyle snapTrigger glass magnifiedSize iconSize dndBehavior tabletMode tabletApps tabletDock keyboardPolicy)
bools=(magnify globalMenu hotCorner highContrast reduceMotion solidTopBar everyScreen desktopIcons lighterOnCritical
  fileContentIndexing edgeLeft edgeRight homeIndicator)
reads=(accentMode accentColor wallpaperColor shellRunning dockAvailable fusionDecoration errorText infoText
  highContrastAvailable previousDesktopAvailable powerCritical fusionLookAndFeel busy noSuchProperty)
methods=(setSchemeAccent setWallpaperAccent useFusionDecoration restorePreviousDesktop resetLayout noSuchMethod)

write_commands() {
  local n i
  echo waitshell
  n=$((RANDOM % 12 + 1))
  for ((i = 0; i < n; i++)); do
    case $((RANDOM % 9)) in
      0) echo dump ;;
      1 | 2)
        pick "${ints[@]}"
        local name=$REPLY
        pick -1 0 1 2 3 7 47 48 62 72 73 2147483647 -2147483648 9999999999 abc ''
        echo "set $name $REPLY"
        ;;
      3)
        pick "${bools[@]}"
        local name=$REPLY
        pick true false 0 1 yes ''
        echo "set $name $REPLY"
        ;;
      4)
        pick "${ints[@]}" "${bools[@]}" "${reads[@]}"
        echo "get $REPLY"
        ;;
      5 | 6)
        pick load save save defaults
        echo "$REPLY"
        ;;
      7)
        pick "${methods[@]}"
        echo "call $REPLY"
        echo waitidle
        ;;
      8) echo "wait $((RANDOM % 100))" ;;
    esac
  done
  echo dump
}

# The range of every integer property (kcm.h).
declare -A low=([style]=-1 [accentMode]=0 [buttonStyle]=0 [snapTrigger]=0 [glass]=0 [magnifiedSize]=48 [iconSize]=0
  [dndBehavior]=0 [tabletMode]=0 [tabletApps]=0 [tabletDock]=0 [keyboardPolicy]=0)
declare -A high=([style]=2 [accentMode]=2 [buttonStyle]=2 [snapTrigger]=1 [glass]=2 [magnifiedSize]=72 [iconSize]=6
  [dndBehavior]=1 [tabletMode]=2 [tabletApps]=1 [tabletDock]=1 [keyboardPolicy]=2)

# Prints the reported values outside their range; the status is 1 when there is one.
check_ranges() {
  local line name v status=0
  while IFS= read -r line; do
    name=${line#kcmctl: }
    v=${name#*=}
    name=${name%%=*}
    [ -n "${low[$name]+set}" ] || continue
    if ! [[ $v =~ ^-?[0-9]+$ ]] || ((v < ${low[$name]} || v > ${high[$name]})); then
      echo "out of range: $name=$v (${low[$name]}..${high[$name]})"
      status=1
    fi
  done < <(grep -E '^kcmctl: [A-Za-z]+=' "$1")
  return "$status"
}

echo "seed $seed, $rounds rounds (repeat with PF_FUZZ_SEED=$seed PF_FUZZ_COUNT=$rounds)"
for ((round = 1; round <= rounds; round++)); do
  write_config
  log=$work/logs/round-$round.log
  write_commands >"$work/logs/round-$round.commands"
  status=0
  dbus-run-session --config-file="$here/session-bus.conf" -- env PATH="$work/bin" "$kcmctl" \
    <"$work/logs/round-$round.commands" >"$log" 2>&1 || status=$?
  problem=
  if [ "$status" -ne 0 ]; then
    problem="kcmctl exited with $status"
  elif ! grep -q "^kcmctl: plugin $plugins/" "$log"; then
    problem="the module was not loaded from $plugins"
  elif ! ranges=$(check_ranges "$log"); then
    problem=$ranges
  fi
  if [ -n "$problem" ]; then
    echo "--- commands"
    cat "$work/logs/round-$round.commands"
    echo "--- configuration"
    tail -n +1 "$work/config/kdeglobals" "$work/config/kwinrc" "$work/config/plasmafusionrc" 2>/dev/null | cut -c1-200
    echo "--- kcmctl"
    cut -c1-300 "$log"
    echo "FAIL: round $round (seed $seed): $problem"
    exit 1
  fi
  echo "round $round: $(grep -c '^kcmctl: > ' "$log") commands, $(grep -c '^kcmctl: [A-Za-z]*=' "$log") values, tools exit $(<"$work/bin/status")"
done
echo "PASS: $rounds random rounds (seed $seed)"
