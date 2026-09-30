#!/bin/bash
# Laptop side: seed a virtual session's HOME on the ThinkPad, run a scenario, fetch the results.
#
#   remote.sh NAME SCENARIO [SEED_HOME_DIR|-] [WIDTHxHEIGHT] [TIMEOUT]
#
# SEED_HOME_DIR is copied over the session HOME (for example a staged ~/.local/share and ~/.config).
# Use '-' to keep the HOME from the previous run of NAME. Results land in ./vsession-out/NAME/.
# PFV_SCALE and PFV_OUTPUTS in the environment are passed on (see vsession.sh).
# The session directory on the host is deleted after the results are fetched; set PFV_KEEP=1 on a
# run whose HOME the next run reuses with '-'.
# PFV_TABLET, PFV_ANIM, PFV_FONT_PT, PFV_LANGUAGE, PFV_SHELL, PFV_CWD, PFV_KDE_PROFILE,
# PFV_XWAYLAND and PFV_LOCK are passed on when set.
# Before the run it checks free space on the host: at least PFV_MIN_FREE_MB (default 2048) MiB in
# /var/tmp and PFV_MIN_TMP_MB (default 256) MiB in /tmp, and PFV_MIN_INODES_PCT (default 10) % free
# inodes on each where the file system counts them; and the host user's inotify use: it refuses
# (exit 75) while the user's inotify instances or watches are above PFV_INOTIFY_MAX_PCT (default
# 75) % of fs.inotify.max_user_instances / max_user_watches (every private session adds about 20
# instances next to the logged-in session's 45; at the limit the real session's file watching
# fails). PFV_NO_GUARD=1 skips these checks. Locally the results need PFV_MIN_LOCAL_MB (default
# 512) MiB. PFV_SSH_OPTS adds ssh options (for example "-o ConnectTimeout=40") to every ssh, scp
# and rsync call.
#
# Session slots: run every call under the laptop's slot lock, build/lead/vslot.sh (N slots in
# build/locks/slots; --exclusive for performance measurements), for example
#   build/lead/vslot.sh tools/vsession/remote.sh NAME SCENARIO SEED 1920x1200 300
# The drivers in tools/tests do this themselves (tools/tests/lib/common.sh, pf_slot). This script
# takes no lock of its own.
# Exit status: 0 the session ran and the results were fetched, 75 the host is too busy (inotify),
# 1 anything else.
set -u
NAME=${1:?name}; SCENARIO=${2:?scenario}; SEED=${3:--}; SIZE=${4:-1440x900}; TMO=${5:-240}
HOST=${PFV_HOST:-thinkpad-fedora}
HERE=$(cd "$(dirname "$0")" && pwd)
BASE=/var/tmp
R=$BASE/pfv-$NAME
SSH_OPTS=(); RSYNC_E=()
if [ -n "${PFV_SSH_OPTS:-}" ]; then
  read -r -a SSH_OPTS <<<"$PFV_SSH_OPTS"
  RSYNC_E=(-e "ssh $PFV_SSH_OPTS")
fi
# Free space and inodes: a full /tmp or /var/tmp on the host also hurts the logged-in session.
if [ "${PFV_NO_GUARD:-0}" != 1 ]; then
  local_kb=$(df -Pk . | awk 'NR==2{print $4}')
  if [ "${local_kb:-0}" -lt $(( ${PFV_MIN_LOCAL_MB:-512} * 1024 )) ]; then
    echo "remote.sh: only $(( ${local_kb:-0} / 1024 )) MiB free here for the results; not starting" >&2
    exit 1
  fi
  ssh -o BatchMode=yes "${SSH_OPTS[@]}" "$HOST" "bash -s $BASE ${PFV_MIN_FREE_MB:-2048} ${PFV_MIN_TMP_MB:-256} ${PFV_MIN_INODES_PCT:-10} ${PFV_INOTIFY_MAX_PCT:-75} && mkdir -p $R/home" <<'GUARD'
check() {  # DIR MIN_MIB MIN_FREE_INODES_PERCENT
  local kb itot ifree
  kb=$(df -Pk "$1" | awk 'NR==2{print $4}')
  read -r itot ifree < <(df -Pi "$1" | awk 'NR==2{print $2, $4}')
  if [ "${kb:-0}" -lt $(( $2 * 1024 )) ]; then
    echo "remote.sh: $1 on $(hostname) has $(( ${kb:-0} / 1024 )) MiB free (less than $2); not starting" >&2
    return 1
  fi
  case "$itot" in ''|*[!0-9]*|0) return 0 ;; esac  # btrfs does not count inodes
  if [ $(( ifree * 100 / itot )) -lt "$3" ]; then
    echo "remote.sh: $1 on $(hostname) has $ifree of $itot inodes free; not starting" >&2
    return 1
  fi
}
# inotify: instances (inotify descriptors) and watches of this user's processes (the ones this
# user can read; KWin, whose /proc entries are private, holds none).
inotify() {  # MAX_PERCENT
  local fds n w=0 lim_n lim_w
  mapfile -t fds < <(find /proc/[0-9]*/fd -maxdepth 1 -lname anon_inode:inotify 2>/dev/null)
  n=${#fds[@]}
  [ "$n" -gt 0 ] && w=$(printf '%s\n' "${fds[@]}" | sed 's|/fd/|/fdinfo/|' | xargs cat 2>/dev/null | grep -c '^inotify wd')
  lim_n=$(cat /proc/sys/fs/inotify/max_user_instances); lim_w=$(cat /proc/sys/fs/inotify/max_user_watches)
  if [ $((n * 100)) -gt $((lim_n * $1)) ] || [ $((w * 100)) -gt $((lim_w * $1)) ]; then
    echo "remote.sh: $(id -un) on $(hostname) uses $n of $lim_n inotify instances and $w of $lim_w watches (more than $1 %); not starting" >&2
    return 75
  fi
}
check "$1" "$2" "$4" && check /tmp "$3" "$4" || exit 1
inotify "$5"
GUARD
  rc=$?
  [ "$rc" = 0 ] || exit $((rc == 75 ? 75 : 1))
else
  ssh -o BatchMode=yes "${SSH_OPTS[@]}" "$HOST" "mkdir -p $R/home" || exit 1
fi
if [ "$SEED" != - ]; then
  rsync -a --delete "${RSYNC_E[@]}" "$SEED"/ "$HOST:$R/home/" || exit 1
fi
scp -q "${SSH_OPTS[@]}" "$HERE/vsession.sh" "$HOST:$R.vsession.sh" && scp -q "${SSH_OPTS[@]}" "$SCENARIO" "$HOST:$R.scenario.sh" \
  && scp -q "${SSH_OPTS[@]}" "$HERE/pfinput.py" "$HOST:$R.pfinput.py" || exit 1
# Optional switches of vsession.sh, passed on only when set.
OPTS=
for v in PFV_TABLET PFV_ANIM PFV_FONT_PT PFV_LANGUAGE PFV_SHELL PFV_CWD PFV_KDE_PROFILE PFV_XWAYLAND PFV_LOCK; do
  [ -n "${!v:-}" ] && OPTS+="$v=$(printf %q "${!v}") "
done
ssh -o BatchMode=yes "${SSH_OPTS[@]}" "$HOST" "${OPTS}PFV_SCALE=${PFV_SCALE:-1} PFV_OUTPUTS=${PFV_OUTPUTS:-1} PFV_BASE=$BASE PFINPUT=$R.pfinput.py bash $R.vsession.sh $NAME $R.scenario.sh $SIZE $TMO" || exit 1
mkdir -p "vsession-out/$NAME"
rsync -a --delete "${RSYNC_E[@]}" "$HOST:$R/out/" "vsession-out/$NAME/"
[ "${PFV_KEEP:-0}" = 1 ] || ssh -o BatchMode=yes "${SSH_OPTS[@]}" "$HOST" "rm -rf $R $R.vsession.sh $R.scenario.sh $R.pfinput.py"
echo "results in $(pwd)/vsession-out/$NAME"
