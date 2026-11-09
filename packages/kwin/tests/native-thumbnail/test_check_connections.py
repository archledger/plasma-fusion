# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
import unittest

from check_connections import check


def records(growing=False, closed=8, release_hidden=True):
    parts = []
    for cycle in range(12):
        for state, count in (("open", 10), ("closed", closed)):
            count += cycle if growing else 0
            parts.append(f"PFTHUMB BEGIN {state}\nOBJECT target\n"
                          "signal: frameGeometryChanged(KWin::RectF)\n"
                          + "  <functor or function pointer>\n" * count
                          + f"signal: other()\nPFTHUMB CLIENTS {1 if state == 'open' or not release_hidden else 0}\n"
                          + f"PFTHUMB END {state}\n")
    return "".join(parts)


class ConnectionTests(unittest.TestCase):
    def test_stable_connections(self):
        self.assertEqual(check(records()), {"open": [10] * 12, "closed": [8] * 12})

    def test_growth_fails(self):
        with self.assertRaisesRegex(AssertionError, "accumulated"):
            check(records(growing=True))

    def test_incomplete_capture_fails(self):
        with self.assertRaisesRegex(AssertionError, "24 snapshots"):
            check(records().replace("PFTHUMB END closed", "incomplete", 1))

    def test_missing_target_fails(self):
        with self.assertRaisesRegex(AssertionError, "target window missing"):
            check(records().replace("OBJECT target", "PFTHUMB MISSING", 1))

    def test_out_of_order_capture_fails(self):
        with self.assertRaisesRegex(AssertionError, "out of order"):
            check(records().replace("PFTHUMB BEGIN open", "PFTHUMB BEGIN closed", 1)
                  .replace("PFTHUMB END open", "PFTHUMB END closed", 1))

    def test_closed_connections_must_decrease(self):
        with self.assertRaisesRegex(AssertionError, "did not release"):
            check(records(closed=10))

    def test_missing_assignment_observation_fails(self):
        with self.assertRaisesRegex(AssertionError, "one client observation"):
            check(records().replace("PFTHUMB CLIENTS 1\n", "", 1))

    def test_duplicate_assignment_observation_fails(self):
        with self.assertRaisesRegex(AssertionError, "one client observation"):
            check(records().replace("PFTHUMB CLIENTS 1", "PFTHUMB CLIENTS 1\nPFTHUMB CLIENTS 1", 1))

    def test_open_preview_requires_client(self):
        with self.assertRaisesRegex(AssertionError, "open preview assignment"):
            check(records().replace("PFTHUMB CLIENTS 1", "PFTHUMB CLIENTS 0", 1))

    def test_closed_preview_releases_client(self):
        with self.assertRaisesRegex(AssertionError, "closed preview assignment"):
            check(records().replace("PFTHUMB CLIENTS 0", "PFTHUMB CLIENTS 1", 1))

    def test_fallback_retains_client(self):
        self.assertEqual(check(records(closed=10, release_hidden=False), release_hidden=False),
                         {"open": [10] * 12, "closed": [10] * 12})

    def test_fallback_must_not_clear_client(self):
        with self.assertRaisesRegex(AssertionError, "closed preview assignment"):
            check(records(), release_hidden=False)

    def test_fallback_still_rejects_geometry_growth(self):
        with self.assertRaisesRegex(AssertionError, "accumulated"):
            check(records(growing=True, closed=10, release_hidden=False), release_hidden=False)


if __name__ == "__main__":
    unittest.main()
