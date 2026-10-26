# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# A Plasma test image with the optional KWin backport (packaging/patches/kwin): the BASE test image
# (tools/container/test) with the rebuilt counterparts of its installed KWin subpackages, installed
# with the command packaging/patches/kwin/README.md documents. Local or CI only: the image and the
# packages are never published. Build context: a directory holding the output of
# packaging/patches/kwin/build.sh (the RPMs and SHA256SUMS) as rpms/ (tools/tests/kwin-backport/run.sh
# assembles it).
ARG BASE=localhost/plasma-fusion-test:f44-6.7.5
FROM ${BASE}
COPY rpms /pf-backport/
RUN cd /pf-backport && sha256sum -c SHA256SUMS \
 && dnf -y install $(for f in *.rpm; do case $f in *.src.rpm) continue ;; esac; \
      rpm -q "$(rpm -qp --qf '%{NAME}' "$f")" >/dev/null && echo "./$f"; done) \
 && dnf clean all && cd / && rm -rf /pf-backport \
 && rpm -q kwin kwin-common kwin-libs && rpm -V kwin kwin-common kwin-libs
