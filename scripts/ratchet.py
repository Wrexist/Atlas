#!/usr/bin/env python3
"""Fail when a CI metric gets worse than its committed baseline.

Report-only numbers drift: nobody compares today's count with last month's.
Each metric in `scripts/ci-baselines.json` has a baseline and a direction.
A PR that makes one worse fails; one that improves it is told to lower the
baseline in the same PR, so the ratchet only ever tightens.

A baseline of null means none has been recorded yet: the value is printed
for a maintainer to commit and the step passes.

    python3 scripts/ratchet.py concurrency_warnings 42
"""
from __future__ import annotations

import json
import pathlib
import sys

BASELINES = pathlib.Path(__file__).with_name("ci-baselines.json")


def verdict(metric: str, value: float, entry: dict) -> tuple[bool, str]:
    """(passes, message) for one measured value against its baseline entry."""
    baseline, better = entry["baseline"], entry["better"]
    if baseline is None:
        return True, (f"::warning::{metric} = {value}; no baseline recorded. "
                      f"Commit it in scripts/ci-baselines.json to start the ratchet.")
    worse = value > baseline if better == "lower" else value < baseline
    if worse:
        return False, (f"::error::{metric} got worse: {value} vs baseline {baseline} "
                       f"({better} is better).")
    if value != baseline:
        return True, (f"{metric} improved to {value} (baseline {baseline}). "
                      f"Tighten the baseline in scripts/ci-baselines.json.")
    return True, f"{metric} holds at its baseline {baseline}."


def main(argv: list[str]) -> int:
    if len(argv) != 3:
        print(__doc__)
        return 2
    metric, raw = argv[1], argv[2]
    entries = json.loads(BASELINES.read_text())
    if metric not in entries:
        print(f"unknown metric '{metric}'; known: {', '.join(sorted(entries))}")
        return 2
    ok, message = verdict(metric, float(raw), entries[metric])
    print(message)
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main(sys.argv))
