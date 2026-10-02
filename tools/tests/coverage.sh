#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Statement coverage of the automated tests, per language (docs/parts/coverage.md). Runs on
# Fedora 44 without a desktop session: in a container or in CI (.github/workflows/coverage.yml).
#
#   tools/tests/coverage.sh [--out DIR] [--deps] [scripts] [cpp:PACKAGE ...]
#
#   scripts        Python (coverage.py), shell (kcov) and JavaScript (node) in one pass (default)
#   cpp:PACKAGE    a compiled part (decoration-cpp, kcm-cpp or navigation-cpp): built with gcc
#                  --coverage, its tests run, the lines of its src/ reported by gcovr
#   --out DIR      results (default build/coverage); an earlier result there is replaced, any
#                  other non-empty directory is refused
#   --deps         only install what the chosen parts need with dnf (as root, in a container or
#                  CI): the tools, the plasma-fusion spec's build requirements and, for cpp:PACKAGE,
#                  the part's own (dnf builddep)
#
# "scripts" runs these tests, with coverage.py watching every Python process (COVERAGE_PROCESS_START
# and the .pth file python3-coverage installs) and kcov every bash script they start (its BASH_ENV
# hook):
#   tools/build.sh                      every part with its built-in checks, as the RPM build runs it
#   generators/plymouth/build.sh        the boot splash theme and tests/check_theme.py
#   tools/checks/tests/run.sh           the lints' self-tests
#   tools/device/tests/gate-unit.sh     the login check's unit tests
#   packages/powerfx/tests/offline.sh   the power tiers service against mock D-Bus services
#   tools/device/fieldlog/tests/fieldlog_test.py   the field log against recorded crash records and
#                                       fake journal, coredumpctl and systemctl
#   generators/cursors/tests/test_cursors.py, generators/decoration/tests/check_aurorae.py,
#   generators/plasma-style/tests/validate.py, generators/icons/validate.py
#                                       the offline checks of the generated themes
#   node --test with coverage over the JavaScript unit tests
# Two of them start their subject with `env -i`, which would drop the coverage hooks. A wrapper
# named env, first in PATH, keeps the hooks' variables for `env -i` children and is the real env
# otherwise. Tracing makes bash slower, so the tests' timing checks (login check under 50 ms, the
# power service's response times) can fail here; the build workflow runs the same tests without it.
#
# cpp:PACKAGE configures the part with --coverage (Debug, -O0), builds it, runs ctest and, for the
# decoration, tests/pfdeco-preview offscreen (it loads the built plugin, renders its scenes and
# checks them; exit 1 on a failed check) for the dark and light schemes.
#
# Results: OUT/summary.md and OUT/summary.json (tools/tests/coverage_summary.py: per language and
# area, product code, maintainer tools and test tooling apart, and every test's exit status), the
# tools' own reports in OUT/python/html, OUT/shell/merged (kcov), OUT/js (lcov), OUT/cpp-PACKAGE
# (gcovr), and each test's output in OUT/logs. Exit status 0 when the measurement finished (also
# when a test failed: see the summary), 1 when it did not, 2 for a usage error or a missing tool.
set -uo pipefail
ROOT=$(cd "$(dirname "$0")/../.." && pwd)
OUT=$ROOT/build/coverage
DEPS=0
parts=()
while [ $# -gt 0 ]; do
  case $1 in
    --out) OUT=${2:?--out needs a directory}; shift ;;
    --deps) DEPS=1 ;;
    -h|--help) sed -n '5,44p' "$0" | sed 's/^# \{0,1\}//'; exit 0 ;;
    scripts|cpp:decoration-cpp|cpp:kcm-cpp|cpp:navigation-cpp) parts+=("$1") ;;
    *) echo "coverage.sh: unknown argument '$1' (--help)" >&2; exit 2 ;;
  esac
  shift
done
[ ${#parts[@]} -gt 0 ] || parts=(scripts)

if [ "$DEPS" = 1 ]; then
  set -e
  for part in "${parts[@]}"; do
    case $part in
      scripts)
        # The spec's requirements run tools/build.sh; the rest switch on the checks it skips
        # without them (as in build.yml), the login check and power tiers tests, and the tools.
        dnf install -y -q dnf-plugins-core
        dnf builddep -y -q --without compiled "$ROOT/packaging/fedora/plasma-fusion.spec"
        dnf install -y -q git-core python3-coverage kcov nodejs \
          ShellCheck desktop-file-utils libxml2 kf6-kconfig glib2 python3-gobject gtk3 gtk4 \
          dbus-daemon dbus-tools systemd libXcursor
        ;;
      cpp:*)
        dnf install -y -q dnf-plugins-core rpm-build gcovr dbus-daemon python3 git-core
        dnf builddep -y -q "$ROOT/packaging/fedora/plasma-fusion.spec"
        ;;
    esac
  done
  exit 0
fi

need() { command -v "$1" >/dev/null || { echo "coverage.sh: $1 is not installed (try --deps)" >&2; exit 2; }; }
for part in "${parts[@]}"; do
  case $part in
    scripts) need python3; need kcov; need node; python3 -c 'import coverage' 2>/dev/null || { echo "coverage.sh: python3-coverage is not installed (try --deps)" >&2; exit 2; } ;;
    cpp:*) need cmake; need ninja; need gcovr; need dbus-run-session ;;
  esac
done

case $OUT in /*) ;; *) OUT=$PWD/$OUT ;; esac
# Replace only an earlier result (it has tests.tsv) or an empty directory.
if [ -d "$OUT" ] && [ -n "$(ls -A "$OUT")" ] && [ ! -f "$OUT/tests.tsv" ]; then
  echo "coverage.sh: $OUT is not empty and holds no earlier result; give a new directory" >&2
  exit 2
fi
rm -rf "${OUT:?}" && mkdir -p "$OUT/logs" "$OUT/work" || exit 1
: >"$OUT/tests.tsv"
cd "$OUT/work" || exit 1
# No display or session bus: generators and checks render offscreen and start nothing in a session.
unset DISPLAY WAYLAND_DISPLAY XAUTHORITY DBUS_SESSION_BUS_ADDRESS
export QT_QPA_PLATFORM=offscreen LANG=C.UTF-8

# run_test NAME COMMAND...: one test, its output in OUT/logs/NAME.log, its exit status and time in
# OUT/tests.tsv.
run_test() {
  local name=$1 start=$SECONDS rc=0
  shift
  "$@" >"$OUT/logs/$name.log" 2>&1 || rc=$?
  printf '%s\t%s\t%s\n' "$name" "$rc" "$((SECONDS - start))" >>"$OUT/tests.tsv"
  echo "  $name: exit $rc, $((SECONDS - start)) s"
}

scripts() {
  echo "== scripts: Python, shell and JavaScript"
  mkdir -p "$OUT/python" "$OUT/shell/runs" "$OUT/js" "$OUT/bin"
  cat >"$OUT/python/coveragerc" <<EOF
[run]
data_file = $OUT/python/.coverage
parallel = true
include = $ROOT/*
omit =
    $ROOT/build/*
    $ROOT/stage/*
    $ROOT/.*
    $OUT/*
disable_warnings = no-data-collected
EOF
  export COVERAGE_PROCESS_START=$OUT/python/coveragerc
  # kcov: report every bash script below these directories, run or not (so the totals hold the
  # scripts no test starts), and nothing outside the repository or in its build output.
  local kcov=(kcov --include-path="$ROOT" --exclude-path="$ROOT/build,$ROOT/stage,$OUT"
              --bash-dont-parse-binary-dir
              --bash-parse-files-in-dir="$ROOT/tools,$ROOT/packages,$ROOT/generators,$ROOT/packaging")
  cat >"$OUT/bin/env" <<'EOF'
#!/bin/bash
# coverage.sh: `env -i` keeps the coverage hooks (kcov's bash trace, coverage.py's start file) for
# the command it starts; anything else is the real env.
if [ "${1:-}" = -i ]; then
  shift
  keep=()
  for v in BASH_ENV BASH_XTRACEFD KCOV_BASH_XTRACEFD KCOV_BASH_COMMAND COVERAGE_PROCESS_START; do
    [ -n "${!v+x}" ] && keep+=("$v=${!v}")
  done
  exec /usr/bin/env -i "${keep[@]}" "$@"
fi
exec /usr/bin/env "$@"
EOF
  chmod 0755 "$OUT/bin/env"
  local stage=$OUT/work/stage
  PATH=$OUT/bin:$PATH run_test build env STAGE="$stage" "${kcov[@]}" "$OUT/shell/runs/build" "$ROOT/tools/build.sh"
  run_test plymouth "${kcov[@]}" "$OUT/shell/runs/plymouth" "$ROOT/generators/plymouth/build.sh" "$OUT/work/plymouth/plasma-fusion"
  run_test lint-selftests "${kcov[@]}" "$OUT/shell/runs/lint-selftests" "$ROOT/tools/checks/tests/run.sh"
  PATH=$OUT/bin:$PATH run_test gate-unit "${kcov[@]}" "$OUT/shell/runs/gate-unit" "$ROOT/tools/device/tests/gate-unit.sh" "$OUT/work/gate"
  PATH=$OUT/bin:$PATH run_test powerfx-offline "${kcov[@]}" "$OUT/shell/runs/powerfx-offline" "$ROOT/packages/powerfx/tests/offline.sh" "$OUT/work/powerfx"
  mkdir -p "$OUT/work/cursors"
  run_test cursors python3 "$ROOT/generators/cursors/tests/test_cursors.py" --work "$OUT/work/cursors"
  run_test aurorae python3 "$ROOT/generators/decoration/tests/check_aurorae.py" "$stage/.local/share/aurorae/themes"
  run_test plasma-style python3 "$ROOT/generators/plasma-style/tests/validate.py" \
    "$stage/.local/share/plasma/desktoptheme/plasma-fusion-dark" "$stage/.local/share/plasma/desktoptheme/plasma-fusion-light"
  run_test icon-themes python3 "$ROOT/generators/icons/validate.py" "$stage/.local/share/icons"
  mkdir -p "$OUT/work/fieldlog"
  run_test fieldlog env PF_FIELDLOG_TEST_DIR="$OUT/work/fieldlog" python3 "$ROOT/tools/device/fieldlog/tests/fieldlog_test.py"
  # JavaScript: node's own coverage (V8) over the unit tests, as lcov.
  local js=()
  mapfile -t js < <(cd "$ROOT" && find packages -path '*/tests/*.test.js' | sort)
  run_test js-unit env -C "$ROOT" node --test --experimental-test-coverage \
    --test-reporter=spec --test-reporter-destination=stdout \
    --test-reporter=lcov --test-reporter-destination="$OUT/js/lcov.info" "${js[@]}"
  unset COVERAGE_PROCESS_START

  echo "== combining"
  { python3 -m coverage combine --rcfile="$OUT/python/coveragerc" -q &&
    python3 -m coverage html --rcfile="$OUT/python/coveragerc" -q -d "$OUT/python/html"; } >"$OUT/logs/coverage-py.log" 2>&1 \
    || { echo "coverage.sh: coverage.py could not combine or report (logs/coverage-py.log)" >&2; return 1; }
  kcov --merge "$OUT/shell/merged" "$OUT/shell/runs"/* >"$OUT/logs/kcov-merge.log" 2>&1 \
    || { echo "coverage.sh: kcov --merge failed (logs/kcov-merge.log)" >&2; return 1; }
}

cpp() { # PACKAGE
  local p=$1 src=$ROOT/packages/$1 dir=$OUT/cpp-$1
  local b=$dir/build
  echo "== cpp: $p"
  mkdir -p "$dir"
  local flags="--coverage -O0"
  cmake -S "$src" -B "$b" -G Ninja -DCMAKE_BUILD_TYPE=Debug -DBUILD_TESTING=ON \
    -DCMAKE_CXX_FLAGS="$flags" -DCMAKE_EXE_LINKER_FLAGS=--coverage \
    -DCMAKE_SHARED_LINKER_FLAGS=--coverage -DCMAKE_MODULE_LINKER_FLAGS=--coverage \
    >"$OUT/logs/$p-cmake.log" 2>&1 || { echo "coverage.sh: cmake failed for $p (logs/$p-cmake.log)" >&2; return 1; }
  cmake --build "$b" >"$OUT/logs/$p-build.log" 2>&1 \
    || { echo "coverage.sh: the build of $p failed (logs/$p-build.log)" >&2; return 1; }
  run_test "$p-ctest" ctest --test-dir "$b" --output-on-failure
  if [ "$p" = decoration-cpp ]; then
    local name scheme other client
    for v in dark:Dark:Light:#1b2031 light:Light:Dark:#ffffff; do
      IFS=: read -r name scheme other client <<<"$v"
      mkdir -p "$OUT/work/deco-$name/config" "$OUT/work/deco-$name/cache" "$OUT/work/deco-$name/out"
      cp "$ROOT/packages/color-schemes/PlasmaFusion$scheme.colors" "$OUT/work/deco-$name/config/kdeglobals"
      run_test "$p-preview-$name" env LANG=en_US.UTF-8 XDG_CONFIG_HOME="$OUT/work/deco-$name/config" \
        XDG_CACHE_HOME="$OUT/work/deco-$name/cache" \
        dbus-run-session -- "$b/bin/pfdeco-preview" --decoration-plugin "$b/bin/org.plasmafusion.decoration.so" \
          --out "$OUT/work/deco-$name/out" --name "$name" \
          --scheme "$ROOT/packages/color-schemes/PlasmaFusion$scheme.colors" \
          --other-scheme "$ROOT/packages/color-schemes/PlasmaFusion$other.colors" \
          --fonts "$ROOT/fonts/manrope/static" --client "$client" --scales 1,1.3333333,1.325
    done
  fi
  gcovr --root "$ROOT" --object-directory "$b" --filter "$src/src/" \
    --json "$dir/gcovr.json" --txt "$dir/gcovr.txt" >"$OUT/logs/$p-gcovr.log" 2>&1 \
    || { echo "coverage.sh: gcovr failed for $p (logs/$p-gcovr.log)" >&2; return 1; }
}

status=0
for part in "${parts[@]}"; do
  case $part in
    scripts) scripts || status=1 ;;
    cpp:*) cpp "${part#cpp:}" || status=1 ;;
  esac
done
python3 "$ROOT/tools/tests/coverage_summary.py" --root "$ROOT" --out "$OUT" || status=1
[ -f "$OUT/summary.md" ] && cat "$OUT/summary.md"
exit "$status"
