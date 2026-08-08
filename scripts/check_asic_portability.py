#!/usr/bin/env python3
"""Check the production synthesis manifest and reject vendor-bound RTL."""

from __future__ import annotations

import argparse
from pathlib import Path
import re
import sys


BANNED_PATTERNS = {
    "Xilinx XPM macro": re.compile(r"\bxpm_", re.IGNORECASE),
    "Xilinx block-RAM primitive": re.compile(r"\bRAMB(?:18|36)", re.IGNORECASE),
    "Xilinx DSP primitive": re.compile(r"\bDSP48", re.IGNORECASE),
    "Xilinx clock primitive": re.compile(r"\b(?:BUFG|MMCME|PLLE)\w*", re.IGNORECASE),
    "Xilinx simulation library": re.compile(r"\b(?:unisim|unimacro|secureip)\b", re.IGNORECASE),
    "FPGA RAM attribute": re.compile(r"\bram_style\b", re.IGNORECASE),
    "FPGA DSP attribute": re.compile(r"\buse_dsp\b", re.IGNORECASE),
}


def parse_args() -> argparse.Namespace:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--repo-root",
        type=Path,
        default=Path(__file__).resolve().parents[1],
    )
    return parser.parse_args()


def main() -> int:
    args = parse_args()
    repo_root = args.repo_root.resolve()
    manifest = repo_root / "asic" / "rtl_files.f"
    errors: list[str] = []
    rtl_files: list[Path] = []

    if not manifest.is_file():
        print(f"[FAIL] Missing manifest: {manifest}")
        return 1

    for raw_line in manifest.read_text(encoding="utf-8").splitlines():
        entry = raw_line.strip()
        if not entry or entry.startswith("#"):
            continue
        rtl_path = (repo_root / entry).resolve()
        if not rtl_path.is_file():
            errors.append(f"manifest entry does not exist: {entry}")
            continue
        if repo_root not in rtl_path.parents:
            errors.append(f"manifest entry escapes repository: {entry}")
            continue
        rtl_files.append(rtl_path)

    if not rtl_files:
        errors.append("manifest contains no RTL files")

    seen: set[Path] = set()
    for rtl_path in rtl_files:
        if rtl_path in seen:
            errors.append(f"duplicate manifest entry: {rtl_path.relative_to(repo_root)}")
        seen.add(rtl_path)

        source_text = rtl_path.read_text(encoding="utf-8", errors="replace")
        for label, pattern in BANNED_PATTERNS.items():
            for match in pattern.finditer(source_text):
                line = source_text.count("\n", 0, match.start()) + 1
                errors.append(
                    f"{rtl_path.relative_to(repo_root)}:{line}: {label}"
                )

    top_path = (
        repo_root
        / "OoO_RISC_V_CPU_DESIGN.srcs"
        / "sources_1"
        / "new"
        / "top_packet_backend.sv"
    )
    if top_path.resolve() not in seen:
        errors.append("top_packet_backend.sv is absent from the manifest")

    if errors:
        for error in errors:
            print(f"[FAIL] {error}")
        print(f"==== ASIC portability check FAIL ({len(errors)} errors) ====")
        return 1

    print(f"[PASS] {len(rtl_files)} synthesis files exist and are unique")
    print("[PASS] no vendor primitive, library, or FPGA mapping attribute found")
    print("[PASS] top_packet_backend is present in the production manifest")
    print("==== ASIC portability check PASS ====")
    return 0


if __name__ == "__main__":
    sys.exit(main())
