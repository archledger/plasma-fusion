#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Checks a build made by tools/sanitizers/run.sh: every plugin and program of it (not CMake's own
# probes) must link the AddressSanitizer runtime. Prints each one that does and exits non-zero at
# the first that does not, or when there is none, so that a build that dropped the flags fails here
# instead of passing untested.
#
#   instrumented.sh BUILD_DIR
set -euo pipefail
build=${1:?usage: instrumented.sh BUILD_DIR}

count=0
while IFS= read -r -d '' f; do
  readelf -h "$f" >/dev/null 2>&1 || continue
  # readelf's output is collected before it is searched, not piped into a grep that stops at the
  # first match: with a dynamic section longer than one write (the notification applet's plugin has
  # 36 entries) such a reader closes the pipe while readelf is still writing, readelf dies of a
  # broken pipe, and pipefail reports a built plugin as not built.
  dynamic=$(readelf -d "$f") || dynamic=
  case $dynamic in
    *NEEDED*libasan*) ;;
    *)
      echo "not built with the sanitizers: $f" >&2
      exit 1
      ;;
  esac
  echo "instrumented: ${f#"$build"/}"
  count=$((count + 1))
done < <(find "$build" -name CMakeFiles -prune -o -type f \( -name '*.so' -o -perm -u+x \) -print0)
if [ "$count" -eq 0 ]; then
  echo "no plugin or program found in $build" >&2
  exit 1
fi
