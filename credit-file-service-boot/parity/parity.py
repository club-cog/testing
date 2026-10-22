#!/usr/bin/env python3
"""Behavioural parity harness for credit-file-service (legacy vs Boot).

  parity.py capture --out fixtures.json   record responses (normally against legacy)
  parity.py compare --fixtures fixtures.json [--report report.md]

Cases live in cases.json and run in file order (reads first, then SOAP mutations, then
downstream calls through score-service / dispute-service). Run against a freshly reset DB.
"""
import argparse
import datetime
import json
import re
import shlex
import subprocess
import sys
import urllib.error
import urllib.request

TODAY = datetime.date.today().isoformat()
TIMING = re.compile(r"^\(\d+ rows?, \d+ ms\)$")
VOLATILE = re.compile(re.escape(TODAY) + r"(?:[ T]\d{2}:\d{2}(?::\d{2}(?:\.\d+)?)?)?")


def mask(value):
    if isinstance(value, str):
        return VOLATILE.sub(lambda m: "<TODAY>" if len(m.group(0)) == 10 else "<NOW>", value)
    if isinstance(value, list):
        return [mask(v) for v in value]
    if isinstance(value, dict):
        return {k: mask(v) for k, v in value.items()}
    return value


def http(base, case):
    data = case.get("body")
    raw = data.encode(case.get("bodyEncoding", "utf-8")) if data is not None else None
    req = urllib.request.Request(base + case["path"], data=raw, method=case.get("method", "GET"))
    for k, v in case.get("headers", {}).items():
        req.add_header(k, v)
    try:
        with urllib.request.urlopen(req, timeout=15) as r:
            status, ctype, body = r.status, r.headers.get("Content-Type"), r.read()
    except urllib.error.HTTPError as e:
        status, ctype, body = e.code, e.headers.get("Content-Type"), e.read()
    text = body.decode("utf-8", errors="replace")
    ctype = (ctype or "").replace(" ", "").lower() or None
    parsed = text
    if ctype and "json" in ctype and text:
        try:
            parsed = json.loads(text)
        except ValueError:
            pass
    return {"status": status, "contentType": ctype, "body": mask(parsed)}


def db(shell, case):
    out = subprocess.run(shell + [case["sql"]], capture_output=True, text=True, timeout=60)
    lines = [l.rstrip() for l in out.stdout.splitlines() if l.strip() and not TIMING.match(l.strip())]
    return {"status": out.returncode, "contentType": "db", "body": mask(lines)}


def run(args):
    bases = {"cf": args.cf, "score": args.score, "dispute": args.dispute}
    shell = shlex.split(args.db_shell) if args.db_shell else None
    with open(args.cases) as f:
        cases = json.load(f)
    results = []
    for c in cases:
        if c.get("target") == "db":
            if shell is None:
                continue
            r = db(shell, c)
        else:
            r = http(bases[c.get("target", "cf")], c)
        r["name"] = c["name"]
        results.append(r)
    return cases, results


def compare(cases, expected, actual):
    by_name = {c["name"]: c for c in cases}
    exp = {r["name"]: r for r in expected}
    rows, failures = [], 0
    for a in actual:
        e = exp.get(a["name"])
        c = by_name[a["name"]]
        if e is None:
            rows.append((a["name"], "-", str(a["status"]), "NEW", "not in baseline"))
            continue
        diffs = [k for k in ("status", "contentType", "body") if e[k] != a[k]]
        if not diffs:
            verdict, note = "MATCH", ""
        elif c.get("intentional") and set(diffs) <= set(c["intentional"]["fields"]):
            verdict, note = "INTENTIONAL", c["intentional"]["reason"]
        else:
            verdict, note = "FAIL", "differs: " + ", ".join(diffs)
            failures += 1
        rows.append((a["name"], str(e["status"]), str(a["status"]), verdict, note))
    return rows, failures


def main():
    p = argparse.ArgumentParser()
    p.add_argument("mode", choices=["capture", "compare"])
    p.add_argument("--cases", default="cases.json")
    p.add_argument("--cf", default="http://localhost:8081")
    p.add_argument("--score", default="http://localhost:8082")
    p.add_argument("--dispute", default="http://localhost:8083")
    p.add_argument("--db-shell", help="command that takes one SQL string as its last argument")
    p.add_argument("--out")
    p.add_argument("--fixtures")
    p.add_argument("--actual-out")
    p.add_argument("--report")
    args = p.parse_args()

    cases, results = run(args)
    if args.mode == "capture":
        with open(args.out, "w") as f:
            json.dump(results, f, indent=1, ensure_ascii=False, sort_keys=True)
            f.write("\n")
        print("captured %d cases -> %s" % (len(results), args.out))
        return 0

    with open(args.fixtures) as f:
        expected = json.load(f)
    if args.actual_out:
        with open(args.actual_out, "w") as f:
            json.dump(results, f, indent=1, ensure_ascii=False, sort_keys=True)
            f.write("\n")
    rows, failures = compare(cases, expected, results)
    table = ["| Case | Legacy | Boot | Result | Note |", "|------|--------|------|--------|------|"]
    table += ["| %s |" % " | ".join(r) for r in rows]
    counts = {v: sum(1 for r in rows if r[3] == v) for v in ("MATCH", "INTENTIONAL", "FAIL", "NEW")}
    summary = "%d cases: %d match, %d intentional, %d fail, %d new" % (
        len(rows), counts["MATCH"], counts["INTENTIONAL"], counts["FAIL"], counts["NEW"])
    out = summary + "\n\n" + "\n".join(table) + "\n"
    if args.report:
        with open(args.report, "w") as f:
            f.write(out)
    print(out)
    return 1 if failures else 0


if __name__ == "__main__":
    sys.exit(main())
