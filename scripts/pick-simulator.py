#!/usr/bin/env python3
"""Pick the iPhone simulator a CI job runs on, the same way in every job.

Reads `xcrun simctl list devices available -j` on stdin and prints one UDID.
Runtimes are tried newest iOS first, and within them the named models in the
order given, then any iPhone. Taking the first iPhone in simctl's dictionary
order let the runtime move between iOS versions from one runner image to the
next, so a test result depended on which image a job happened to land on.

    xcrun simctl list devices available -j | python3 scripts/pick-simulator.py "iPhone 16 Pro"

The chosen model and runtime go to stderr, so the log says what ran.
"""
from __future__ import annotations

import json
import re
import sys


def runtime_version(runtime: str) -> tuple[int, ...]:
    """`com.apple.CoreSimulator.SimRuntime.iOS-18-2` → (18, 2)."""
    return tuple(int(n) for n in re.findall(r"\d+", runtime.rsplit(".", 1)[-1]))


def pick(devices: dict[str, list[dict]], preferred: list[str]) -> tuple[dict, str] | None:
    """The device and runtime to use, or None when there is no iPhone at all."""
    iphones = [(device, runtime)
               for runtime in sorted((r for r in devices if "SimRuntime.iOS-" in r),
                                     key=runtime_version, reverse=True)
               for device in devices[runtime] if "iPhone" in device.get("name", "")]
    for name in [*preferred, None]:
        match = next(((d, r) for d, r in iphones if name is None or d["name"] == name), None)
        if match:
            return match
    return None


def main() -> int:
    preferred = [name for name in sys.argv[1:] if name]
    choice = pick(json.load(sys.stdin)["devices"], preferred)
    if choice is None:
        print("::error::No iPhone simulator available on this runner image.", file=sys.stderr)
        return 1
    device, runtime = choice
    if preferred and device["name"] not in preferred:
        print(f"::warning::None of {', '.join(preferred)} is installed; using {device['name']}.",
              file=sys.stderr)
    print(f"Simulator: {device['name']} on {runtime.rsplit('.', 1)[-1]} ({device['udid']})", file=sys.stderr)
    print(device["udid"])
    return 0


if __name__ == "__main__":
    sys.exit(main())
