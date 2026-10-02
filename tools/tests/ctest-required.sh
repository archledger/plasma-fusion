#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Fails unless a compiled part's CMake build directory has the tests (ctest) the part is meant to
# run. The parts leave a test out when something it needs is missing (dbus-run-session, the colour
# schemes of the repository); ctest would then still pass, with ECM's appstream test alone. Run by
# tools/sanitizers/run.sh and .github/workflows/compiled.yml after the build.
#
#   ctest-required.sh PART_DIR BUILD_DIR
set -euo pipefail
part=${1:?usage: ctest-required.sh PART_DIR BUILD_DIR}
build=${2:?usage: ctest-required.sh PART_DIR BUILD_DIR}

case $(basename "$part") in
  decoration-cpp) required=(pfdeco-preview-dark pfdeco-preview-light pfdeco-fuzz) ;;
  kcm-cpp) required=(kcmctl-load) ;;
  # The navigation effect has no tests of its own yet.
  *) required=() ;;
esac

listed=$(ctest --test-dir "$build" -N)
missing=()
for test in "${required[@]}"; do
  if ! grep -qE "^ *Test +#[0-9]+: ${test}\$" <<<"$listed"; then
    missing+=("$test")
  fi
done
if [ "${#missing[@]}" -gt 0 ]; then
  echo "$listed"
  echo "missing tests in $build: ${missing[*]} (is dbus-run-session installed?)" >&2
  exit 1
fi
echo "required tests registered: ${required[*]:-none for $(basename "$part")}"
