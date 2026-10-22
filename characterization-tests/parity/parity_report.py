#!/usr/bin/env python3
"""Builds docs/cutover/score-service-parity-report.md from two characterization-suite runs.

Each run directory holds the module's surefire-reports/ and characterization/<target>/ outputs:

  parity_report.py --legacy runs/legacy --candidate runs/boot --candidate-label boot \
      --findings docs/cutover/parity-findings.json --out docs/cutover/score-service-parity-report.md

Only checks in the ScoreApi category (the ones executed in the candidate run) are compared. With
--candidate-label legacy the report is a legacy-vs-legacy baseline.
"""
import argparse
import datetime
import glob
import json
import os
import sys
import xml.etree.ElementTree as ET

MATCHED, DIFFERED, INTENTIONAL = "MATCHED", "DIFFERED", "INTENTIONAL CHANGE"


def load_run(path):
    cases = {}
    for f in sorted(glob.glob(os.path.join(path, "surefire-reports", "TEST-*.xml"))):
        for tc in ET.parse(f).getroot().iter("testcase"):
            name = tc.get("classname").rsplit(".", 1)[-1] + "." + tc.get("name")
            problem = next((c for c in tc if c.tag in ("failure", "error")), None)
            skipped = tc.find("skipped") is not None
            cases[name] = {
                "status": "SKIPPED" if skipped else ("PASS" if problem is None else problem.tag.upper()),
                "message": (problem.get("message") or "").strip() if problem is not None else "",
            }
    diffs = {}
    for f in glob.glob(os.path.join(path, "characterization", "*", "*-golden-diff.json")):
        with open(f, encoding="utf-8") as fh:
            diffs[os.path.basename(f)] = json.load(fh)
    return cases, diffs


def one_line(s, n=160):
    s = " ".join(s.split()).replace("|", "\\|")
    return s if len(s) <= n else s[: n - 1] + "…"


def classify(legacy, cand, finding):
    if legacy is None or legacy["status"] != "PASS":
        return DIFFERED, "legacy baseline did not pass this check; the suite or environment is broken"
    if cand is not None and cand["status"] == "PASS":
        return MATCHED, ""
    if finding.get("classification") == INTENTIONAL:
        return INTENTIONAL, finding.get("root_cause", "")
    return DIFFERED, finding.get("root_cause", "not yet analysed")


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--legacy", required=True)
    ap.add_argument("--candidate", required=True)
    ap.add_argument("--candidate-label", default="boot")
    ap.add_argument("--findings")
    ap.add_argument("--meta", action="append", default=[], help="key=value rows for the Environment table")
    ap.add_argument("--out", required=True)
    a = ap.parse_args()

    legacy_cases, _ = load_run(a.legacy)
    cand_cases, cand_diffs = load_run(a.candidate)
    if not cand_cases:
        sys.exit("no surefire results under " + a.candidate)
    findings = {"checks": {}, "consumers": {}}
    if a.findings and os.path.exists(a.findings):
        with open(a.findings, encoding="utf-8") as fh:
            findings.update(json.load(fh))
    baseline = a.candidate_label == "legacy"
    meta = dict(kv.split("=", 1) for kv in a.meta)

    rows = []
    for name in sorted(cand_cases):
        f = findings["checks"].get(name, {})
        cls, cause = classify(legacy_cases.get(name), cand_cases[name], f)
        rows.append((name, legacy_cases.get(name, {"status": "MISSING"})["status"], cand_cases[name]["status"],
                     cls, cause, cand_cases[name]["message"]))
    counts = {k: sum(1 for r in rows if r[3] == k) for k in (MATCHED, DIFFERED, INTENTIONAL)}

    score_diff = cand_diffs.get("score-golden-diff.json", {"checked": 0, "diffs": {}})
    consumer_rows = []
    for cid, d in sorted(score_diff.get("diffs", {}).items()):
        f = findings["consumers"].get(cid, {})
        cls = INTENTIONAL if f.get("classification") == INTENTIONAL else DIFFERED
        consumer_rows.append((cid, cls, f.get("root_cause", "not yet analysed"), d))
    c_counts = {
        MATCHED: score_diff.get("checked", 0) - len(consumer_rows),
        DIFFERED: sum(1 for r in consumer_rows if r[1] == DIFFERED),
        INTENTIONAL: sum(1 for r in consumer_rows if r[1] == INTENTIONAL),
    }

    if baseline:
        verdict = ("**NOT A CUTOVER DECISION — baseline only.** No `score-service` migration PR was open, so "
                   "the candidate is the legacy score-service itself. This run proves the suite is deterministic "
                   "and green on legacy; cutover remains **NO-GO** until this report is regenerated against "
                   "`score-service-boot`.")
    elif counts[DIFFERED] or c_counts[DIFFERED]:
        verdict = ("**NO-GO.** %d check(s) / %d consumer score(s) differ from legacy without an approved "
                   "intentional-change record. Fix or obtain Risk/Model Governance approval, then re-run."
                   % (counts[DIFFERED], c_counts[DIFFERED]))
    else:
        verdict = ("**GO**, subject to the sign-offs below. All score-service checks match legacy"
                   + (" or are approved intentional changes." if counts[INTENTIONAL] or c_counts[INTENTIONAL] else "."))

    cand_title = "legacy score-service (re-run)" if baseline else "score-service-" + a.candidate_label
    out = []
    w = out.append
    w("# Cutover sign-off: score-service parity report")
    w("")
    w("_Generated by `characterization-tests/parity/parity_report.py` on %s. Do not hand-edit tables; "
      "edit `docs/cutover/parity-findings.json` and regenerate._"
      % datetime.datetime.utcnow().strftime("%Y-%m-%d %H:%M UTC"))
    w("")
    if baseline:
        w("> **Baseline only: legacy vs legacy.** No open PR into `uk-credit-legacy` titled `score-service…` "
          "was found, so no `score-service-boot` run is included. Re-run the generator against the Boot run "
          "(see *How to regenerate*) before using this as a cutover decision.")
        w("")
    w("## Scope")
    w("")
    w("- **Under test:** `%s`, black-box over HTTP (`-Dscore.url`), compared with legacy `score-service` "
      "(Java 8 / Spring 4)." % cand_title)
    w("- **Checks compared:** every characterization test in the `ScoreApi` category (%d checks), including the "
      "golden master of `GET /score/{id}?asOf=2024-12-31` for all %d seeded consumers."
      % (len(rows), score_diff.get("checked", 0)))
    w("- **Out of scope:** credit-file-service and dispute-service behaviour (still legacy at cutover; covered "
      "by the legacy run of the same suite), batch-ingest, performance and non-functional checks.")
    w("")
    w("## Environment")
    w("")
    w("| Item | Value |")
    w("|---|---|")
    for k, v in [("Legacy score-service", meta.get("legacy_url", "http://localhost:8082")),
                 ("Candidate", meta.get("candidate_url", "http://localhost:8082" if baseline else "")),
                 ("Database", meta.get("db", "PostgreSQL 15, shared by both implementations")),
                 ("JDK", meta.get("jdk", "legacy: 8")),
                 ("Legacy revision", meta.get("legacy_rev", "")),
                 ("Candidate revision", meta.get("candidate_rev", "")),
                 ("Run", meta.get("run", "local"))]:
        w("| %s | %s |" % (k, v or "n/a"))
    w("")
    w("## Seed")
    w("")
    w("`scripts/db-reset.sh` (Flyway V1–V7 + `SeedDataGenerator`, `Random(20241231L)`): consumers "
      "100001–100016 are the documented edge cases, 100017–%d random filler. Scores are requested "
      "`asOf=2024-12-31`. The golden files were recorded on legacy straight after a reset."
      % (100000 + score_diff.get("checked", 256)))
    w("")
    w("## Suite version")
    w("")
    w("`characterization-tests` at %s; golden files `score-uks3.json`, `creditfile-edge-cases.json`."
      % (meta.get("suite_rev") or "this commit"))
    w("")
    w("## Summary")
    w("")
    w("| Result | Checks | Consumer scores (golden master) |")
    w("|---|---:|---:|")
    for k in (MATCHED, DIFFERED, INTENTIONAL):
        w("| %s | %d | %d |" % (k, counts[k], c_counts[k]))
    w("| **Total** | **%d** | **%d** |" % (len(rows), score_diff.get("checked", 0)))
    w("")
    w("## Per-check results")
    w("")
    w("| Check | Legacy | %s | Result | Root cause / note |" % ("Legacy re-run" if baseline else a.candidate_label))
    w("|---|---|---|---|---|")
    for name, ls, cs, cls, cause, msg in rows:
        note = cause or ""
        if cls != MATCHED and msg:
            note = (note + " — " if note else "") + "`" + one_line(msg, 120) + "`"
        w("| `%s` | %s | %s | %s | %s |" % (name, ls, cs, cls, one_line(note, 400) if note else ""))
    w("")
    w("## Differences and root causes")
    w("")
    if not consumer_rows and not any(r[3] != MATCHED for r in rows):
        w("None. Every compared check and all %d golden-master scores are identical." % score_diff.get("checked", 0))
    else:
        for name, ls, cs, cls, cause, msg in rows:
            if cls != MATCHED:
                w("- **`%s`** (%s): %s" % (name, cls, cause or "not yet analysed"))
        if consumer_rows:
            w("")
            w("Golden-master consumers that differ (field: legacy → %s):" % a.candidate_label)
            w("")
            w("| Consumer | Result | Fields | Root cause |")
            w("|---|---|---|---|")
            for cid, cls, cause, d in consumer_rows:
                w("| %s | %s | %s | %s |" % (cid, cls, one_line("; ".join(d), 300), one_line(cause, 300)))
    w("")
    w("## Recommendation")
    w("")
    w(verdict)
    w("")
    w("## Sign-off")
    w("")
    w("| Role | Name | Decision (GO / NO-GO) | Date |")
    w("|---|---|---|---|")
    for role in ("Engineering", "QA", "Risk / Model Governance", "Platform"):
        w("| %s | | | |" % role)
    w("")
    w("## How to regenerate")
    w("")
    w("```sh")
    w("scripts/build.sh && . scripts/env-postgres.sh && scripts/db-reset.sh && scripts/run-all.sh")
    w("mvn -B -pl characterization-tests test -Dcharacterization=true                       # legacy, full suite")
    w("cp -r characterization-tests/target runs/legacy")
    w("# start the candidate on :8092 against the same DB, then:")
    w("mvn -B -pl characterization-tests test -Dcharacterization=true -Dsuite.target=boot \\")
    w("    -Dscore.url=http://localhost:8092 -Dgroups=com.ukcredit.characterization.ScoreApi")
    w("cp -r characterization-tests/target runs/boot")
    w("python3 characterization-tests/parity/parity_report.py --legacy runs/legacy --candidate runs/boot \\")
    w("    --candidate-label boot --findings docs/cutover/parity-findings.json \\")
    w("    --out docs/cutover/score-service-parity-report.md")
    w("```")
    w("")
    w("The `characterization` GitHub Actions workflow does the same on every PR into `uk-credit-legacy` and "
      "uploads the generated report as the `parity-report` artifact.")

    os.makedirs(os.path.dirname(os.path.abspath(a.out)), exist_ok=True)
    with open(a.out, "w", encoding="utf-8") as fh:
        fh.write("\n".join(out) + "\n")
    summary = "| Result | Checks | Consumer scores |\n|---|---:|---:|\n" + "\n".join(
        "| %s | %d | %d |" % (k, counts[k], c_counts[k]) for k in (MATCHED, DIFFERED, INTENTIONAL))
    print(summary)
    return 1 if (counts[DIFFERED] or c_counts[DIFFERED]) else 0


if __name__ == "__main__":
    sys.exit(main())
