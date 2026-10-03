#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Release candidate: every channel's packages from one commit, each built, installed and checked in a
# container of its system (tools/tests/packages/), one after another, into $PF_REL/rc (status in
# $PF_REL/rc/status). The VM tests (run-all.sh) serve them through channels.sh.
#
#   tools/tests/release-vm/build-all.sh [COMMIT]     (default HEAD of this repository)
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
REPO=$(cd "$HERE/../../.." && pwd)
R=${PF_REL:-$HOME/pf-rel}
rm -rf "$R/src" "$R/rc" && git clone -q "$REPO" "$R/src" && git -C "$R/src" checkout -q "${1:-HEAD}" && mkdir -p "$R/rc"
cd "$R/src" || exit 1
UP=$(packaging/version.sh --deb)
echo "commit $(git rev-parse --short HEAD) version $(packaging/version.sh) deb $UP" >"$R/rc/status"
packaging/make-source.sh --top plasma-fusion --output "$R/rc/src-arch" >/dev/null
packaging/make-source.sh --output "$R/rc/src" >/dev/null
tarball=$R/rc/src/plasma-fusion-$(cat VERSION).tar.gz
run() { # NAME IMAGE CMD...
  local name=$1 image=$2
  shift 2
  nice -n 10 podman run --rm --cpus "${PF_CPUS:-8}" --user root -v "$R:$R:rw,z" -w "$R/src" "$image" "$@" >"$R/rc/$name.log" 2>&1
  echo "$name rc=$?" >>"$R/rc/status"
}
run fedora registry.fedoraproject.org/fedora:44 bash -c "dnf install -y -q git >/dev/null && tools/tests/packages/fedora.sh $R/rc/fedora"
run arch docker.io/library/archlinux:latest bash tools/tests/packages/arch.sh "$R/rc/src-arch/plasma-fusion-$(cat VERSION).tar.gz" "$R/rc/arch"
run debian-testing docker.io/library/debian:testing bash tools/tests/packages/deb.sh debian:testing "$tarball" "$R/rc/debian-testing" "$UP"
run ubuntu-stonking docker.io/library/ubuntu:26.10 bash tools/tests/packages/deb.sh ubuntu:stonking "$tarball" "$R/rc/ubuntu-stonking" "$UP"
run neon invent-registry.kde.org/neon/docker-images/plasma:user bash tools/tests/packages/deb.sh neon "$tarball" "$R/rc/neon" "$UP"
run plain docker.io/library/debian:testing bash tools/tests/packages/deb.sh plain "$tarball" "$R/rc/plain" "$UP"
echo DONE >>"$R/rc/status"
cat "$R/rc/status"
