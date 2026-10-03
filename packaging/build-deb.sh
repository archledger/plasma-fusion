#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build the Debian packages of one source tarball (packaging/make-source.sh) for one target, on a
# system of that target (a container of it): the shared part plasma-fusion (Architecture: all, the
# same for every target) and the compiled parts, which depend on the KWin they were built against.
#
#   packaging/build-deb.sh --tarball T --target TARGET [--upstream VERSION] [--output DIR] [--source]
#
#   --tarball T    plasma-fusion-X.Y.Z.tar.gz from make-source.sh (it holds packaging/debian)
#   --target       ubuntu:SERIES   Launchpad PPA (X.Y.Z-0ppa1~SERIES1)
#                  neon            KDE neon (X.Y.Z-1~neon1, its Ubuntu base series)
#                  debian:SUITE    Debian testing or unstable (X.Y.Z-1~SUITE1)
#                  plain           X.Y.Z-1 for unstable
#   --upstream V   the upstream version (default: from the tarball's VERSION); a snapshot passes
#                  packaging/version.sh --deb (X.Y.Z~N.gitHASH)
#   --output DIR   where the packages go (default: the current directory)
#   --source       an unsigned source package for Launchpad (dpkg-buildpackage -S -d) instead of
#                  binary packages; it is signed with debsign by the release key's owner
#
# Needs dpkg-dev and debhelper, and for a binary build the Build-Depends of packaging/debian/control
# (apt-get build-dep on the unpacked tree installs them).
set -euo pipefail
TARBALL='' TARGET='' UPSTREAM='' OUT=$PWD SOURCE=0
while [ $# -gt 0 ]; do
  case $1 in
    --tarball) TARBALL=$(realpath "$2"); shift ;;
    --target) TARGET=$2; shift ;;
    --upstream) UPSTREAM=$2; shift ;;
    --output) OUT=$(mkdir -p "$2" && realpath "$2"); shift ;;
    --source) SOURCE=1 ;;
    -h|--help) sed -n '5,24p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
[ -f "$TARBALL" ] || { echo "--tarball: no such file" >&2; exit 2; }
work=$(mktemp -d "$OUT/.build-deb.XXXXXX")
trap 'rm -rf "$work"' EXIT
tar -xzf "$TARBALL" -C "$work"
top=$(find "$work" -mindepth 1 -maxdepth 1 -type d)
[ "$(echo "$top" | wc -l)" = 1 ] || { echo "the tarball has more than one top directory" >&2; exit 1; }
UPSTREAM=${UPSTREAM:-$(tr -d '[:space:]' <"$top/VERSION")}

case $TARGET in
  ubuntu:*) series=${TARGET#ubuntu:}; version=$UPSTREAM-0ppa1~${series}1; dist=$series ;;
  neon) series=$(. /etc/os-release && echo "${UBUNTU_CODENAME:-$VERSION_CODENAME}"); version=$UPSTREAM-1~neon1; dist=$series
    # neon ships the layer-shell QML module in layer-shell-qt (packaging/debian/rules).
    export LAYERSHELL_DEP=layer-shell-qt ;;
  debian:*) series=${TARGET#debian:}; version=$UPSTREAM-1~${series}1; dist=$series ;;
  plain) version=$UPSTREAM-1; dist=unstable ;;
  *) echo "--target: ubuntu:SERIES, neon, debian:SUITE or plain" >&2; exit 2 ;;
esac
[ "$dist" != sid ] || dist=unstable

src=$work/plasma-fusion-$UPSTREAM
[ "$top" = "$src" ] || mv "$top" "$src"
cp "$TARBALL" "$work/plasma-fusion_$UPSTREAM.orig.tar.gz"
cp -a "$src/packaging/debian" "$src/debian"
# The changelog of this build: the target's version above the release entries.
{
  printf 'plasma-fusion (%s) %s; urgency=medium\n\n' "$version" "$dist"
  if [ "$UPSTREAM" != "$(tr -d '[:space:]' <"$src/VERSION")" ]; then
    printf '  * Snapshot %s.\n' "$UPSTREAM"
  else
    printf '  * Plasma Fusion %s for %s.\n' "$UPSTREAM" "${TARGET/:/ }"
  fi
  printf '\n -- Wisbendji Fimerlus <archledger236@gmail.com>  %s\n\n' "$(date -R -u -d "@${SOURCE_DATE_EPOCH:-$(stat -c %Y "$src/VERSION")}")"
  cat "$src/packaging/debian/changelog"
} >"$src/debian/changelog"
echo "== plasma-fusion $version ($dist)"
cd "$src"
if [ "$SOURCE" = 1 ]; then
  # -sa: the upload carries the original tarball, which Launchpad needs the first time a PPA sees
  # this upstream version (it accepts the same tarball again later).
  dpkg-buildpackage -S -sa -d -us -uc
  files=("$work/plasma-fusion_$version.dsc" "$work/plasma-fusion_$version.debian.tar.xz"
         "$work/plasma-fusion_${version}_source.changes" "$work/plasma-fusion_${version}_source.buildinfo"
         "$work/plasma-fusion_$UPSTREAM.orig.tar.gz")
  for f in "${files[@]}"; do [ -e "$f" ] || { echo "missing from the source package: ${f##*/}" >&2; exit 1; }; done
else
  dpkg-buildpackage -b -us -uc
  files=("$work"/*.deb "$work"/*.ddeb "$work"/*.buildinfo "$work"/*.changes)
fi
for f in "${files[@]}"; do [ -e "$f" ] && cp "$f" "$OUT/"; done
for f in "$OUT"/*"$version"*; do [ -e "$f" ] && echo "${f##*/}"; done
