# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
import json
from pathlib import Path
import tempfile
import subprocess
import sys
import unittest

from PIL import Image

from check_first_frame import CaptureError, check


class FirstFrameTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.path = Path(temporary.name)
        self.events = []
        outputs = []
        for index in range(2):
            name = f'Virtual-{index}'
            outputs.append({'name': name, 'geo': {'x': index * 320, 'y': 0, 'w': 320, 'h': 240}})
            self.events.append({'event': 'completed', 'id': index + 1, 'output': name,
                                'owner': 'Virtual-1', 'opacity': index, 'visible': True})
            self.events.append({**self.events[-1], 'event': 'first-frame', 'image': f'first-{index + 1}.png',
                                'width': 320, 'height': 240})
            Image.new('RGB', (320, 240), 'blue').save(self.path / f'first-{index + 1}.png')
        Image.new('RGB', (640, 240), 'blue').save(self.path / 'before.png')
        (self.path / 'before.json').write_text(json.dumps({'outputs': outputs}))
        (self.path / 'target.json').write_text(json.dumps({'output': 'Virtual-1'}))

    def run_check(self):
        (self.path / 'probe.jsonl').write_text(''.join(json.dumps(event) + '\n' for event in self.events))
        return check(self.path)

    def test_passes_matching_first_frame(self):
        self.assertEqual(self.run_check(), 1)

    def test_rejects_initial_wrong_opacity(self):
        self.events[0]['opacity'] = 1
        with self.assertRaisesRegex(AssertionError, 'wrong opacity at completion'):
            self.run_check()

    def test_rejects_hidden_view(self):
        self.events[0]['visible'] = False
        with self.assertRaisesRegex(AssertionError, 'hidden'):
            self.run_check()

    def test_rejects_missing_first_frame(self):
        self.events.pop(1)
        with self.assertRaisesRegex(AssertionError, 'missing or duplicate'):
            self.run_check()

    def test_rejects_black_first_frame(self):
        Image.new('RGB', (320, 240), 'black').save(self.path / 'first-1.png')
        with self.assertRaisesRegex(AssertionError, 'black non-owner first frame'):
            self.run_check()

    def test_rejects_changed_nonblack_first_frame(self):
        Image.new('RGB', (320, 240), 'red').save(self.path / 'first-1.png')
        with self.assertRaisesRegex(AssertionError, 'changed non-owner'):
            self.run_check()

    def test_rejects_wrong_first_frame_opacity(self):
        self.events[1]['opacity'] = 1
        with self.assertRaisesRegex(AssertionError, 'wrong first-frame state'):
            self.run_check()

    def test_rejects_capture_path_escape(self):
        self.events[1]['image'] = '../first-1.png'
        with self.assertRaisesRegex(AssertionError, 'invalid first-frame'):
            self.run_check()

    def test_rejects_wrong_frame_owner(self):
        self.events[1]['owner'] = 'Virtual-0'
        with self.assertRaisesRegex(AssertionError, 'identity changed'):
            self.run_check()

    def test_rejects_probe_error(self):
        self.events.append({'event': 'lookup-failed'})
        with self.assertRaisesRegex(AssertionError, 'native probe error'):
            self.run_check()

    def test_rejects_duplicate_completion(self):
        self.events.append(self.events[0].copy())
        with self.assertRaisesRegex(AssertionError, 'duplicate completion'):
            self.run_check()

    def test_rejects_unregistered_frame(self):
        self.events[1]['id'] = 99
        with self.assertRaisesRegex(AssertionError, 'unregistered first-frame'):
            self.run_check()

    def test_rejects_duplicate_frame(self):
        self.events.append(self.events[1].copy())
        with self.assertRaisesRegex(AssertionError, 'duplicate first-frame'):
            self.run_check()

    def test_rejects_undecodable_owner_frame(self):
        (self.path / 'first-2.png').write_text('not an image')
        with self.assertRaises(CaptureError):
            self.run_check()

    def test_incomplete_bad_baseline_is_not_product_failure(self):
        self.events[0]['opacity'] = 1
        self.events.pop(1)
        with self.assertRaisesRegex(CaptureError, 'missing or duplicate'):
            self.run_check()
        result = subprocess.run([sys.executable, str(Path(__file__).with_name('check_first_frame.py')), str(self.path)],
                                text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 2)
        self.assertNotIn('wrong opacity at completion', result.stderr)

    def test_bad_baseline_with_missing_later_state_is_infrastructure_failure(self):
        for index, field in [(2, 'visible'), (3, 'opacity')]:
            with self.subTest(field=field):
                original = self.events[index].pop(field)
                self.events[0]['opacity'] = 1
                with self.assertRaises(CaptureError):
                    self.run_check()
                result = subprocess.run([sys.executable, str(Path(__file__).with_name('check_first_frame.py')), str(self.path)],
                                        text=True, capture_output=True, check=False)
                self.assertEqual(result.returncode, 2)
                self.assertNotIn('wrong opacity at completion', result.stderr)
                self.events[index][field] = original

    def test_rejects_wrong_state_field_types_before_semantic_failure(self):
        for field, value in [('visible', 'true'), ('opacity', '1'), ('id', True)]:
            with self.subTest(field=field):
                original = self.events[3][field]
                self.events[3][field] = value
                self.events[0]['opacity'] = 1
                with self.assertRaises(CaptureError):
                    self.run_check()
                self.events[3][field] = original

    def test_new_output_requires_state_and_capture_but_has_no_prior_pixels(self):
        completion = {'event': 'completed', 'id': 3, 'output': 'Virtual-2',
                      'owner': 'Virtual-1', 'opacity': 0, 'visible': True}
        self.events.extend([completion, {**completion, 'event': 'first-frame',
                                        'image': 'first-3.png', 'width': 320, 'height': 240}])
        Image.new('RGB', (320, 240), 'black').save(self.path / 'first-3.png')
        self.assertEqual(self.run_check(), 1)
        completion['opacity'] = 1
        with self.assertRaisesRegex(AssertionError, 'wrong opacity at completion'):
            self.run_check()

    def test_validates_gesture_diagnostics(self):
        event = {'event': 'gesture', 'owner': 'Virtual-1', 'inProgress': False,
                 'squaredVelocity': 0.01, 'flickThreshold': 0.25}
        self.events.append(event)
        self.assertEqual(self.run_check(), 1)
        event['squaredVelocity'] = float('nan')
        with self.assertRaises(CaptureError):
            self.run_check()


if __name__ == '__main__':
    unittest.main()
