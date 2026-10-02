#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build the plasma-fusion source RPM and noarch RPM on this machine with rpmbuild.
#
#   packaging/build-rpm.sh [--topdir DIR] [--no-lint]
#
#   --topdir DIR   rpmbuild's _topdir (default: build/rpmbuild in the repository; git-ignored)
#   --no-lint      skip rpmlint
#
# Version 0.1.0; Release <number of commits>.git<short revision>, plus ".dirty<UTC time>" when the
# working tree differs from that revision (the package is built from the working tree as it is:
# tracked and untracked files that are not git-ignored), so that each such test build is newer
# than the one before. The source tarball holds that tree; %build runs
# tools/build.sh inside rpmbuild, %install copies its HOME tree (.local/share) to /usr/share.
# Needs rpm-build, python3, python3-pillow, python3-pyside6 (and rpmlint for the check).
# Reads git only (no index refresh, no commits).
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
TOPDIR=$ROOT/build/rpmbuild
LINT=1
while [ $# -gt 0 ]; do
  case $1 in
    --topdir) TOPDIR=$(mkdir -p "$2" && cd "$2" && pwd); shift ;;
    --no-lint) LINT=0 ;;
    -h|--help) sed -n '5,18p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

NAME=plasma-fusion
VERSION=0.1.0
git=(git -C "$ROOT" --no-optional-locks)
rev=$("${git[@]}" rev-parse HEAD)
short=$("${git[@]}" rev-parse --short=7 HEAD)
count=$("${git[@]}" rev-list --count HEAD)
dirty=
[ -z "$("${git[@]}" status --porcelain --untracked-files=normal)" ] || dirty=.dirty$(date -u +%Y%m%d%H%M)
RELEASE=$count.git$short$dirty
epoch=$("${git[@]}" log -1 --format=%ct HEAD)
export SOURCE_DATE_EPOCH=$epoch
echo "== $NAME-$VERSION-$RELEASE (revision $rev${dirty:+, working tree with changes})"

mkdir -p "$TOPDIR"/{BUILD,RPMS,SOURCES,SPECS,SRPMS}
rm -f "$TOPDIR/SOURCES/$NAME-$VERSION.tar.gz" "$TOPDIR/SRPMS/$NAME-$VERSION"-*.src.rpm \
  "$TOPDIR/RPMS/noarch/$NAME-$VERSION"-*.noarch.rpm

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

changelog_date=$(LC_ALL=C date -u -d "@$epoch" '+%a %b %d %Y')
sed -e "s/@VERSION@/$VERSION/g" -e "s/@RELEASE@/$RELEASE/g" -e "s/@GITREV@/$rev/g" -e "s/@CHANGELOG_DATE@/$changelog_date/g" \
  "$ROOT/packaging/$NAME.spec.in" >"$TOPDIR/SPECS/$NAME.spec"

# No session for the generators (they render offscreen). The package's build time is the
# revision's commit time and its build host a fixed name, so that two builds of one revision give
# identical packages (rpm clamps the files' times to the same time already).
env -u DISPLAY -u WAYLAND_DISPLAY -u XAUTHORITY -u DBUS_SESSION_BUS_ADDRESS \
  rpmbuild --define "_topdir $TOPDIR" --define "use_source_date_epoch_as_buildtime 1" \
  --define "_buildhost reproducible" -ba "$TOPDIR/SPECS/$NAME.spec"

rpm_file=$(ls "$TOPDIR/RPMS/noarch/$NAME-$VERSION-$RELEASE".*.noarch.rpm)
srpm_file=$(ls "$TOPDIR/SRPMS/$NAME-$VERSION-$RELEASE".*.src.rpm)
echo "rpm:  $rpm_file"
echo "srpm: $srpm_file"
if [ "$LINT" = 1 ]; then
  if command -v rpmlint >/dev/null; then
    rpmlint -r "$ROOT/packaging/$NAME.rpmlintrc" "$TOPDIR/SPECS/$NAME.spec" "$srpm_file" "$rpm_file"
  else
    echo "rpmlint is not installed; skipped"
  fi
fi
