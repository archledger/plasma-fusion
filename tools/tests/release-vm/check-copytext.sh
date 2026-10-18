#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Copy text's own selection on the VM's KWin (plasma-fusion-copytext, docs/parts/copytext-cpp.md),
# run by vmtest.sh in the new Plasma session after the install: Start() on the session bus starts
# the overlay (D-Bus activation), which takes a picture of every screen through KWin's ScreenShot2
# (allowed by its desktop file) and shows them. Passes when the overlay logs "shown in"; fails on
# KWin's refusal ("no picture of"), on no answer to Start() and when nothing shows in 20 s. The
# overlay is then ended by the PID the bus names (not pkill -f: the pattern would match this shell).
# The 0.6.0 release tests ran it on all eight systems (2026-10-18).
set -u
kwin=$(kwin_wayland --version 2>/dev/null || echo "kwin ?")
since=$(date '+%Y-%m-%d %H:%M:%S')
busctl --user call org.plasmafusion.CopyTextOverlay / org.plasmafusion.CopyTextOverlay Start ||
  { echo "FAIL: Start() not answered ($kwin)"; exit 1; }
out=
for _ in $(seq 1 40); do
  # The user's journal, and the system journal for this user where there is no per-user one
  # (Debian and Ubuntu keep none by default).
  out=$({ journalctl --user --since "$since" --no-pager -o cat 2>/dev/null
    sudo -n journalctl --since "$since" --no-pager -o cat "_UID=$(id -u)" 2>/dev/null; } |
    grep "copytext-overlay:" | sort -u || true)
  case $out in *"shown in"* | *"no picture"*) break ;; esac
  sleep 0.5
done
printf '%s\n' "$out"
pid=$(busctl --user call org.freedesktop.DBus /org/freedesktop/DBus org.freedesktop.DBus \
  GetConnectionUnixProcessID s org.plasmafusion.CopyTextOverlay 2>/dev/null | awk '{print $2}')
echo "overlay pid ${pid:-?}: $(readlink "/proc/${pid:-0}/exe" 2>/dev/null)"
[ -z "$pid" ] || kill "$pid"
case $out in
  *"no picture"*) echo "FAIL: KWin gave the overlay no pictures ($kwin)"; exit 1 ;;
  *"shown in"*) echo "overlay shown on $kwin: $(printf '%s\n' "$out" | grep -o 'shown in [0-9]* ms' | head -n 1)" ;;
  *) echo "FAIL: the overlay did not show ($kwin)"; exit 1 ;;
esac
