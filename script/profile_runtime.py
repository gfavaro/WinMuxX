#!/usr/bin/env python3
"""Finite, read-only macOS process sampling; never prevents system sleep.

Reports process counters, not watts, battery life, or WindowServer work. Sampling
does not open windows, query Accessibility, or change WinMuxX configuration.
"""
import argparse
import ctypes
import datetime
import json
import math
from pathlib import Path
import signal
import statistics
import sys
import time


# SDK sys/resource.h, rusage_info_v4 (RUSAGE_INFO_V4 == 4).
FIELDS = """user_time system_time pkg_idle_wkups interrupt_wkups pageins
wired_size resident_size phys_footprint proc_start_abstime proc_exit_abstime
child_user_time child_system_time child_pkg_idle_wkups child_interrupt_wkups
child_pageins child_elapsed_abstime diskio_bytesread diskio_byteswritten
cpu_time_qos_default cpu_time_qos_maintenance cpu_time_qos_background
cpu_time_qos_utility cpu_time_qos_legacy cpu_time_qos_user_initiated
cpu_time_qos_user_interactive billed_system_time serviced_system_time
logical_writes lifetime_max_phys_footprint instructions cycles billed_energy
serviced_energy interval_max_phys_footprint runnable_time""".split()


class UsageV4(ctypes.Structure):
    _fields_ = [("uuid", ctypes.c_uint8 * 16)] + [(name, ctypes.c_uint64) for name in FIELDS]


def native_reader():
    if sys.platform != "darwin":
        raise RuntimeError("This sampler requires macOS")
    lib = ctypes.CDLL("/usr/lib/libproc.dylib", use_errno=True)
    lib.proc_pid_rusage.argtypes = [ctypes.c_int, ctypes.c_int, ctypes.c_void_p]
    lib.proc_pid_rusage.restype = ctypes.c_int

    def read(pid):
        usage = UsageV4()
        if lib.proc_pid_rusage(pid, 4, ctypes.byref(usage)) != 0:
            raise OSError(ctypes.get_errno(), "proc_pid_rusage failed")
        return {name: getattr(usage, name) for name in FIELDS}

    return read


def summarize(samples, interval, status, error=None):
    result = {"status": status, "samples": len(samples), "error": error,
              "scope": "Process counters only; no battery-life or leak-free certification"}
    if not samples:
        return result
    first, last = samples[0], samples[-1]
    if any(s["proc_start_abstime"] != first["proc_start_abstime"] for s in samples):
        raise ValueError("Process identity changed; counters cannot be combined")
    elapsed = last["elapsed"] - first["elapsed"]
    result.update(elapsed_seconds=elapsed, started_utc=first["utc"], last_sample_utc=last["utc"])
    footprints = [s["phys_footprint"] / 1024**2 for s in samples]
    # Linear trend uses all samples; report it alongside edge medians, never as a
    # leak verdict. Workload phases and process lifetime must still be matched.
    times = [sample["elapsed"] - first["elapsed"] for sample in samples]
    center = statistics.mean(times)
    denominator = sum((value - center) ** 2 for value in times)
    slope = (sum((value - center) * (memory - statistics.mean(footprints))
                 for value, memory in zip(times, footprints)) / denominator * 60
             if denominator else None)
    result["footprint_trend_mib_per_minute"] = slope
    if all("resident_size" in sample for sample in samples):
        resident = [sample["resident_size"] / 1024**2 for sample in samples]
        result.update(resident_first_mib=resident[0], resident_last_mib=resident[-1],
                      resident_peak_mib=max(resident))
    edge = max(1, len(samples) // 10)
    result.update(footprint_first_mib=footprints[0], footprint_last_mib=footprints[-1],
                  footprint_peak_mib=max(footprints), footprint_delta_mib=footprints[-1] - footprints[0],
                  footprint_first_decile_median_mib=statistics.median(footprints[:edge]),
                  footprint_last_decile_median_mib=statistics.median(footprints[-edge:]))
    gaps = [b["elapsed"] - a["elapsed"] for a, b in zip(samples, samples[1:])]
    result["sample_gaps_over_twice_interval"] = sum(g > 2 * interval for g in gaps)
    result["maximum_sample_gap_seconds"] = max(gaps, default=0)
    for field in ["logical_writes", "diskio_byteswritten", "pkg_idle_wkups", "interrupt_wkups"]:
        delta = last[field] - first[field]
        if delta < 0:
            raise ValueError("Counter moved backwards: " + field)
        result[field] = delta
    cpu_ns = sum(last[k] - first[k] for k in ["user_time", "system_time"])
    if cpu_ns < 0:
        raise ValueError("CPU counter moved backwards")
    result["app_cpu_seconds"] = cpu_ns / 1e9
    result["cpu_percent_one_core"] = cpu_ns / 1e9 / elapsed * 100 if elapsed > 0 else None
    return result


def save_summary(directory, samples, interval, status, error=None):
    temporary = directory / "summary.json.tmp"
    temporary.write_text(json.dumps(summarize(samples, interval, status, error), indent=2) + "\n")
    temporary.replace(directory / "summary.json")


def sample(pid, seconds, interval, directory):
    read = native_reader()
    directory.mkdir(parents=True, mode=0o700, exist_ok=False)
    (directory / "metadata.json").write_text(json.dumps({
        "pid": pid, "requested_seconds": seconds, "interval_seconds": interval,
        "started_utc": datetime.datetime.now(datetime.timezone.utc).isoformat(),
        "prevents_system_sleep": False,
    }, indent=2) + "\n")
    started = time.monotonic()
    deadline = started + seconds
    samples = []
    status, error, code = "completed", None, 0
    try:
        with (directory / "samples.jsonl").open("w") as stream:
            while True:
                usage = read(pid)
                if samples and usage["proc_start_abstime"] != samples[0]["proc_start_abstime"]:
                    raise RuntimeError("Target PID was reused; stopping instead of mixing processes")
                # Persist only the counters needed for this report, never window titles or configuration.
                record = {key: usage[key] for key in ["proc_start_abstime", "phys_footprint", "resident_size",
                    "user_time", "system_time", "logical_writes", "diskio_byteswritten",
                    "pkg_idle_wkups", "interrupt_wkups"]}
                record.update(elapsed=time.monotonic() - started,
                    utc=datetime.datetime.now(datetime.timezone.utc).isoformat())
                samples.append(record)
                stream.write(json.dumps(record) + "\n")
                stream.flush()
                save_summary(directory, samples, interval, "running")
                remaining = deadline - time.monotonic()
                if remaining <= 0:
                    break
                time.sleep(min(interval, remaining))
    except (OSError, RuntimeError, KeyboardInterrupt) as exc:
        status, error, code = "interrupted", str(exc) or type(exc).__name__, 1
    finally:
        save_summary(directory, samples, interval, status, error)
    return code


def positive(value):
    number = float(value)
    if not math.isfinite(number) or number <= 0:
        raise argparse.ArgumentTypeError("must be finite and positive")
    return number


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--pid", type=int, required=True)
    parser.add_argument("--seconds", type=positive, default=7200)
    parser.add_argument("--interval", type=positive, default=10)
    parser.add_argument("--output", type=Path, required=True, help="New private output directory")
    args = parser.parse_args()
    if args.pid <= 0:
        parser.error("--pid must be positive")
    def stop(_signal, _frame):
        raise KeyboardInterrupt("Sampler terminated")
    signal.signal(signal.SIGTERM, stop)
    return sample(args.pid, args.seconds, args.interval, args.output)


if __name__ == "__main__":
    sys.exit(main())
