#!/usr/bin/env python3
"""Extract stable key/value metrics from the Vivado ASIC portability proxy."""

from __future__ import annotations

import argparse
import re
from pathlib import Path


def read_report(report_dir: Path, name: str) -> str:
    path = report_dir / name
    if not path.is_file():
        raise FileNotFoundError(f"missing baseline report: {path}")
    return path.read_text(encoding="utf-8", errors="replace")


def first_match(text: str, pattern: str, default: str = "unavailable") -> str:
    match = re.search(pattern, text, re.MULTILINE)
    return match.group(1).strip() if match else default


def parse_utilization(text: str) -> dict[str, str]:
    for line in text.splitlines():
        columns = [column.strip() for column in line.split("|")]
        if len(columns) >= 12 and columns[1] == "top_packet_backend":
            return {
                "lut_cells": columns[3],
                "lut_logic_cells": columns[4],
                "flip_flops": columns[7],
                "bram36_cells": columns[8],
                "bram18_cells": columns[9],
                "dsp_cells": columns[10],
            }
    raise ValueError("top_packet_backend row not found in utilization report")


def main() -> int:
    repo_root = Path(__file__).resolve().parents[1]
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--report-dir",
        type=Path,
        default=repo_root / "asic" / "reports" / "vivado_proxy",
    )
    args = parser.parse_args()
    report_dir = args.report_dir.resolve()

    utilization = parse_utilization(
        read_report(report_dir, "utilization_hierarchical.rpt")
    )
    timing = read_report(report_dir, "timing_summary.rpt")
    drc = read_report(report_dir, "drc.rpt")
    check_timing = read_report(report_dir, "check_timing.rpt")

    metrics = {
        "tool": "Vivado 2019.1 synthesis proxy",
        "top": "top_packet_backend",
        "target_clock_ns": "5.000",
        **utilization,
        "worst_setup_slack_ns": first_match(
            timing, r"Slack \(VIOLATED\)\s*:\s*([-+0-9.]+)ns"
        ),
        "worst_path_source": first_match(timing, r"^\s*Source:\s*(.+)$"),
        "worst_path_destination": first_match(
            timing, r"^\s*Destination:\s*(.+)$"
        ),
        "worst_data_path_delay_ns": first_match(
            timing, r"^\s*Data Path Delay:\s*([-+0-9.]+)ns"
        ),
        "drc_violations": first_match(drc, r"Violations found:\s*([0-9]+)"),
        "combinational_loops": first_match(
            drc,
            r"\|\s*LUTLP-1\s*\|[^\n]*\|\s*([0-9]+)\s*\|",
            "0",
        ),
        "unclocked_register_latch_pins": first_match(
            check_timing,
            r"There are\s+([0-9]+)\s+register/latch pins with no clock",
            "0",
        ),
    }

    summary_path = report_dir / "baseline_summary.txt"
    summary_path.write_text(
        "\n".join(f"{key}={value}" for key, value in metrics.items()) + "\n",
        encoding="ascii",
    )
    print(summary_path)
    for key, value in metrics.items():
        print(f"{key}={value}")
    return 0


if __name__ == "__main__":
    raise SystemExit(main())
