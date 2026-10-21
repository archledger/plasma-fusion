#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The SDDM mode of tools/system/greeter-apply.sh and greeter-restore.sh as root, on the system's
# own files with the distribution's sddm package: what the unprivileged suite
# (greeter-sddm-unit.sh) cannot show - owners and groups kept by apply and restore, and the theme
# read as SDDM's greeter user. It changes /etc/sddm.conf, /etc/sddm.conf.d and
# /usr/share/sddm/themes, so it runs only as root in a throw-away container (CI's, or
#   podman run --rm -v "$PWD:/src:ro,z" registry.fedoraproject.org/fedora:44 bash -c \
#     'dnf -y -q install sddm kf6-kconfig python3 util-linux && cp -a /src /work && /work/tools/system/tests/greeter-sddm-root.sh'
# ; PF_DISPOSABLE_SYSTEM=1 allows another machine meant to be thrown away). Test tooling only.
#
#   tools/system/tests/greeter-sddm-root.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
TOP=$(cd "$HERE/../../.." && pwd)
APPLY=$TOP/tools/system/greeter-apply.sh
RESTORE=$TOP/tools/system/greeter-restore.sh
[ "$(id -u)" = 0 ] || { echo "greeter-sddm-root: run as root, in a throw-away container" >&2; exit 1; }
[ -e /run/.containerenv ] || [ -e /.dockerenv ] || [ "${PF_DISPOSABLE_SYSTEM:-}" = 1 ] ||
  { echo "greeter-sddm-root: not in a container; this changes the system's SDDM files" >&2; exit 1; }
getent passwd sddm >/dev/null && [ -x /usr/bin/sddm-greeter-qt6 ] && command -v setpriv >/dev/null ||
  { echo "greeter-sddm-root: install the sddm and util-linux packages first" >&2; exit 1; }
PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; [ -z "${2:-}" ] || printf '%s\n' "$2" | sed 's/^/    /'; }
apply() { OUT=$(bash "$APPLY" "$@" 2>&1); RC=$?; }
restore() { OUT=$(bash "$RESTORE" 2>&1); RC=$?; }
check() { OUT=$(bash "$APPLY" --check 2>&1); RC=$?; }
# The check as a user who is neither root nor in SDDM's group
check_nobody() { OUT=$(setpriv --reuid=65534 --regid=65534 --clear-groups -- bash "$APPLY" --check "$@" 2>&1); RC=$?; }
has() { grep -qF -- "$1" <<<"$OUT"; }
own() { stat -c '%U:%G %a' "$1"; }
CONF=/etc/sddm.conf
KDE=/etc/sddm.conf.d/kde_settings.conf
T=/usr/share/sddm/themes/plasmafusion
USER_CONF=$T/theme.conf.user

# What the package installs, built from the source: the theme, the cursors' index and the
# wallpapers (stand-ins; their contents are not read).
bash "$TOP/packages/sddm-theme/build.sh" /usr/share/sddm/themes >/dev/null
mkdir -p /usr/share/icons/PlasmaFusion-cursors /usr/share/plasma-fusion/backgrounds
: >/usr/share/icons/PlasmaFusion-cursors/index.theme
for v in login dimmed blurred; do : >"/usr/share/plasma-fusion/backgrounds/dusk-ridge-dark-$v.png"; done
mkdir -p /etc/systemd/system
ln -sf /usr/lib/systemd/system/sddm.service /etc/systemd/system/display-manager.service
[ -f "$CONF" ] || : >"$CONF"
cp -a "$CONF" /tmp/sddm.conf.before
KDE_BEFORE=absent
[ ! -e "$KDE" ] || KDE_BEFORE=present
# Undo every run and put the starting files back between sections
reset() {
  bash "$RESTORE" >/dev/null 2>&1 || true
  rm -rf /var/lib/plasma-fusion "$USER_CONF"
  [ "$KDE_BEFORE" = present ] || rm -f "$KDE"
  cp -a /tmp/sddm.conf.before "$CONF"
  chmod 0755 "$T"
}
set +e

# --- apply and restore on the distribution's files
check_nobody
[ "$RC" = 1 ] && has "Plasma Fusion greeter: no" && ok "an unprivileged check before: another theme (exit 1)" || bad "check before" "$OUT"
apply --login-image blurred
[ "$RC" = 0 ] && grep -qx Current=plasmafusion "$KDE" && [ "$(own "$KDE")" = "root:root 644" ] &&
  [ "$(own "$USER_CONF")" = "root:root 644" ] && ok "apply: kde_settings.conf and theme.conf.user root:root 0644" ||
  bad "apply" "$OUT
$(own "$KDE"; own "$USER_CONF")"
check_nobody --login-image blurred
[ "$RC" = 0 ] && has "Plasma Fusion greeter: yes" && ok "  an unprivileged check reads them (exit 0)" || bad "  check after" "$OUT"
restore
[ "$RC" = 0 ] && cmp -s "$CONF" /tmp/sddm.conf.before && [ ! -e "$USER_CONF" ] &&
  { [ "$KDE_BEFORE" = present ] || [ ! -e "$KDE" ]; } && ok "restore: the system's files as they were" ||
  bad "restore" "$OUT"
reset

# --- /etc/sddm.conf readable for SDDM's group only (root:sddm 0640) and naming a theme: apply
# removes that line and keeps the file's owner, group and mode; restore too
printf '[Theme]\nCurrent=breeze\n' >"$CONF"
chown root:sddm "$CONF"
chmod 0640 "$CONF"
apply
[ "$RC" = 0 ] && ! grep -q '^Current' "$CONF" && [ "$(own "$CONF")" = "root:sddm 640" ] &&
  ok "apply keeps /etc/sddm.conf root:sddm 0640" || bad "apply sddm.conf owner" "$OUT
$(own "$CONF")"
restore
[ "$RC" = 0 ] && grep -qx Current=breeze "$CONF" && [ "$(own "$CONF")" = "root:sddm 640" ] &&
  ok "  restore puts the line back, root:sddm 0640" || bad "  restore sddm.conf owner" "$OUT
$(own "$CONF")"
reset

# --- theme.conf.user readable for SDDM's group only: restore gives it its owner and group back
printf '[General]\ntype=image\n' >"$USER_CONF"
chown root:sddm "$USER_CONF"
chmod 0640 "$USER_CONF"
apply --login-image dimmed
[ "$RC" = 0 ] && [ "$(own "$USER_CONF")" = "root:root 644" ] && ok "apply writes theme.conf.user root:root 0644" ||
  bad "apply theme.conf.user" "$OUT"
restore
[ "$RC" = 0 ] && [ "$(own "$USER_CONF")" = "root:sddm 640" ] && grep -qx type=image "$USER_CONF" &&
  ok "  restore: root:sddm 0640 and its old contents" || bad "  restore theme.conf.user owner" "$OUT
$(own "$USER_CONF")"
reset

# --- a theme tree only root can read: SDDM's greeter runs as user sddm and could not load it.
# Twice: with setpriv, and as on a system without it (a minimal Fedora: util-linux-core only),
# where the mode bits are read for that user.
NOSETPRIV=$(mktemp -d)
# Searchable for user sddm too: the check runs find as that user through this PATH
chmod 0755 "$NOSETPRIV"
for f in /usr/bin/* /usr/sbin/*; do [ "${f##*/}" = setpriv ] || ln -sf "$f" "$NOSETPRIV/"; done
for how in setpriv "no setpriv"; do
  p=$PATH
  [ "$how" = setpriv ] || p=$NOSETPRIV
  chmod 0700 "$T"
  OUT=$(PATH=$p bash "$APPLY" 2>&1); RC=$?
  [ "$RC" = 1 ] && has "cannot be read by SDDM's greeter user" && { [ "$KDE_BEFORE" = present ] || [ ! -e "$KDE" ]; } &&
    ok "apply refuses a theme tree only root can read ($how)" || bad "0700 apply ($how)" "$OUT"
  OUT=$(PATH=$p bash "$APPLY" --check 2>&1); RC=$?
  [ "$RC" = 1 ] && has "unreadable for sddm" && ok "  root's check reads it as sddm ($how)" || bad "  0700 check ($how)" "$OUT"
  # A public theme tree below a directory that user cannot pass (ThemeDir under /srv/private, 0700)
  mkdir -p /srv/private/themes
  cp -a "$T" /srv/private/themes/
  chmod 0755 /srv/private/themes/plasmafusion
  chmod 0700 /srv/private
  mkdir -p /etc/sddm.conf.d
  printf '[Theme]\nThemeDir=/srv/private/themes\n' >/etc/sddm.conf.d/00-themedir.conf
  OUT=$(PATH=$p bash "$APPLY" 2>&1); RC=$?
  [ "$RC" = 1 ] && has "cannot be read by SDDM's greeter user" && ok "  a tree below a directory sddm cannot pass is refused ($how)" ||
    bad "  0700 parent ($how)" "$OUT"
  # The same through a link in the path (/srv/link -> /srv/private): the target's directories count
  ln -s private /srv/link
  printf '[Theme]\nThemeDir=/srv/link/themes\n' >/etc/sddm.conf.d/00-themedir.conf
  OUT=$(PATH=$p bash "$APPLY" 2>&1); RC=$?
  [ "$RC" = 1 ] && has "cannot be read by SDDM's greeter user" && ok "  and through a link to it ($how)" ||
    bad "  0700 parent via a link ($how)" "$OUT"
  rm -rf /etc/sddm.conf.d/00-themedir.conf /srv/link
  # A theme file that is a link to one below that directory: the greeter cannot follow it (the tree
  # itself readable again)
  chmod 0755 "$T"
  cp "$T/LoginCard.qml" /srv/private/LoginCard.qml
  mv "$T/LoginCard.qml" /tmp/LoginCard.qml
  ln -s /srv/private/LoginCard.qml "$T/LoginCard.qml"
  OUT=$(PATH=$p bash "$APPLY" 2>&1); RC=$?
  [ "$RC" = 1 ] && has "cannot be read by SDDM's greeter user" && ok "  a theme file linked to one sddm cannot reach is refused ($how)" ||
    bad "  in-tree link ($how)" "$OUT"
  rm "$T/LoginCard.qml"
  mv /tmp/LoginCard.qml "$T/LoginCard.qml"
  rm -rf /srv/private
  # The same tree readable for SDDM's group only: the greeter reads it
  chgrp -R sddm "$T"
  chmod 0750 "$T"
  OUT=$(PATH=$p bash "$APPLY" 2>&1); RC=$?
  [ "$RC" = 0 ] && ok "  one readable for SDDM's group (root:sddm 0750) is taken ($how)" || bad "  0750 sddm ($how)" "$OUT"
  chgrp -R root "$T"
  reset
done
chmod 0700 "$T"
check_nobody
[ "$RC" = 2 ] && has "Plasma Fusion greeter: unknown" && ok "an unprivileged check of that tree leaves the answer open" ||
  bad "0700 check nobody" "$OUT"
reset

# --- a theme tree others can write to
chmod o+w "$T"
apply
[ "$RC" = 1 ] && has "writable by others than root" && ok "apply refuses a theme tree others can write to" ||
  bad "o+w" "$OUT"
chmod o-w "$T"
reset
set -e

echo "greeter-sddm-root: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
