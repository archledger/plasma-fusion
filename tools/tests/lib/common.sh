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
run_remote() {
  local log=$1 name=$2; shift 2
  "$@" >"$log" 2>&1 && return 0
  grep -qx 'kwin.log' "$log" && return 1  # the session ran (vsession.sh lists out/ at its end)
  grep -qiE 'banner exchange|timed out|connection (refused|reset|closed)|kex_exchange_identification|no route to host|could not resolve|broken pipe' "$log" || return 1
  session_in_use "$name" && return 1
  echo "   ssh connection failed before the session started; retrying once (first log: $log.1)"
  mv -f "$log" "$log.1"
  sleep 10
  "$@" >"$log" 2>&1
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
