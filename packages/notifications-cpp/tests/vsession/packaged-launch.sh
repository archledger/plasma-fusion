#!/bin/bash
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
#
# Use the installed drop-in's launch command in the direct-start test harness.
set -euo pipefail

config=/usr/share/plasma-fusion/tools/device/fusion-config.sh
[[ -n ${PFV:-} && ${XDG_RUNTIME_DIR:-} == "$PFV/run" && "$HOME" == "$PFV/home" ]]
[[ -f $config && -x /usr/libexec/plasma-fusion/plasma-fusion-notifications-select ]]
# The fixture neither uses the host manager nor copies the plugin into HOME. Take the launch
# command and its paths from the installed renderer, not a second implementation.
# shellcheck source=/dev/null
source <(sed -n -E '/^NOTIFICATIONS_(VENDOR|SELECTOR|ROOT|SHELL|WATCH)=/p;
  /^notifications_unit_arg\(\) \{/,/^}/p;
  /^notifications_shell_dropin\(\) \{/,/^}/p' "$config")
read -r digest _ < <(sha256sum "$NOTIFICATIONS_VENDOR")
dropin=$(notifications_shell_dropin "$digest")
exec python3 - "$dropin" <<'PY'
import os
import shlex
import sys

prefix = "ExecStart=:"
line, = (line for line in sys.argv[1].splitlines() if line.startswith(prefix))
args = shlex.split(line.removeprefix(prefix).replace("%%", "%"))
os.execv(args[0], args)
PY
