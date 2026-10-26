#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Internal entry point: called by native-tests.sh, never against the host's RPM database.
# Usage: native-tests-in-container.sh VERSION-RELEASE backport|stock
# Exit status: 0 every suite passed, 1 a suite failed in all its attempts, 3 setup or build failed.
set -euo pipefail
[[ $# == 2 && $1 =~ ^6\.7\.5-[0-9]+\.fc44$ && $2 =~ ^(backport|stock)$ ]] || exit 64
vr=$1
variant=$2
trap 'echo "setup or build failed (line $LINENO)" >&2; exit 3' ERR
top=/root/rpmbuild
spec=$top/SPECS/kwin.spec
# The suites the README names: the backported tests and those around tiling and geometry.
tests=(testTiles testXdgShellWindow testQuickTiling testMoveResize testInternalWindow testMaximized
    testPlacement testX11Window)
echo "$variant" > /out/variant
dnf install -y rpm-build dnf5-plugins python3 dbus-daemon > /out/dependencies.log 2>&1
python3 -B -m unittest discover -s /patches -v
mkdir -p /root/source
cd /root/source
dnf download --srpm "kwin-$vr" > /out/download.log 2>&1
source="kwin-$vr.src.rpm"
[[ $(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE}' "$source") == "kwin-$vr" ]]
rpm -i --define "_topdir $top" "$source"
if [[ $variant == backport ]]; then
    sha256sum "$source" /patches/*.patch > /out/inputs.sha256
    cp /patches/*.patch "$top/SOURCES/"
    python3 /patches/prepare_spec.py "$spec" "$vr"
    [[ $(rpmspec -q --srpm --qf '%{VERSION}-%{RELEASE}' "$spec") == "$vr.pf1" ]]
else
    # Fedora's spec as it is: the comparison the backport's results are judged against.
    sha256sum "$source" > /out/inputs.sha256
    [[ $(rpmspec -q --srpm --qf '%{VERSION}-%{RELEASE}' "$spec") == "$vr" ]]
fi
dnf builddep -y "$spec" >> /out/dependencies.log 2>&1
# Development packages the tests need besides the package build.
dnf install -y 'cmake(KPipeWire)' 'pkgconfig(libei-1.0)' 'cmake(Qt6WaylandClientPrivate)' \
    'pkgconfig(vulkan)' >> /out/dependencies.log 2>&1
rpm -qa --qf '%{NAME}-%{VERSION}-%{RELEASE}.%{ARCH}\n' | sort > /out/packages.txt
# Fedora's %prep: its patches (%autosetup -p1), and on the backport this one too.
rpmbuild -bp --define "_topdir $top" "$spec" > /out/prep.log 2>&1
src=$top/BUILD/kwin-${vr%%-*}-build/kwin-${vr%%-*}
# The source holds the backport exactly when it should (a "!" command would not stop set -e).
if grep -q 'requestedGeometryChanged' "$src/src/window.h"; then has=backport; else has=stock; fi
if [[ $has != "$variant" ]]; then
    echo "the prepared source is $has, not $variant" >&2
    exit 3
fi
cd "$src"
# Fedora's configure step (%cmake_kf6: its flags, build type and options) with the tests on.
configure=$(rpm --define "_topdir $top" --eval '%{cmake_kf6}')
if ! eval "$configure -DBUILD_TESTING:BOOL=ON" > /out/configure.log 2>&1; then
    tail -40 /out/configure.log >&2
    exit 3
fi
# testUnresponsiveWindow runs the helper "kill" (autotests/integration/helper), found next to the
# tests: build it with them.
if ! cmake --build redhat-linux-build -j4 --target "${tests[@]}" kill > /out/build.log 2>&1; then
    tail -60 /out/build.log >&2
    exit 3
fi
trap - ERR
export XDG_RUNTIME_DIR=/tmp/kwin-test-runtime
mkdir -p "$XDG_RUNTIME_DIR" /tmp/.X11-unix && chmod 700 "$XDG_RUNTIME_DIR" && chmod 1777 /tmp/.X11-unix
unset DISPLAY WAYLAND_DISPLAY DBUS_SESSION_BUS_ADDRESS
# On the backport a failing suite runs again, up to three attempts, as in KWin's own CI (its
# .kde-ci.yml: ctest --repeat until-pass:3): some integration tests wait a few milliseconds for a
# signal that must not come, which a busy machine can miss. The stock build runs every suite ten
# times, pass or fail, so that a test which fails there now and then shows it (on 2026-10-26
# testX11Window's stacking tests failed in 15 and in 6 of 20 runs of either build). Every attempt
# keeps its log ($t.log is the last), and $t.attempts says how many ran. Whether a failure is the
# backport's is the comparison of the two (tools/tests/kwin-backport/native_compare.py).
attempts=3
[[ $variant == backport ]] || attempts=10
status=0
for t in "${tests[@]}"; do
    for (( attempt = 1; attempt <= attempts; attempt++ )); do
        rc=0
        (cd redhat-linux-build/bin && timeout --signal=INT --kill-after=10s 900 dbus-run-session "./$t") \
            > "/out/$t.$attempt.log" 2>&1 || rc=$?
        printf '%s attempt %s exit=%s %s\n' "$t" "$attempt" "$rc" \
            "$(grep -E '^Totals:' "/out/$t.$attempt.log" | tail -n 1)"
        grep -E '^FAIL!' "/out/$t.$attempt.log" || true
        [[ $variant == stock ]] || (( rc != 0 )) || break
    done
    (( attempt <= attempts )) || attempt=$attempts
    cp "/out/$t.$attempt.log" "/out/$t.log"
    echo "$rc" > "/out/$t.exit"
    echo "$attempt" > "/out/$t.attempts"
    (( rc == 0 )) || status=1
done
exit "$status"
