import argparse
import ctypes
import unittest

from script.profile_runtime import UsageV4, positive, summarize


def point(elapsed, footprint=10 * 1024**2, start=1, cpu=0, writes=0):
    return {"elapsed": elapsed, "utc": "fixture", "phys_footprint": footprint,
            "proc_start_abstime": start, "user_time": cpu, "system_time": 0,
            "logical_writes": writes, "diskio_byteswritten": 0,
            "pkg_idle_wkups": 0, "interrupt_wkups": 0}


class RuntimeProfileTest(unittest.TestCase):
    def test_cpu_memory_io_units_and_completed_status(self):
        result = summarize([point(0), point(10, 12 * 1024**2, cpu=100_000_000, writes=4096)], 10, "completed")
        self.assertEqual(result["cpu_percent_one_core"], 1)
        self.assertEqual(result["footprint_delta_mib"], 2)
        self.assertEqual(result["logical_writes"], 4096)
        self.assertEqual(result["status"], "completed")

    def test_reused_pid_cannot_produce_combined_metrics(self):
        with self.assertRaises(ValueError):
            summarize([point(0), point(10, start=2)], 10, "completed")

    def test_missing_samples_and_interruption_are_explicit(self):
        result = summarize([], 10, "interrupted", "process exited")
        self.assertEqual(result["samples"], 0)
        self.assertEqual(result["status"], "interrupted")
        result = summarize([point(0), point(40)], 10, "running")
        self.assertEqual(result["sample_gaps_over_twice_interval"], 1)
        self.assertEqual(result["maximum_sample_gap_seconds"], 40)

    def test_initial_sample_does_not_claim_zero_cpu_average(self):
        self.assertIsNone(summarize([point(0)], 10, "running")["cpu_percent_one_core"])

    def test_counter_reset_is_rejected(self):
        with self.assertRaises(ValueError):
            summarize([point(0, writes=10), point(10)], 10, "completed")

    def test_sdk_v4_layout_and_invalid_durations(self):
        self.assertEqual(ctypes.sizeof(UsageV4), 296)
        for value in ["0", "-1", "nan", "inf"]:
            with self.assertRaises(argparse.ArgumentTypeError):
                positive(value)


if __name__ == "__main__":
    unittest.main()
