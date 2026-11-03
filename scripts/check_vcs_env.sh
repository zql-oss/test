#!/usr/bin/env bash
# Quick preflight for the VCS flow. No license is checked here.
set -u
fail=0

for t in vcs urg gcc python3; do
    if command -v "$t" >/dev/null 2>&1; then
        printf 'OK   %-6s %s\n' "$t" "$(command -v "$t")"
    else
        printf 'MISS %-6s not found in PATH\n' "$t"
        fail=1
    fi
done

if ! python3 -c 'import yaml' >/dev/null 2>&1; then
    echo "MISS python3 PyYAML (pip install pyyaml)"
    fail=1
else
    echo "OK   PyYAML"
fi

VCS_HOME=${VCS_HOME:-}
if [ -z "$VCS_HOME" ] && command -v vcs >/dev/null 2>&1; then
    VCS_HOME=$(dirname "$(dirname "$(command -v vcs)")")
fi
if [ -n "$VCS_HOME" ] && [ -f "$VCS_HOME/include/svdpi.h" ]; then
    echo "OK   svdpi.h under $VCS_HOME/include"
else
    echo "MISS svdpi.h (set VCS_HOME to the VCS installation root)"
    fail=1
fi

if [ -f tb/dpi/ecc_inject.c ]; then
    echo "OK   DPI source tb/dpi/ecc_inject.c"
else
    echo "MISS tb/dpi/ecc_inject.c (run from the project root)"
    fail=1
fi

echo
if [ "$fail" -eq 0 ]; then
    echo "Environment looks ready. Run: bash scripts/run_all_vcs.sh"
else
    echo "Fix the MISS items above (usually: source your VCS setup script)."
fi
exit "$fail"
