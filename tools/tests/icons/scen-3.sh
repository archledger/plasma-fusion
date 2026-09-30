# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Icon-position test, session 3 of 3: the same HOME with two outputs (PFV_OUTPUTS=2), as when the
# laptop is docked. The first output (the one that holds the icons) is disabled and enabled again,
# as when the lid closes and opens; then the second output goes away.
# shellcheck shell=bash
exec 2>&1
# shellcheck source=tools/tests/icons/lib.sh
source "$HOME/pf-tools/tests/icons/lib.sh"
log "session 3: two outputs"
sleep 4
check 09-second-output-at-login
mapfile -t OUTS < <(outputs)
log "outputs: ${OUTS[*]}"
if [ "${#OUTS[@]}" -ge 2 ]; then
  kscreen "output.${OUTS[0]}.disable"
  check 10-first-output-disabled
  kscreen "output.${OUTS[0]}.enable"
  check 11-first-output-enabled
  kscreen "output.${OUTS[1]}.disable"
  check 12-second-output-removed
else
  log "SETUP FAIL: only ${#OUTS[@]} output"
fi
log "session 3 done"
