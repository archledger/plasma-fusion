# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
from pathlib import Path
import tempfile
import unittest

from check_runtime import failures


class RuntimeEvidenceTest(unittest.TestCase):
    def setUp(self):
        temporary = tempfile.TemporaryDirectory()
        self.addCleanup(temporary.cleanup)
        self.root = Path(temporary.name)
        for name in ['kwin.log', 'plasmashell.log']:
            (self.root / name).write_text('normal startup\n')

    def test_accepts_complete_clean_logs(self):
        self.assertEqual(failures(self.root), [])

    def test_rejects_missing_required_log(self):
        (self.root / 'plasmashell.log').unlink()
        self.assertTrue(failures(self.root))

    def test_rejects_unreadable_required_log(self):
        (self.root / 'kwin.log').unlink()
        (self.root / 'kwin.log').mkdir()
        self.assertTrue(failures(self.root))

    def test_rejects_fatal_formats(self):
        for line in ['ASSERT: failed condition', 'ASSERT_X: bad invariant', 'Aborted',
                     '147 Aborted (core dumped) plasmashell', 'Segmentation fault',
                     'assertion "pending != NULL" failed', "KCrash: Application 'plasmashell' crashing"]:
            with self.subTest(line=line):
                (self.root / 'kwin.log').write_text(line)
                self.assertTrue(failures(self.root))

    def test_rejects_parent_shell_abort(self):
        (self.root / 'driver.log').write_text('Aborted\n')
        self.assertTrue(failures(self.root))


if __name__ == '__main__':
    unittest.main()
