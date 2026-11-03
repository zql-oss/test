#!/usr/bin/env python3
"""Compare a VCS run_summary.txt against the UVS baseline (1:1 run list check).

Both files are produced by scripts/run_all_vcs.sh and scripts/run_all_uvs.sh
and use the same run IDs (tNNN_<plan name>), seeds and plan order.

Usage:
    python3 scripts/compare_results.py
    python3 scripts/compare_results.py --vcs reports/regression/run_summary.txt \
                                       --uvs reports/uvs_baseline/run_summary.txt
"""

import argparse
import sys
from collections import Counter


def parse(path):
    rows = {}
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.split()
            if len(parts) < 3:
                continue
            status, run_id, seed = parts[0], parts[1], parts[2]
            if "=" in seed:
                seed = seed.split("=", 1)[1]
            rows[(run_id, seed)] = status
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--vcs", default="reports/regression/run_summary.txt")
    ap.add_argument("--uvs", default="reports/uvs_baseline/run_summary.txt")
    args = ap.parse_args()

    try:
        vcs = parse(args.vcs)
        uvs = parse(args.uvs)
    except OSError as exc:
        print(f"ERROR: {exc}")
        return 2

    only_vcs = sorted(set(vcs) - set(uvs))
    only_uvs = sorted(set(uvs) - set(vcs))
    common = sorted(set(vcs) & set(uvs))
    mismatches = [(k, uvs[k], vcs[k]) for k in common if uvs[k] != vcs[k]]

    print(f"VCS runs : {len(vcs)}  {dict(Counter(vcs.values()))}")
    print(f"UVS runs : {len(uvs)}  {dict(Counter(uvs.values()))}")
    print(f"common   : {len(common)}")
    if only_vcs:
        print(f"only in VCS ({len(only_vcs)}):")
        for k in only_vcs:
            print(f"  {k[0]} seed={k[1]} -> {vcs[k]}")
    if only_uvs:
        print(f"only in UVS ({len(only_uvs)}):")
        for k in only_uvs:
            print(f"  {k[0]} seed={k[1]} -> {uvs[k]}")
    if mismatches:
        print(f"status mismatches ({len(mismatches)}):")
        for k, u, v in mismatches:
            print(f"  {k[0]} seed={k[1]}: UVS={u} VCS={v}")

    ok = not only_vcs and not only_uvs and not mismatches
    print("RESULT:", "MATCH" if ok else "DIFF")
    return 0 if ok else 1


if __name__ == "__main__":
    sys.exit(main())
