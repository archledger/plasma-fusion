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
# PFV_TABLET, PFV_ANIM, PFV_FONT_PT, PFV_LANGUAGE, PFV_SHELL and PFV_CWD are passed on when set.
# Before the run it checks free space on the host: at least PFV_MIN_FREE_MB (default 2048) MiB in
# /var/tmp and PFV_MIN_TMP_MB (default 256) MiB in /tmp, and PFV_MIN_INODES_PCT (default 10) % free
# inodes on each where the file system counts them; PFV_NO_GUARD=1 skips the check. Locally the
# results need PFV_MIN_LOCAL_MB (default 512) MiB. PFV_SSH_OPTS adds ssh options (for example
# "-o ConnectTimeout=40") to every ssh, scp and rsync call.
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
  ssh -o BatchMode=yes "${SSH_OPTS[@]}" "$HOST" "bash -s $BASE ${PFV_MIN_FREE_MB:-2048} ${PFV_MIN_TMP_MB:-256} ${PFV_MIN_INODES_PCT:-10} && mkdir -p $R/home" <<'GUARD' || exit 1
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
check "$1" "$2" "$4" && check /tmp "$3" "$4"
GUARD
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
for v in PFV_TABLET PFV_ANIM PFV_FONT_PT PFV_LANGUAGE PFV_SHELL PFV_CWD; do
  [ -n "${!v:-}" ] && OPTS+="$v=$(printf %q "${!v}") "
done
ssh -o BatchMode=yes "${SSH_OPTS[@]}" "$HOST" "${OPTS}PFV_SCALE=${PFV_SCALE:-1} PFV_OUTPUTS=${PFV_OUTPUTS:-1} PFV_BASE=$BASE PFINPUT=$R.pfinput.py bash $R.vsession.sh $NAME $R.scenario.sh $SIZE $TMO" || exit 1
mkdir -p "vsession-out/$NAME"
rsync -a --delete "${RSYNC_E[@]}" "$HOST:$R/out/" "vsession-out/$NAME/"
[ "${PFV_KEEP:-0}" = 1 ] || ssh -o BatchMode=yes "${SSH_OPTS[@]}" "$HOST" "rm -rf $R $R.vsession.sh $R.scenario.sh $R.pfinput.py"
echo "results in $(pwd)/vsession-out/$NAME"
