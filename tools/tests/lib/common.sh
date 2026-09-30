# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Laptop-side helpers shared by the test drivers in tools/tests (sourced).
# shellcheck shell=bash

HOST=${PFV_HOST:-thinkpad-fedora}
# Wi-Fi host: bounded connection time for every call (also passed on to remote.sh).
export PFV_SSH_OPTS=${PFV_SSH_OPTS:--o ConnectTimeout=40}

# hssh CMD: ssh to the test host; one retry when the connection itself fails (exit 255).
hssh() {
  local rc
  # shellcheck disable=SC2086  # PFV_SSH_OPTS is a list of options
  ssh -o BatchMode=yes $PFV_SSH_OPTS "$HOST" "$@"; rc=$?
  if [ "$rc" = 255 ]; then
    sleep 5
    # shellcheck disable=SC2086
    ssh -o BatchMode=yes $PFV_SSH_OPTS "$HOST" "$@"; rc=$?
  fi
  return "$rc"
}

# make_seed STAGE TOOLS SEED: a session HOME seed with the built HOME tree at ~/pf-stage and the
# tools tree at ~/pf-tools.
make_seed() {
  mkdir -p "$3/pf-stage" "$3/pf-tools" || return 1
  rsync -a --delete "$1"/ "$3/pf-stage/" && rsync -a --delete --exclude __pycache__ "$2"/ "$3/pf-tools/"
}

# host_state: virtual sessions with live processes (a kept HOME without processes does not count)
# and the load, for the record next to every result.
host_state() {
  hssh 'echo "time=$(date -Is) load=$(cut -d" " -f1-3 /proc/loadavg) sessions=$(python3 -c "
import os
s = set()
for p in os.listdir(\"/proc\"):
    try:
        env = open(\"/proc/%s/environ\" % p, \"rb\").read().split(b\"\\0\")
    except OSError:
        continue
    s.update(e[16:].decode().split(\"/\")[3] for e in env if e.startswith(b\"XDG_RUNTIME_DIR=/var/tmp/pfv-\"))
print(\" \".join(sorted(s)))
")"'
}

# session_in_use NAME...: true when a process on the host runs in /var/tmp/pfv-NAME for one of the
# names (another agent's session with the same name, or an earlier run of this test that is still
# going). The drivers refuse to start then: they would share, and finally delete, its directory.
# An unreachable host counts as in use.
session_in_use() {
  local s n
  s=$(host_state) || return 0
  s=" ${s##*sessions=} "
  for n in "$@"; do
    case "$s" in *" pfv-$n "*) return 0 ;; esac
  done
  return 1
}

# host_cleanup NAME...: stop the processes of the named sessions (matched by their runtime dir in
# /proc/PID/environ, never by process name; KWin exits with its session) and remove their
# directories and copied scripts on the host.
host_cleanup() {
  local n
  for n in "$@"; do
    [[ "$n" =~ ^[A-Za-z0-9][A-Za-z0-9._-]*$ ]] || continue
    hssh "for p in /proc/[0-9]*; do grep -qz '^XDG_RUNTIME_DIR=/var/tmp/pfv-$n/run\$' \$p/environ 2>/dev/null && kill -9 \${p#/proc/} 2>/dev/null; done; rm -rf /var/tmp/pfv-$n /var/tmp/pfv-$n.vsession.sh /var/tmp/pfv-$n.scenario.sh /var/tmp/pfv-$n.pfinput.py"
  done
}

# run_remote LOG NAME CMD...: run a remote.sh command line with output in LOG; when it failed
# before the session started because the ssh connection failed (Wi-Fi banner timeouts) and no
# process of session NAME runs on the host, wait 10 s and run it once more (first log kept as LOG.1).
# When remote.sh refused because the host user's inotify use is high (exit 75), wait
# PFV_BUSY_WAIT seconds (default 120) and try again, at most PFV_BUSY_TRIES times (default 3);
# the slot is not held while waiting (the slot wrapper is part of CMD).
run_remote() {
  local log=$1 name=$2 rc busy=0; shift 2
  while :; do
    "$@" >"$log" 2>&1 && return 0
    rc=$?
    grep -qx 'kwin.log' "$log" && return 1  # the session ran (vsession.sh lists out/ at its end)
    if [ "$rc" = 75 ] && grep -q 'inotify' "$log" && [ "$busy" -lt "${PFV_BUSY_TRIES:-3}" ]; then
      busy=$((busy + 1))
      echo "   host busy ($(grep -m1 inotify "$log" | sed 's/^remote.sh: //')); waiting ${PFV_BUSY_WAIT:-120} s ($busy)"
      mv -f "$log" "$log.busy$busy"
      sleep "${PFV_BUSY_WAIT:-120}"
      continue
    fi
    break
  done
  grep -qiE 'banner exchange|timed out|connection (refused|reset|closed)|kex_exchange_identification|no route to host|could not resolve|broken pipe' "$log" || return 1
  session_in_use "$name" && return 1
  echo "   ssh connection failed before the session started; retrying once (first log: $log.1)"
  mv -f "$log" "$log.1"
  sleep 10
  "$@" >"$log" 2>&1
}

# Session slots. Every private session, performance measurement and container build that runs
# on the test host from this laptop holds the lead's slot lock, build/lead/vslot.sh: N session
# slots (N in build/locks/slots, changed by the lead at any time), --exclusive takes all of them
# (a quiet host for measurements), --build the single container-build lock. The drivers in
# tools/tests wrap each remote.sh call themselves:
#
#   slot_prefix one|exclusive|build || exit 2
#   run_remote LOG NAME "${SLOT[@]}" env ... bash tools/vsession/remote.sh NAME ...
#
# "exclusive" here also takes the build lock, so no container build runs during a measurement.
# A driver started under vslot.sh inherits the lock's open descriptor (flock locks belong to the
# open file, which the child shares); it then runs its sessions in that slot instead of taking a
# second one, which with every slot busy would wait for itself. Asking for "exclusive" while
# holding a single slot is refused for the same reason. Without vslot.sh (PFV_VSLOT, else
# build/lead/vslot.sh in this checkout or one of its parents, which finds it from a snapshot in
# build/<prefix>/snap too) the drivers run unlocked with a note. PFV_VSLOT=none turns it off.

# pf_vslot: path of vslot.sh, or failure.
pf_vslot() {
  local d
  case "${PFV_VSLOT:-}" in none) return 1 ;; '') ;; *) echo "$PFV_VSLOT"; return 0 ;; esac
  d=$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P) || return 1
  while [ "$d" != / ]; do
    [ -x "$d/build/lead/vslot.sh" ] && { echo "$d/build/lead/vslot.sh"; return 0; }
    d=$(dirname "$d")
  done
  return 1
}

# pf_locks_held LOCKDIR: HELD_SLOTS (session slots) and HELD_BUILD (0/1) this shell inherited.
pf_locks_held() {
  local fd t
  HELD_SLOTS=0; HELD_BUILD=0
  for fd in /proc/$$/fd/*; do
    t=$(readlink "$fd" 2>/dev/null) || continue
    case "$t" in
      "$1"/slot[0-9]*) HELD_SLOTS=$((HELD_SLOTS + 1)) ;;
      "$1"/build.lock) HELD_BUILD=1 ;;
    esac
  done
}

# slot_prefix MODE: SLOT=(the vslot.sh command line to put in front of a remote.sh call) for MODE
# one, exclusive or build; SLOT=() when this driver already holds what MODE needs or runs without
# vslot.sh. Returns 1 (with a message) when MODE cannot be taken from here.
slot_prefix() {
  local v d n
  SLOT=()
  v=$(pf_vslot) || {
    [ "${PFV_VSLOT:-}" = none ] || echo "note: no build/lead/vslot.sh found (set PFV_VSLOT); running without the session-slot lock" >&2
    return 0
  }
  d=$(cd "$(dirname "$v")/../locks" 2>/dev/null && pwd -P) || { echo "slot_prefix: no lock directory next to $v" >&2; return 1; }
  n=$(cat "$d/slots" 2>/dev/null || echo 3)
  pf_locks_held "$d"
  case "$1" in
    one) [ "$HELD_SLOTS" -gt 0 ] || SLOT=("$v") ;;
    build) [ "$HELD_BUILD" = 1 ] || SLOT=("$v" --build) ;;
    exclusive)
      if [ "$HELD_SLOTS" -gt 0 ] && [ "$HELD_SLOTS" -lt "$n" ]; then
        echo "this driver holds $HELD_SLOTS of $n session slots but measures on a quiet host: start it under 'vslot.sh --exclusive' or without vslot.sh" >&2
        return 1
      fi
      [ "$HELD_BUILD" = 1 ] || SLOT=("$v" --build)
      [ "$HELD_SLOTS" -ge "$n" ] || SLOT+=("$v" --exclusive) ;;
    *) echo "slot_prefix: unknown mode $1" >&2; return 1 ;;
  esac
  return 0
}

# slot_note: one line for the results: which lock the sessions ran under.
slot_note() {
  local v
  if [ ${#SLOT[@]} -gt 0 ]; then echo "slot lock: ${SLOT[*]}"
  elif v=$(pf_vslot); then echo "slot lock: inherited from the caller (${HELD_SLOTS:-0} session slots, build lock ${HELD_BUILD:-0})"
  else echo "slot lock: none (no vslot.sh)"; fi
}

# host_packages: versions of what the measured sessions run besides the stage (Plasma, KWin, Qt and
# the system-wide Plasma Fusion packages, which a stage overrides per package), one per line.
host_packages() {
  hssh 'rpm -q plasma-workspace kwin libplasma qt6-qtbase qt6-qtdeclarative mesa-dri-drivers kernel-core \
    plasma-fusion plasma-fusion-decoration plasma-fusion-settings 2>/dev/null | sort; uname -r'
}

# host_coredumps SINCE_EPOCH RUNDIR: JSON list of core dumps since SINCE_EPOCH whose environment
# names RUNDIR as XDG_RUNTIME_DIR (the test's own sessions).
host_coredumps() {
  hssh "journalctl -o json MESSAGE_ID=fc2e22bc6ee647b6b90729ab34a250b1 --since @$1 --no-pager 2>/dev/null" | python3 -c '
import json, sys
run = "XDG_RUNTIME_DIR=" + sys.argv[1]
out = []
for line in sys.stdin:
    try:
        e = json.loads(line)
    except ValueError:
        continue
    env = e.get("COREDUMP_ENVIRON") or ""
    if isinstance(env, list):
        env = bytes(env).decode("utf-8", "replace")
    if run in env.split("\n"):
        out.append({"exe": e.get("COREDUMP_EXE"), "pid": e.get("COREDUMP_PID"), "signal": e.get("COREDUMP_SIGNAL_NAME"),
                    "time": int(e.get("__REALTIME_TIMESTAMP", "0")) / 1e6})
print(json.dumps(out))' "$2"
}
