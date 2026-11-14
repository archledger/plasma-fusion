#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# fulltest.sh NAME [fresh|switch]: the full profile's release test in one Fedora VM (ADR 0001's
# verification, docs/full-profile.md), a fresh overlay of its provisioned base. The installer is
# this tree's, stamped as a release stamps it (packaging/stamp-installer.sh --full-fedora), and
# the packages are the full Copr project's own builds - the fork tag's KWin and the metapackage:
# the installer knows no other place for the fork, so the project must carry them first.
#
#   fresh (default)  a system without Plasma Fusion: install.sh --full (the plan, the packages,
#                    the lock, the record, the setup), a new login (status, the login check, both
#                    gated features and the tiler on the fork, no crash), --full-restore (the
#                    stock KWin again, the six packages kept), a new login (status, the features'
#                    fallbacks on stock KWin, no crash), then uninstall.
#   switch           the stock profile first - the published installer and the public Copr
#                    project (lane-env.sh) - then install.sh --full on top of it (the six
#                    packages move to the full project's builds; the setup is updated, not
#                    redone), the same checks on the fork, and uninstall on the full system,
#                    which returns the stock KWin before it removes the packages.
#
# The gated features (ADR 0001): the switcher's thumbnails (plasmaFusionThumbnailSourceLifecycle-
# Version: a hidden card lets go of its window; on stock it keeps it) and the navigation effect
# (plasmaFusionOffscreenOpacityVersion: it runs; on stock it stays idle and says so). What each
# one does with the property is the subject of the parts' own tests; here the session shows that
# the fork advertises them, that the features run on it and that they still work, by their
# fallbacks, on stock KWin with the same packages.
#
# PF_PUBLIC=1: after a release, the published installer for --full too. Results:
# ~/pf-vm/results/NAME-full/ (switch: NAME-full-switch/).
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd)
ROOT=$(cd "$HERE/../../.." && pwd)
# C and lane: for lane-env.sh (the published installer, in the Copr lane's way)
# shellcheck disable=SC2034
H=${PF_VM_HOME:-$HOME/pf-vm} C=${PF_REL:-$HOME/pf-rel}/channels
# shellcheck disable=SC2034
name=$1 mode=${2:-fresh} lane=copr
case $mode in
  fresh) OUT=$H/results/$name-full ;;
  switch) OUT=$H/results/$name-full-switch ;;
  *) echo "usage: fulltest.sh NAME [fresh|switch]" >&2; exit 2 ;;
esac
rm -rf "$OUT" && mkdir -p "$OUT"
SIX="plasma-fusion plasma-fusion-decoration plasma-fusion-settings plasma-fusion-navigation"
SIX="$SIX plasma-fusion-quicklook plasma-fusion-copytext"
KWIN="kwin kwin-common kwin-libs"
vm() { bash "$HERE/vm.sh" "$@"; }
log() { printf '%s %s\n' "$(date -u +%H:%M:%S)" "$*" | tee -a "$OUT/steps.log"; }
cleanup_vm() {
  local status=$1 disk=$H/vms/$name/run.qcow2
  trap - EXIT
  vm stop "$name" >/dev/null || { log "FAIL: could not stop the VM during cleanup"; exit 1; }
  if [ -f "$disk" ]; then
    if [ "$status" = 0 ]; then
      rm -f "$disk"
    else
      local saved
      saved=$H/vms/$name/failed-full-run-$(date -u +%Y%m%dT%H%M%S)-$$.qcow2
      mv "$disk" "$saved" || { log "FAIL: could not preserve failed overlay"; exit 1; }
      log "failed overlay preserved: $saved"
    fi
  fi
  [ "$status" != 0 ] || log "done $name (full profile, $mode)"
  exit "$status"
}
# insession CMD: run CMD as pf with the environment of pf's plasmashell (the tty1 session).
insession() {
  vm ssh "$name" "pid=\$(pgrep -u pf -x plasmashell | head -n 1); [ -n \"\$pid\" ] || { echo 'no plasmashell'; exit 97; }
    while IFS= read -r -d '' kv; do case \${kv%%=*} in
      DBUS_SESSION_BUS_ADDRESS|XDG_RUNTIME_DIR|WAYLAND_DISPLAY|DISPLAY|XDG_CURRENT_DESKTOP|XDG_SESSION_TYPE|XDG_SESSION_DESKTOP|KDE_SESSION_VERSION|KDE_FULL_SESSION|XDG_DATA_DIRS|XDG_CONFIG_DIRS|QT_QPA_PLATFORM|XAUTHORITY|PATH|LANG) export \"\$kv\" ;;
    esac; done < /proc/\$pid/environ
    $1"
}
guest() { insession "bash ~/full-guest.sh $*"; }
wait_plasma() { # wait for a settled desktop
  local _
  for _ in $(seq 1 60); do
    vm ssh "$name" 'pgrep -u pf -x plasmashell >/dev/null' && break
    sleep 5
  done
  sleep 25
  # Plasma's welcome app opens on a first login; it would cover the desktop in the screenshots.
  vm ssh "$name" 'for p in $(pgrep -u pf -x plasma-welcome); do kill "$p"; done' 2>/dev/null || true
  sleep 3
}
# The VM's session on tty1 (loginctl list-sessions has no TTY column in every systemd version).
TTY1='tty1_session() { for s in $(loginctl list-sessions --no-legend | awk "{print \$1}"); do [ "$(loginctl show-session "$s" -p TTY --value)" = tty1 ] && [ "$(loginctl show-session "$s" -p State --value)" != closing ] && echo "$s"; done; }; '
# Log out the way the logout dialog does, as the installer asks ("Log out and back in once"):
# getty logs pf in on tty1 again, and the new Plasma session starts the KWin now installed.
relogin() {
  local before now='' _
  before=$(vm ssh "$name" "$TTY1 tty1_session")
  insession "busctl --user call org.kde.Shutdown /Shutdown org.kde.Shutdown logout" >/dev/null 2>&1 || true
  for _ in $(seq 1 40); do
    sleep 3
    now=$(vm ssh "$name" "$TTY1 tty1_session" 2>/dev/null)
    [ -n "$now" ] && [ "$now" != "$before" ] && break
  done
  log "relogin: session $before -> ${now:-none}"
  wait_plasma
}
shot() { vm shot "$name" "$OUT/$1.png" >/dev/null && log "screenshot $1"; }

# ---------- checks: every one is logged, a phase fails at its end with all of them known ----------
bad=0
want() { # WHAT GOT EXPECTED
  if [ "$2" = "$3" ]; then
    log "  ok   $1: ${2:-(none)}"
  else
    log "  FAIL $1: '$2', expected '$3'"
    bad=1
  fi
}
same() { # WHAT FILE FILE: the two files say the same
  if cmp -s "$OUT/$2" "$OUT/$3"; then log "  ok   $1"; else log "  FAIL $1 ($2 and $3 differ)"; bad=1; fi
}
has() { # WHAT FILE PATTERN: the file has a line that matches (grep -E)
  if grep -a -q -E -- "$3" "$OUT/$2"; then log "  ok   $1"; else log "  FAIL $1 (no such line in $2)"; bad=1; fi
}
hasnot() { # WHAT FILE PATTERN: no line of the file matches
  if grep -a -q -E -- "$3" "$OUT/$2"; then
    log "  FAIL $1 (in $2: $(grep -a -m 1 -E -- "$3" "$OUT/$2" | cut -c1-120))"
    bad=1
  else
    log "  ok   $1"
  fi
}
phase() { [ "$bad" = 0 ] || { log "FAIL: $1"; exit 1; }; }
facts() { vm ssh "$name" 'bash ~/full-guest.sh facts' >"$OUT/$1" 2>&1 || { log "FAIL: could not read the package facts ($1)"; exit 1; }; }
fact() { # FILE KEY [NAME]: "pin EVR" -> EVR; "pkg kwin EVR" -> EVR
  awk -v k="$2" -v n="${3:-}" '$1 == k && (n == "" || $2 == n) { print (n == "" ? $2 : $3); exit }' "$OUT/$1"
}
crashes() { # WHEN: this boot's crashes; a collector that cannot say is not zero crashes
  local n
  n=$(vm ssh "$name" 'python3 -' <"$HERE/crash-count.py") || { log "FAIL: crash collector unavailable or failed"; exit 1; }
  want "crashes $1" "$n" 0
}
is_fork() { case $1 in *.pf[0-9]*) return 0 ;; esac; return 1; }

# The package side of the full profile. FILE: facts; the stock KWin it replaced: STOCK[].
declare -A STOCK
check_full_packages() {
  local f=$1 pin meta p
  pin=$(fact "$f" pin) meta=$(fact "$f" pkg plasma-fusion-full)
  if is_fork "$pin"; then
    log "  ok   the metapackage's record names the pin: $pin (fork tag $(fact "$f" tag))"
  else
    log "  FAIL the metapackage's record names no fork pin: '$pin'"
    bad=1
  fi
  if [ -n "$meta" ] && [ "$meta" != none ]; then
    log "  ok   plasma-fusion-full: $meta"
  else
    log "  FAIL plasma-fusion-full is not installed"
    bad=1
  fi
  for p in $KWIN; do
    want "$p is the pinned fork" "$(fact "$f" pkg "$p")" "$pin"
    want "$p is locked at the pin" "$(fact "$f" lock "$p")" "$pin"
    want "the restore record keeps the stock $p" "$(fact "$f" record "$p")" "${STOCK[$p]}"
  done
  for p in $SIX; do want "$p is the metapackage's build" "$(fact "$f" pkg "$p")" "$meta"; done
  want "the full profile's repository is enabled" "$(fact "$f" repo)" yes
}
# The package side after the way back. FILE: facts; SIX_EVR: what the six packages must be
# (none after an uninstall).
check_stock_packages() {
  local f=$1 six=$2 p
  for p in $KWIN; do
    want "$p is the recorded stock one" "$(fact "$f" pkg "$p")" "${STOCK[$p]}"
    want "$p is not locked" "$(fact "$f" lock "$p")" ""
  done
  want "plasma-fusion-full is gone" "$(fact "$f" pkg plasma-fusion-full)" none
  want "the full profile's repository is gone" "$(fact "$f" repo)" no
  want "the restore record is gone" "$(fact "$f" recordfile)" no
  for p in $SIX; do want "$p" "$(fact "$f" pkg "$p")" "$six"; done
}
# The switcher, held open by a real Alt (a shortcut called over the bus shows none): three
# windows, the cards on the screen, and another window in front once Alt is released.
switcher() { # PREFIX
  local before after
  guest windows >"$OUT/$1-windows.log" 2>&1 || { log "FAIL: the test windows did not open"; exit 1; }
  before=$(guest active) || { log "FAIL: KWin did not name the active window"; exit 1; }
  python3 "$HERE/vm-keys.py" "$H/vms/$name/qmp.sock" down:alt tap:tab sleep:2 "shot:$OUT/$1-switcher.png" up:alt sleep:2 \
    >"$OUT/$1-keys.log" 2>&1 || { log "FAIL: the keys for the switcher ($(tail -n 1 "$OUT/$1-keys.log"))"; exit 1; }
  log "screenshot $1-switcher"
  after=$(guest active) || { log "FAIL: KWin did not name the active window"; exit 1; }
  if [ -n "$after" ] && [ "$after" != none ] && [ "$after" != "$before" ]; then
    log "  ok   the switcher went from $before to $after"
  else
    log "  FAIL the switcher did not switch (before: $before, after: $after)"
    bad=1
  fi
}
# The tiler's shortcut twice, with one of the test windows active, and what KWin's journal has
# of it since: on the fork a session and its end, on stock the script's own refusal.
tiler() { # PREFIX
  local since
  since=$(vm ssh "$name" 'date +%s') || { log "FAIL: the VM's clock"; exit 1; }
  guest tile || { log "FAIL: the tiler's shortcut could not be called"; exit 1; }
  sleep 4
  shot "$1-tiler"
  guest tile
  sleep 4
  vm ssh "$name" "journalctl --user --no-pager -o cat --since @$since _COMM=kwin_wayland | grep -a 'plasmafusion-placement: tiling'" \
    >"$OUT/$1-tiler.log" 2>&1
}
status() { # FILE
  local rc=0
  insession "plasma-fusion status" >"$OUT/$1" 2>&1 || rc=$?
  [ "$rc" = 0 ] || { log "FAIL: plasma-fusion status (rc=$rc, $1)"; exit 1; }
}
# The published installer, fetched in the VM as a user fetches it (lane-env.sh, the public way).
published() { # TARGET in the VM's home
  vm ssh "$name" 'rm -f ~/install.sh' || return 1
  # shellcheck source=tools/tests/release-vm/lane-env.sh
  (PF_PUBLIC=1 && . "$HERE/lane-env.sh" && lane_installer) || return 1
  vm ssh "$name" 'test -s ~/install.sh' || return 1
  [ "$1" = install.sh ] || vm ssh "$name" "mv ~/install.sh ~/$1"
}

# ---------- the VM ----------
log "start $name (full profile, $mode)"
if [ "${PF_PUBLIC:-}" != 1 ]; then
  "$ROOT/packaging/stamp-installer.sh" --copr "${PF_COPR_FEDORA:-44 45}" --ppa "${PF_PPA_SERIES:-stonking}" \
    --deb "${PF_DEB_TARGETS:-neon testing}" --full-fedora "${PF_FULL_FEDORA:-44}" "$OUT/install.sh" >"$OUT/00-stamp.log" 2>&1 ||
    { log "FAIL: could not stamp the installer"; exit 1; }
fi
vm start "$name" run >/dev/null || { log "FAIL: the VM did not start"; exit 1; }
trap 'cleanup_vm $?' EXIT
vm wait "$name" >/dev/null || { log "FAIL: the VM did not come up"; exit 1; }
vm ssh "$name" 'cat >~/full-guest.sh' <"$HERE/full-guest.sh" || { log "FAIL: could not copy the guest's script into the VM"; exit 1; }
# No dimming, screen off or suspend in the test sessions (from the next login on).
vm ssh "$name" 'mkdir -p ~/.config && printf "[AC][Display]\nDimDisplayWhenIdle=false\nTurnOffDisplayWhenIdle=false\n\n[AC][SuspendAndShutdown]\nAutoSuspendAction=0\n" >~/.config/powerdevilrc'
wait_plasma
shot 01-stock
facts 01-facts.txt
vm ssh "$name" 'grep -E "^(PRETTY_NAME|VERSION_ID)=" /etc/os-release; rpm -q plasma-workspace; grep -h LookAndFeelPackage ~/.config/kdeglobals' >"$OUT/01-system.txt" 2>&1
log "system: $(tr '\n' ' ' <"$OUT/01-system.txt")"
for p in $KWIN; do
  STOCK[$p]=$(fact 01-facts.txt pkg "$p")
  if [ -z "${STOCK[$p]}" ] || [ "${STOCK[$p]}" = none ] || is_fork "${STOCK[$p]}"; then
    log "  FAIL $p at the start is not a stock package: '${STOCK[$p]}'"
    bad=1
  else
    log "  ok   $p at the start: ${STOCK[$p]}"
  fi
done
want "no full profile at the start" "$(fact 01-facts.txt pkg plasma-fusion-full) $(fact 01-facts.txt repo) $(fact 01-facts.txt recordfile)" "none no no"
want "no Plasma Fusion at the start" "$(fact 01-facts.txt pkg plasma-fusion)" none
phase "the VM's base is not a stock system without Plasma Fusion"
before=01-facts.txt

# ---------- switch: the stock profile first, as it is published ----------
if [ "$mode" = switch ]; then
  log "stock profile: the published installer"
  published install-stock.sh || { log "FAIL: could not fetch the published installer"; exit 1; }
  insession "sh ~/install-stock.sh --yes" >"$OUT/05-stock-install.log" 2>&1
  rc=$?
  log "  rc=$rc"
  [ "$rc" = 0 ] || { log "FAIL: the stock profile's install"; tail -n 30 "$OUT/05-stock-install.log"; exit "$rc"; }
  relogin
  shot 06-stock-profile
  status 06-stock-status.log
  log "status: $(head -n 1 "$OUT/06-stock-status.log")"
  facts 06-facts.txt
  for p in $KWIN; do want "$p is untouched by the stock profile" "$(fact 06-facts.txt pkg "$p")" "${STOCK[$p]}"; done
  want "no full profile on the stock profile" "$(fact 06-facts.txt pkg plasma-fusion-full) $(fact 06-facts.txt repo) $(fact 06-facts.txt recordfile)" "none no no"
  crashes "on the stock profile"
  phase "the stock profile before the switch"
  before=06-facts.txt
fi

# ---------- install.sh --full ----------
if [ "${PF_PUBLIC:-}" = 1 ]; then
  published install.sh || { log "FAIL: could not fetch the published installer"; exit 1; }
else
  vm ssh "$name" 'cat >~/install.sh' <"$OUT/install.sh" || { log "FAIL: could not copy the installer into the VM"; exit 1; }
  log "installer: this tree's, $(grep -m 1 '^PF_VERSION=' "$OUT/install.sh") $(grep -m 1 '^PF_FULL_FEDORA=' "$OUT/install.sh")"
fi
log "installer: --full --dry-run"
insession "sh ~/install.sh --full --dry-run" >"$OUT/10-dry-run.log" 2>&1
rc=$?
log "  rc=$rc $(grep -c . "$OUT/10-dry-run.log") lines"
[ "$rc" = 0 ] || { log "FAIL: dry run"; exit "$rc"; }
has "the plan records the stock KWin" 10-dry-run.log 'full-restore\.txt'
has "the plan enables the full profile's repository" 10-dry-run.log 'dnf -y copr enable archledger/plasma-fusion-full'
has "the plan names the packages it replaces" 10-dry-run.log 'dnf -y install plasma-fusion-full .*replaces the stock KWin'
has "the plan locks the set" 10-dry-run.log 'dnf -y versionlock add kwin kwin-common kwin-libs'
has "the plan states the security cadence" 10-dry-run.log 'security fixes on its weekly cadence'
facts 10-facts.txt
same "the dry run changed nothing" 10-facts.txt "$before"
phase "the dry run"

log "installer: --full"
insession "sh ~/install.sh --full --yes" >"$OUT/11-install.log" 2>&1
rc=$?
log "  rc=$rc"
[ "$rc" = 0 ] || { log "FAIL: install --full"; tail -n 30 "$OUT/11-install.log"; exit "$rc"; }
facts 12-facts.txt
check_full_packages 12-facts.txt
# The set holds against the distribution's own packages: with the full profile's repository
# out of the question, a sync to what Fedora offers finds nothing it may do.
vm ssh "$name" "sudo dnf -q --assumeno --disablerepo='copr:*plasma-fusion-full*' distro-sync $KWIN" >"$OUT/12-lock-holds.log" 2>&1
has "a sync to the distribution's KWin finds nothing to do" 12-lock-holds.log '^Nothing to do'
# Before the new login the session still runs the KWin from before: status says so.
status 13-status-before-login.log
has "status: the full profile, its pin and tag" 13-status-before-login.log "profile: full \(the maintained KWin fork, pinned at $(fact 12-facts.txt pin), fork tag $(fact 12-facts.txt tag)\)"
has "status: the running KWin is still the one from before" 13-status-before-login.log 'log out and in'
shot 13-after-setup
phase "the full profile's packages"

relogin
shot 20-full-desktop
status 21-status.log
has "status: the full profile" 21-status.log "profile: full \(the maintained KWin fork, pinned at $(fact 12-facts.txt pin), fork tag $(fact 12-facts.txt tag)\)"
has "status: thumbnail source lifecycle, version 1" 21-status.log 'thumbnail source lifecycle: version 1'
has "status: offscreen opacity, version 1" 21-status.log 'offscreen opacity: version 1'
has "status: transient tiling" 21-status.log 'transient tiling \(dynamic tiling\): yes'
hasnot "status: no note about another KWin" 21-status.log 'log out and in|restore the stock KWin'
has "the login check switched nothing off" 21-status.log 'switched off: nothing'
phase "status on the full profile"

log "the gated features on the fork"
guest gesturelock
guest kwinlog >"$OUT/22-kwin.log" 2>&1
hasnot "navigation: the effect is not idle" 22-kwin.log 'plasmafusion-navigation: .*the effect stays idle'
has "navigation: the effect follows the gesture lock (on)" 22-kwin.log 'plasmafusion-navigation: gesture lock on'
has "navigation: the effect follows the gesture lock (off)" 22-kwin.log 'plasmafusion-navigation: gesture lock off'
switcher 23-full
tiler 24-full
has "the tiler: a session on the fork" 24-full-tiler.log 'tiling: on \('
has "the tiler: and its end" 24-full-tiler.log 'tiling: off'
guest close
guest kwinlog >"$OUT/25-kwin.log" 2>&1
hasnot "no script error in KWin" 25-kwin.log 'TypeError|ReferenceError|SyntaxError'
vm ssh "$name" 'tail -n 5 ~/.local/state/plasma-fusion/gate.log' >"$OUT/26-gate.log" 2>&1
crashes "on the full profile"
phase "the full profile's session"

# ---------- the way back ----------
if [ "$mode" = fresh ]; then
  log "installer: --full-restore --dry-run"
  insession "sh ~/install.sh --full-restore --dry-run" >"$OUT/30-restore-dry-run.log" 2>&1
  rc=$?
  log "  rc=$rc"
  [ "$rc" = 0 ] || { log "FAIL: --full-restore dry run"; exit "$rc"; }
  has "the plan names the recorded stock KWin" 30-restore-dry-run.log "kwin=${STOCK[kwin]}"
  facts 30-facts.txt
  same "the dry run changed nothing" 30-facts.txt 12-facts.txt
  log "installer: --full-restore"
  insession "sh ~/install.sh --full-restore --yes" >"$OUT/31-restore.log" 2>&1
  rc=$?
  log "  rc=$rc"
  [ "$rc" = 0 ] || { log "FAIL: --full-restore"; tail -n 30 "$OUT/31-restore.log"; exit "$rc"; }
  facts 32-facts.txt
  check_stock_packages 32-facts.txt "$(fact 12-facts.txt pkg plasma-fusion-full)"
  # Before the new login the session still runs the fork: status says so, and does not take
  # it for a fork installed by hand.
  status 33-status-before-login.log
  has "status: the stock profile, before the new login too" 33-status-before-login.log 'profile: stock \(the distribution.s KWin\)'
  has "status: the running KWin is still the fork from before" 33-status-before-login.log 'log out and in \(the session still runs the KWin from before the restore\)'
  hasnot "status: not taken for a fork installed by hand" 33-status-before-login.log 'a fork installed by hand'
  phase "the stock KWin after --full-restore"

  relogin
  shot 40-restored-desktop
  status 41-status.log
  has "status: the stock profile" 41-status.log 'profile: stock \(the distribution.s KWin\)'
  has "status: none of the fork's capabilities" 41-status.log "capabilities: none of the fork's \(every feature uses its stock fallback\)"
  hasnot "status: no note about another KWin" 41-status.log 'log out and in|a fork installed by hand'
  has "the login check switched nothing off" 41-status.log 'switched off: nothing'
  vm ssh "$name" 'grep -h LookAndFeelPackage ~/.config/kdeglobals' >"$OUT/41-theme.txt" 2>&1
  has "the session is still Plasma Fusion's" 41-theme.txt 'org\.plasmafusion\.'
  phase "status after the restore"

  log "the features' fallbacks on stock KWin"
  guest gesturelock
  guest kwinlog >"$OUT/42-kwin.log" 2>&1
  has "navigation: the effect stays idle and says why" 42-kwin.log 'plasmafusion-navigation: compositor lacks offscreen opacity capability version 1; the effect stays idle'
  hasnot "navigation: nothing follows the gesture lock" 42-kwin.log 'plasmafusion-navigation: gesture lock'
  switcher 43-stock
  tiler 44-stock
  has "the tiler: refused, it needs the fork" 44-stock-tiler.log 'tiling: the native facade is not available; the tiler needs the fork'
  hasnot "the tiler: no session on stock KWin" 44-stock-tiler.log 'tiling: on \('
  guest close
  guest kwinlog >"$OUT/45-kwin.log" 2>&1
  hasnot "no script error in KWin" 45-kwin.log 'TypeError|ReferenceError|SyntaxError'
  crashes "after the restore"
  phase "Plasma Fusion on stock KWin after the restore"
fi

log "installer: uninstall"
insession "sh ~/install.sh uninstall --yes" >"$OUT/50-uninstall.log" 2>&1
rc=$?
log "  rc=$rc"
[ "$rc" = 0 ] || { log "FAIL: uninstall"; tail -n 30 "$OUT/50-uninstall.log"; exit "$rc"; }
facts 51-facts.txt
check_stock_packages 51-facts.txt none
relogin
shot 52-after-uninstall
vm ssh "$name" 'grep -h LookAndFeelPackage ~/.config/kdeglobals' >"$OUT/52-theme.txt" 2>&1
hasnot "the previous desktop is back" 52-theme.txt 'org\.plasmafusion\.'
crashes "after the uninstall"
phase "the uninstall"
