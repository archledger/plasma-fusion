# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Icon-position test, session 2 of 3: a new session on the HOME that session 1 left (a log-out and
# log-in). vsession.sh has already started plasmashell.
# shellcheck shell=bash
exec 2>&1
# shellcheck source=tools/tests/icons/lib.sh
source "$HOME/pf-tools/tests/icons/lib.sh"
log "session 2: same HOME, new session"
sleep 4
check 08-second-session
log "session 2 done"
