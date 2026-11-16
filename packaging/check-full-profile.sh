#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# The full-profile spec branch's automated checks (docs/full-profile.md): the stock default
# never emits plasma-fusion-full; a full build with a matching exact pin emits it once; a full
# build with a wrong-series pin fails; a full build without a pin fails; a full build requires
# the fork's kwin-devel at exactly the pin, and its %check refuses a navigation effect built
# against another KWin; a full build's packages carry the release suffix .full and sort above
# the stock build of the same version, also from the spec packaging/build-rpm.sh writes (#197).
# Keeps the %{with full} gate exercised in CI without building the fork's RPMs. The pin's pf
# suffix carries any number of digits (check-version.sh accepts pf10), so the two-digit gates
# mirror the one-digit ones.
#
# A release sets the pin in the spec itself (%global kwin_full_pin), and a %global in the spec
# wins over a --define on the command line. The gates therefore run on a copy of the spec
# without that line, and the spec as it is has checks of its own at the end.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
real="$ROOT/packaging/fedora/plasma-fusion.spec"
work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT
spec="$work/plasma-fusion.spec"
sed '/^%global kwin_full_pin /d' "$real" >"$spec"
own=$(sed -n 's/^%global kwin_full_pin *//p' "$real" | tr -d '[:space:]')
rc=0
query() { # DESC EXPECTED_COUNT ARGS...
  local desc=$1 expected=$2
  shift 2
  local count
  count=$(rpmspec --define 'fedora 44' "$@" -q --qf '%{NAME}\n' "$spec" 2>/dev/null | grep -c '^plasma-fusion-full$' || true)
  if [ "$count" = "$expected" ]; then
    echo "ok   $desc (plasma-fusion-full x$count)"
  else
    echo "FAIL $desc: expected x$expected, got x$count"
    rc=1
  fi
}
query "stock default never emits the metapackage" 0
query "a pin alone (no --with full) never emits it" 0 --define 'kwin_full_pin 6.8.2-3.fc44.pf2'
query "full + matching fc44 pin emits it once" 1 --with full --define 'kwin_full_pin 6.8.2-3.fc44.pf2'
query "full + matching fc44 pin with a two-digit pf suffix emits it once" 1 --with full --define 'kwin_full_pin 6.8.2-3.fc44.pf10'
query "full + fc45 pin is refused" 0 --with full --define 'kwin_full_pin 6.8.2-3.fc45.pf2'
query "full + fc45 pin with a two-digit pf suffix is refused" 0 --with full --define 'kwin_full_pin 6.8.2-3.fc45.pf10'
# the refused cases must be hard errors, not silent skips
if rpmspec --define 'fedora 44' --with full --define 'kwin_full_pin 6.8.2-3.fc45.pf2' -q "$spec" >/dev/null 2>&1; then
  echo "FAIL full + fc45 pin: expected a hard error"
  rc=1
else
  echo "ok   full + fc45 pin fails the build"
fi
if rpmspec --define 'fedora 44' --with full -q "$spec" >/dev/null 2>&1; then
  echo "FAIL full without a pin: expected a hard error"
  rc=1
else
  echo "ok   full without a pin fails the build"
fi
# A full build's packages sort above the stock build's of the same version. Both Copr projects
# build the same source package, against different KWins; without the suffix their packages have
# the same version-release, so a machine that switches from the stock profile keeps the stock
# project's six, and with both projects enabled dnf can take either (#197).
suffix() { # SPEC PIN DESC: the stock and the full build's release, their order, the requires
  local spec=$1 pin=$2 stock full order version reqs how desc
  # The dist tag as a build can have it: from the system's macros (mock, Copr, build-rpm.sh) and
  # from the command line. The spec's %global dist wins over both.
  for how in system command-line; do
    local -a args=(--define 'fedora 44' --define "kwin_full_pin $pin")
    [ "$how" = system ] || args+=(--define 'dist .fc44')
    desc="$3, the $how dist tag"
    stock=$(rpmspec "${args[@]}" -q --qf '%{RELEASE}\n' "$spec" 2>/dev/null | sort -u)
    full=$(rpmspec "${args[@]}" --with full -q --qf '%{RELEASE}\n' "$spec" 2>/dev/null | sort -u)
    case $stock in
      '' | *.full*) echo "FAIL $desc: a stock build's release: '$stock'"; rc=1 ;;
      *) echo "ok   $desc: a stock build's release has no suffix ($stock)" ;;
    esac
    if [ -n "$stock" ] && [ "$full" = "$stock.full" ]; then
      echo "ok   $desc: a full build's packages carry the release suffix once ($full)"
    else
      echo "FAIL $desc: a full build's release: '$full' (stock '$stock')"
      rc=1
    fi
    order=$(rpm --eval "%{lua: print(rpm.vercmp('${full:-x}', '${stock:-x}'))}" 2>/dev/null)
    if [ "$order" = 1 ]; then
      echo "ok   $desc: a full build sorts above the stock build of the same version"
    else
      echo "FAIL $desc: rpm.vercmp('$full', '$stock') = '$order', expected 1"
      rc=1
    fi
    version=$(rpmspec --define 'fedora 44' -q --srpm --qf '%{VERSION}' "$spec" 2>/dev/null)
    reqs=$(rpmspec "${args[@]}" --with full -q --requires "$spec" 2>/dev/null |
      grep -cxE "plasma-fusion(-decoration|-settings|-navigation|-quicklook|-copytext)? = ${version//./\\.}-${full//./\\.}" ||
      true)
    if [ "$reqs" = 6 ]; then
      echo "ok   $desc: the metapackage requires the six at the full build's release"
    else
      echo "FAIL $desc: the metapackage's requires on the six at $version-$full: found x$reqs of 6"
      rc=1
    fi
  done
}
suffix "$spec" 6.8.2-3.fc44.pf2 "a test pin"
# The Release line keeps the dist tag at its end, where both tools that rewrite the line look for
# it: packaging/build-rpm.sh writes RELEASE%{?dist}, and Packit's source packages split the dist
# tag off the end only (the specfile library). The full build's suffix lives in the dist tag.
if grep -qE '^Release:[[:space:]]+[^[:space:]%]+%\{\?dist\}$' "$real"; then
  echo "ok   the Release line ends with the dist tag, as build-rpm.sh and Packit rewrite it"
else
  echo "FAIL the Release line: '$(grep -m 1 '^Release:' "$real")', expected N%{?dist}"
  rc=1
fi
# build-rpm.sh's own rewrite, taken from the script (the release's source package can come from
# it, docs/RELEASING.md): a full build of the spec it writes still carries the suffix.
rewrite=$(sed -n "/<<'PY'\$/,/^PY\$/p" "$ROOT/packaging/build-rpm.sh" | sed '1d;$d')
if [ -z "$rewrite" ]; then
  echo "FAIL packaging/build-rpm.sh: its rewrite of the spec was not found"
  rc=1
else
  for r in 1 1.dirty202611160000; do
    out=$work/rewritten-$r.spec
    if ! python3 -I - "$spec" "$out" 0.8.0 "$r" "Mon Nov 16 2026" 0123456 <<<"$rewrite" 2>/dev/null; then
      echo "FAIL build-rpm.sh's rewrite of the spec (release $r) failed"
      rc=1
      continue
    fi
    # The system's dist tag, as rpmbuild in mock or Copr has it.
    stock=$(rpmspec --define 'fedora 44' -q --qf '%{RELEASE}\n' "$out" 2>/dev/null | sort -u)
    full=$(rpmspec --define 'fedora 44' --with full --define 'kwin_full_pin 6.8.2-3.fc44.pf2' \
      -q --qf '%{RELEASE}\n' "$out" 2>/dev/null | sort -u)
    if [ "$stock" = "$r$(rpm --eval '%{?dist}')" ] && [ "$full" = "$stock.full" ]; then
      echo "ok   build-rpm.sh's spec (release $r): a stock build $stock, a full build $full"
    else
      echo "FAIL build-rpm.sh's spec (release $r): a stock build '$stock', a full build '$full'"
      rc=1
    fi
  done
fi
# The profile's record (plasma-fusion status reads it): written by a full build only, with the
# pin and the fork tag it is built from, and shipped by the metapackage only.
record() { # DESC EXPECTED ARGS...: the record's two lines as %install writes them
  local desc=$1 expected=$2 body got
  shift 2
  body=$(rpmspec --define 'fedora 44' "$@" -P "$spec" 2>/dev/null |
    sed -n "/^pin='/,/full-profile\$/p")
  if [ -z "$body" ]; then
    got=
  else
    got=$(buildroot=$(mktemp -d) && eval "$(printf '%s\n' "$body" | sed "s#>.*/plasma-fusion/full-profile#>$buildroot/record#")" &&
      tr '\n' ' ' <"$buildroot/record" && rm -rf "$buildroot")
  fi
  if [ "$got" = "$expected" ]; then
    echo "ok   $desc"
  else
    echo "FAIL $desc: expected '$expected', got '$got'"
    rc=1
  fi
}
record "a full build writes the pin and its fork tag" "kwin=6.8.2-3.fc44.pf2 tag=v6.8.2-pf2 " --with full --define 'kwin_full_pin 6.8.2-3.fc44.pf2'
record "a two-digit pf suffix gives its tag" "kwin=6.8.2-3.fc44.pf10 tag=v6.8.2-pf10 " --with full --define 'kwin_full_pin 6.8.2-3.fc44.pf10'
record "a stock build writes no record" ""
files=$(rpmspec --define 'fedora 44' --with full --define 'kwin_full_pin 6.8.2-3.fc44.pf2' -P "$spec" 2>/dev/null |
  awk '/^%files full$/{p=1; next} /^%files/{p=0} p' | grep -c '/plasma-fusion/full-profile$' || true)
if [ "$files" = 1 ]; then
  echo "ok   the metapackage ships the record"
else
  echo "FAIL the metapackage ships the record: found x$files in its file list"
  rc=1
fi
# A full build compiles against the KWin it pins: it requires the fork's kwin-devel at exactly
# the pin, because cmake(KWin) takes the newest kwin-devel in the build root - the
# distribution's, once that is newer than the pin (#191) - and its %check refuses a navigation
# effect built against another KWin, which would stay idle on every full-profile machine. The
# pin replaces cmake(KWin) rather than joining it: next to a newer kwin-devel the two cannot both
# get their best candidate, and mock's dnf runs with best=1.
buildreq() { # DESC EXPECTED ARGS...: the build's KWin requirements, one per line
  local desc=$1 expected=$2 got
  shift 2
  got=$(rpmspec --define 'fedora 44' "$@" -q --buildrequires "$spec" 2>/dev/null | grep -E '^(kwin-devel|cmake\(KWin\))' || true)
  if [ "$got" = "$expected" ]; then
    echo "ok   $desc"
  else
    echo "FAIL $desc: expected '$expected', got '$got'"
    rc=1
  fi
}
buildreq "a full build requires the pinned kwin-devel exactly, and no other KWin" "kwin-devel = 6.8.2-3.fc44.pf2" --with full --define 'kwin_full_pin 6.8.2-3.fc44.pf2'
buildreq "a stock build requires any KWin 6.7 or later" "cmake(KWin) >= 6.7" --define 'kwin_full_pin 6.8.2-3.fc44.pf2'
buildreq "a full build without the compiled parts requires no KWin" "" --with full --without compiled --define 'kwin_full_pin 6.8.2-3.fc44.pf2'
navcheck() { # DESC EXPECTED(pass|fail|absent) BUILT ARGS...: %check on a navigation record of KWin BUILT
  local desc=$1 expected=$2 built=$3 body got dir
  shift 3
  body=$(rpmspec --define 'fedora 44' "$@" -P "$spec" 2>/dev/null | sed -n "/^pinned='/,/^fi\$/p")
  if [ -z "$body" ]; then
    got=absent
  else
    dir=$(mktemp -d)
    printf 'kwin=%s\nqt=6.11.2\n' "$built" >"$dir/navigation"
    if (eval "$(printf '%s\n' "$body" | sed "s#[^ \"]*/plasma-fusion/built-against/navigation#$dir/navigation#g")") 2>/dev/null; then
      got=pass
    else
      got=fail
    fi
    rm -rf "$dir"
  fi
  if [ "$got" = "$expected" ]; then
    echo "ok   $desc"
  else
    echo "FAIL $desc: expected $expected, got $got"
    rc=1
  fi
}
navcheck "a full build's %check accepts the navigation effect built against the pinned KWin" pass 6.8.2 --with full --define 'kwin_full_pin 6.8.2-3.fc44.pf2'
navcheck "a full build's %check refuses one built against the distribution's newer KWin" fail 6.8.3 --with full --define 'kwin_full_pin 6.8.2-3.fc44.pf2'
navcheck "a full build's %check refuses one without a KWin version" fail "" --with full --define 'kwin_full_pin 6.8.2-3.fc44.pf2'
navcheck "a stock build's %check does not compare it with a pin" absent 6.8.3 --define 'kwin_full_pin 6.8.2-3.fc44.pf2'
# The spec as it is: with a pin of its own, the stock build still never emits the metapackage,
# the full build emits it once with exact requires on that pin, and the record names it.
if [ -n "$own" ]; then
  spec=$real
  query "the spec's own pin ($own): a stock build never emits the metapackage" 0
  query "the spec's own pin: a full build emits it once" 1 --with full
  suffix "$real" "$own" "the spec's own pin"
  requires=$(rpmspec --define 'fedora 44' --with full -q --requires "$real" 2>/dev/null |
    grep -cxE "kwin(-common|-libs)? = ${own//./\\.}" || true)
  if [ "$requires" = 3 ]; then
    echo "ok   the metapackage requires kwin, kwin-common and kwin-libs at exactly $own"
  else
    echo "FAIL the metapackage's exact requires on $own: found x$requires of 3"
    rc=1
  fi
  record "the spec's own pin: the record names it and its fork tag" "kwin=$own tag=v${own%%-*}-${own##*.} " --with full
  buildreq "the spec's own pin: a full build requires kwin-devel at exactly $own, and no other KWin" "kwin-devel = $own" --with full
  navcheck "the spec's own pin: %check accepts the navigation effect built against KWin ${own%%-*}" pass "${own%%-*}" --with full
else
  echo "ok   the spec sets no pin of its own (plasma-fusion-full is not built)"
fi
exit "$rc"
