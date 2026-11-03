#!/usr/bin/env python3
"""Build an HTML scoreboard from a regression run_summary.txt + per-run logs.

This is a viewer for the UVM scoreboard/report results (UVM_ERROR / UVM_FATAL
counts and the first failure message), not a replacement for the UVM
scoreboard itself. It works for both the VCS and UVS flows because both write
the same run IDs, log names and report-summary format.

Usage:
    python3 scripts/regression/make_scoreboard.py
    python3 scripts/regression/make_scoreboard.py --summary reports/regression/run_summary.txt
"""

import argparse
import html
import os
import re
from collections import Counter, defaultdict
from datetime import datetime

STATUS_ORDER = ["FATAL", "FAIL", "TIMEOUT", "NORUN", "PASS"]
STATUS_COLOR = {
    "PASS": "#1b7f3a",
    "FATAL": "#b00020",
    "FAIL": "#c25e00",
    "TIMEOUT": "#6a1b9a",
    "NORUN": "#555555",
}


def parse_summary(path):
    rows = []
    with open(path, encoding="utf-8", errors="replace") as f:
        for line in f:
            parts = line.split()
            if len(parts) < 3:
                continue
            status, run_id, seed = parts[0], parts[1], parts[2]
            if "=" in seed:
                seed = seed.split("=", 1)[1]
            rows.append((status, run_id, seed))
    return rows


def last_int(text, key):
    vals = re.findall(rf"^\s*{key}\s*:\s*(\d+)", text, re.M)
    return int(vals[-1]) if vals else None


def first_failure(text):
    for line in text.splitlines():
        if re.match(r"^\s*UVM_(ERROR|FATAL)\s*:", line):
            continue
        if re.search(r"\bUVM_(FATAL|ERROR)\b", line):
            return line.strip()
    return ""


def inspect_log(path):
    info = {
        "emoji": "",
        "test": "",
        "err": None,
        "fat": None,
        "warn": None,
        "first": "",
        "sim_end": "",
    }
    if not os.path.isfile(path):
        return info
    with open(path, encoding="utf-8", errors="replace") as f:
        text = f.read()
    m = re.search(r"\+UVM_TESTNAME=(\S+)", text)
    if m:
        info["test"] = m.group(1)
    info["err"] = last_int(text, "UVM_ERROR")
    info["fat"] = last_int(text, "UVM_FATAL")
    info["warn"] = last_int(text, "UVM_WARNING")
    info["first"] = first_failure(text)
    m = re.findall(r"@\s*([0-9]+(?:\.[0-9]+)?)\s*(?:ps|ns|us|ms|s)\b", text)
    if m:
        info["sim_end"] = m[-1]
    return info


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--summary", default="reports/regression/run_summary.txt")
    ap.add_argument("--log-dir", default="reports/regression")
    ap.add_argument("--out", default="reports/regression/scoreboard.html")
    args = ap.parse_args()

    if not os.path.isfile(args.summary):
        print(f"ERROR: {args.summary} not found")
        return 2

    rows = parse_summary(args.summary)
    counts = Counter(s for s, _, _ in rows)
    details = []
    for status, run_id, seed in rows:
        log = os.path.join(args.log_dir, f"{run_id}_s{seed}.log")
        info = inspect_log(log)
        details.append((status, run_id, seed, log, info))

    details.sort(
        key=lambda r: (
            STATUS_ORDER.index(r[0]) if r[0] in STATUS_ORDER else 99,
            r[1],
            int(r[2]),
        )
    )

    by_test = defaultdict(lambda: Counter())
    for status, _, _, _, info in details:
        by_test[info["test"] or "unknown"][status] += 1

    cov_link = "../coverage/merged/dashboard.html"
    cov_exists = os.path.isfile(os.path.join(os.path.dirname(args.out), cov_link))

    total = len(rows)
    pass_n = counts.get("PASS", 0)
    fail_n = total - pass_n
    now = datetime.now().strftime("%Y-%m-%d %H:%M:%S")

    def badge(status):
        color = STATUS_COLOR.get(status, "#555")
        return (
            f'<span class="badge" style="background:{color}">'
            f"{html.escape(status)}</span>"
        )

    rows_html = []
    for status, run_id, seed, log, info in details:
        first = html.escape(info["first"]) if info["first"] else ""
        title = html.escape(info["first"], quote=True) if info["first"] else ""
        log_rel = os.path.relpath(log, os.path.dirname(args.out))
        rows_html.append(f"""
        <tr data-status="{html.escape(status)}">
          <td>{badge(status)}</td>
          <td class="mono">{html.escape(run_id)}</td>
          <td>{html.escape(seed)}</td>
          <td class="mono">{html.escape(info["test"])}</td>
          <td class="num">{"" if info["err"] is None else info["err"]}</td>
          <td class="num">{"" if info["fat"] is None else info["fat"]}</td>
          <td class="num">{"" if info["warn"] is None else info["warn"]}</td>
          <td class="msg" title="{title}">{first}</td>
          <td><a href="{html.escape(log_rel)}">log</a></td>
        </tr>""")

    test_rows = []
    for test in sorted(by_test):
        c = by_test[test]
        test_rows.append(
            f"<tr><td class='mono'>{html.escape(test)}</td>"
            f"<td class='num'>{c.get('PASS', 0)}</td>"
            f"<td class='num'>{c.get('FATAL', 0)}</td>"
            f"<td class='num'>{c.get('FAIL', 0)}</td>"
            f"<td class='num'>{c.get('TIMEOUT', 0)}</td>"
            f"<td class='num'>{c.get('NORUN', 0)}</td></tr>"
        )

    cov_html = (
        f'<a href="{cov_link}">Coverage dashboard</a>'
        if cov_exists
        else "Coverage dashboard (not generated)"
    )

    doc = f"""<!DOCTYPE html>
<html lang="zh-CN"><head><meta charset="utf-8">
<title>L2 Cache Scoreboard</title>
<style>
  :root {{ --bg:#f5f6f8; --card:#fff; --line:#d9dde3; --text:#1f2328; }}
  * {{ box-sizing:border-box; }}
  body {{ margin:0; padding:24px; background:var(--bg); color:var(--text);
         font:14px/1.45 -apple-system,BlinkMacSystemFont,"Segoe UI",Arial,sans-serif; }}
  h1 {{ margin:0 0 4px; font-size:22px; }}
  .sub {{ color:#5b6573; margin-bottom:18px; }}
  .cards {{ display:flex; gap:12px; flex-wrap:wrap; margin-bottom:18px; }}
  .card {{ background:var(--card); border:1px solid var(--line); border-radius:8px;
           padding:12px 16px; min-width:120px; }}
  .card .n {{ font-size:24px; font-weight:700; }}
  .card .l {{ color:#5b6573; font-size:12px; }}
  table {{ width:100%; border-collapse:collapse; background:var(--card);
           border:1px solid var(--line); border-radius:8px; overflow:hidden;
           margin-bottom:22px; }}
  th {{ background:#eef1f5; text-align:left; padding:8px 10px; font-size:12px;
        color:#3b4452; border-bottom:1px solid var(--line); position:sticky; top:0; }}
  td {{ padding:7px 10px; border-bottom:1px solid #edf0f3; vertical-align:top; }}
  tr:last-child td {{ border-bottom:none; }}
  .mono {{ font-family:ui-monospace,SFMono-Regular,Consolas,monospace; font-size:12px; }}
  .num {{ text-align:right; font-variant-numeric:tabular-nums; }}
  .msg {{ max-width:620px; overflow:hidden; text-overflow:ellipsis; white-space:nowrap;
          color:#6b1b1b; font-size:12px; }}
  .badge {{ display:inline-block; color:#fff; border-radius:10px; padding:1px 8px;
            font-size:11px; font-weight:700; letter-spacing:.02em; }}
  a {{ color:#0b5cad; text-decoration:none; }}
  a:hover {{ text-decoration:underline; }}
  .toolbar {{ margin-bottom:10px; display:flex; gap:10px; align-items:center; }}
  input, select {{ padding:6px 8px; border:1px solid var(--line); border-radius:6px;
                   background:#fff; }}
  .hint {{ color:#5b6573; font-size:12px; }}
</style></head><body>
<h1>L2 Cache — UVM Scoreboard Results</h1>
<div class="sub">Generated {now} &nbsp;|&nbsp; {cov_html}</div>

<div class="cards">
  <div class="card"><div class="n">{total}</div><div class="l">runs</div></div>
  <div class="card"><div class="n" style="color:#1b7f3a">{pass_n}</div><div class="l">PASS</div></div>
  <div class="card"><div class="n" style="color:#b00020">{fail_n}</div><div class="l">not PASS</div></div>
  <div class="card"><div class="n" style="color:#b00020">{counts.get("FATAL", 0)}</div><div class="l">FATAL</div></div>
  <div class="card"><div class="n" style="color:#c25e00">{counts.get("FAIL", 0)}</div><div class="l">FAIL</div></div>
  <div class="card"><div class="n" style="color:#6a1b9a">{counts.get("TIMEOUT", 0)}</div><div class="l">TIMEOUT</div></div>
</div>

<div class="toolbar">
  <input id="q" placeholder="filter run id / test / message" size="40">
  <select id="st">
    <option value="">all statuses</option>
    {"".join(f"<option>{s}</option>" for s in STATUS_ORDER)}
  </select>
  <span class="hint">点击 log 查看完整 UVM 日志；失败行按 FATAL → FAIL → TIMEOUT → NORUN → PASS 排序。</span>
</div>

<table id="runs">
  <thead><tr>
    <th>status</th><th>run id</th><th>seed</th><th>test class</th>
    <th>ERR</th><th>FATAL</th><th>WARN</th><th>first scoreboard message</th><th>log</th>
  </tr></thead>
  <tbody>
  {"".join(rows_html)}
  </tbody>
</table>

<h2 style="font-size:17px;margin:4px 0 10px">Per-test summary</h2>
<table>
  <thead><tr><th>test class</th><th>PASS</th><th>FATAL</th><th>FAIL</th>
  <th>TIMEOUT</th><th>NORUN</th></tr></thead>
  <tbody>{"".join(test_rows)}</tbody>
</table>

<script>
function applyFilter() {{
  const q = document.getElementById('q').value.toLowerCase();
  const st = document.getElementById('st').value;
  for (const tr of document.querySelectorAll('#runs tbody tr')) {{
    const text = tr.innerText.toLowerCase();
    const okQ = !q || text.includes(q);
    const okS = !st || tr.dataset.status === st;
    tr.style.display = (okQ && okS) ? '' : 'none';
  }}
}}
document.getElementById('q').addEventListener('input', applyFilter);
document.getElementById('st').addEventListener('change', applyFilter);
</script>
</body></html>"""

    os.makedirs(os.path.dirname(args.out), exist_ok=True)
    with open(args.out, "w", encoding="utf-8") as f:
        f.write(doc)
    print(f"[SCOREBOARD] {args.out}")
    print(
        f"[SCOREBOARD] {pass_n}/{total} PASS, "
        f"{fail_n} not PASS (FATAL={counts.get('FATAL', 0)}, "
        f"FAIL={counts.get('FAIL', 0)}, TIMEOUT={counts.get('TIMEOUT', 0)}, "
        f"NORUN={counts.get('NORUN', 0)})"
    )
    return 0 if fail_n == 0 else 1


if __name__ == "__main__":
    raise SystemExit(main())
