#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Fetch Fedora's KWin source package of one version-release into a directory, and check that what
# arrived is that package. A stable update reaches Fedora's source repositories on some mirrors
# hours after the binary ones, and dnf5's "download --srpm" then exits 0 having fetched nothing:
# the backport lane used to stop at the next step on a missing file, which said nothing about the
# mirrors (issue #203). So the outcome is judged by the file, never by dnf's status, and each
# further attempt refreshes the metadata, which also lets the mirror list pick another mirror.
#
# Usage: fetch-source.sh VERSION-RELEASE DIR [ATTEMPTS]
#   VERSION-RELEASE  the build, as the callers name it (6.8.3-1.fc44)
#   DIR              where kwin-VERSION-RELEASE.src.rpm is put (created when missing)
#   ATTEMPTS         downloads to try, 1-20 (default 4); the waits between them grow by 30 s
#                    (PF_FETCH_WAIT, the step in seconds: 0 in the tests)
# dnf's own output goes to standard output (the callers keep it as download.log), the outcome to
# standard error. Runs where dnf reads Fedora's repositories: in the lane's containers.
# Exit status: 0 DIR holds that source package; 3 no attempt fetched it; 64 usage.
set -euo pipefail
usage() {
    echo "usage: $0 VERSION-RELEASE DIR [ATTEMPTS]${1:+ ($1)}" >&2
    exit 64
}
(( $# >= 2 && $# <= 3 )) || usage
vr=$1
dir=$2
attempts=${3:-4}
step=${PF_FETCH_WAIT:-30}
[[ $vr =~ ^[0-9][0-9A-Za-z.+~_]*-[0-9][0-9A-Za-z.+~_]*$ ]] || usage "not a version-release: '$vr'"
[[ -n $dir ]] || usage "no directory"
# Decimal only: bash's arithmetic would read 08 as octal.
[[ $attempts =~ ^[1-9][0-9]?$ ]] && (( attempts <= 20 )) || usage "not 1-20 attempts: '$attempts'"
[[ $step =~ ^(0|[1-9][0-9]{0,3})$ ]] || usage "PF_FETCH_WAIT is not a number of seconds: '$step'"
mkdir -p -- "$dir"
src=kwin-$vr.src.rpm
file=$dir/$src
# The package asked for, and a source package: rpm reads a source package's SOURCERPM as (none).
fetched() {
    [[ -f $file ]] &&
        [[ $(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE} %{SOURCERPM}' "$file" 2>/dev/null) == "kwin-$vr (none)" ]]
}
for (( attempt = 1; attempt <= attempts; attempt++ )); do
    rm -f -- "$file"
    refresh=()
    (( attempt == 1 )) || refresh=(--refresh)
    dnf "${refresh[@]}" download --srpm --destdir="$dir" "kwin-$vr" 2>&1 || true
    if fetched; then
        echo "fetched $src (attempt $attempt of $attempts)" >&2
        exit 0
    fi
    (( attempt < attempts )) || break
    echo "attempt $attempt of $attempts: no $src from this mirror; trying again with fresh metadata in $(( attempt * step )) s" >&2
    sleep "$(( attempt * step ))"
done
# Nothing that is not the package asked for stays under its name.
rm -f -- "$file"
echo "could not fetch $src: $attempts attempts found it on none of the mirrors this machine reads. A stable update reaches Fedora's source repositories (updates-source) hours after the binary ones on some mirrors, so this usually clears within the day; nothing was built." >&2
exit 3
