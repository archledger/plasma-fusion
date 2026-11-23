#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Sourced by scenario-bridge.sh in pipeline seeds only, after the first online exchange; the
# caller retains child/cleanup ownership. It fires a burst of wake-ups at the provider and
# changes nothing else.
set -euo pipefail

# The burst is a native session action, so also require a real private container.
[[ ${PFV:-} == /var/tmp/pfv-layout-control-* && ${HOME:-} == "$PFV/home" &&
   ${XDG_RUNTIME_DIR:-} == "$PFV/run" && ${PF_LAYOUT_PRIVATE_CONTAINER:-} == 1 &&
   -f /run/.containerenv ]] || {
  echo "Refusing a non-private pipeline scenario" >&2
  return 64
}

pipeline_helper="$HOME/.local/lib/layout-control/pipeline.py"
pipeline_wakes=24
pipeline_mark() { python3 "$pipeline_helper" mark "$OUT" "$1" >/dev/null; }
# The step's checker replays every pipeline event of the run up to its confirmation.
pipeline_wait() {
  local step=$1
  for _ in {1..100}; do
    if python3 "$pipeline_helper" step "$OUT" "$step" >/dev/null \
      2>>"$OUT/pipeline-$step-wait.log"; then
      return 0
    fi
    sleep 0.1
  done
  echo "FAIL: pipeline $step evidence not confirmed" >&2
  return 1
}

pipeline_mark burst
printf '{"schema": 1, "wakes": %d}\n' "$pipeline_wakes" >"$OUT/pipeline-burst.json"
# The wake-ups are sent concurrently, so that several arrive while a read or publication runs.
# Only these clients are waited for: the sourcing shell also owns the session's processes.
pipeline_pids=()
for ((wake = 0; wake < pipeline_wakes; ++wake)); do
  qdbus org.kde.kglobalaccel /component/kwin org.kde.kglobalaccel.Component.invokeShortcut \
    "Plasma Fusion: Layout Probe Wake" >/dev/null &
  pipeline_pids+=("$!")
done
# wait with several PIDs returns only the last one's status, so wait for each client in turn.
pipeline_failed=0
for pipeline_pid in "${pipeline_pids[@]}"; do
  wait "$pipeline_pid" || pipeline_failed=$((pipeline_failed + 1))
done
((pipeline_failed == 0)) || {
  echo "FAIL: $pipeline_failed of $pipeline_wakes wake-up dispatches failed" >&2
  return 1
}
pipeline_wait settled

# The checker recomputes the settled record from the raw logs before it writes the receipt.
python3 "$pipeline_helper" receipt "$OUT"
echo "PASS: serialized pipeline, coalesced wake-ups and settled consumers"
