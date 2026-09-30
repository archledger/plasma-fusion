# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# shellcheck shell=bash
#
# Upgrade regression (tools/vsession scenario; test tooling). Seed HOME: scen-ld1.sh (the lead's
# upgrade scenario, copied unchanged), pf-tools-old/ + pf-stage-old/ (the deployed version) and
# pf-tools-new/ + pf-stage-new/ (with the login check). Runs scen-ld1.sh, then checks the login
# check through the same steps.
. "$HOME/scen-ld1.sh"
set +x
GATE_LOG=$HOME/.local/state/plasma-fusion/gate.log
{
  echo "== login check after scen-ld1"
  echo "fc-2 (upgrade) login-check section:"; sed -n '/^Login check/,/^Done/p' "$OUT/fc-2-new.log"
  echo "fc-6 (rerun) changes: $(grep '^Done' "$OUT/fc-6-rerun.log")"
  echo "fc-6 login-check section:"; sed -n '/^Login check/,/^Done/p' "$OUT/fc-6-rerun.log"
  echo "restore --latest kept the check (its backup had the stub): stub=$(ls "$HOME/.config/plasma-workspace/env" 2>/dev/null) engine=$(ls "$HOME/.local/share/plasma-fusion/gate" 2>/dev/null)"
  echo "gate.log:"; cat "$GATE_LOG" 2>/dev/null
  echo "My previous desktop: $(ls "$HOME/.local/share/plasma/look-and-feel/")"
  # Made at the upgrade from the pre-Fusion backup while Plasma Fusion is live (the real device's
  # case): the live ~/.config/kdedefaults must not leak into it.
  echo "fc-2 previous-look section:"; sed -n '/^Previous look/,/^Install/p' "$OUT/fc-2-new.log"
  P=$HOME/.local/share/plasma/look-and-feel/org.plasmafusion.previous.desktop/contents/defaults
  cp "$P" "$OUT/previous-defaults.txt"
  echo "Plasma Fusion values in My previous desktop: $(grep -c -e plasmafusion -e Manrope "$P")"
} >>"$OUT/gate-upgrade.txt" 2>&1
/bin/sh /usr/libexec/plasma-sourceenv.sh "$HOME/.config/plasma-workspace/env/plasma-fusion-gate.sh" >/dev/null
echo "login after restore --latest: $(grep ' login: ' "$GATE_LOG" | tail -n1)" >>"$OUT/gate-upgrade.txt"
