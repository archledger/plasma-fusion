#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Unit tests of `plasma-fusion status`' profile and capability lines (ADR 0001), the command as it
# is, against stand-ins for kwin_wayland, busctl (KWin's support information, its scripting
# interface) and journalctl (where the probe's answer is read), with a throw-away package tree:
#   1. outside a session: the stock profile, and where to run the command to see the capabilities;
#   2. stock KWin: none of the fork's capabilities, the probe loaded, run and unloaded, its file gone;
#   3. the fork without the metapackage: the three capabilities and the note that says so;
#   4. the full profile: the pin and the fork tag from the metapackage's record;
#   5. the full profile with the session still on the KWin from before: the note to log in again;
#   6. the full profile under another Plasma: the note that names both versions;
#   7. an answer that never reaches the journal: said, and the support information still read;
#   8. no KWin on the session bus: as outside a session;
#   9. the probe KWin is given reads the properties and the function ADR 0001 names;
#  10. every call's probe is found by the compositor: KWin's QML loader keeps the listing of a
#      directory it has read for as long as it runs, and a file made there later does not exist
#      for it (the stand-in keeps the same list);
#  11. the fork's capabilities without the full profile, the KWin on the disk put there after
#      the session's KWin started (after --full-restore, before the next login): the note to
#      log in again, not the one about a fork installed by hand;
#  12. the same with a KWin whose start cannot be read: the note about a fork installed by hand;
#  13. a program put on the disk just before KWin started is never taken for a later one: the
#      start read from /proc is up to two seconds early (the boot time and the clock ticks are
#      both rounded down), so the times must be further apart than that;
#  14. without getconf the clock ticks are taken as the kernel's usual hundred a second;
#  15. the full profile with the decoration record and the installed KDecoration at one version:
#      no decoration note and no navigation note, though KWin is the pin's older one (the record
#      holds KDecoration's version, not KWin's, so a comparison with KWin would make this note
#      permanent, #194);
#  16. a decoration built against an older KDecoration than the installed one: the note names the
#      two KDecoration versions, not KWin's;
#  17. the installed version from the other databases the login check reads (pacman's pkgver and
#      pkgrel, dpkg's source package with its epoch and revision, Nix's store path name), compared
#      upstream only, so a distribution rebuild alone is no note;
#  18. the databases in the login check's order: rpm's answer is the one read;
#  19. no database answers: no decoration note (a missing note, never a wrong one);
#  20. the stock profile: no note when the installed KDecoration is the build's, whether or not
#      KWin is another version;
#  21. two installed versions of one source package (a partial upgrade): no note, whichever of
#      them the record matches - an ambiguous answer is not a version - and one version in two
#      revisions is one version;
#  22. NixOS without nix-store on the PATH: the system profile's own binary answers, as it does
#      for the login check (PF_NIX_SW names the profile here);
#  23. a database that does not answer in time: the query is bounded as the login check's are, so
#      status finishes and the version stays unknown;
#  24. the system's database fails while a foreign package manager's files are there: no note,
#      because the system's database is the one asked and its failure is an unknown, never another
#      installation's answer.
# Test tooling only, not installed.
#
#   status-unit.sh BASE
#
# BASE must be a scratch directory on disk (not /tmp); it is emptied first.
set -euo pipefail
BASE=${1:?scratch directory}
BASE=$(realpath -m -- "$BASE")
case $BASE in /tmp/* | /tmp) echo "use a directory on disk, not /tmp" >&2; exit 2 ;; esac
TOP=$(cd "$(dirname "$0")/../.." && pwd)
CLI=$TOP/tools/plasma-fusion
[ -f "$CLI" ] || { echo "FAIL: $CLI is missing"; exit 1; }
rm -rf "${BASE:?}"
mkdir -p "$BASE"

PASS=0 FAIL=0
ok() { PASS=$((PASS + 1)); echo "PASS $1"; }
bad() { FAIL=$((FAIL + 1)); echo "FAIL $1"; }
has() { # NAME TEXT: the last output has the line (or part of one)
  if grep -qF -- "$2" <<<"$OUT"; then ok "$1"; else bad "$1 (no '$2' in the output)"; fi
}
hasnot() {
  if grep -qF -- "$2" <<<"$OUT"; then bad "$1 ('$2' in the output)"; else ok "$1"; fi
}

# The package: a data directory with the version and nothing compiled.
export T=$BASE/t HOME=$BASE/home
SHARE=$BASE/share
mkdir -p "$T" "$HOME" "$SHARE/plasma-fusion" "$BASE/run" "$BASE/root"
echo 0.0.0-test >"$SHARE/plasma-fusion/version"
echo 6.8 >"$SHARE/plasma-fusion/tested-plasma.txt"
export XDG_DATA_DIRS=$SHARE XDG_DATA_HOME=$HOME/.local/share XDG_STATE_HOME=$HOME/.local/state
export XDG_RUNTIME_DIR=$BASE/run PF_GREETER_ROOT=$BASE/root

# The stand-ins, first in PATH. $T/mode says which compositor answers: stock, fork, silent
# (the fork, its probe's answer never written) or absent (no KWin on the bus). $T/kwin is the
# version kwin_wayland reports, $T/pid the process the bus names as KWin (none: no answer).
BIN=$BASE/bin
mkdir -p "$BIN"
cat >"$BIN/kwin_wayland" <<'EOF'
#!/bin/bash
echo "kwin $(cat "$T/kwin")"
EOF
cat >"$BIN/journalctl" <<'EOF'
#!/bin/bash
cat "$T/journal" 2>/dev/null
EOF
cat >"$BIN/busctl" <<'EOF'
#!/bin/bash
mode=$(cat "$T/mode")
printf '%s\n' "$*" >>"$T/busctl.calls"
case "$*" in
  *NameHasOwner*)
    if [ "$mode" = absent ]; then echo "b false"; else echo "b true"; fi ;;
  *GetConnectionUnixProcessID*)
    [ -s "$T/pid" ] || exit 1
    echo "u $(cat "$T/pid")" ;;
  *supportInformation*)
    if [ "$mode" = stock ]; then
      printf 's "KWin Support Information:\\nLoaded Effects:\\noverview:\\nlayout: 1\\n"\n'
    else
      printf 's "KWin Support Information:\\nLoaded Effects:\\noverview:\\nlayout: 1\\nplasmaFusionOffscreenOpacityVersion: 1\\n"\n'
    fi ;;
  *loadDeclarativeScript*)
    # ... loadDeclarativeScript ss FILE NAME
    file=${*: -2:1} name=${*: -1}
    cp "$file" "$T/probe.qml"
    echo "$name" >"$T/nonce"
    # Qt's QML loader reads a directory once and keeps what it found (QQmlTypeLoader's
    # directory cache): a file made later in a directory it has read fails to load ("File name
    # case mismatch"), and the script it would have been says nothing.
    dir=$(dirname "$file")
    if grep -qxF -- "$dir" "$T/read-directories" 2>/dev/null; then
      echo stale >"$T/load"
    else
      echo "$dir" >>"$T/read-directories"
      echo fresh >"$T/load"
    fi
    echo "i 7" ;;
  */Scripting/Script7*run*)
    nonce=$(cat "$T/nonce")
    [ "$(cat "$T/load")" = fresh ] || exit 0
    case $mode in
      stock) echo "qml: plasma-fusion-probe $nonce thumbnail=0 tiling=0" >>"$T/journal" ;;
      fork) echo "qml: plasma-fusion-probe $nonce thumbnail=1 tiling=1" >>"$T/journal" ;;
    esac ;;
  *unloadScript*)
    echo "${*: -1}" >>"$T/unloaded" ;;
esac
EOF
# getconf, as it is; with $T/no-getconf, a system without one.
REAL_GETCONF=$(command -v getconf)
cat >"$BIN/getconf" <<EOF
#!/bin/bash
[ ! -e "\$T/no-getconf" ] || exit 127
exec "$REAL_GETCONF" "\$@"
EOF
# The package databases the login check reads (plasma-fusion-gate.sh, DB_PACKAGES, in its order:
# rpm, pacman, dpkg, nix). $T/kdecoration-<db> is the version that database reports for
# kdecoration; without it the database is there and does not know the package, as rpm, pacman and
# nix-store do for a package that is not installed (dpkg-query just lists nothing).
cat >"$BIN/rpm" <<'EOF'
#!/bin/bash
[ ! -e "$T/hang-rpm" ] || sleep 30
v=$(cat "$T/kdecoration-rpm" 2>/dev/null) || exit 1
[ -n "$v" ] || exit 1
echo "$v"
EOF
cat >"$BIN/pacman" <<'EOF'
#!/bin/bash
v=$(cat "$T/kdecoration-pacman" 2>/dev/null) || exit 1
[ -n "$v" ] || exit 1
echo "kdecoration $v"
EOF
cat >"$BIN/dpkg-query" <<'EOF'
#!/bin/bash
# Every line of the file is an installed binary of the source package: a partial upgrade can leave
# two at different versions.
while IFS= read -r v; do
  [ -n "$v" ] && printf 'installed kdecoration=%s\n' "$v"
done <"$T/kdecoration-dpkg" 2>/dev/null
exit 0
EOF
cat >"$BIN/nix-store" <<'EOF'
#!/bin/bash
v=$(cat "$T/kdecoration-nix" 2>/dev/null) || exit 1
[ -n "$v" ] || exit 1
printf '/nix/store/00000000000000000000000000000000-kdecoration-%s\n' "$v"
EOF
chmod +x "$BIN/kwin_wayland" "$BIN/journalctl" "$BIN/busctl" "$BIN/getconf" "$BIN/rpm" \
  "$BIN/pacman" "$BIN/dpkg-query" "$BIN/nix-store"
export PATH=$BIN:$PATH
# The package database's files, in the tree status reads (PF_STATUS_ROOT): the login check picks the
# first database whose files are there, and the tests choose the system the same way. A database
# whose files are there answers alone - a package manager installed beside it is never asked.
ROOTFS=$T/root
mkdir -p "$ROOTFS"
export PF_STATUS_ROOT=$ROOTFS
dbev() { # DB: that database's evidence, and no other's
  rm -rf "$ROOTFS"
  mkdir -p "$ROOTFS"
  case $1 in
    rpm) mkdir -p "$ROOTFS/var/lib/rpm"; : >"$ROOTFS/var/lib/rpm/rpmdb.sqlite" ;;
    pacman) mkdir -p "$ROOTFS/var/lib/pacman/local"; : >"$ROOTFS/var/lib/pacman/local/ALPM_DB_VERSION" ;;
    dpkg) mkdir -p "$ROOTFS/var/lib/dpkg"; : >"$ROOTFS/var/lib/dpkg/status" ;;
    nix) : ;; # PF_NIX_SW's directory is the evidence
  esac
}
dbnone() { rm -rf "$ROOTFS"; mkdir -p "$ROOTFS"; }

run() { # MODE [KWIN VERSION]: the command's output in OUT
  echo "$1" >"$T/mode"
  echo "${2:-6.8.2}" >"$T/kwin"
  rm -f "$T/journal" "$T/busctl.calls" "$T/unloaded" "$T/nonce" "$T/probe.qml"
  OUT=$(bash "$CLI" status 2>&1) || { bad "status exits 0 ($1)"; OUT=; }
}
# The session's KWin, for the process the bus names: a process of this test, started now.
# The program status compares it with is the kwin_wayland stand-in above, written before.
sleep 600 &
KWIN_PID=$!
trap 'kill "$KWIN_PID" 2>/dev/null || true' EXIT
echo "$KWIN_PID" >"$T/pid"
record() { # the metapackage's record, or none
  if [ "${1:-}" = none ]; then
    rm -f "$SHARE/plasma-fusion/full-profile"
  else
    printf 'kwin=%s\ntag=%s\n' 6.8.2-3.fc44.pf3 v6.8.2-pf3 >"$SHARE/plasma-fusion/full-profile"
  fi
}
# The compiled parts' records, as the packages install them: "kdecoration=<version>" for the
# decoration (CMake's upstream version), "kwin=<version>" for the navigation.
built() { # PART LINE...
  local p=$1
  shift
  mkdir -p "$SHARE/plasma-fusion/built-against"
  printf '%s\n' "$@" >"$SHARE/plasma-fusion/built-against/$p"
}
nobuilt() { rm -rf "$SHARE/plasma-fusion/built-against"; }

# 1. outside a session
record none
unset DBUS_SESSION_BUS_ADDRESS
run fork
has "1 the stock profile" "  profile: stock (the distribution's KWin)"
has "1 where the capabilities can be seen" "the running KWin's capabilities: run this in a terminal inside your Plasma session"
if [ -e "$T/busctl.calls" ]; then bad "1 nothing is asked of a bus outside a session"; else ok "1 nothing is asked of a bus outside a session"; fi

export DBUS_SESSION_BUS_ADDRESS=unix:path=$BASE/run/bus

# 2. stock KWin
run stock
has "2 the stock profile" "  profile: stock (the distribution's KWin)"
has "2 none of the fork's capabilities" "the running KWin's capabilities: none of the fork's (every feature uses its stock fallback)"
hasnot "2 no note" "note: this KWin advertises"
if [ "$(cat "$T/unloaded" 2>/dev/null)" = "$(cat "$T/nonce" 2>/dev/null)" ] && [ -s "$T/nonce" ]; then
  ok "2 the probe is unloaded again"
else
  bad "2 the probe is unloaded again"
fi
if compgen -G "$XDG_RUNTIME_DIR/plasma-fusion-probe-*" >/dev/null; then bad "2 the probe's file is gone"; else ok "2 the probe's file is gone"; fi

# 3. the fork, installed by hand
run fork
has "3 the stock profile" "  profile: stock (the distribution's KWin)"
has "3 the thumbnail lifecycle" "    thumbnail source lifecycle: version 1"
has "3 offscreen opacity" "    offscreen opacity: version 1"
has "3 the tiling facade" "    transient tiling (dynamic tiling): yes"
has "3 the fork without the profile is named" "note: this KWin advertises the fork's capabilities without the full profile (a fork installed by hand)"
hasnot "3 no note to log in again" "log out and in"

# 4. the full profile
record
run fork
has "4 the full profile with its pin and tag" "  profile: full (the maintained KWin fork, pinned at 6.8.2-3.fc44.pf3, fork tag v6.8.2-pf3)"
has "4 the capabilities" "    transient tiling (dynamic tiling): yes"
hasnot "4 no note about a fork by hand" "without the full profile"
hasnot "4 no note about another Plasma" "the full profile pins KWin"
hasnot "4 no note to log in again" "log out and in"

# 5. the full profile, the session still on the KWin from before
run stock
has "5 the full profile" "  profile: full (the maintained KWin fork, pinned at 6.8.2-3.fc44.pf3, fork tag v6.8.2-pf3)"
has "5 none advertised" "the running KWin's capabilities: none of the fork's"
has "5 the note to log in again" "log out and in (the session still runs the KWin from before the profile)"

# 6. the full profile under another Plasma
run fork 6.9.0
has "6 both versions are named" "note: the full profile pins KWin 6.8.2 and the running KWin is 6.9.0"
has "6 the way back" "install.sh --full-restore"

# 7. the probe's answer never reaches the journal
run silent
has "7 the thumbnail lifecycle could not be asked" "    thumbnail source lifecycle: could not be asked"
has "7 the tiling facade could not be asked" "    transient tiling (dynamic tiling): could not be asked"
has "7 the support information is still read" "    offscreen opacity: version 1"
hasnot "7 no note on an incomplete answer" "log out and in"

# 8. no KWin on the session bus
record none
run absent
has "8 as outside a session" "the running KWin's capabilities: run this in a terminal inside your Plasma session"

# 9. the probe
run fork
for word in 'import org.kde.kwin' WindowThumbnail plasmaFusionThumbnailSourceLifecycleVersion 'Workspace.transientTiling' "plasma-fusion-probe $(cat "$T/nonce")"; do
  if grep -qF -- "$word" "$T/probe.qml"; then ok "9 the probe has '$word'"; else bad "9 the probe has '$word'"; fi
done
if grep -qF 'supportInformation' "$T/busctl.calls"; then ok "9 the support information is asked"; else bad "9 the support information is asked"; fi

# 10. one compositor, several calls
run fork
has "10 a second call's probe is found" "    thumbnail source lifecycle: version 1"
run fork
has "10 a third call's probe is found" "    transient tiling (dynamic tiling): yes"
if [ "$(sort "$T/read-directories" | uniq -d | wc -l)" -eq 0 ] && [ "$(wc -l <"$T/read-directories")" -ge 8 ]; then
  ok "10 every probe had a directory of its own"
else
  bad "10 every probe had a directory of its own"
fi

# 11. after a restore, before the next login: the program on the disk is newer than the
# session's KWin, by more than the two seconds from which the times are certain to tell.
record none
sleep 2.2
chmod +x "$BIN/kwin_wayland"
run fork
has "11 the stock profile" "  profile: stock (the distribution's KWin)"
has "11 the capabilities of the KWin that still runs" "    offscreen opacity: version 1"
has "11 the note names the state" "note: the full profile is not installed and the running KWin still advertises the fork's capabilities:"
has "11 the note to log in again" "log out and in (the KWin on the disk was put there after this session's KWin started, as after --full-restore)"
hasnot "11 no note about a fork by hand" "a fork installed by hand"

# 12. a KWin whose start cannot be read
rm -f "$T/pid"
run fork
has "12 a fork installed by hand" "note: this KWin advertises the fork's capabilities without the full profile (a fork installed by hand)"
hasnot "12 no note to log in again" "log out and in"
echo 999999999 >"$T/pid"
run fork
has "12 no such process: a fork installed by hand" "(a fork installed by hand)"

# 13. the program first, KWin right after it, at 24 points across a second and a half
wrong=0
for _ in $(seq 1 24); do
  chmod +x "$BIN/kwin_wayland"
  sleep 30 &
  later=$!
  echo "$later" >"$T/pid"
  run fork
  kill "$later" 2>/dev/null || true
  if ! grep -qF "(a fork installed by hand)" <<<"$OUT" || grep -qF "log out and in" <<<"$OUT"; then
    wrong=$((wrong + 1))
  fi
  sleep 0.06
done
if [ "$wrong" = 0 ]; then
  ok "13 a program from just before KWin's start is never taken for a later one (24 starts)"
else
  bad "13 a program from just before KWin's start is never taken for a later one ($wrong of 24 starts were)"
fi
echo "$KWIN_PID" >"$T/pid"

# 14. no getconf: the first process again, older than the program by now
touch "$T/no-getconf"
run fork
has "14 the note to log in again without getconf" "log out and in (the KWin on the disk was put there after this session's KWin started"
rm -f "$T/no-getconf"

# 15. the full profile with the decoration record and the installed KDecoration at one version.
# KWin is the pin's older one; the record holds KDecoration's version, so the note (which compared
# with KWin) used to be permanent (#194).
record
nobuilt
dbev rpm
echo 6.8.3 >"$T/kdecoration-rpm"
built decoration kdecoration=6.8.3 qt=6.11.2
built navigation kwin=6.8.2 qt=6.11.2
run fork 6.8.2
hasnot "15 no decoration note when the installed KDecoration is the build's" "the decoration part was built against"
hasnot "15 no navigation note" "the navigation part was built against"

# 16. a decoration built against an older KDecoration than the installed one: the note says what it
# compares, and names the two KDecoration versions, not KWin's
built decoration kdecoration=6.8.2 qt=6.11.2
run fork 6.8.2
has "16 the decoration's rebuild note" "  note: the decoration part was built against 6.8.2, the installed KDecoration is 6.8.3: update or rebuild that package"
hasnot "16 the note is not about KWin" "KWin is"
hasnot "16 no navigation note" "the navigation part was built against"

# 17. the other databases the login check reads, upstream only as CMake recorded it: pacman's
# pkgver-pkgrel, dpkg's source package with its epoch and revision, Nix's store path name
rm -f "$T"/kdecoration-*
built decoration kdecoration=6.8.3 qt=6.11.2
dbev pacman
echo 6.8.3-1 >"$T/kdecoration-pacman"
run fork 6.8.2
hasnot "17 pacman: the revision does not count" "the decoration part was built against"
rm -f "$T/kdecoration-pacman"
dbev dpkg
echo 4:6.8.3-1 >"$T/kdecoration-dpkg"
run fork 6.8.2
hasnot "17 dpkg: the epoch and the revision do not count" "the decoration part was built against"
rm -f "$T/kdecoration-dpkg"
dbev nix
mkdir -p "$T/nixsw"
echo 6.8.3 >"$T/kdecoration-nix"
PF_NIX_SW=$T/nixsw run fork 6.8.2
hasnot "17 Nix: the store path's version counts" "the decoration part was built against"
echo 6.8.4 >"$T/kdecoration-nix"
PF_NIX_SW=$T/nixsw run fork 6.8.2
has "17 Nix: a newer installed KDecoration is named" "the installed KDecoration is 6.8.4"

# 18. the databases in the login check's order: rpm's answer is the one read, though pacman's is
# another version
rm -f "$T"/kdecoration-*
dbev rpm
mkdir -p "$ROOTFS/var/lib/pacman/local"; : >"$ROOTFS/var/lib/pacman/local/ALPM_DB_VERSION"
echo 6.8.3 >"$T/kdecoration-rpm"
echo 6.9.0 >"$T/kdecoration-pacman"
built decoration kdecoration=6.8.3 qt=6.11.2
run fork 6.8.2
hasnot "18 rpm's answer is the one read" "the decoration part was built against"

# 19. no database answers: no decoration note, though the record is older than the running KWin
rm -f "$T"/kdecoration-*
dbnone
nobuilt
built decoration kdecoration=6.8.2 qt=6.11.2
run fork 6.8.3
hasnot "19 no decoration note without an answer" "the decoration part was built against"

# 20. the stock profile: no note when the installed KDecoration is the build's - and none either
# when that older KDecoration is the installed one, though KWin is another version
record none
dbev rpm
built decoration kdecoration=6.8.3 qt=6.11.2
echo 6.8.3 >"$T/kdecoration-rpm"
run stock 6.8.3
hasnot "20 stock: no note when the installed KDecoration is the build's" "the decoration part was built against"
built decoration kdecoration=6.8.2 qt=6.11.2
echo 6.8.2 >"$T/kdecoration-rpm"
run stock 6.8.3
hasnot "20 stock: no note when it is the installed KDecoration, not KWin" "the decoration part was built against"

# 21. two installed versions of one source package: a partial upgrade leaves Debian's two binaries
# of it at different versions, or two Nix store paths. Whichever of them the record matches, the
# answer is ambiguous and there is no note - never one built on the database's first line.
rm -f "$T"/kdecoration-*
record
dbev dpkg
built decoration kdecoration=6.8.3 qt=6.11.2
printf '4:6.8.2-1\n4:6.8.3-1\n' >"$T/kdecoration-dpkg"
run fork 6.8.2
hasnot "21 two installed versions: no note, though the record matches one of them" "the decoration part was built against"
run fork 6.8.2
hasnot "21 and the same on a second run" "the decoration part was built against"
printf '4:6.8.3-1\n4:6.8.3-2\n' >"$T/kdecoration-dpkg"
built decoration kdecoration=6.8.3 qt=6.11.2
run fork 6.8.2
hasnot "21 one version in two revisions is one version" "the decoration part was built against"

# 22. NixOS without nix-store on the PATH: the login check falls back to the system profile's own
# binary, and the note is built on its answer (PF_NIX_SW names the profile here)
rm -f "$T"/kdecoration-*
dbev nix
mkdir -p "$T/nixsw/bin"
cp "$BIN/nix-store" "$T/nixsw/bin/nix-store"
rm -f "$BIN/nix-store"
echo 6.8.4 >"$T/kdecoration-nix"
built decoration kdecoration=6.8.3 qt=6.11.2
PF_NIX_SW=$T/nixsw run fork 6.8.2
has "22 the system profile's nix-store answers" "the installed KDecoration is 6.8.4"
rm -rf "$T/nixsw"

# 23. a database that does not answer in time: a locked or wedged one leaves the version unknown
# after the bounded query, and status finishes (the login check bounds its own the same way)
rm -f "$T"/kdecoration-*
dbev rpm
cat >"$BIN/nix-store" <<'EOF'
#!/bin/bash
v=$(cat "$T/kdecoration-nix" 2>/dev/null) || exit 1
printf '/nix/store/00000000000000000000000000000000-kdecoration-%s\n' "$v"
EOF
chmod +x "$BIN/nix-store"
echo 6.8.3 >"$T/kdecoration-rpm"
built decoration kdecoration=6.8.2 qt=6.11.2
touch "$T/hang-rpm"
started=$SECONDS
run fork 6.8.2
elapsed=$((SECONDS - started))
rm -f "$T/hang-rpm"
hasnot "23 a database that does not answer gives no note" "the decoration part was built against"
[ "$elapsed" -le 6 ] && ok "23 and status finishes ($elapsed s, bounded)" || bad "23 status took ${elapsed} s with a wedged database"

# 24. the system's database does not answer while a foreign package manager's files are there: the
# login check asks the first database present and no other, so a wedged rpm is an unknown - not
# pacman's KDecoration, which describes a different installation (a false note would name it)
rm -f "$T"/kdecoration-*
record
dbev rpm
mkdir -p "$ROOTFS/var/lib/pacman/local"; : >"$ROOTFS/var/lib/pacman/local/ALPM_DB_VERSION"
echo 6.8.3 >"$T/kdecoration-rpm"
echo 6.9.0 >"$T/kdecoration-pacman"
built decoration kdecoration=6.8.3 qt=6.11.2
touch "$T/hang-rpm"
run fork 6.8.2
rm -f "$T/hang-rpm"
hasnot "24 no note from a foreign database while the system's fails" "the decoration part was built against"
dbev rpm
echo 6.8.3 >"$T/kdecoration-rpm"
rm -f "$T/kdecoration-pacman"
run fork 6.8.2
hasnot "24 and the system's own answer is the one read" "the decoration part was built against"

echo "status-unit: $PASS passed, $FAIL failed"
[ "$FAIL" -eq 0 ]
