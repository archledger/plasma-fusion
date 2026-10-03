#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Test channels from the release-candidate packages (~/pf-rel/rc), served on 127.0.0.1:8088 (the
# VMs reach it as 10.0.2.2:8088): a dnf repository, an apt repository, a release directory signed
# with a throwaway key (never the release key), and the Arch source.
set -euo pipefail
shopt -s nullglob
R=${PF_REL:-$HOME/pf-rel} C=$R/channels
rm -rf "$C" && mkdir -p "$C"/{fedora,ubuntu,release,arch}
for f in "$R"/rc/fedora/RPMS/*/plasma-fusion*.rpm; do [[ $f == *-debug* ]] || cp "$f" "$C/fedora/"; done
[ -z "$(ls "$C/fedora")" ] || createrepo_c -q "$C/fedora"
for f in "$R"/rc/ubuntu-stonking/*.deb; do [[ $f == *dbgsym* ]] || cp "$f" "$C/ubuntu/"; done
[ -z "$(ls "$C/ubuntu")" ] || podman run --rm -v "$C/ubuntu:/c:rw,z" docker.io/library/debian:testing bash -c \
  "apt-get update -qq && apt-get install -y -qq dpkg-dev >/dev/null && cd /c && dpkg-scanpackages -m . >Packages 2>/dev/null && gzip -kf Packages"
for t in neon debian-testing plain; do
  for f in "$R"/rc/$t/*.deb; do [[ $f == *dbgsym* ]] || cp "$f" "$C/release/"; done
done
# Only the shared part of the plain build is a release file.
rm -f "$C"/release/plasma-fusion-{decoration,settings,navigation}_*-1_amd64.deb
export GNUPGHOME=$R/testkey
if [ ! -d "$GNUPGHOME" ]; then
  mkdir -p "$GNUPGHOME" && chmod 700 "$GNUPGHOME"
  gpg --batch --passphrase '' --quick-gen-key 'Plasma Fusion VM test (not a release key) <vmtest@example.invalid>' ed25519 sign never 2>/dev/null
fi
fp=$(gpg --list-keys --with-colons vmtest@example.invalid | awk -F: '/^fpr/ {print $10; exit}')
gpg --armor --export "$fp" >"$C/test-key.asc"
echo "$fp" >"$C/test-key.fp"
debs=("$C"/release/*.deb)
if [ ${#debs[@]} -gt 0 ]; then
  (cd "$C/release" && sha256sum -- ./*.deb | sed 's| \./| |' | LC_ALL=C sort -k2 >SHA256SUMS)
  gpg --batch --yes --armor --local-user "$fp" --detach-sign -o "$C/release/SHA256SUMS.asc" "$C/release/SHA256SUMS"
fi
for f in "$R"/rc/src-arch/plasma-fusion-*.tar.gz; do cp "$f" "$C/arch/"; done
cp "$R/src/packaging/arch/PKGBUILD" "$C/arch/"
# The installer of the branch head (copied in by the laptop), else the candidate's.
if [ -f "$R/install.sh" ]; then cp "$R/install.sh" "$C/install.sh"; else cp "$R/src/scripts/install.sh" "$C/install.sh"; fi
# The server (one for every VM).
if ! curl -fsS -o /dev/null http://127.0.0.1:8088/install.sh 2>/dev/null; then
  nohup python3 -m http.server 8088 --bind 127.0.0.1 --directory "$C" >"$R/http.log" 2>&1 </dev/null &
  sleep 1
fi
find "$C" -maxdepth 2 -type f | sed "s|$C/||" | sort
