#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build a release's files from its signed tag (docs/RELEASING.md), in podman containers:
#
#   packaging/release-assets.sh vX.Y.Z OUTDIR
#
#   OUTDIR/release/  the GitHub release assets: plasma-fusion-X.Y.Z.tar.gz (git archive of the tag),
#                    install.sh (stamped), the .deb sets for KDE neon and Debian testing and the
#                    shared part alone (X.Y.Z-1_all), and SHA256SUMS over all of them. The release
#                    key's owner signs it: gpg -u F35053398E3C80FE20891B82C10B8492BD7F30C6!
#                    --armor --detach-sign -o SHA256SUMS.asc SHA256SUMS
#   OUTDIR/ppa/      the unsigned source package for each PPA series (debsign, then dput)
#   OUTDIR/logs/
#
# The Copr, AUR and Nix builds come from the tag itself (.packit.yaml, packaging/arch/PKGBUILD,
# flake.nix). Environment: PF_COPR_FEDORA (default "44 45"), PF_PPA_SERIES (default "stonking"),
# PF_DEB_TARGETS (default "neon testing"): stamped into install.sh.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TAG=${1:?usage: release-assets.sh vX.Y.Z OUTDIR}
OUT=$(mkdir -p "${2:?usage: release-assets.sh vX.Y.Z OUTDIR}" && realpath "$2")
COPR=${PF_COPR_FEDORA:-44 45} PPA=${PF_PPA_SERIES:-stonking} DEBT=${PF_DEB_TARGETS:-neon testing}
git=(git -C "$ROOT")
[[ $TAG =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "not a release tag: $TAG" >&2; exit 2; }
version=${TAG#v}
[ "$("${git[@]}" rev-parse HEAD)" = "$("${git[@]}" rev-parse "$TAG^{commit}")" ] ||
  { echo "check out $TAG first (HEAD is not the tag)" >&2; exit 1; }
"${git[@]}" verify-tag "$TAG" >/dev/null 2>&1 || { echo "$TAG is not a signed tag that verifies" >&2; exit 1; }
"$ROOT/packaging/check-version.sh"
[ -z "$("${git[@]}" status --porcelain)" ] || { echo "the working tree has changes" >&2; exit 1; }

rm -rf "$OUT/release" "$OUT/ppa" "$OUT/logs" "$OUT/work"
mkdir -p "$OUT/release" "$OUT/ppa" "$OUT/logs" "$OUT/work"
tarball=$("$ROOT/packaging/make-source.sh" --ref "$TAG" --output "$OUT/release")
"$ROOT/packaging/stamp-installer.sh" --copr "$COPR" --ppa "$PPA" --deb "$DEBT" "$OUT/release/install.sh"

# Containers build from a copy of the tree at the tag (the tarball), with the test scripts.
tar -xzf "$tarball" -C "$OUT/work"
src=$OUT/work/plasma-fusion-$version
deb() { # NAME IMAGE TARGET
  podman run --rm --user root -v "$OUT:$OUT:rw,z" -w "$src" "$2" \
    bash tools/tests/packages/deb.sh "$3" "$tarball" "$OUT/work/$1" >"$OUT/logs/$1.log" 2>&1 ||
    { tail -40 "$OUT/logs/$1.log"; echo "the $1 build failed" >&2; exit 1; }
  for f in "$OUT/work/$1"/*.deb; do [[ $f == *dbgsym* ]] || cp "$f" "$OUT/release/"; done
  echo "built: $1"
}
for t in $DEBT; do
  case $t in
    neon) deb neon invent-registry.kde.org/neon/docker-images/plasma:user neon ;;
    testing) deb testing docker.io/library/debian:testing debian:testing ;;
    *) echo "unknown .deb target $t" >&2; exit 2 ;;
  esac
done
deb plain docker.io/library/debian:testing plain
# The shared part of the plain build is the universal .deb; its compiled parts are not shipped.
rm -f "$OUT/release"/plasma-fusion-{decoration,settings,navigation}_"$version"-1_amd64.deb

# The PPA's source packages (Launchpad builds them; nothing is signed here).
for s in $PPA; do
  podman run --rm --user root -v "$OUT:$OUT:rw,z" -w "$src" "docker.io/library/ubuntu:26.10" bash -c "
    export DEBIAN_FRONTEND=noninteractive
    apt-get update -qq && apt-get install -y -qq --no-install-recommends dpkg-dev debhelper >/dev/null &&
    bash packaging/build-deb.sh --tarball '$tarball' --target ubuntu:$s --source --output '$OUT/ppa'" \
    >"$OUT/logs/ppa-$s.log" 2>&1 || { tail -30 "$OUT/logs/ppa-$s.log"; echo "the PPA source for $s failed" >&2; exit 1; }
  echo "built: PPA source for $s"
done

(cd "$OUT/release" && sha256sum -- * | LC_ALL=C sort -k2 >SHA256SUMS)
rm -rf "$OUT/work"
echo "release files in $OUT/release:"
cat "$OUT/release/SHA256SUMS"
echo "next: sign SHA256SUMS (see the header), debsign the PPA sources in $OUT/ppa"
