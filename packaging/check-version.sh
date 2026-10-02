#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# VERSION is the only version: check that the Fedora spec, the Arch PKGBUILD and the Debian changelog
# say the same (the Nix packages and the installer read VERSION themselves). With a tag vX.Y.Z on
# HEAD, also that the tag is VERSION.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
version=$(tr -d '[:space:]' <"$ROOT/VERSION")
rc=0
check() { # WHAT VALUE
  if [ "$2" = "$version" ]; then echo "ok   $1: $2"; else echo "FAIL $1: '$2', VERSION says $version"; rc=1; fi
}
check packaging/fedora/plasma-fusion.spec "$(sed -n 's/^Version:[[:space:]]*//p' "$ROOT/packaging/fedora/plasma-fusion.spec")"
check packaging/arch/PKGBUILD "$(sed -n 's/^pkgver=//p' "$ROOT/packaging/arch/PKGBUILD")"
check packaging/debian/changelog "$(sed -n '1s/^plasma-fusion (\([^-)]*\)-[^)]*).*/\1/p' "$ROOT/packaging/debian/changelog")"
tag=$(git -C "$ROOT" describe --exact-match --tags --match 'v[0-9]*' HEAD 2>/dev/null || true)
[ -z "$tag" ] || check "tag $tag" "${tag#v}"
exit "$rc"
