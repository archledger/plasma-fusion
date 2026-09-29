#!/bin/bash
# Build every part into a HOME tree (default: stage/home), ready to copy to a user's HOME.
#
#   tools/build.sh [PART...]     build all parts, or only the named ones (e.g. "icons plasma-style")
#
# Each part is tools/build.d/NN-<part>.sh. It receives ROOT (repository root) and STAGE (the HOME
# tree) in the environment and writes only below $STAGE in the paths docs/PLAN.md assigns to it.
set -euo pipefail
ROOT=$(cd "$(dirname "$0")/.." && pwd)
STAGE=${STAGE:-$ROOT/stage/home}
export ROOT STAGE
mkdir -p "$STAGE"
shopt -s nullglob
for script in "$ROOT"/tools/build.d/*.sh; do
  part=$(basename "$script" .sh); part=${part#*-}
  if [ $# -gt 0 ]; then
    wanted=0
    for p in "$@"; do [ "$p" = "$part" ] && wanted=1; done
    [ "$wanted" = 1 ] || continue
  fi
  echo "== $part"
  bash "$script"
done
