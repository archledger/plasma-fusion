#!/bin/bash
# Laptop side: seed a virtual session's HOME on the ThinkPad, run a scenario, fetch the results.
#
#   remote.sh NAME SCENARIO [SEED_HOME_DIR|-] [WIDTHxHEIGHT] [TIMEOUT]
#
# SEED_HOME_DIR is copied over the session HOME (for example a staged ~/.local/share and ~/.config).
# Use '-' to keep the HOME from the previous run of NAME. Results land in ./vsession-out/NAME/.
set -u
NAME=${1:?name}; SCENARIO=${2:?scenario}; SEED=${3:--}; SIZE=${4:-1440x900}; TMO=${5:-240}
HOST=${PFV_HOST:-thinkpad-fedora}
HERE=$(cd "$(dirname "$0")" && pwd)
ssh -o BatchMode=yes "$HOST" "mkdir -p /tmp/pfv-$NAME/home" || exit 1
if [ "$SEED" != - ]; then
  rsync -a --delete "$SEED"/ "$HOST:/tmp/pfv-$NAME/home/" || exit 1
fi
scp -q "$HERE/vsession.sh" "$HOST:/tmp/pfv-$NAME.vsession.sh" && scp -q "$SCENARIO" "$HOST:/tmp/pfv-$NAME.scenario.sh" || exit 1
ssh -o BatchMode=yes "$HOST" "bash /tmp/pfv-$NAME.vsession.sh $NAME /tmp/pfv-$NAME.scenario.sh $SIZE $TMO" || exit 1
mkdir -p "vsession-out/$NAME"
rsync -a --delete "$HOST:/tmp/pfv-$NAME/out/" "vsession-out/$NAME/"
echo "results in $(pwd)/vsession-out/$NAME"
