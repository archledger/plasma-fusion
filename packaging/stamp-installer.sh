#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Stamp scripts/install.sh for a release (docs/RELEASING.md): the version, the tested Plasma series
# (packaging/tested-plasma.txt), the Fedora releases Copr builds, the Ubuntu series the PPA builds
# and the .deb targets the release carries. An unstamped installer refuses to run.
#
#   packaging/stamp-installer.sh --copr "44 45" --ppa "stonking" --deb "neon testing" OUTPUT
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
COPR='' PPA='' DEB='' OUT=''
while [ $# -gt 0 ]; do
  case $1 in
    --copr) COPR=$2; shift ;;
    --ppa) PPA=$2; shift ;;
    --deb) DEB=$2; shift ;;
    -h|--help) sed -n '5,10p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "unknown option: $1" >&2; exit 2 ;;
    *) OUT=$1 ;;
  esac
  shift
done
[ -n "$OUT" ] || { echo "no output file" >&2; exit 2; }
version=$("$ROOT/packaging/version.sh" --plain)
series=$(grep -v '^[[:space:]]*#' "$ROOT/packaging/tested-plasma.txt" | tr -s '[:space:]' ' ' | sed 's/^ //; s/ $//')
for v in "$COPR" "$PPA" "$DEB" "$series"; do
  [[ $v =~ ^[a-z0-9.\ ]+$ ]] || { echo "invalid list: '$v'" >&2; exit 2; }
done
sed -e "s|^PF_VERSION='@PF_VERSION@'\$|PF_VERSION='$version'|" \
    -e "s|^PF_PLASMA_SERIES='@PF_PLASMA_SERIES@'\$|PF_PLASMA_SERIES='$series'|" \
    -e "s|^PF_COPR_FEDORA='@PF_COPR_FEDORA@'\$|PF_COPR_FEDORA='$COPR'|" \
    -e "s|^PF_PPA_SERIES='@PF_PPA_SERIES@'\$|PF_PPA_SERIES='$PPA'|" \
    -e "s|^PF_DEB_TARGETS='@PF_DEB_TARGETS@'\$|PF_DEB_TARGETS='$DEB'|" \
    "$ROOT/scripts/install.sh" >"$OUT"
if grep -q "^PF_[A-Z_]*='@" "$OUT"; then echo "not every value was stamped" >&2; exit 1; fi
chmod 0755 "$OUT"
echo "$OUT: Plasma Fusion $version, Plasma $series, Copr: $COPR, PPA: $PPA, .deb: $DEB"
