#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Exercise the real analyzer and gate CLI on synthetic session files."""
import json
from pathlib import Path
import shutil
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, str(Path(__file__).resolve().parents[1]))
import analyze_ab  # noqa: E402
from launcher_timing import CONTRACT  # noqa: E402
from test_launcher_timing import event  # noqa: E402

PERF = Path(__file__).resolve().parents[1]


class GateLauncherTest(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.addCleanup(self.temp.cleanup)
        self.root = Path(self.temp.name)
        self.run = self.root / 'run'
        self.run.mkdir()
        marks = {'begin': 0, 'sweep0': 3, 'sweep1': 4, 'sweep-events-900': 4}
        labels = {'settled': 0.5, 'idle0': 1, 'idle1': 2, 'sweep0': 3, 'sweep1': 4, 'end': 60}
        windows, frames = [], []
        for group, first in (('launcher', 10), ('qs', 22), ('alttab', 34), ('ov', 46)):
            for i in range(1, 4):
                at = first + (i - 1) * 4
                name = f'{group}{i}'
                marks[name] = at
                marks[name + '-close'] = at + 1.5
                labels[name + '-0'] = at - 0.01
                labels[name + '-1'] = at + 3
                # The legacy selector accepts the earlier full-screen dimmer.
                cls = 'org.kde.kwin' if group == 'alttab' else 'org.kde.plasmashell'
                windows.append(f'   string "PFPERF added {int((1000 + at) * 1000 + 40)} {cls}|plasmashell||||id"')
                if group == 'launcher':
                    windows.append(event((1000 + at) * 1000 + 40, name + '-dimmer', 0).strip())
                    windows.append(event((1000 + at) * 1000 + 100, name).strip())
                for offset, render in ((0.05, 0.03), (0.13, 0.09), (0.15, 0.14)):
                    present = round((at + offset) * 1e9)
                    frames.append(f'{present},{present},{round((at + render) * 1e9)},{present - 1000},0,0,0,0,0')
        (self.run / 'arm.txt').write_text('arm=fusion\n')
        (self.run / 'dbusmon.log').write_text('\n'.join(windows) + '\n')
        (self.run / 'marks.jsonl').write_text(''.join(
            json.dumps({'mark': name, 'epoch': at + 1000, 'mono': at}) + '\n'
            for name, at in marks.items()))
        (self.run / 'stats.jsonl').write_text(''.join(
            json.dumps({'label': name, 'mono': at, 'clk_tck': 100,
                        'cpu': [0, 0, 0, int(at * 10_000), 0, 0, 0, 0, 0, 0],
                        'load': [0, 0, 0], 'procs': [
                            {'comm': comm, 'pid': pid, 'ticks': 0, 'Pss': 1024, 'VmRSS': 1024}
                            for pid, comm in ((1, 'plasmashell'), (2, 'kwin_wayland'))]}) + '\n'
            for name, at in labels.items()))
        (self.run / 'kwin perf statistics Virtual-0.csv').write_text(
            'target,present,start,end,a,b,c,d,e\n' + '\n'.join(frames) + '\n')
        self.budget = self.root / 'budget.json'
        self.budget.write_text(json.dumps({'metrics': {
            name: {'label': name, 'unit': 'ms', 'budget': {'default': 50},
                   'noise': {'abs': 1, 'rel': 0.01}}
            for name in ('launcher_first_frame_ms', 'launcher_settled_ms')}}))

    def gate(self, *args, extra_runs=()):
        return subprocess.run([sys.executable, str(PERF / 'gate.py'), '--geometry', 'test',
                               '--budget', str(self.budget), *args, str(self.run), *map(str, extra_runs)],
                              text=True, capture_output=True, check=False)

    def test_analyzer_selects_card_and_post_mapping_composition(self):
        result = analyze_ab.analyze(str(self.run))
        for value in result['launcher_first_frame_ms']:
            self.assertAlmostEqual(value, 150)
        self.assertEqual(result['launcher_timing_contract'], CONTRACT)

    def test_partial_opening_cannot_be_hidden_by_median(self):
        path = self.run / 'dbusmon.log'
        path.write_text('\n'.join(line for line in path.read_text().splitlines()
                                  if '"id": "launcher2"' not in line))
        result = self.gate('--baseline', '')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('MISSING', result.stdout)

    def test_legacy_baseline_is_rejected_even_if_its_values_match(self):
        baseline = self.root / 'old.json'
        baseline.write_text(json.dumps({'geometry': 'test', 'metrics': {
            'launcher_first_frame_ms': {'median': 150, 'min': 150, 'max': 150}}}))
        result = self.gate('--baseline', str(baseline))
        self.assertEqual(result.returncode, 6, result.stdout + result.stderr)
        self.assertIn('incompatible launcher timing', result.stdout)

    def test_one_invalid_run_cannot_be_hidden_by_other_runs(self):
        invalid = self.root / 'invalid'
        shutil.copytree(self.run, invalid)
        (invalid / 'dbusmon.log').write_text('')
        result = self.gate('--baseline', '', extra_runs=(invalid,))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('launcher1 INVALID', result.stdout)

    def test_missing_input_marker_cannot_drop_a_requested_run(self):
        invalid = self.root / 'missing-marker'
        shutil.copytree(self.run, invalid)
        path = invalid / 'marks.jsonl'
        path.write_text('\n'.join(line for line in path.read_text().splitlines()
                                  if json.loads(line)['mark'] != 'launcher2'))
        saved = self.root / 'incomplete.json'
        result = self.gate('--baseline', '', '--save', str(saved), extra_runs=(invalid,))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('unusable', result.stdout + result.stderr)
        self.assertFalse(saved.exists())

    def test_ab_cli_does_not_average_partial_or_missing_openings(self):
        for missing in ('second', 'all'):
            with self.subTest(missing=missing):
                invalid = self.root / ('ab-' + missing)
                shutil.copytree(self.run, invalid)
                path = invalid / 'dbusmon.log'
                path.write_text('' if missing == 'all' else '\n'.join(
                    line for line in path.read_text().splitlines() if '"id": "launcher2"' not in line))
                result = subprocess.run([sys.executable, str(PERF / 'analyze_ab.py'),
                                         str(self.run), str(invalid)], cwd=self.root,
                                        text=True, capture_output=True, check=False)
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                for line in result.stdout.splitlines():
                    if line.startswith('| launcher: key->'):
                        self.assertIn('INVALID', line)
                self.assertIn('incomplete launcher timing', result.stdout)

    def test_ab_cli_accepts_complete_runs(self):
        result = subprocess.run([sys.executable, str(PERF / 'analyze_ab.py'), str(self.run)],
                                cwd=self.root, text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertNotIn('INVALID', result.stdout)

    def test_ab_cli_preserves_fractional_late_frame_counts(self):
        late = self.root / 'late'
        shutil.copytree(self.run, late)
        path = late / 'kwin perf statistics Virtual-0.csv'
        lines = path.read_text().splitlines()
        # Make exactly one frame late in each overview opening of the second run.
        first_frames = {46_050_000_000, 50_050_000_000, 54_050_000_000}
        for i in range(1, len(lines)):
            fields = lines[i].split(',')
            if int(fields[1]) in first_frames:
                fields[3] = str(int(fields[0]) + 1000)
                lines[i] = ','.join(fields)
        path.write_text('\n'.join(lines) + '\n')
        result = subprocess.run([sys.executable, str(PERF / 'analyze_ab.py'),
                                 str(self.run), str(late)], cwd=self.root,
                                text=True, capture_output=True, check=False)
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.assertIn('| overview: late frames (median) | 0.5 (0..1) |', result.stdout)

    def test_unknown_contract_is_rejected_without_overwriting_saved_output(self):
        baseline = self.root / 'baseline.json'
        baseline.write_text(json.dumps({'geometry': 'test', 'launcher_timing_contract': 'future'}))
        saved = self.root / 'saved.json'
        saved.write_text('preserve existing result')
        result = self.gate('--baseline', str(baseline), '--save', str(saved))
        self.assertEqual(result.returncode, 6, result.stdout + result.stderr)
        self.assertEqual(saved.read_text(), 'preserve existing result')

    def test_save_records_contract_and_first_cached_diagnostics(self):
        saved = self.root / 'result.json'
        result = self.gate('--baseline', '', '--save', str(saved))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        data = json.loads(saved.read_text())
        self.assertEqual(data['launcher_timing_contract'], CONTRACT)
        diagnostics = data['per_run'][0]['noise']['launcher_timing']
        self.assertAlmostEqual(diagnostics['first_open_ms'], 150)
        self.assertAlmostEqual(diagnostics['cached_median_ms'], 150)
        self.assertEqual(len(diagnostics['openings']), 3)
        compared = self.gate('--baseline', str(saved))
        self.assertEqual(compared.returncode, 0, compared.stdout + compared.stderr)
        self.assertIn('same', compared.stdout)

    def test_budget_still_fails_above_fifty_ms(self):
        result = self.gate('--baseline', '', '--strict-budget')
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        self.assertIn('FAIL', result.stdout)


if __name__ == '__main__':
    unittest.main()
