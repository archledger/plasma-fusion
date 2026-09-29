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
set -u
NAME=${1:?name}; SCENARIO=${2:?scenario}; SEED=${3:--}; SIZE=${4:-1440x900}; TMO=${5:-240}
HOST=${PFV_HOST:-thinkpad-fedora}
HERE=$(cd "$(dirname "$0")" && pwd)
BASE=/var/tmp
R=$BASE/pfv-$NAME
ssh -o BatchMode=yes "$HOST" "mkdir -p $R/home" || exit 1
if [ "$SEED" != - ]; then
  rsync -a --delete "$SEED"/ "$HOST:$R/home/" || exit 1
fi
scp -q "$HERE/vsession.sh" "$HOST:$R.vsession.sh" && scp -q "$SCENARIO" "$HOST:$R.scenario.sh" \
  && scp -q "$HERE/pfinput.py" "$HOST:$R.pfinput.py" || exit 1
ssh -o BatchMode=yes "$HOST" "PFV_SCALE=${PFV_SCALE:-1} PFV_OUTPUTS=${PFV_OUTPUTS:-1} PFV_BASE=$BASE PFINPUT=$R.pfinput.py bash $R.vsession.sh $NAME $R.scenario.sh $SIZE $TMO" || exit 1
mkdir -p "vsession-out/$NAME"
rsync -a --delete "$HOST:$R/out/" "vsession-out/$NAME/"
[ "${PFV_KEEP:-0}" = 1 ] || ssh -o BatchMode=yes "$HOST" "rm -rf $R $R.vsession.sh $R.scenario.sh $R.pfinput.py"
echo "results in $(pwd)/vsession-out/$NAME"
