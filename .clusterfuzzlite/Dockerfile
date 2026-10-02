# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# ClusterFuzzLite build image (docs/parts/ci.md, "Fuzzing"): OSS-Fuzz's Python builder (Python 3.11,
# atheris, PyInstaller), pinned by digest (base-builder-python as of 2026-10-02). The fuzzed tools
# use the standard library only, so nothing else is installed.
FROM gcr.io/oss-fuzz-base/base-builder-python@sha256:1de9e4ac301ddea42b8846480d5e4903580ed5071357c9173a4d26a4af65a6fa
COPY . $SRC/plasma-fusion
WORKDIR $SRC/plasma-fusion
COPY .clusterfuzzlite/build.sh $SRC/
