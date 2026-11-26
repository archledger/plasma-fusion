#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit test of the sanitizer build's instrumented check (tools/sanitizers/instrumented.sh) with a
# stand-in readelf: no compiler and no sanitizer build. The stand-in reads a "build" of small text
# files as ELF files and prints their lines as a dynamic section, waiting a moment where a real
# readelf would still be working between two writes of a long section. Checked: programs and
# plugins that link the runtime are instrumented, also with a dynamic section longer than one
# write (the regression: a reader that stopped at the first match closed the pipe while readelf
# was still writing, and pipefail then reported a built plugin as not built); one that does not
# link the runtime stops the check; CMake's own probes and files that are not ELF are left alone;
# a build with nothing to check fails; no argument is a usage error.
#
#   tools/tests/sanitizers/instrumented-unit.sh
set -euo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
CHECK=$HERE/../../sanitizers/instrumented.sh
WORK=$(mktemp -d)
trap 'rm -rf "$WORK"' EXIT

mkdir -p "$WORK/bin"
# Stand-in for readelf. A file whose first line is "elf" is an ELF file and its other lines are what
# -d prints; a line "pause" is where readelf would still be working between two writes. -h succeeds
# for an ELF file and fails for any other file. cat writes the lines, as readelf writes: to a
# reader that has gone away cat dies of a broken pipe, where sed would exit 0.
cat >"$WORK/bin/readelf" <<'EOF'
#!/bin/bash
set -uo pipefail
file=${!#}
kind=other
IFS= read -r kind <"$file" 2>/dev/null || :
[ "$kind" = elf ] || exit 1
[ "${1:-}" = -h ] && exit 0
pause_line=$(grep -n -x pause "$file" | cut -d: -f1)
if [ -n "$pause_line" ]; then
  tail -n +2 "$file" | head -n $((pause_line - 2)) | cat
  sleep "${STANDIN_PAUSE:-0.3}"
  tail -n +$((pause_line + 1)) "$file" | cat
else
  tail -n +2 "$file" | cat
fi
EOF
chmod +x "$WORK/bin/readelf"
export PATH="$WORK/bin:$PATH"

PASS=0 FAIL=0
pass() { PASS=$((PASS + 1)); echo "PASS $1"; }
fail() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
expect() { # DESCRIPTION CONDITION...
  local d=$1; shift
  if "$@"; then pass "$d"; else fail "$d"; fi
}
elf() { # FILE [LINE...]: a plugin or program whose dynamic section is the lines; without lines it links the runtime
  local f=$1; shift
  mkdir -p "$(dirname "$f")"
  { echo elf
    [ $# = 0 ] && echo '  NEEDED   Shared library: [libasan.so.8]'
    [ $# = 0 ] || printf '%s\n' "$@"
    true; } >"$f"
  chmod +x "$f"
}
check() { # BUILD_DIR: leaves RC, OUT (stdout, one line per file) and ERR (stderr)
  RC=0
  OUT=$(bash "$CHECK" "$1" 2>"$WORK/err") || RC=$?
  ERR=$(cat "$WORK/err")
}
listed() { [ "$(printf '%s\n' "$OUT" | sort | tr '\n' ' ')" = "$1" ]; }
exit_saying() { [ "$RC" = "$1" ] && [ "$ERR" = "$2" ]; }
silent() { [ -z "$ERR" ]; }
nothing_listed() { [ -z "$OUT" ]; }

# A dynamic section longer than one write, as the notification applet's plugin has: the runtime is
# named early and the section goes on.
B=$WORK/long
mkdir -p "$B/bin/plasma/applets"
{ echo elf
  echo '  NEEDED   Shared library: [libstdc++.so.6]'
  echo '  NEEDED   Shared library: [libasan.so.8]'
  echo pause
  for i in $(seq 60); do echo "  NEEDED   Shared library: [lib$i.so]"; done
  true; } >"$B/bin/plasma/applets/org.kde.plasma.notifications.so"
elf "$B/bin/program"
check "$B"
expect "a dynamic section longer than one write is read to its end: exit 0" [ "$RC" = 0 ]
expect "  and the plugin and the program are instrumented" listed "instrumented: bin/plasma/applets/org.kde.plasma.notifications.so instrumented: bin/program "
expect "  with nothing on stderr" silent

B=$WORK/plain
mkdir -p "$B/bin"
elf "$B/bin/libhelper.so"
chmod -x "$B/bin/libhelper.so"
elf "$B/bin/tool"
check "$B"
expect "a plugin without the executable bit and a program that link the runtime: exit 0" [ "$RC" = 0 ]
expect "  both instrumented" listed "instrumented: bin/libhelper.so instrumented: bin/tool "

B=$WORK/dropped
mkdir -p "$B/bin"
elf "$B/bin/program"
elf "$B/bin/plugin.so" '  NEEDED   Shared library: [libubsan.so.1]'
check "$B"
expect "a plugin that does not link the runtime stops the check: exit 1, naming it" exit_saying 1 "not built with the sanitizers: $B/bin/plugin.so"

B=$WORK/skipped
mkdir -p "$B/CMakeFiles/6.0.0/CompilerIdCXX" "$B/bin"
elf "$B/CMakeFiles/6.0.0/CompilerIdCXX/a.out" '  NEEDED   Shared library: [libm.so.6]'
printf '#!/bin/bash\necho not a binary\n' >"$B/bin/script"
chmod +x "$B/bin/script"
check "$B"
expect "CMake's own probe and a file that is not ELF are no plugin or program: exit 1, none found" exit_saying 1 "no plugin or program found in $B"
expect "  and nothing is reported instrumented" nothing_listed

mkdir "$WORK/empty"
check "$WORK/empty"
expect "a build directory with nothing in it: exit 1, none found" exit_saying 1 "no plugin or program found in $WORK/empty"

RC=0
OUT=$(bash "$CHECK" 2>"$WORK/err") || RC=$?
ERR=$(cat "$WORK/err")
usage() { [ "$RC" = 1 ] && grep -qF 'usage: instrumented.sh BUILD_DIR' <<<"$ERR"; }
expect "no build directory: exit 1, the usage" usage
expect "  and nothing else" nothing_listed

echo "sanitizers instrumented: $PASS passed, $FAIL failed"
[ "$FAIL" = 0 ]
