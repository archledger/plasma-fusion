#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
# Fetch Fedora's source package of one build into a directory, and check that what arrived is that
# package. Both patch lanes use it: each one's build script mounts this file into its container as
# /fetch-source.sh (kwin/, plasma-workspace/), and the KWin backport workflow's first job runs it
# from the tree. A stable update reaches Fedora's source repositories on some mirrors hours after the
# binary ones, and dnf5's "download --srpm" then exits 0 having fetched nothing: the KWin lane used
# to stop at the next step on a missing file, which said nothing about the mirrors (issue #203), and
# the plasma-workspace build with no message at all (#206). So the outcome is judged by the file,
# never by dnf's status, and each further attempt refreshes the metadata, which also lets the mirror
# list pick another mirror.
#
# Usage: fetch-source.sh NAME VERSION-RELEASE DIR [ATTEMPTS]
#   NAME             the source package (kwin, plasma-workspace)
#   VERSION-RELEASE  the build (6.8.3-1.fc44)
#   DIR              where NAME-VERSION-RELEASE.src.rpm is put (created when missing)
#   ATTEMPTS         downloads to try, 1-20 (default 4); the waits between them grow by 30 s
#                    (PF_FETCH_WAIT, the step in seconds: 0 in the tests)
# dnf's own output goes to standard output (the callers keep it as download.log), the outcome to
# standard error. Runs where dnf reads Fedora's repositories: in the lanes' containers.
# Exit status: 0 DIR holds that source package; 3 no attempt fetched it; 64 usage.
set -euo pipefail
usage() {
    echo "usage: $0 NAME VERSION-RELEASE DIR [ATTEMPTS]${1:+ ($1)}" >&2
    exit 64
}
(( $# >= 3 && $# <= 4 )) || usage
name=$1
vr=$2
dir=$3
attempts=${4:-4}
step=${PF_FETCH_WAIT:-30}
# An RPM package name: letters, digits and . _ + -, starting with a letter or a digit.
[[ $name =~ ^[A-Za-z0-9][A-Za-z0-9._+-]*$ ]] || usage "not a package name: '$name'"
[[ $vr =~ ^[0-9][0-9A-Za-z.+~_]*-[0-9][0-9A-Za-z.+~_]*$ ]] || usage "not a version-release: '$vr'"
[[ -n $dir ]] || usage "no directory"
# Decimal only: bash's arithmetic would read 08 as octal.
[[ $attempts =~ ^[1-9][0-9]?$ ]] && (( attempts <= 20 )) || usage "not 1-20 attempts: '$attempts'"
[[ $step =~ ^(0|[1-9][0-9]{0,3})$ ]] || usage "PF_FETCH_WAIT is not a number of seconds: '$step'"
mkdir -p -- "$dir"
src=$name-$vr.src.rpm
file=$dir/$src
# The package asked for, and a source package: rpm reads a source package's SOURCERPM as (none).
fetched() {
    [[ -f $file ]] &&
        [[ $(rpm -qp --qf '%{NAME}-%{VERSION}-%{RELEASE} %{SOURCERPM}' "$file" 2>/dev/null) == "$name-$vr (none)" ]]
}
for (( attempt = 1; attempt <= attempts; attempt++ )); do
    rm -f -- "$file"
    refresh=()
    (( attempt == 1 )) || refresh=(--refresh)
    dnf "${refresh[@]}" download --srpm --destdir="$dir" "$name-$vr" 2>&1 || true
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
# The two causes seen: a build newer than the mirrors, and one the repositories no longer carry
# (their updates keep only each package's newest build; a lane's default, the installed build, is
# that on a machine behind Fedora's updates).
echo "could not fetch $src: $attempts attempts found it on none of the mirrors this machine reads. Either the build is newer than those mirrors - a stable update reaches Fedora's source repositories (updates-source) hours after the binary ones on some mirrors, which usually clears within the day - or it is no longer in Fedora's repositories, whose updates keep only each package's newest build: 'dnf repoquery --srpm $name' lists the builds they carry. Nothing was built." >&2
exit 3
