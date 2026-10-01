#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Build and install Plasma Fusion's compiled parts against the image's Plasma (inside the image build).
set -euo pipefail
mkdir -p /tmp/pf && cd /tmp/pf
for part in decoration-cpp kcm-cpp navigation-cpp; do
  cmake -S "/pf-src/packages/$part" -B "/tmp/pf/$part" -G Ninja -DCMAKE_BUILD_TYPE=RelWithDebInfo -DCMAKE_INSTALL_PREFIX=/usr -DBUILD_TESTING=OFF >/dev/null
  ninja -C "/tmp/pf/$part" >/dev/null
  ninja -C "/tmp/pf/$part" install >/dev/null
  echo "installed $part"
done
rm -rf /tmp/pf /pf-src
