#!/usr/bin/env python3
# -----------------------------------------------------------------------------
# parse_benchmark_metrics.py -- Extract cycle metrics from verilate_soc_benchmark
# output and write a Prometheus key-value file for GitLab CI metrics reports.
#
# Usage:
#   python3 parse_benchmark_metrics.py <log_file> [<out_metrics_file>]
#
# Defaults:
#   log_file         - required positional argument
#   out_metrics_file - benchmark_metrics.txt in the current directory
#
# Exit code 1 if benchmark_speedup is not found in the log (simulation failed).
# -----------------------------------------------------------------------------
import re
import sys
from pathlib import Path

PATTERNS = [
    ("benchmark_speedup", r"Speedup:\s+([\d.]+)x"),
    ("benchmark_compute_cyc", r"compute:\s+(\d+)\s+cyc"),
    ("benchmark_bus_cyc", r"bus:\s+(\d+)\s+cyc\s+\("),
    ("benchmark_sw_overhead_cyc", r"SW overhead:\s*(\d+)\s+cyc"),
    ("benchmark_accel_path_cyc", r"Accel path:\s+(\d+)\s+cyc"),
    ("benchmark_cpu_gemm_cyc", r"CPU  GEMM:\s+(\d+)\s+cyc"),
]


def main() -> int:
    if len(sys.argv) < 2:
        print(f"usage: {sys.argv[0]} <log_file> [<out_metrics_file>]", file=sys.stderr)
        return 1

    log_path = Path(sys.argv[1])
    out_path = Path(sys.argv[2]) if len(sys.argv) > 2 else Path("benchmark_metrics.txt")

    text = log_path.read_text()
    metrics: dict[str, str] = {}
    for key, pattern in PATTERNS:
        m = re.search(pattern, text)
        if m:
            metrics[key] = m.group(1)

    out_path.write_text("".join(f"{k} {v}\n" for k, v in metrics.items()))

    print("\n=== Benchmark Metrics ===")
    for k, v in metrics.items():
        print(f"  {k}: {v}")

    if "benchmark_speedup" not in metrics:
        print(
            "ERROR: benchmark_speedup not found in simulation output", file=sys.stderr
        )
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main())
