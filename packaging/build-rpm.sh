#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build the plasma-fusion source RPM and RPMs of the working tree on this machine with rpmbuild,
# from packaging/fedora/plasma-fusion.spec (the spec Copr builds releases from).
#
#   packaging/build-rpm.sh [--topdir DIR] [--compiled] [--no-lint]
#
#   --topdir DIR   rpmbuild's _topdir (default: build/rpmbuild in the repository; git-ignored)
#   --compiled     also build the compiled parts (-decoration, -settings, -navigation); needs their
#                  build requirements (KWin, KDecoration and KDE Frameworks development packages)
#   --no-lint      skip rpmlint
#
# Version: packaging/version.sh (0.2.0~N.gitHASH before the tag v0.2.0, 0.2.0 at it); Release 1,
# plus ".dirty<UTC time>" when the working tree differs from that revision (the package is built
# from the working tree as it is: tracked and untracked files that are not git-ignored), so that
# each such test build is newer than the one before. Needs rpm-build, python3, python3-pillow,
# python3-numpy, python3-pyside6 (and rpmlint for the check). Reads git only (no index refresh, no
# commits).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TOPDIR=$ROOT/build/rpmbuild
LINT=1
COMPILED=0
while [ $# -gt 0 ]; do
  case $1 in
    --topdir) TOPDIR=$(mkdir -p "$2" && cd "$2" && pwd); shift ;;
    --compiled) COMPILED=1 ;;
    --no-lint) LINT=0 ;;
    -h|--help) sed -n '5,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

NAME=plasma-fusion
SPEC=$ROOT/packaging/fedora/$NAME.spec
VERSION=$("$ROOT/packaging/version.sh" --rpm)
git=(git -C "$ROOT" --no-optional-locks)
rev=$("${git[@]}" rev-parse HEAD)
dirty=
[ -z "$("${git[@]}" status --porcelain --untracked-files=normal)" ] || dirty=.dirty$(date -u +%Y%m%d%H%M)
RELEASE=1$dirty
epoch=$("${git[@]}" log -1 --format=%ct HEAD)
export SOURCE_DATE_EPOCH=$epoch
echo "== $NAME-$VERSION-$RELEASE (revision $rev${dirty:+, working tree with changes}$([ "$COMPILED" = 1 ] && echo ", with the compiled parts"))"

mkdir -p "$TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
rm -f "$TOPDIR/SOURCES/$NAME-"*.tar.gz "$TOPDIR/SRPMS/$NAME-"*.src.rpm "$TOPDIR/RPMS/"*/"$NAME-"*.rpm

# Source tarball: the working tree's files (tracked and untracked, not ignored), in a stable
# order with neutral owners and the revision's time stamp.
list=$(mktemp)
trap 'rm -f "$list"' EXIT
"${git[@]}" ls-files -z --cached --others --exclude-standard |
  while IFS= read -r -d '' f; do [ -e "$ROOT/$f" ] || [ -L "$ROOT/$f" ] && printf '%s\0' "$f"; done |
  sort -z -u >"$list"
tar -C "$ROOT" --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner \
  --transform="s,^,$NAME-$VERSION/," -czf "$TOPDIR/SOURCES/$NAME-$VERSION.tar.gz" \
  --null --no-recursion --files-from="$list"
echo "source: $TOPDIR/SOURCES/$NAME-$VERSION.tar.gz ($(tr -cd '\0' <"$list" | wc -c) files)"

# The spec with this build's version and release, and a changelog entry for the snapshot.
changelog_date=$(LC_ALL=C date -u -d "@$epoch" '+%a %b %d %Y')
python3 - "$SPEC" "$TOPDIR/SPECS/$NAME.spec" "$VERSION" "$RELEASE" "$changelog_date" "$rev" <<'PY'
import re, sys
src, dst, version, release, date, rev = sys.argv[1:]
t = open(src).read()
t, n1 = re.subn(r'^Version:(\s+)\S+$', lambda m: f'Version:{m.group(1)}{version}', t, count=1, flags=re.M)
t, n2 = re.subn(r'^Release:(\s+)\S+$', lambda m: f'Release:{m.group(1)}{release}%{{?dist}}', t, count=1, flags=re.M)
assert n1 == 1 and n2 == 1, 'Version/Release lines not found'
if not re.fullmatch(r'\d+\.\d+\.\d+', version) or release != '1':
    entry = f'* {date} Wisbendji Fimerlus <archledger236@gmail.com> - {version}-{release}\n- Snapshot of git revision {rev}\n\n'
    t = t.replace('%changelog\n', '%changelog\n' + entry, 1)
open(dst, 'w').write(t)
PY

# No session for the generators (they render offscreen). The package's build time is the
# revision's commit time and its build host a fixed name, so that two builds of one revision give
# identical packages (rpm clamps the files' times to the same time already).
without=()
[ "$COMPILED" = 1 ] || without=(--without compiled)
env -u DISPLAY -u WAYLAND_DISPLAY -u XAUTHORITY -u DBUS_SESSION_BUS_ADDRESS \
  rpmbuild --define "_topdir $TOPDIR" --define "use_source_date_epoch_as_buildtime 1" \
  --define "_buildhost reproducible" "${without[@]}" -ba "$TOPDIR/SPECS/$NAME.spec"

mapfile -t rpms < <(ls "$TOPDIR"/RPMS/*/"$NAME"-*"$VERSION-$RELEASE".*.rpm)
srpm_file=$(ls "$TOPDIR/SRPMS/$NAME-$VERSION-$RELEASE".*.src.rpm)
printf 'rpm:  %s\n' "${rpms[@]}"
echo "srpm: $srpm_file"
if [ "$LINT" = 1 ]; then
  if command -v rpmlint >/dev/null; then
    rpmlint -r "$ROOT/packaging/$NAME.rpmlintrc" "$TOPDIR/SPECS/$NAME.spec" "$srpm_file" "${rpms[@]}"
  else
    echo "rpmlint is not installed; skipped"
  fi
fi
