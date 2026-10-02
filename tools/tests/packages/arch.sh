#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# In an archlinux container, as root: build packaging/arch/PKGBUILD from a source tarball of this
# tree (instead of the signed tag), check it with namcap, install it and check the installed files.
#
#   tools/tests/packages/arch.sh TARBALL OUTPUT_DIR
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
TARBALL=$(realpath "$1") OUT=$(mkdir -p "$2" && realpath "$2")
pacman -Syu --noconfirm --needed base-devel git namcap sudo >/dev/null
id builder >/dev/null 2>&1 || useradd -m builder
echo 'builder ALL=(ALL) NOPASSWD: ALL' >/etc/sudoers.d/builder
work=/home/builder/pkg
rm -rf "$work" && mkdir -p "$work"
cp "$ROOT/packaging/arch/PKGBUILD" "$TARBALL" "$work/"
version=$(sed -n 's/^pkgver=//p' "$work/PKGBUILD")
# The tarball's top directory must be plasma-fusion/, as the git source would be.
sed -i -e "s|^source=.*|source=(\"plasma-fusion::file://$work/${TARBALL##*/}\")|" -e '/^validpgpkeys=/d' "$work/PKGBUILD"
[ "$(tar -tzf "$TARBALL" | head -n 1 | cut -d/ -f1)" = plasma-fusion ] || { echo "the tarball's top directory must be plasma-fusion" >&2; exit 1; }
chown -R builder: "$work"
cd "$work"
# The log is written by root (the redirection), the build runs as builder.
# shellcheck disable=SC2024
if ! sudo -u builder env MAKEFLAGS="-j$(nproc)" makepkg -s --noconfirm --noprogressbar >makepkg.log 2>&1; then
  tail -60 makepkg.log
  exit 1
fi
cp ./*.pkg.tar.zst "$OUT/"
echo "== namcap (errors other than the links to apps' own icons and the debug package's links)"
namcap PKGBUILD ./*.pkg.tar.zst >namcap.log 2>&1 || true
if grep " E: " namcap.log | grep -vE "/(hicolor|flatpak)/|plasma-fusion-debug E: Symlink"; then exit 1; fi
echo "== install"
pacman -U --noconfirm ./plasma-fusion-*.pkg.tar.zst >/dev/null
pacman -Q | grep '^plasma-fusion'
test "$(plasma-fusion version)" = "$version"
grep -q 'exec.path">/usr/lib/plasma-fusion/plasma-fusion-charge-limit<' /usr/share/polkit-1/actions/org.plasmafusion.charge-limit.policy
for p in decoration settings navigation; do test -s "/usr/share/plasma-fusion/built-against/$p"; done
broken=$(find /usr/share/icons/PlasmaFusion* -xtype l | grep -vcE '/(hicolor|flatpak)/' || true)
[ "$broken" = 0 ] || { echo "$broken broken icon links" >&2; exit 1; }
echo "arch: ok"
