#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Make the source tarball every channel builds from: plasma-fusion-VERSION.tar.gz with one top
# directory plasma-fusion-VERSION/ (a release asset; Copr, the AUR, Debian and Nix build the same
# files).
#
#   packaging/make-source.sh [--ref REF | --worktree] [--top NAME] [--output DIR]
#
#   --ref REF     git archive of a commit or tag (default HEAD): what a release ships
#   --worktree    the working tree as it is (tracked and untracked files that are not ignored),
#                 for test builds of uncommitted changes
#   --top NAME    the top directory (default plasma-fusion-VERSION; VERSION from
#                 packaging/version.sh --plain at that commit)
#   --output DIR  where the tarball goes (default build/source)
#
# The files are sorted, owned by root and dated with the commit's time, and gzip writes no name or
# time, so the same commit gives the same bytes. Prints the tarball's path.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
REF=HEAD WORKTREE=0 TOP='' OUT=$ROOT/build/source
while [ $# -gt 0 ]; do
  case $1 in
    --ref) REF=$2; shift ;;
    --worktree) WORKTREE=1 ;;
    --top) TOP=$2; shift ;;
    --output) OUT=$2; shift ;;
    -h|--help) sed -n '5,20p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done
git=(git -C "$ROOT" --no-optional-locks)
commit=$("${git[@]}" rev-parse --verify "$REF^{commit}")
epoch=$("${git[@]}" log -1 --format=%ct "$commit")
if [ "$WORKTREE" = 1 ]; then
  version=$(tr -d '[:space:]' <"$ROOT/VERSION")
else
  version=$("${git[@]}" show "$commit:VERSION" | tr -d '[:space:]')
fi
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION is not X.Y.Z: $version" >&2; exit 1; }
TOP=${TOP:-plasma-fusion-$version}
mkdir -p "$OUT"
tarball=$OUT/plasma-fusion-$version.tar.gz
tmp=$(mktemp "$OUT/.make-source.XXXXXX")
trap 'rm -f "$tmp"' EXIT
if [ "$WORKTREE" = 1 ]; then
  "${git[@]}" ls-files -z --cached --others --exclude-standard |
    while IFS= read -r -d '' f; do [ -e "$ROOT/$f" ] || [ -L "$ROOT/$f" ] && printf '%s\0' "$f"; done |
    sort -z -u |
    tar -C "$ROOT" --sort=name --mtime="@$epoch" --owner=0 --group=0 --numeric-owner \
      --transform="s,^,$TOP/," --null --no-recursion --files-from=- -cf - | gzip -n -9 >"$tmp"
else
  "${git[@]}" archive --format=tar --prefix="$TOP/" "$commit" | gzip -n -9 >"$tmp"
fi
chmod 0644 "$tmp"
mv -f "$tmp" "$tarball"
trap - EXIT
echo "$tarball"
