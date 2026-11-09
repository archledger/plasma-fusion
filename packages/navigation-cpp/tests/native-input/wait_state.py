# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Wait for a strictly verified state of the private navigation probe."""
import json
import subprocess
import sys
import time


def matches(state, mode, owner='', count=0):
    if not state.get('registered') or not state.get('ioOk'):
        return False
    if mode == 'closed':
        return not state.get('running', True) and state.get('activeOutput') == '' and state.get('views') == []
    views = state.get('views', [])
    return (state.get('running') is True and state.get('focusMatches') is True
            and state.get('hasFocusObject') is True and state.get('inputMethodQueryValid') is True
            and state.get('closeTimerAvailable') is True and state.get('closeTimerActive') is False
            and state.get('inputMethodEnabled') is False and state.get('ownerOutput') == owner
            and state.get('activeOutput') == owner and len(views) == count
            and len({view['output'] for view in views}) == count
            and all(view['visible'] is True and view['firstFrameSeen'] is True
                    and view['opacity'] == (1 if view['output'] == owner else 0) for view in views))


def main():
    mode = sys.argv[1]
    assert mode in ('open', 'closed')
    owner = sys.argv[2] if mode == 'open' else ''
    count = int(sys.argv[3]) if mode == 'open' else 0
    deadline = time.monotonic() + 5
    state = {}
    while time.monotonic() < deadline:
        result = subprocess.run(['qdbus-qt6', 'org.kde.KWin', '/PlasmaFusionNavigationTest',
                                 'org.plasmafusion.NavigationTest.snapshot'], text=True,
                                capture_output=True, check=True, timeout=1)
        state = json.loads(result.stdout)
        if matches(state, mode, owner, count):
            print(json.dumps(state))
            return
        time.sleep(0.05)
    raise AssertionError(f'navigation did not reach {mode}: {state}')


if __name__ == '__main__':
    main()
