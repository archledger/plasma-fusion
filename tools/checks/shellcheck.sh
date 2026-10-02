#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# ShellCheck over the repository's shell scripts (the tracked *.sh files and the files without a
# suffix that start with a sh or bash #! line), at severity warning, following sourced files (-x).
# Run from the top directory; the style workflow runs it on every pull request and push to main.
# docs/parts/ci.md, "Coding style", says what it checks.
#
#   tools/checks/shellcheck.sh [--list]     --list: print the scripts instead of checking them
set -euo pipefail
cd "$(dirname "$0")/../.."

scripts=()
while IFS= read -r -d '' file; do
  case ${file##*/} in
    *.sh) ;;
    *.*) continue ;;
    *) head -n 1 -- "$file" | grep -qE '^#!.*\b(ba)?sh\b' || continue ;;
  esac
  scripts+=("$file")
done < <(git ls-files -z)

if [ "${1:-}" = --list ]; then
  printf '%s\n' "${scripts[@]}"
  exit 0
fi
shellcheck --version | sed -n 's/^version: /shellcheck /p'
echo "${#scripts[@]} scripts"
shellcheck -x -S warning "${scripts[@]}"
