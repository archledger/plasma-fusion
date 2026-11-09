# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
import copy
import unittest

from wait_state import matches


class WaitStateTest(unittest.TestCase):
    def setUp(self):
        self.state = {'registered': True, 'ioOk': True, 'running': True, 'focusMatches': True,
                      'closeTimerAvailable': True, 'closeTimerActive': False,
                      'hasFocusObject': True, 'inputMethodQueryValid': True, 'inputMethodEnabled': False,
                      'ownerOutput': 'Virtual-0', 'activeOutput': 'Virtual-0',
                      'views': [{'output': 'Virtual-0', 'opacity': 1, 'visible': True, 'firstFrameSeen': True},
                                {'output': 'Virtual-1', 'opacity': 0, 'visible': True, 'firstFrameSeen': True}]}

    def test_accepts_complete_open_state(self):
        self.assertTrue(matches(self.state, 'open', 'Virtual-0', 2))

    def test_rejects_missing_focus_or_query(self):
        for key in ['registered', 'ioOk', 'running', 'focusMatches', 'hasFocusObject', 'inputMethodQueryValid', 'closeTimerAvailable']:
            with self.subTest(key=key):
                bad = copy.deepcopy(self.state)
                bad[key] = False
                self.assertFalse(matches(bad, 'open', 'Virtual-0', 2))

    def test_rejects_enabled_text_input_in_normal_navigation(self):
        self.state['inputMethodEnabled'] = True
        self.assertFalse(matches(self.state, 'open', 'Virtual-0', 2))

    def test_rejects_wrong_owner(self):
        self.state['ownerOutput'] = 'Virtual-1'
        self.assertFalse(matches(self.state, 'open', 'Virtual-0', 2))

    def test_rejects_incomplete_view(self):
        for key in ['visible', 'firstFrameSeen']:
            with self.subTest(key=key):
                bad = copy.deepcopy(self.state)
                bad['views'][1][key] = False
                self.assertFalse(matches(bad, 'open', 'Virtual-0', 2))
        self.state['views'][1]['opacity'] = 1
        self.assertFalse(matches(self.state, 'open', 'Virtual-0', 2))

    def test_rejects_wrong_count_or_duplicate_output(self):
        self.assertFalse(matches(self.state, 'open', 'Virtual-0', 3))
        self.state['views'][1]['output'] = 'Virtual-0'
        self.assertFalse(matches(self.state, 'open', 'Virtual-0', 2))

    def test_closed_requires_views_and_active_output_gone(self):
        closed = {'registered': True, 'ioOk': True, 'running': False, 'views': [], 'activeOutput': ''}
        self.assertTrue(matches(closed, 'closed'))
        closed['activeOutput'] = 'Virtual-0'
        self.assertFalse(matches(closed, 'closed'))
        self.assertFalse(matches({}, 'closed'))


if __name__ == '__main__':
    unittest.main()
