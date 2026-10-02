#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# In a Debian-family container, as root: install the build requirements, build the packages for
# TARGET with packaging/build-deb.sh, list lintian's errors, install the packages and check them.
#
#   tools/tests/packages/deb.sh TARGET TARBALL OUTPUT_DIR [UPSTREAM_VERSION]
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/../../.." && pwd)
TARGET=$1 TARBALL=$(realpath "$2") OUT=$(mkdir -p "$3" && realpath "$3")
UPSTREAM=${4:-}
export DEBIAN_FRONTEND=noninteractive
apt-get update -qq
apt-get install -y -qq --no-install-recommends dpkg-dev debhelper devscripts equivs lintian ca-certificates >/dev/null
bd=$(mktemp -d)
tar -xzf "$TARBALL" -C "$bd" --wildcards '*/packaging/debian/control' --strip-components=2
(cd "$bd" && mk-build-deps -i -r -t "apt-get -y -qq --no-install-recommends" debian/control) >"$bd/build-deps.log" 2>&1 ||
  { tail -40 "$bd/build-deps.log"; exit 1; }
echo "== built against kwin-dev $(dpkg-query -W -f '${Version}' kwin-dev), Qt $(dpkg-query -W -f '${Version}' qt6-base-dev), breeze-icon-theme $(dpkg-query -W -f '${Version}' breeze-icon-theme)"
bash "$ROOT/packaging/build-deb.sh" --tarball "$TARBALL" --target "$TARGET" ${UPSTREAM:+--upstream "$UPSTREAM"} --output "$OUT" >"$bd/build.log" 2>&1 ||
  { tail -80 "$bd/build.log"; exit 1; }
echo "== lintian errors"
lintian "$OUT"/*.changes 2>&1 | grep -E '^E: ' || echo none
echo "== install"
debs=()
for f in "$OUT"/plasma-fusion*.deb; do [[ $f == *dbgsym* ]] || debs+=("$f"); done
apt-get install -y -qq --no-install-recommends "${debs[@]}" >/dev/null
dpkg-query -W 'plasma-fusion*'
test "$(plasma-fusion version)" = "$(tar -xzOf "$TARBALL" --wildcards '*/VERSION' | tr -d '[:space:]')"
grep -q 'exec.path">/usr/libexec/plasma-fusion/plasma-fusion-charge-limit<' /usr/share/polkit-1/actions/org.plasmafusion.charge-limit.policy
for p in decoration settings navigation; do test -s "/usr/share/plasma-fusion/built-against/$p"; done
broken=$(find /usr/share/icons/PlasmaFusion* -xtype l | grep -vcE '/(hicolor|flatpak)/' || true)
[ "$broken" = 0 ] || { echo "$broken broken icon links" >&2; exit 1; }
echo "navigation depends: $(dpkg-query -W -f '${Depends}' plasma-fusion-navigation)"
echo "deb ($TARGET): ok"
