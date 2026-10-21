#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The SDDM mode of tools/system/greeter-apply.sh and its undo in greeter-restore.sh, on a system
# tree in a temporary directory (PF_GREETER_ROOT; never as root, nothing outside the tree is
# touched): which file chooses SDDM's theme, what a later file overrides, backups, and that a theme
# chosen on System Settings' Login Screen (SDDM) page after a run is kept by the undo. The theme is
# the real one (packages/sddm-theme/build.sh); the greeter binary is a stand-in. Needs kreadconfig6
# and kwriteconfig6 (kf6-kconfig), as the scripts do. Test tooling only.
#
#   tools/system/tests/greeter-sddm-unit.sh [WORKDIR]
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../../.." && pwd)
APPLY=$TOP/tools/system/greeter-apply.sh
RESTORE=$TOP/tools/system/greeter-restore.sh
WORK=${1:-$(mktemp -d "${TMPDIR:-/tmp}/greeter-sddm-unit.XXXXXX")}
mkdir -p "$WORK"
WORK=$(cd "$WORK" && pwd)
if [ "$(id -u)" = 0 ]; then
  # CI containers run as root, and the scripts refuse PF_GREETER_ROOT for root: the suite runs as
  # nobody (the checkout must be readable for it, the work directory becomes nobody's).
  chown -R 65534:65534 "$WORK"
  exec setpriv --reuid=65534 --regid=65534 --clear-groups -- env HOME="$WORK" bash "$0" "$WORK"
fi
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
expect() { # NAME COMMAND...: the command succeeds
  local name=$1; shift
  if "$@" >/dev/null 2>&1; then ok "$name"; else bad "$name" "$OUT"; fi
}
LOGIN=/usr/share/plasma-fusion/backgrounds/dusk-ridge-dark-login.png
DIMMED=/usr/share/plasma-fusion/backgrounds/dusk-ridge-dark-dimmed.png
THEME=usr/share/sddm/themes/plasmafusion

# A system with SDDM as Fedora 44 ships it: the theme and cursor choice in the vendor directory,
# /etc/sddm.conf with comments only, sddm.service enabled.
fresh() { # NAME: a new tree in $R
  R=$WORK/$1
  rm -rf "$R"
  mkdir -p "$R/usr/share/sddm/themes" "$R/usr/bin" "$R/usr/share/icons/PlasmaFusion-cursors" \
    "$R/usr/share/plasma-fusion/backgrounds" "$R/usr/lib/sddm/sddm.conf.d" "$R/etc/systemd/system" \
    "$R/etc/sddm.conf.d"
  cp -a "$WORK/theme" "$R/$THEME"
  printf '#!/bin/sh\n' >"$R/usr/bin/sddm-greeter-qt6"
  chmod +x "$R/usr/bin/sddm-greeter-qt6"
  : >"$R/usr/share/icons/PlasmaFusion-cursors/index.theme"
  for v in login dimmed blurred; do : >"$R/usr/share/plasma-fusion/backgrounds/dusk-ridge-dark-$v.png"; done
  printf '[Theme]\nCurrent=01-breeze-fedora\nCursorTheme=breeze_cursors\nCursorSize=24\n' \
    >"$R/usr/lib/sddm/sddm.conf.d/kde_settings.conf"
  printf '[Autologin]\n# Whether sddm should automatically log back into sessions when they exit\n#Relogin=false\n\n[Theme]\n# Current theme name\n#Current=\n' \
    >"$R/etc/sddm.conf"
  ln -s /usr/lib/systemd/system/sddm.service "$R/etc/systemd/system/display-manager.service"
  cp -a "$R/etc" "$WORK/$1.etc-before"
}
apply() { OUT=$(PF_GREETER_ROOT=$R bash "$APPLY" "$@" 2>&1); RC=$?; }
restore() { OUT=$(PF_GREETER_ROOT=$R bash "$RESTORE" "$@" 2>&1); RC=$?; }
check() { OUT=$(PF_GREETER_ROOT=$R bash "$APPLY" --check "$@" 2>&1); RC=$?; }
has() { grep -qF -- "$1" <<<"$OUT"; }
val() { kreadconfig6 --file "$1" --group "$2" --key "$3" 2>/dev/null; } # FILE GROUP KEY
backups() { find "$R/var/lib/plasma-fusion" -mindepth 1 -maxdepth 1 -name 'greeter-backup-*' 2>/dev/null | wc -l; }
# Backup names carry the second: two runs in the same second must not collide.
tick() { sleep 1.1; }
KDE=etc/sddm.conf.d/kde_settings.conf

bash "$TOP/packages/sddm-theme/build.sh" "$WORK/build" >/dev/null
rm -rf "$WORK/theme"
cp -a "$WORK/build/plasmafusion" "$WORK/theme"
# The plasma-fusion command finds a package by its version file; status runs its greeter-apply.sh.
P=$WORK/pkg
rm -rf "$P"
mkdir -p "$P/share/plasma-fusion/tools/system" "$WORK/home"
echo 0.0.0 >"$P/share/plasma-fusion/version"
echo 6.7 >"$P/share/plasma-fusion/tested-plasma.txt"
cp "$APPLY" "$P/share/plasma-fusion/tools/system/"
status() { OUT=$(HOME=$WORK/home XDG_DATA_DIRS=$P/share XDG_DATA_HOME=$WORK/home/data XDG_STATE_HOME=$WORK/home/state \
  PF_GREETER_ROOT=$R bash "$TOP/tools/plasma-fusion" status 2>&1); RC=$?; }

# --- choosing the theme
fresh a
set +e
check
[ "$RC" = 1 ] && has "01-breeze-fedora (/usr/lib/sddm/sddm.conf.d/kde_settings.conf) differs" &&
  ok "check: Fedora's vendor file chooses its theme (not Plasma Fusion, exit 1)" || bad "check before" "$OUT"
apply --dry-run
[ "$RC" = 0 ] && has "+Current=plasmafusion" && [ ! -e "$R/$KDE" ] && [ "$(backups)" = 0 ] &&
  ok "dry run shows the change and changes nothing" || bad "dry run" "$OUT"
apply
[ "$RC" = 0 ] && [ "$(val "$R/$KDE" Theme Current)" = plasmafusion ] &&
  [ "$(val "$R/$KDE" Theme CursorTheme)" = PlasmaFusion-cursors ] &&
  ok "auto (sddm.service enabled): kde_settings.conf chooses the theme and the cursors" || bad "apply" "$OUT"
[ "$(stat -c %a "$R/$KDE")" = 644 ] && ok "  kde_settings.conf is 0644, as the page makes it" || bad "  mode $(stat -c %a "$R/$KDE")"
cmp -s "$R/etc/sddm.conf" "$WORK/a.etc-before/sddm.conf" && ok "  /etc/sddm.conf without the keys is left as it was" || bad "  sddm.conf changed"
[ ! -e "$R/$THEME/theme.conf.user" ] && ok "  the theme's own wallpaper needs no theme.conf.user" || bad "  theme.conf.user written"
b=$(find "$R/var/lib/plasma-fusion" -mindepth 1 -maxdepth 1 -name 'greeter-backup-*')
grep -qx greeter=sddm "$b/info" && grep -qx before=other "$b/info" && grep -qx "absent $KDE" "$b/manifest" &&
  [ "$(stat -c %a "$b")" = 700 ] && ok "  backup: greeter=sddm, before=other, kde_settings.conf absent, 0700" || bad "  backup" "$(cat "$b/info" "$b/manifest")"
check
[ "$RC" = 0 ] && has "Plasma Fusion greeter: yes" && ok "check: Plasma Fusion (exit 0)" || bad "check after" "$OUT"
apply
[ "$RC" = 0 ] && has "uses Plasma Fusion already" && [ "$(backups)" = 1 ] &&
  ok "a second run changes nothing and leaves no backup" || bad "second run" "$OUT"

# --- the wallpaper variants
tick
apply --login-image dimmed
[ "$RC" = 0 ] && [ "$(val "$R/$THEME/theme.conf.user" General background)" = "$DIMMED" ] &&
  ok "--login-image dimmed: theme.conf.user carries the background" || bad "dimmed" "$OUT"
check --login-image dimmed
[ "$RC" = 0 ] && has "(theme.conf.user) ok" && ok "  check reads theme.conf.user over theme.conf" || bad "  check dimmed" "$OUT"
grep -qx before=plasma-fusion "$(find "$R/var/lib/plasma-fusion" -mindepth 1 -maxdepth 1 -name 'greeter-backup-*' | sort | tail -1)/info" &&
  ok "  its backup says the greeter used Plasma Fusion already" || bad "  before=plasma-fusion"
check
[ "$RC" = 0 ] && ok "  check without --login-image counts any of the three wallpapers" || bad "  check any variant" "$OUT"
check --login-image login
[ "$RC" = 1 ] && ok "  check --login-image login wants that one" || bad "  check exact variant" "$OUT"
status
[ "$RC" = 0 ] && has "login screen (SDDM): Plasma Fusion" && ok "  status: Plasma Fusion with the dimmed wallpaper" || bad "  status dimmed" "$OUT"
tick
apply
[ "$RC" = 0 ] && [ "$(val "$R/$THEME/theme.conf.user" General background)" = "$LOGIN" ] &&
  ok "the default run sets the Login board's wallpaper again" || bad "back to login" "$OUT"

# --- back to before Plasma Fusion: three runs undone, newest first
restore --dry-run
[ "$RC" = 0 ] && has "dry run: nothing is changed" && [ -e "$R/$KDE" ] && [ -e "$R/$THEME/theme.conf.user" ] &&
  ok "restore --dry-run changes nothing" || bad "restore dry run" "$OUT"
restore
[ "$RC" = 0 ] && has "(3 runs of greeter-apply.sh to undo" && [ ! -e "$R/$KDE" ] && [ ! -e "$R/$THEME/theme.conf.user" ] &&
  diff -r --no-dereference "$R/etc" "$WORK/a.etc-before" >/dev/null &&
  ok "restore: every run undone, /etc as before, no theme.conf.user" || bad "restore" "$OUT"
check
[ "$RC" = 1 ] && has "01-breeze-fedora" && ok "  SDDM chooses Fedora's theme again" || bad "  check after restore" "$OUT"

# --- /etc/sddm.conf sets the theme: it is read last, so those lines go (and come back)
fresh b
printf '[Autologin]\n# keep me\nUser=\n\n[Theme]\n# the old one\nCurrent=breeze # chosen by hand\nCursorTheme=breeze_cursors\n\n[Users]\nMinimumUid=1000\n' >"$R/etc/sddm.conf"
chmod 0600 "$R/etc/sddm.conf"
cp -p "$R/etc/sddm.conf" "$WORK/b.sddm.conf"
check
has "breeze (/etc/sddm.conf)" && ok "check: SDDM's parser (comment after the value, last file wins)" || bad "parser" "$OUT"
apply
[ "$RC" = 0 ] && ! grep -q '^Current=\|^CursorTheme=' "$R/etc/sddm.conf" && grep -qx '# the old one' "$R/etc/sddm.conf" &&
  grep -qx 'MinimumUid=1000' "$R/etc/sddm.conf" && [ "$(wc -l <"$R/etc/sddm.conf")" = 9 ] &&
  [ "$(stat -c %a "$R/etc/sddm.conf")" = 600 ] &&
  ok "/etc/sddm.conf loses exactly the two lines, comments and mode stay" || bad "sddm.conf lines" "$OUT
$(cat "$R/etc/sddm.conf")"
check
[ "$RC" = 0 ] && ok "  and kde_settings.conf decides" || bad "  check" "$OUT"
restore
[ "$RC" = 0 ] && cmp -s "$R/etc/sddm.conf" "$WORK/b.sddm.conf" && [ "$(stat -c %a "$R/etc/sddm.conf")" = 600 ] &&
  ok "restore puts /etc/sddm.conf back byte for byte, with its mode" || bad "restore sddm.conf" "$OUT"

# --- a theme chosen on System Settings' page after the run is kept
fresh c
cp -p "$WORK/b.sddm.conf" "$R/etc/sddm.conf"
apply
# What the page's save does: kde_settings.conf gets the new theme (KConfig), and the key is
# removed from /etc/sddm.conf (not there any more, so that file stays as it is).
kwriteconfig6 --file "$R/$KDE" --group Theme --key Current breeze-dark
kwriteconfig6 --file "$R/$KDE" --group Autologin --key User alice
restore
[ "$RC" = 0 ] && [ "$(val "$R/$KDE" Theme Current)" = breeze-dark ] && [ "$(val "$R/$KDE" Autologin User)" = alice ] &&
  [ -z "$(val "$R/$KDE" Theme CursorTheme)" ] &&
  ok "restore keeps a theme chosen since, removes the run's cursor, keeps the page's other keys" || bad "chosen since" "$OUT"
! grep -q '^Current=' "$R/etc/sddm.conf" && grep -q '^CursorTheme=breeze_cursors' "$R/etc/sddm.conf" &&
  [ "$(stat -c %a "$R/etc/sddm.conf")" = 600 ] &&
  ok "  /etc/sddm.conf gets back the cursor line only (its old theme would override the new choice), mode 0600 kept" ||
  bad "  sddm.conf after chosen-since" "$OUT
$(cat "$R/etc/sddm.conf")"
check
has "breeze-dark (/etc/sddm.conf.d/kde_settings.conf)" && ok "  SDDM reads the theme chosen on the page" ||
  bad "  effective after chosen-since" "$OUT"

# --- only other keys changed on the page: the run's theme still goes back
fresh d
apply
kwriteconfig6 --file "$R/$KDE" --group Autologin --key User alice
restore
[ "$RC" = 0 ] && [ -z "$(val "$R/$KDE" Theme Current)" ] && [ -z "$(val "$R/$KDE" Theme CursorTheme)" ] &&
  [ "$(val "$R/$KDE" Autologin User)" = alice ] &&
  ok "restore removes the run's keys from a file the page changed since, its keys stay" || bad "other keys" "$OUT"

# --- /etc/sddm.conf removed after the run: left removed, the rest undone
fresh d2
cp -p "$WORK/b.sddm.conf" "$R/etc/sddm.conf"
apply
rm "$R/etc/sddm.conf"
restore
[ "$RC" = 0 ] && has "/etc/sddm.conf was removed after that run" && [ ! -e "$R/etc/sddm.conf" ] && [ ! -e "$R/$KDE" ] &&
  ok "restore leaves a removed /etc/sddm.conf removed and undoes the rest" || bad "removed sddm.conf" "$OUT"

# --- each greeter's backups are a chain of their own
fresh d3
apply
B=$R/var/lib/plasma-fusion/greeter-backup-29991231T000000Z
mkdir -p "$B"
printf 'created=29991231T000000Z\nbefore=other\n' >"$B/info"
: >"$B/manifest"
restore
# The plasma-login-manager run needs its greeter user, which the test tree cannot have.
has "Restore the login greeter (SDDM) to" && has "Restore the login greeter (plasma-login-manager) to $B" &&
  [ ! -e "$R/$KDE" ] && has "PF_GREETER_ROOT is only for SDDM backups" &&
  ok "a newer plasma-login-manager run does not hide the SDDM run from the default restore" || bad "chains" "$OUT"
fresh d3b
apply
B=$R/var/lib/plasma-fusion/greeter-backup-29991231T000000Z
mkdir -p "$B"
printf 'created=29991231T000000Z\nbefore=other\n' >"$B/info"
: >"$B/manifest"
restore --greeter sddm
[ "$RC" = 0 ] && [ ! -e "$R/$KDE" ] && ! has "plasma-login-manager) to" &&
  ok "restore --greeter sddm undoes SDDM's runs only" || bad "--greeter sddm" "$OUT"
rm -r "$B"
restore --greeter plasmalogin
[ "$RC" = 1 ] && has "no plasma-login-manager backup" && ok "  --greeter plasmalogin without its backups: refused" || bad "  --greeter plasmalogin" "$OUT"

# --- an unprivileged check that cannot read a file
fresh d4
apply
chmod 000 "$R/etc/sddm.conf"
check
[ "$RC" = 2 ] && has "cannot read /etc/sddm.conf" && has "Plasma Fusion greeter: unknown" &&
  ok "check: an unreadable file leaves the answer open (exit 2)" || bad "unreadable" "$OUT"
status
[ "$RC" = 0 ] && has "login screen (SDDM): cannot tell without root" && ok "  status says so" || bad "  status unreadable" "$OUT"
chmod 0644 "$R/etc/sddm.conf"
chmod 0311 "$R/etc/sddm.conf.d"
check
[ "$RC" = 2 ] && has "cannot read /etc/sddm.conf.d" && ok "  a directory it cannot list: exit 2 too" || bad "  unlistable" "$OUT"
chmod 0755 "$R/etc/sddm.conf.d"

# --- the undo puts back what was there: several lines of a key in order, an explicit empty value
fresh d5
printf '[Theme]\nCurrent=first\nCurrent=second\n' >"$R/etc/sddm.conf"
apply
echo '# edited since' >>"$R/etc/sddm.conf"
restore
check
[ "$RC" = 1 ] && has "second (/etc/sddm.conf)" && [ "$(grep -c '^Current=' "$R/etc/sddm.conf")" = 2 ] &&
  ok "key-wise restore puts several lines of a key back in their order (the last wins again)" || bad "line order" "$OUT
$(cat "$R/etc/sddm.conf")"
fresh d6
printf '[Theme]\nCurrent=\n' >"$R/$KDE"
apply
kwriteconfig6 --file "$R/$KDE" --group Autologin --key User alice
restore
check
grep -qx 'Current=' "$R/$KDE" && has "<unset> (/etc/sddm.conf.d/kde_settings.conf)" &&
  ok "an explicit empty Current= comes back (it hides the vendor file's theme), not removed" || bad "empty value" "$OUT
$(cat "$R/$KDE")"

# --- NixOS: the module chose the theme; the read-only check and status follow the system profile
fresh n
SW=$R/run/current-system/sw
mkdir -p "$SW/share/sddm/themes" "$SW/bin" "$SW/share/plasma-fusion/backgrounds"
bash "$TOP/packages/sddm-theme/build.sh" "$SW/share/sddm/themes" /run/current-system/sw/share/plasma-fusion/backgrounds/dusk-ridge-dark-login.png >/dev/null
: >"$SW/share/plasma-fusion/backgrounds/dusk-ridge-dark-login.png"
cp -p "$R/usr/bin/sddm-greeter-qt6" "$SW/bin/"
rm -r "${R:?}/usr/bin/sddm-greeter-qt6" "$R/etc/systemd/system/display-manager.service" "$R/usr/lib/sddm/sddm.conf.d/kde_settings.conf"
: >"$R/etc/NIXOS"
printf '[Unit]\nDescription=Display Manager\n' >"$R/etc/systemd/system/display-manager.service"
printf '[Theme]\nCurrent=plasmafusion\nCursorTheme=PlasmaFusion-cursors\nThemeDir=/run/current-system/sw/share/sddm/themes\n' \
  >"$R/etc/sddm.conf.d/00-nixos.conf"
check
[ "$RC" = 0 ] && has "(/run/current-system/sw/bin/sddm-greeter-qt6)" && ok "NixOS: check reads the module's choice" || bad "nixos check" "$OUT"
status
[ "$RC" = 0 ] && has "login screen (SDDM): Plasma Fusion" && ok "  status: Plasma Fusion" || bad "  nixos status" "$OUT"
printf '[Theme]\nCurrent=breeze\nThemeDir=/run/current-system/sw/share/sddm/themes\n' >"$R/etc/sddm.conf.d/00-nixos.conf"
status
has "programs.plasma-fusion.sddm = true chooses Plasma Fusion" && ok "  status names the module option" || bad "  nixos hint" "$OUT"

# --- what stops a run before anything changes
fresh e
mkdir -p "$R/etc/sddm.conf.d"
printf '[Theme]\nCurrent=local\n' >"$R/etc/sddm.conf.d/kde-local.conf"
apply
[ "$RC" = 1 ] && has "depends on its locale" && [ ! -e "$R/$KDE" ] && [ "$(backups)" = 0 ] &&
  ok "a drop-in whose order against kde_settings.conf depends on the locale stops the run" || bad "locale order" "$OUT"
check
[ "$RC" = 2 ] && has "depends on its locale" && ok "  check leaves the answer open" || bad "  check locale" "$OUT"
rm "$R/etc/sddm.conf.d/kde-local.conf"
mkdir -p "$R/etc/sddm.conf.d"
printf '[Theme]\nCurrent=local\n' >"$R/etc/sddm.conf.d/zz-local.conf"
apply
[ "$RC" = 1 ] && has "/etc/sddm.conf.d/zz-local.conf would still set [Theme] Current=local" && [ ! -e "$R/$KDE" ] &&
  [ "$(backups)" = 0 ] && ok "a drop-in read after kde_settings.conf stops the run, nothing changed" || bad "later drop-in" "$OUT"
rm "$R/etc/sddm.conf.d/zz-local.conf"
printf '[Theme]\nCurrent=vendor\n' >"$R/etc/sddm.conf.d/00-vendor.conf"
apply
[ "$RC" = 0 ] && ok "one read before it does not" || bad "earlier drop-in" "$OUT"
fresh f
rm "$R/usr/bin/sddm-greeter-qt6"
apply
[ "$RC" = 1 ] && has "sddm-greeter-qt6 is missing" && [ ! -e "$R/$KDE" ] && ok "no Qt 6 greeter: refused" || bad "no greeter" "$OUT"
check
[ "$RC" = 1 ] && has "Qt 6 greeter   missing" && ok "  check names it" || bad "  check no greeter" "$OUT"
fresh g
rm -r "${R:?}/$THEME"
apply
[ "$RC" = 1 ] && has "theme is not in /usr/share/sddm/themes" && ok "no theme installed: refused" || bad "no theme" "$OUT"
fresh g2
ln -s ../../../../../etc/sddm.conf "$R/$THEME/theme.conf.user"
apply --login-image dimmed
[ "$RC" = 1 ] && has "theme.conf.user is a link" && [ ! -e "$R/$KDE" ] &&
  ok "a link as theme.conf.user: refused (root would copy what it points to)" || bad "link" "$OUT"
mv "$R/etc/sddm.conf" "$R/etc/sddm.conf.real"
ln -s sddm.conf.real "$R/etc/sddm.conf"
apply
[ "$RC" = 1 ] && has "/etc/sddm.conf is a link" && [ -L "$R/etc/sddm.conf" ] && [ ! -e "$R/$KDE" ] &&
  ok "a link as /etc/sddm.conf: refused (the run would replace it)" || bad "sddm.conf link" "$OUT"
rm "$R/etc/sddm.conf"
mv "$R/etc/sddm.conf.real" "$R/etc/sddm.conf"
rm "$R/$THEME/theme.conf.user"
apply --login-image dimmed
ln -sf /nonexistent "$R/$THEME/theme.conf.user"
restore
[ "$RC" = 0 ] && has "theme.conf.user is a link now: left alone" && [ -L "$R/$THEME/theme.conf.user" ] &&
  ok "  restore leaves a link put there since alone" || bad "  restore link" "$OUT"
fresh h
: >"$R/etc/NIXOS"
apply
[ "$RC" = 1 ] && has "programs.plasma-fusion.sddm" && ok "NixOS: refused, the module option named" || bad "nixos" "$OUT"
fresh i
apply --greeter sddm --output "$WORK/out"
[ "$RC" = 1 ] && has "--output writes plasma-login-manager's files" && ok "--output with --greeter sddm: refused" || bad "output" "$OUT"
apply --display-from "$R/etc/sddm.conf"
[ "$RC" = 1 ] && has "--display-from is for plasma-login-manager" && ok "--display-from on SDDM: refused" || bad "display-from" "$OUT"
rm "$R/etc/systemd/system/display-manager.service"
ln -s /usr/lib/systemd/system/plasmalogin.service "$R/etc/systemd/system/display-manager.service"
apply
[ "$RC" = 1 ] && has "PF_GREETER_ROOT is only for the SDDM mode" && ok "auto with plasmalogin.service enabled takes plasma-login-manager" || bad "auto plasmalogin" "$OUT"
apply --greeter sddm
[ "$RC" = 0 ] && has "plasmalogin.service is enabled; SDDM shows this once" && ok "--greeter sddm still prepares SDDM, with a note" || bad "explicit sddm" "$OUT"

# --- plasma-fusion status: the login screen row (readable without root)
fresh j
status
[ "$RC" = 0 ] && has "login screen (SDDM): another theme" && ok "status: SDDM with another theme" || bad "status other" "$OUT"
apply
status
[ "$RC" = 0 ] && has "login screen (SDDM): Plasma Fusion" && ok "status: SDDM with Plasma Fusion" || bad "status fusion" "$OUT"
rm "$R/etc/systemd/system/display-manager.service"
ln -s /usr/lib/systemd/system/plasmalogin.service "$R/etc/systemd/system/display-manager.service"
status
[ "$RC" = 0 ] && has "login screen (plasma-login-manager): sudo" && ok "status: plasma-login-manager names the check" || bad "status plasmalogin" "$OUT"
set -e

echo "greeter-sddm-unit: $PASS passed, $FAIL failed (work: $WORK)"
[ "$FAIL" = 0 ]
