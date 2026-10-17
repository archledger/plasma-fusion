#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The flow test's stand-in for plasma-fusion-copytext, installed next to the test program where the
# overlay looks for its helper: each run appends its arguments and PLASMA_FUSION_COPYTEXT_NO_OVERLAY
# to $FLOW_OUT/runs, after keeping a copy of the picture it was given (--image FILE) as
# $FLOW_OUT/region.png and the mode of its directory as $FLOW_OUT/mode.
set -euo pipefail
: "${FLOW_OUT:?}"
if [ "${1:-}" = --image ]; then
  cp -- "$2" "$FLOW_OUT/region.png"
  stat -c %a -- "$(dirname -- "$2")" >"$FLOW_OUT/mode"
fi
printf '%s|%s\n' "$*" "${PLASMA_FUSION_COPYTEXT_NO_OVERLAY:-}" >>"$FLOW_OUT/runs"
