#!/usr/bin/env python3
# SPDX-FileCopyrightText: 2026 Wisbendji Fimerlus <archledger236@gmail.com>
# SPDX-License-Identifier: GPL-2.0-or-later
"""Offline regressions for DRM accounting and missing performance measurements."""
import unittest

import analyze_ab
import drmstats
import gate


class DrmAccountingTest(unittest.TestCase):
    def test_i915_and_duplicate_descriptors(self):
        sample = """drm-driver: i915
drm-pdev: 0000:00:02.0
drm-client-id: 34
drm-engine-render: 100 ns
drm-engine-copy: 20 ns
drm-engine-capacity-copy: 1
drm-total-system0: 2048 KiB
drm-resident-system0: 1024 KiB
"""
        self.assertEqual(drmstats.summarize([sample, sample]), {
            "gpu_ns": 120, "gem_total_kB": 2048, "gem_resident_kB": 1024,
        })

    def test_xe_memory_is_counted_but_cycles_are_not_nanoseconds(self):
        sample = """drm-driver: xe
drm-pdev: 0000:00:02.0
drm-client-id: 34
drm-total-system: 0
drm-resident-system: 0
drm-total-gtt: 533608 KiB
drm-resident-gtt: 533608 KiB
drm-total-stolen: 0
drm-resident-stolen: 0
drm-cycles-rcs: 5791428511
drm-total-cycles-rcs: 2387943753024
"""
        self.assertEqual(drmstats.summarize([sample, sample]), {
            "gem_total_kB": 533608, "gem_resident_kB": 533608,
        })

    def test_client_ids_are_scoped_to_devices(self):
        sample = "drm-driver: i915\ndrm-client-id: 1\ndrm-pdev: {}\ndrm-engine-render: 10 ns\n"
        self.assertEqual(drmstats.summarize([sample.format("0000:00:02.0"), sample.format("0000:03:00.0")]), {"gpu_ns": 20})

    def test_missing_counters_are_not_zero(self):
        self.assertIsNone(drmstats.summarize(["drm-client-id: 1\n"]))
        self.assertIsNone(drmstats.summarize([]))
        self.assertIsNone(drmstats.summarize([None, "pos: 0\n"]))

    def test_reported_zero_is_a_real_measurement(self):
        self.assertEqual(drmstats.summarize([
            "drm-client-id: 1\ndrm-engine-render: 0 ns\ndrm-total-system0: 0 KiB\n",
        ]), {"gpu_ns": 0, "gem_total_kB": 0})

    def test_unitless_engine_zero_is_unavailable(self):
        self.assertIsNone(drmstats.summarize([
            "drm-client-id: 1\ndrm-engine-render: 0\n",
        ]))

    def test_unitless_memory_zero_is_a_real_measurement(self):
        self.assertEqual(drmstats.summarize([
            "drm-client-id: 1\ndrm-total-system: 0\ndrm-resident-system: 0\n",
        ]), {"gem_total_kB": 0, "gem_resident_kB": 0})

    def test_partial_client_coverage_does_not_undercount(self):
        self.assertIsNone(drmstats.summarize([
            "drm-client-id: 1\ndrm-engine-render: 100 ns\n",
            "drm-client-id: 2\n",
        ]))

    def test_units_and_regions(self):
        self.assertEqual(drmstats.summarize([
            "drm-client-id: 1\ndrm-total-system: 1 MiB\ndrm-total-vram: 2048 B\n"
            "drm-resident-system: 10 KiB\ndrm-resident-vram: 2 KiB\n",
        ]), {"gem_total_kB": 1026, "gem_resident_kB": 12})

    def test_malformed_values_are_unavailable(self):
        for value in ("bad", "-1 ns", "2 cycles", "10"):
            with self.subTest(value=value):
                self.assertIsNone(drmstats.summarize([f"drm-client-id: 1\ndrm-engine-render: {value}\n"]))


class GpuMeasurementTest(unittest.TestCase):
    @staticmethod
    def snapshot(time, **values):
        return {"mono": time, "procs": [{"pid": 1, "comm": "plasmashell", "start": 10, **values}]}

    def test_valid_time_and_true_zero(self):
        self.assertEqual(analyze_ab.gpu_pct(self.snapshot(1, gpu_ns=0), self.snapshot(2, gpu_ns=100000000), "plasmashell"), 10)
        self.assertEqual(analyze_ab.gpu_pct(self.snapshot(1, gpu_ns=0), self.snapshot(2, gpu_ns=0), "plasmashell"), 0)

    def test_missing_time_is_unavailable(self):
        self.assertIsNone(analyze_ab.gpu_pct(self.snapshot(1), self.snapshot(2), "plasmashell"))
        self.assertIsNone(analyze_ab.gpu_pct(self.snapshot(1, gpu_ns=0), self.snapshot(2), "plasmashell"))

    def test_reset_and_process_replacement_are_unavailable(self):
        self.assertIsNone(analyze_ab.gpu_pct(self.snapshot(1, gpu_ns=100), self.snapshot(2, gpu_ns=0), "plasmashell"))
        self.assertIsNone(analyze_ab.gpu_pct(self.snapshot(1, gpu_ns=0), self.snapshot(2, gpu_ns=10, start=20), "plasmashell"))

    def test_zero_interval_is_unavailable(self):
        self.assertIsNone(analyze_ab.gpu_pct(self.snapshot(1, gpu_ns=0), self.snapshot(1, gpu_ns=10), "plasmashell"))

    def test_process_disappearance_and_invalid_values_are_unavailable(self):
        self.assertIsNone(analyze_ab.gpu_pct(self.snapshot(1, gpu_ns=0), {"mono": 2, "procs": []}, "plasmashell"))
        for value in (None, -1, float("nan"), float("inf")):
            with self.subTest(value=value):
                self.assertIsNone(analyze_ab.gpu_pct(self.snapshot(1, gpu_ns=0), self.snapshot(2, gpu_ns=value), "plasmashell"))

    def test_kwin_frame_metric_rejects_a_counter_reset(self):
        a, b = self.snapshot(1, gpu_ns=100), self.snapshot(2, gpu_ns=0)
        a["procs"][0]["comm"] = b["procs"][0]["comm"] = "kwin_wayland"
        samples = {f"launcher{i}-{j}": value for i in (1, 2, 3) for j, value in ((0, a), (1, b))}
        self.assertIsNone(gate.kwin_gpu_ms_per_frame(samples, {}, [(0, 1500000000, 0, 1)]))

    def test_nonzero_fractional_counts_do_not_print_as_zero(self):
        self.assertEqual(gate.fmt(0.5, ""), "0.5")
        self.assertEqual(gate.fmt(0, ""), "0")
        self.assertEqual(analyze_ab.fmt_count(0.5), "0.5")

    def test_fractional_counts_keep_small_and_near_integer_values(self):
        for value in (1 / 21, 0.01, 0.0001, 1e-12, 0.9999, 1.0001, 1000000.5):
            with self.subTest(value=value):
                self.assertEqual(float(gate.fmt(value, "")), value)
                self.assertEqual(float(analyze_ab.fmt_count(value)), value)

    def test_count_precision_does_not_change_other_units_or_missing_values(self):
        self.assertEqual(gate.fmt(0.04, "ms"), "0.04")
        self.assertEqual(gate.fmt(0.04, "MiB"), "0")
        self.assertEqual(gate.fmt(0, ""), "0")
        self.assertEqual(gate.fmt(None, ""), "-")
        self.assertEqual(analyze_ab.fmt(0, 0), "0")
        self.assertEqual(analyze_ab.fmt(None, 0), "-")
        self.assertEqual(analyze_ab.fmt_count(0), "0")
        self.assertEqual(analyze_ab.fmt_count(None), "-")
        self.assertEqual(analyze_ab.fmt(12.3456, 0), "12")
        self.assertEqual(analyze_ab.fmt(145.01234, 0), "145")


if __name__ == "__main__":
    unittest.main()
