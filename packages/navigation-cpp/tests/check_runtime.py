# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Require complete logs and reject native crashes during private tests."""
from pathlib import Path
import re

FATAL = re.compile(r'\bASSERT(?:_X)?\s*:|assertion.*failed|Segmentation fault|\bAborted\b|\bSIGABRT\b|core dumped|Application .*crashing', re.I)


def failures(directory, *, require_bus_log=False):
    directory = Path(directory)
    found = []
    for name in ['kwin.log', 'dbus.log', 'plasmashell.log', 'scenario.log', 'container.log', 'driver.log']:
        path = directory / name
        try:
            text = path.read_text(errors='replace')
        except OSError as error:
            if (name in ('kwin.log', 'plasmashell.log')
                    or (name == 'dbus.log' and (require_bus_log or not isinstance(error, FileNotFoundError)))):
                found.append(f'{name}: missing or unreadable: {error}')
            continue
        found.extend(f'{name}:{index}: {line}' for index, line in enumerate(text.splitlines(), 1) if FATAL.search(line))
    return found
