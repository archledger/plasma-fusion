#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Print the version of the tree in the form a package format wants. VERSION (the repository's top
# directory) is the only source: the release being prepared, or just made.
#
#   packaging/version.sh [--rpm | --deb | --plain] [--git DIR]
#
#   at the tag vX.Y.Z      X.Y.Z                      (every format)
#   after the tag          X.Y.Z^N.gitHASH (rpm)      X.Y.Z+N.gitHASH (deb)    N commits since the tag
#   before the tag         X.Y.Z~N.gitHASH (rpm)      X.Y.Z~N.gitHASH (deb)    N commits in all
#   --plain                X.Y.Z, whatever the commit
#
# A snapshot thus sorts above the release before it and below the release it leads to, in rpm and
# in dpkg; each later commit sorts higher. Without git (a release tarball) the version is X.Y.Z.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
FORM=rpm
GITDIR=$ROOT
while [ $# -gt 0 ]; do
  case $1 in
    --rpm) FORM=rpm ;;
    --deb) FORM=deb ;;
    --plain) FORM=plain ;;
    --git) GITDIR=$2; shift ;;
    -h|--help) sed -n '5,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    *) echo "unknown option: $1" >&2; exit 2 ;;
  esac
  shift
done

version=$(tr -d '[:space:]' <"$ROOT/VERSION")
[[ $version =~ ^[0-9]+\.[0-9]+\.[0-9]+$ ]] || { echo "VERSION is not X.Y.Z: $version" >&2; exit 1; }
git=(git -C "$GITDIR" --no-optional-locks)
if [ "$FORM" = plain ] || ! "${git[@]}" rev-parse --git-dir >/dev/null 2>&1; then
  echo "$version"
  exit 0
fi
short=$("${git[@]}" rev-parse --short=7 HEAD)
if "${git[@]}" rev-parse -q --verify "refs/tags/v$version^{commit}" >/dev/null; then
  tagged=$("${git[@]}" rev-parse "v$version^{commit}")
  if [ "$tagged" = "$("${git[@]}" rev-parse HEAD)" ]; then
    echo "$version"
  elif "${git[@]}" merge-base --is-ancestor "$tagged" HEAD; then
    count=$("${git[@]}" rev-list --count "v$version..HEAD")
    if [ "$FORM" = deb ]; then echo "$version+$count.git$short"; else echo "$version^$count.git$short"; fi
  else
    echo "HEAD does not contain the tag v$version" >&2
    exit 1
  fi
else
  echo "$version~$("${git[@]}" rev-list --count HEAD).git$short"
fi
