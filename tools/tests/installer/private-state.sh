#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Full uninstall as an unprivileged user when only root can see pending splash state. The real
# sudo boundary is used; package commands are stand-ins. Only a disposable container is allowed.
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
INSTALLER=${1:-$HERE/../../../scripts/install.sh}
[ "$(id -u)" = 0 ] && { [ -e /run/.containerenv ] || [ -e /.dockerenv ]; } ||
  { echo "private-state: run as root in a disposable container" >&2; exit 1; }
command -v sudo >/dev/null
command -v runuser >/dev/null
[ ! -e /etc/sudoers.d/pf-private-state ] || { echo "private-state: existing sudo rule; refusing" >&2; exit 1; }
WORK=$(mktemp -d)
trap 'rm -f /etc/sudoers.d/pf-private-state; rm -rf "$WORK"' EXIT
chmod 0755 "$WORK"
mkdir -p "$WORK/bin" "$WORK/home" "$WORK/root/etc" \
  "$WORK/root/var/lib/plasma-fusion/plymouth" "$WORK/root/usr/share/plasma-fusion/tools/system"
chown nobody "$WORK/home"
chmod 0700 "$WORK/root/var/lib/plasma-fusion"
printf 'plymouth-plugin-script\n' >"$WORK/root/var/lib/plasma-fusion/plymouth/installed-packages"
printf 'ID=fedora\nVERSION_ID=44\nPRETTY_NAME="Fedora fixture"\n' >"$WORK/root/etc/os-release"
cat >"$WORK/bin/rpm" <<'EOF'
#!/bin/sh
for last; do :; done
case $last in
  %fedora) echo 44 ;;
  plasma-workspace|kwin) echo 6.7.5 ;;
  plasma-fusion) echo 0.6.0-1 ;;
  *) exit 1 ;;
esac
EOF
printf '#!/bin/sh\n[ -f "%s/cleaned" ] || exit 99\necho "packages removed"\n' "$WORK" >"$WORK/bin/dnf"
printf '#!/bin/sh\nexit 0\n' >"$WORK/bin/curl"
helper=$WORK/root/usr/share/plasma-fusion/tools/system/plymouth-uninstall.sh
printf '#!/bin/sh\n# no other installed package needs\ntouch "%s/cleaned"\n' "$WORK" >"$helper"
chmod 0755 "$WORK/bin/"* "$helper"
printf 'Defaults:nobody secure_path="%s/bin:/usr/sbin:/usr/bin:/bin"\nnobody ALL=(root) NOPASSWD: ALL\n' "$WORK" > /etc/sudoers.d/pf-private-state
chmod 0440 /etc/sudoers.d/pf-private-state
runuser -u nobody -- test ! -d "$WORK/root/var/lib/plasma-fusion/plymouth"
runuser -u nobody -- env HOME="$WORK/home" PATH="$WORK/bin:/usr/bin:/bin" \
  PLASMA_FUSION_DEV=1 PLASMA_FUSION_DEV_VERSION=0.6.0 PLASMA_FUSION_DEV_SERIES=6.7 \
  PLASMA_FUSION_DEV_ROOT="$WORK/root" sh "$INSTALLER" uninstall --yes --package-only
test -f "$WORK/cleaned"
echo "PASS unprivileged uninstall cleans splash state behind a root-only parent"
