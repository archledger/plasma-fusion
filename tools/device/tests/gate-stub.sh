#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The login check's env stub, sourced the way startplasma sources ~/.config/plasma-workspace/env/*.sh
# (plasma-workspace 6.7.5 startplasma.cpp sourceFiles: `/bin/sh plasma-sourceenv.sh FILES...`, each
# file `. $i >/dev/null`, then `env -0`, which startplasma imports). Test tooling only; runs on the
# test device against a throw-away HOME, never the logged-in session.
#
#   gate-stub.sh BASE
set -u
BASE=${1:?scratch directory}
# The cases change directory, so a relative BASE is made absolute first.
BASE=$(realpath -m -- "$BASE")
HERE=$(cd "$(dirname "$0")" && pwd)
DEVICE=$HERE/..
SOURCEENV=/usr/libexec/plasma-sourceenv.sh
case $BASE in /tmp/* | /tmp) echo "use a directory on disk, not /tmp" >&2; exit 2 ;; esac
[ -r "$SOURCEENV" ] || { echo "no $SOURCEENV (run this on the test device)" >&2; exit 2; }
rm -rf "${BASE:?}"
mkdir -p "$BASE/run" "$BASE/home" && chmod 700 "$BASE/run"
H=$BASE/home

PASS=0 FAIL=0
check() { local d=$1; shift; if "$@"; then PASS=$((PASS + 1)); echo "PASS $d"; else FAIL=$((FAIL + 1)); echo "FAIL $d"; fi; }

# The stub exactly as fusion-config.sh writes it, for an engine path.
eval "$(sed -n '/^sh_quote() /p' "$DEVICE/fusion-config.sh")"
eval "$(sed -n '/^gate_stub() {/,/^}/p' "$DEVICE/fusion-config.sh")"
make_stub() { # ENGINE OUT
  GATE_ENGINE=$1 # read by gate_stub (from fusion-config.sh)
  export GATE_ENGINE
  gate_stub >"$2"
}
mkdir -p "$H/.local/share/plasma-fusion/gate" "$H/.config/plasma-workspace/env"
cp "$DEVICE/gate/plasma-fusion-gate.sh" "$H/.local/share/plasma-fusion/gate/"
STUB=$H/.config/plasma-workspace/env/plasma-fusion-gate.sh
make_stub "$H/.local/share/plasma-fusion/gate/plasma-fusion-gate.sh" "$STUB"
echo "== stub:"; cat "$STUB"
check "stub passes sh -n" sh -n "$STUB"

mapfile -t SYSTEM < <(ls /etc/xdg/plasma-workspace/env/*.sh 2>/dev/null)
login_env() { # FILES...: run like startplasma; prints the captured environment, one per line
  env -i HOME="$H" USER="$(id -un)" PATH=/usr/local/bin:/usr/bin:/bin XDG_RUNTIME_DIR="$BASE/run" \
    LANG=C.UTF-8 XDG_SESSION_TYPE=wayland /bin/sh "$SOURCEENV" "$@" | tr '\0' '\n' | LC_ALL=C sort
  return "${PIPESTATUS[0]}"
}

without=$(login_env "${SYSTEM[@]}")
t=${EPOCHREALTIME/[.,]/}
with=$(login_env "${SYSTEM[@]}" "$STUB")
rc=$?
ms=$(((${EPOCHREALTIME/[.,]/} - t) / 1000))
check "sourced after the system scripts: /bin/sh exits 0" [ "$rc" = 0 ]
check "the captured environment is unchanged by the stub" [ "$with" = "$without" ]
[ "$with" = "$without" ] || diff <(echo "$without") <(echo "$with")
check "earlier scripts' variables still captured (XDG_CONFIG_DIRS, GDK_CORE_DEVICE_EVENTS)" \
  bash -c 'grep -q "^XDG_CONFIG_DIRS=" <<<"$1" && grep -q "^GDK_CORE_DEVICE_EVENTS=1" <<<"$1"' _ "$with"
check "the check ran and logged" grep -q " login: " "$H/.local/state/plasma-fusion/gate.log"
echo "sourcing all env scripts with the stub: $ms ms"
for _ in 1 2 3 4 5 6 7 8 9 10 11; do
  t=${EPOCHREALTIME/[.,]/}; login_env "${SYSTEM[@]}" "$STUB" >/dev/null; a+=($(((${EPOCHREALTIME/[.,]/} - t) / 1000)))
  t=${EPOCHREALTIME/[.,]/}; login_env "${SYSTEM[@]}" >/dev/null; b+=($(((${EPOCHREALTIME/[.,]/} - t) / 1000)))
done
mapfile -t a < <(printf '%s\n' "${a[@]}" | sort -n)
mapfile -t b < <(printf '%s\n' "${b[@]}" | sort -n)
echo "median over 11 interleaved runs: with stub ${a[5]} ms, without ${b[5]} ms (cost ~$((a[5] - b[5])) ms; no Fusion parts on, so no version check)"
grep -o '([0-9]* ms)' "$H/.local/state/plasma-fusion/gate.log" | tail -1 | sed 's/^/engine-internal time of the last run: /'

# A hanging check: bounded by the stub's timeout (4 s, kill after 1 s more).
printf '#!/bin/bash\nsleep 60\n' >"$BASE/hang.sh"
make_stub "$BASE/hang.sh" "$BASE/stub-hang.sh"
t=${EPOCHREALTIME/[.,]/}
out=$(login_env "${SYSTEM[@]}" "$BASE/stub-hang.sh")
rc=$?
ms=$(((${EPOCHREALTIME/[.,]/} - t) / 1000))
check "hanging check: /bin/sh exits 0 ($rc)" [ "$rc" = 0 ]
check "hanging check: login delayed at most 5.5 s ($ms ms)" [ "$ms" -lt 5500 ]
check "hanging check: environment still captured" [ "$out" = "$without" ]
sleep 1
left=0
for p in /proc/[0-9]*; do grep -qz "^XDG_RUNTIME_DIR=$BASE/run\$" "$p/environ" 2>/dev/null && left=$((left + 1)); done
check "hanging check: no process of the test login left ($left)" [ "$left" = 0 ]

# A failing, noisy check that even tries to leave the shell and change variables.
printf '#!/bin/bash\necho noise; echo noise >&2; export LEAK=1; exit 7\n' >"$BASE/fail.sh"
make_stub "$BASE/fail.sh" "$BASE/stub-fail.sh"
out=$(login_env "${SYSTEM[@]}" "$BASE/stub-fail.sh")
check "failing check: /bin/sh exits 0" [ $? = 0 ]
check "failing check: environment unchanged" [ "$out" = "$without" ]

# An env script sourced just before it left `set -e` on: the stub still never ends the shell.
printf 'set -e\n' >"$BASE/00-set-e.sh"
out=$(login_env "${SYSTEM[@]}" "$BASE/00-set-e.sh" "$BASE/stub-fail.sh")
check "set -e from an earlier script: environment still captured" bash -c 'grep -q "^GDK_CORE_DEVICE_EVENTS=1" <<<"$1"' _ "$out"
# Engine missing (package removed without fusion-restore.sh).
make_stub "$BASE/missing.sh" "$BASE/stub-missing.sh"
out=$(login_env "${SYSTEM[@]}" "$BASE/00-set-e.sh" "$BASE/stub-missing.sh")
check "missing engine under set -e: environment still captured" bash -c 'grep -q "^GDK_CORE_DEVICE_EVENTS=1" <<<"$1"' _ "$out"

echo "== $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
