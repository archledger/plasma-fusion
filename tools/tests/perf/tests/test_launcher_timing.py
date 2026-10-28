#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offline launcher-oracle regressions: python3 -m unittest discover -s tools/tests/perf/tests."""
import json
from pathlib import Path
import sys
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
from launcher_timing import launcher_timings  # noqa: E402


def event(at, window_id, window_type=18, cls='org.kde.plasmashell', caption='plasmashell'):
    data = {'schema': 1, 'event': 'added', 'time_ms': at, 'id': window_id,
            'resourceClass': cls, 'caption': caption, 'windowType': window_type,
            'appletPopup': window_type == 18, 'width': 680, 'height': 700}
    return '   string "PFPERF window ' + json.dumps(data) + '"\n'


class LauncherTimingTest(unittest.TestCase):
    def setUp(self):
        self.marks = {'launcher1': {'epoch': 10.0, 'mono': 20.0},
                      'launcher1-close': {'epoch': 11.5, 'mono': 21.5}}
        # timestamp tuple: target presentation, presentation, render start, render end.
        self.frames = [(20_050_000_000, 20_050_000_000, 20_030_000_000, 20_040_000_000),
                       (20_130_000_000, 20_130_000_000, 20_090_000_000, 20_120_000_000),
                       (20_150_000_000, 20_150_000_000, 20_140_000_000, 20_145_000_000)]

    def opening(self, text, frames=None):
        return launcher_timings(self.marks, self.frames if frames is None else frames, text)[0]

    def test_ignores_dimmer_tooltip_and_another_application(self):
        text = (event(10_040, 'dimmer', 0) + event(10_050, 'tooltip', 12)
                + event(10_060, 'other', cls='other-app') + event(10_100, 'card'))
        result = self.opening(text)
        self.assertIsNone(result['error'])
        self.assertEqual(result['window_id'], 'card')
        self.assertAlmostEqual(result['mapped_ms'], 100)

    def test_does_not_use_a_composition_started_before_mapping(self):
        result = self.opening(event(10_100, 'card'))
        self.assertAlmostEqual(result['first_frame_ms'], 150)
        self.assertAlmostEqual(result['settled_ms'], 150)

    def test_missing_or_ambiguous_card_fails_closed(self):
        for text in ('', event(10_040, 'dimmer', 0),
                     event(10_100, 'card-a') + event(10_110, 'card-b')):
            with self.subTest(text=text):
                result = self.opening(text)
                self.assertIsNotNone(result['error'])
                self.assertIsNone(result['first_frame_ms'])

    def test_repeated_delivery_of_same_event_is_not_a_second_window(self):
        line = event(10_100, 'card')
        self.assertIsNone(self.opening(line + line)['error'])

    def test_conflicting_events_with_same_id_are_not_deduplicated(self):
        result = self.opening(event(10_100, 'card') + event(10_110, 'card'))
        self.assertIsNotNone(result['error'])

    def test_caption_delimiters_and_quotes_do_not_change_identity(self):
        result = self.opening(event(10_100, 'card', caption='a|b "quoted"\nnext'))
        self.assertEqual(result['window_id'], 'card')

    def test_rejects_missing_malformed_and_unknown_schema_metadata(self):
        valid = event(10_100, 'card')
        for bad in ('   string "PFPERF window {broken}"\n',
                    valid.replace('"schema": 1', '"schema": 2'),
                    valid.replace('"appletPopup": true', '"appletPopup": "true"'),
                    valid.replace('"width": 680', '"width": 0')):
            with self.subTest(bad=bad):
                self.assertIsNotNone(self.opening(bad)['error'])

    def test_legacy_logs_are_not_accepted_as_card_identity(self):
        old = '   string "PFPERF added 10040 org.kde.plasmashell|plasmashell|||special|{id}"\n'
        self.assertIsNotNone(self.opening(old)['error'])

    def test_card_after_close_is_not_used(self):
        self.assertIsNotNone(self.opening(event(11_501, 'card'))['error'])

    def test_missing_output_frames_is_not_zero_latency(self):
        result = self.opening(event(10_100, 'card'), [])
        self.assertIsNotNone(result['error'])
        self.assertIsNone(result['first_frame_ms'])

    def test_each_opening_is_reported_even_if_another_is_missing(self):
        self.assertEqual(len(launcher_timings(self.marks, self.frames, event(10_100, 'card'))), 3)


if __name__ == '__main__':
    unittest.main()
