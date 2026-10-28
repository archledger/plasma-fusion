#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""First-open and cached ceilings must not be hidden by an aggregate median."""
import json
from pathlib import Path
import shutil
import unittest

import test_gate_launcher
from test_launcher_timing import event

PERF = Path(__file__).resolve().parents[1]
RESPONSE_CONTRACT = 'first-open/cached-max-per-run/v1'
RESPONSE_METRICS = ('launcher_first_open_ms', 'launcher_cached_max_ms')


class LauncherBudgetTest(unittest.TestCase):
    def setUp(self):
        test_gate_launcher.GateLauncherTest.setUp(self)

    def gate(self, *args, extra_runs=()):
        return test_gate_launcher.GateLauncherTest.gate(self, *args, extra_runs=extra_runs)

    def use_response_budget(self):
        self.budget.write_text(json.dumps({'metrics': {
            name: {'label': name, 'unit': 'ms', 'budget': {'default': limit},
                   'noise': {'abs': 15, 'rel': 0.25}}
            for name, limit in zip(RESPONSE_METRICS, (150, 80))}}))

    def response_times(self, values, run=None):
        run = run or self.run
        path = run / 'dbusmon.log'
        lines = path.read_text().splitlines()
        path = run / 'kwin perf statistics Virtual-0.csv'
        header, *frames = path.read_text().splitlines()
        for i, milliseconds in enumerate(values, 1):
            at = 10 + (i - 1) * 4
            name = f'launcher{i}'
            lines = [line for line in lines if f'"id": "{name}"' not in line]
            lines.append(event((1000 + at) * 1000 + 1, name).strip())
            frames = [line for line in frames if not at * 1e9 <= int(line.split(',')[0]) < (at + 1.5) * 1e9]
            for offset in (milliseconds, milliseconds + 20):
                present = at * 1_000_000_000 + round(offset * 1_000_000)
                frames.append(f'{present},{present},{present - 1_000_000},{present - 1000},0,0,0,0,0')
        (run / 'dbusmon.log').write_text('\n'.join(lines) + '\n')
        frames.sort(key=lambda line: int(line.split(',')[0]))
        path.write_text(header + '\n' + '\n'.join(frames) + '\n')

    def test_default_limits_are_split_without_changing_settling(self):
        spec = json.loads((PERF / 'budget.json').read_text())['metrics']
        self.assertNotIn('launcher_first_frame_ms', spec)
        for name, limit in zip(RESPONSE_METRICS, (150, 80)):
            self.assertEqual(spec[name]['budget']['default'], limit)
        self.assertEqual(spec['launcher_settled_ms']['budget']['default'], 300)

    def test_first_and_worst_cached_values_are_saved_separately(self):
        self.use_response_budget()
        self.response_times((140, 60, 70))
        saved = self.root / 'result.json'
        result = self.gate('--baseline', '', '--strict-budget', '--save', str(saved))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        data = json.loads(saved.read_text())
        self.assertEqual(data['launcher_response_contract'], RESPONSE_CONTRACT)
        for name, value in zip(RESPONSE_METRICS, (140, 70)):
            self.assertAlmostEqual(data['metrics'][name]['median'], value)
        self.assertAlmostEqual(data['per_run'][0]['noise']['launcher_timing']['cached_median_ms'], 65)

    def test_exact_limits_pass_and_exceeding_either_limit_fails(self):
        self.use_response_budget()
        for values, failed in (((150, 80, 80), []), ((150.000001, 60, 70), [RESPONSE_METRICS[0]]),
                               ((140, 80.000001, 60), [RESPONSE_METRICS[1]])):
            with self.subTest(values=values):
                self.response_times(values)
                saved = self.root / 'result.json'
                result = self.gate('--baseline', '', '--strict-budget', '--save', str(saved))
                self.assertEqual(result.returncode, 1 if failed else 0, result.stdout + result.stderr)
                self.assertEqual(json.loads(saved.read_text())['budget_fail'], failed)

    def test_one_slow_run_is_not_hidden_by_two_fast_runs(self):
        self.use_response_budget()
        self.response_times((120, 50, 60))
        fast, slow = self.root / 'fast', self.root / 'slow'
        shutil.copytree(self.run, fast)
        shutil.copytree(self.run, slow)
        self.response_times((160, 81, 50), slow)
        saved = self.root / 'result.json'
        result = self.gate('--baseline', '', '--strict-budget', '--save', str(saved), extra_runs=(fast, slow))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        data = json.loads(saved.read_text())
        self.assertEqual(data['budget_fail'], list(RESPONSE_METRICS))
        self.assertAlmostEqual(data['metrics'][RESPONSE_METRICS[0]]['median'], 120)

    def test_missing_first_or_cached_card_cannot_pass(self):
        self.use_response_budget()
        self.response_times((120, 50, 60))
        path = self.run / 'dbusmon.log'
        original = path.read_text()
        for i in (1, 2, 3):
            with self.subTest(opening=i):
                path.write_text('\n'.join(line for line in original.splitlines()
                                          if f'"id": "launcher{i}"' not in line))
                result = self.gate('--baseline', '', '--strict-budget')
                self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
                self.assertIn('MISSING', result.stdout)

    def test_regression_still_fails_below_the_new_absolute_limits(self):
        self.use_response_budget()
        self.response_times((100, 30, 40))
        baseline = self.root / 'baseline.json'
        result = self.gate('--baseline', '', '--save', str(baseline))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.response_times((130, 60, 60))
        saved = self.root / 'result.json'
        result = self.gate('--baseline', str(baseline), '--save', str(saved))
        self.assertEqual(result.returncode, 1, result.stdout + result.stderr)
        data = json.loads(saved.read_text())
        self.assertEqual(data['budget_fail'], [])
        self.assertEqual(data['regressions'], list(RESPONSE_METRICS))

    def test_old_mixed_only_baseline_cannot_disable_regression_checks(self):
        baseline = self.root / 'old.json'
        result = self.gate('--baseline', '', '--save', str(baseline))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        self.use_response_budget()
        self.response_times((120, 50, 60))
        saved = self.root / 'result.json'
        result = self.gate('--baseline', str(baseline), '--save', str(saved))
        self.assertEqual(result.returncode, 6, result.stdout + result.stderr)
        self.assertIn('incompatible launcher response', result.stdout)
        self.assertFalse(saved.exists())

    def test_response_tag_does_not_hide_a_missing_baseline_metric(self):
        self.use_response_budget()
        self.response_times((120, 50, 60))
        baseline = self.root / 'baseline.json'
        result = self.gate('--baseline', '', '--save', str(baseline))
        self.assertEqual(result.returncode, 0, result.stdout + result.stderr)
        original = baseline.read_text()
        for name in RESPONSE_METRICS:
            with self.subTest(missing=name):
                data = json.loads(original)
                del data['metrics'][name]
                baseline.write_text(json.dumps(data))
                saved = self.root / 'preserved.json'
                saved.write_text('preserve existing output')
                result = self.gate('--baseline', str(baseline), '--save', str(saved))
                self.assertEqual(result.returncode, 6, result.stdout + result.stderr)
                self.assertIn('incompatible launcher response', result.stdout)
                self.assertEqual(saved.read_text(), 'preserve existing output')


if __name__ == '__main__':
    unittest.main()
