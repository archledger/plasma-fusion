#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Builds one compiled part with AddressSanitizer and UndefinedBehaviorSanitizer and runs its tests
# (ctest) so that a memory error, a leak or undefined behaviour fails. Used by
# .github/workflows/sanitizers.yml. Locally, in a Fedora 44 container with the part's build
# requirements (dnf builddep packages/PART/*.spec) and libasan libubsan dbus-daemon binutils:
#
#   tools/sanitizers/run.sh packages/decoration-cpp BUILD_DIR
#
# The flags go in through CXXFLAGS and LDFLAGS, which the CMake build extends with its own flags;
# a check after the build makes sure every plugin and program carries the sanitizer runtime.
set -euo pipefail
src=${1:?usage: run.sh PART_DIR BUILD_DIR}
build=${2:?usage: run.sh PART_DIR BUILD_DIR}
here=$(cd "$(dirname "$0")" && pwd)

export CXXFLAGS="${CXXFLAGS:-} -fsanitize=address,undefined -fno-omit-frame-pointer -g -O1"
export LDFLAGS="${LDFLAGS:-} -fsanitize=address,undefined"
cmake -S "$src" -B "$build" -G Ninja -DCMAKE_BUILD_TYPE=None -DBUILD_TESTING=ON
cmake --build "$build"

# Every ELF plugin and program of the build (not CMake's own probes) must link the runtime.
count=0
while IFS= read -r -d '' f; do
  readelf -h "$f" >/dev/null 2>&1 || continue
  if ! readelf -d "$f" | grep -q 'NEEDED.*libasan'; then
    echo "not built with the sanitizers: $f" >&2
    exit 1
  fi
  echo "instrumented: ${f#"$build"/}"
  count=$((count + 1))
done < <(find "$build" -name CMakeFiles -prune -o -type f \( -name '*.so' -o -perm -u+x \) -print0)
if [ "$count" -eq 0 ]; then
  echo "no plugin or program found in $build" >&2
  exit 1
fi

export QT_QPA_PLATFORM=offscreen
# Stop at the first error of either sanitizer; LeakSanitizer runs at exit.
export ASAN_OPTIONS=halt_on_error=1:abort_on_error=1:detect_leaks=1:detect_stack_use_after_return=1:check_initialization_order=1:strict_init_order=1
export UBSAN_OPTIONS=halt_on_error=1:print_stacktrace=1
export LSAN_OPTIONS=suppressions=$here/lsan.supp:print_suppressions=0
tests=$(ctest --test-dir "$build" -N | sed -n 's/^Total Tests: //p')
echo "ctest: ${tests:-0} tests"
ctest --test-dir "$build" --output-on-failure --no-tests=ignore
