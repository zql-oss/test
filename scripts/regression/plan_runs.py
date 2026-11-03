#!/usr/bin/env python3
"""Expand scripts/regression/test_plan.yaml into a flat, tool-neutral run list.

Output (tab-separated, one line per simulation):
    run_id  test_class  seed  timeout_s  plusargs

The same expansion is used by the UVS and VCS one-click flows so that both
tools execute exactly the same tests, seeds, timeouts and plusargs.
"""

import argparse
import os
import re
import sys

import yaml


def sanitize(name: str) -> str:
    return re.sub(r"[^A-Za-z0-9_.-]+", "_", name).strip("_")


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--plan", default="scripts/regression/test_plan.yaml")
    ap.add_argument(
        "--seeds-cap",
        type=int,
        default=0,
        help="cap num_seeds per plan entry (0 = no cap)",
    )
    ap.add_argument(
        "--tag",
        default=os.environ.get("TAG", ""),
        help="only run entries carrying this tag",
    )
    ap.add_argument(
        "--timeout-override",
        type=int,
        default=int(os.environ.get("TIMEOUT_S", "0") or 0),
        help="override per-test wall-clock timeout in seconds",
    )
    ap.add_argument("--default-verbosity", default="UVM_MEDIUM")
    args = ap.parse_args()

    with open(args.plan) as f:
        plan = yaml.safe_load(f)

    g = plan.get("global", {}) or {}
    default_seeds = int(g.get("default_seeds", 3))
    default_timeout = int(g.get("timeout_s", 1800))
    global_plusargs = dict(g.get("plusargs", {}) or {})

    for idx, t in enumerate(plan.get("tests", []) or []):
        if not t.get("enabled", True):
            continue
        tags = set(t.get("tags", []) or [])
        if args.tag and args.tag not in tags:
            continue

        name = str(t.get("name", t.get("test_class", f"test{idx}")))
        cls = str(t.get("test_class", name))
        num_seeds = int(t.get("num_seeds", default_seeds))
        if args.seeds_cap > 0:
            num_seeds = min(num_seeds, args.seeds_cap)
        if num_seeds <= 0:
            continue

        timeout = int(t.get("timeout_s", default_timeout))
        if args.timeout_override > 0:
            timeout = args.timeout_override

        plusargs = dict(global_plusargs)
        plusargs.update(t.get("plusargs", {}) or {})
        plusargs.setdefault("UVM_VERBOSITY", args.default_verbosity)
        pa = " ".join(f"+{k}={v}" for k, v in plusargs.items())

        run_id = f"t{idx:03d}_{sanitize(name)}"
        for seed in range(1, num_seeds + 1):
            print(f"{run_id}\t{cls}\t{seed}\t{timeout}\t{pa}")

    return 0


if __name__ == "__main__":
    sys.exit(main())
