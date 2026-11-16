#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Stamp scripts/install.sh for a release (docs/RELEASING.md): the version, the tested Plasma series
# (packaging/tested-plasma.txt), the Fedora releases Copr builds, the Ubuntu series the PPA builds
# and the .deb targets the release carries. An unstamped installer refuses to run. --full-fedora,
# optional, stamps the Fedora releases the full profile builds (ADR 0001); empty (the default while
# the full Copr project is not live) makes the installer refuse --full. --full-pin, optional,
# stamps the full profile's pinned KWin EVR: the spec's %global kwin_full_pin unless given (empty
# when the spec has none), and --full's plan names that version against the stock KWin (#198).
# --full-repo, optional, stamps the full profile's Copr project (OWNER/NAME, default
# archledger/plasma-fusion-full); the release tests name a candidate's own project, so the live one
# never carries a candidate.
#
#   packaging/stamp-installer.sh --copr "44 45" --ppa "stonking" --deb "neon testing" [--full-fedora "44"]
#     [--full-pin 6.8.2-3.fc44.pf5] [--full-repo OWNER/NAME] OUTPUT
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
# The pin is the spec's, read as packaging/release-assets.sh reads it (empty when it has none).
COPR='' PPA='' DEB='' FULLF='' FULLREPO=archledger/plasma-fusion-full OUT=''
FULLPIN=$(sed -n 's/^%global kwin_full_pin *//p' "$ROOT/packaging/fedora/plasma-fusion.spec" | tr -d '[:space:]')
while [ $# -gt 0 ]; do
  case $1 in
    --copr) COPR=$2; shift ;;
    --ppa) PPA=$2; shift ;;
    --deb) DEB=$2; shift ;;
    --full-fedora) FULLF=$2; shift ;;
    --full-pin) FULLPIN=$2; shift ;;
    --full-repo) FULLREPO=$2; shift ;;
    -h|--help) sed -n '5,17p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
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
[[ $FULLF =~ ^[a-z0-9.\ ]*$ ]] || { echo "invalid list: '$FULLF'" >&2; exit 2; }
# A version-release EVR (6.8.2-3.fc44.pf5), or nothing. Nothing else goes into the installer, where
# it is echoed in the plan and compared as an upstream version.
[[ $FULLPIN =~ ^([0-9][0-9A-Za-z.+~_]*-[0-9A-Za-z.+~_]+)?$ ]] || { echo "invalid pin: '$FULLPIN'" >&2; exit 2; }
[[ $FULLREPO =~ ^[a-z0-9._-]+/[a-z0-9._-]+$ ]] || { echo "invalid Copr project (OWNER/NAME): '$FULLREPO'" >&2; exit 2; }
sed -e "s|^PF_VERSION='@PF_VERSION@'\$|PF_VERSION='$version'|" \
    -e "s|^PF_PLASMA_SERIES='@PF_PLASMA_SERIES@'\$|PF_PLASMA_SERIES='$series'|" \
    -e "s|^PF_COPR_FEDORA='@PF_COPR_FEDORA@'\$|PF_COPR_FEDORA='$COPR'|" \
    -e "s|^PF_PPA_SERIES='@PF_PPA_SERIES@'\$|PF_PPA_SERIES='$PPA'|" \
    -e "s|^PF_DEB_TARGETS='@PF_DEB_TARGETS@'\$|PF_DEB_TARGETS='$DEB'|" \
    -e "s|^PF_FULL_FEDORA='@PF_FULL_FEDORA@'\$|PF_FULL_FEDORA='$FULLF'|" \
    -e "s|^PF_FULL_REPO='@PF_FULL_REPO@'\$|PF_FULL_REPO='$FULLREPO'|" \
    -e "s|^PF_FULL_PIN='@PF_FULL_PIN@'\$|PF_FULL_PIN='$FULLPIN'|" \
    "$ROOT/scripts/install.sh" >"$OUT"
if grep -q "^PF_[A-Z_]*='@" "$OUT"; then echo "not every value was stamped" >&2; exit 1; fi
chmod 0755 "$OUT"
echo "$OUT: Plasma Fusion $version, Plasma $series, Copr: $COPR, PPA: $PPA, .deb: $DEB${FULLF:+, full profile: Fedora $FULLF ($FULLREPO${FULLPIN:+, pin $FULLPIN})}"
