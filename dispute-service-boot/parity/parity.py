#!/usr/bin/env python3
"""Behavioural parity harness for dispute-service (legacy) vs dispute-service-boot.

  record:  python3 parity.py record --dispute http://localhost:8083 --out fixtures/legacy
  compare: python3 parity.py compare fixtures/legacy target/parity/boot

`record` runs a fixed scenario list against a freshly seeded DB (scripts/db-reset.sh) and writes one
JSON fixture per scenario. It also starts two capturing proxies (credit-file on :18081, score on :18082)
so the outbound SOAP envelopes and score recalculation calls are recorded byte for byte. Start the
service under test with creditfile.url=http://localhost:18081 and score.url=http://localhost:18082.
Values stamped with "now" (event/letter/resolve timestamps written during the run) are normalised.
"""
import argparse
import datetime
import json
import os
import re
import sys
import threading
import urllib.error
import urllib.request
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

CAPTURED_HEADERS = ("Content-Type", "SOAPAction", "Accept")
SOAP = ('<soapenv:Envelope xmlns:soapenv="http://schemas.xmlsoap.org/soap/envelope/" '
        'xmlns:tl="urn:ukcredit:tradeline:v1"><soapenv:Header/><soapenv:Body>'
        '<tl:GetTradelineRequest><tl:tradelineId>{}</tl:tradelineId></tl:GetTradelineRequest>'
        '</soapenv:Body></soapenv:Envelope>')

# (name, method, path, body, target) - target is the service the request goes to
SCENARIOS = [
    ("s01_get_seeded_open", "GET", "/disputes/40001", None, "dispute"),
    ("s02_get_historic_closed", "GET", "/disputes/40005", None, "dispute"),
    ("s03_get_not_found", "GET", "/disputes/99999", None, "dispute"),
    ("s04_get_non_numeric_id", "GET", "/disputes/abc", None, "dispute"),
    ("s05_get_trailing_slash", "GET", "/disputes/40001/", None, "dispute"),
    ("s06_sla_before_cutoff_ew", "GET", "/disputes/sla?received=2024-12-20T10:15:00&region=EW", None, "dispute"),
    ("s07_sla_after_cutoff_ew", "GET", "/disputes/sla?received=2024-12-20T18:00:00&region=EW", None, "dispute"),
    ("s08_sla_after_cutoff_sc", "GET", "/disputes/sla?received=2024-12-20T18:00:00&region=SC", None, "dispute"),
    ("s09_sla_exactly_cutoff", "GET", "/disputes/sla?received=2024-12-20T17:30:00&region=EW", None, "dispute"),
    ("s10_sla_one_minute_after", "GET", "/disputes/sla?received=2024-12-20T17:31:00&region=EW", None, "dispute"),
    ("s11_sla_saturday_default_region", "GET", "/disputes/sla?received=2024-12-21T09:00:00", None, "dispute"),
    ("s12_sla_easter_ew", "GET", "/disputes/sla?received=2025-04-17T12:00:00&region=EW", None, "dispute"),
    ("s13_sla_easter_sc", "GET", "/disputes/sla?received=2025-04-17T12:00:00&region=SC", None, "dispute"),
    ("s14_sla_missing_received", "GET", "/disputes/sla", None, "dispute"),
    ("s15_sla_bad_received", "GET", "/disputes/sla?received=2024-12-20", None, "dispute"),
    ("s16_open_missing_fields", "POST", "/disputes", {"cnsmrId": 100012}, "dispute"),
    ("s17_open_malformed_json", "POST", "/disputes", "{not json", "dispute"),
    ("s18_open_scotland_after_cutoff", "POST", "/disputes",
     {"cnsmrId": 100012, "trdlnId": 7000016, "rsnCd": "WRONGBAL", "chnlCd": "TEL", "rcvdTs": "2024-12-20T18:00:00"},
     "dispute"),
    ("s19_tradeline_flag_after_open", "SOAP", "/ws/TradelineMaintenance", 7000016, "creditfile"),
    ("s20_open_bt_postcode_default_channel", "POST", "/disputes",
     {"cnsmrId": 100008, "trdlnId": 7000012, "rsnCd": "NOTMINE", "rcvdTs": "2024-12-20T10:15:00"}, "dispute"),
    ("s21_open_public_record", "POST", "/disputes",
     {"cnsmrId": 100014, "pubRecId": 1, "rsnCd": "PAIDOFF", "chnlCd": "PST", "rcvdTs": "2025-01-02T09:00:00"},
     "dispute"),
    ("s22_public_record_flag_after_open", "GET", "/creditfile/100014", None, "creditfile"),
    ("s23_open_string_ids", "POST", "/disputes",
     {"cnsmrId": "100013", "trdlnId": "7000017", "rsnCd": "FRAUD", "chnlCd": "WEB", "rcvdTs": "2024-12-24T16:00:00"},
     "dispute"),
    ("s24_resolve_bad_outcome", "POST", "/disputes/40014/resolve", {"outcome": "UPHELD", "operatorId": "OPS0002"},
     "dispute"),
    ("s25_resolve_unknown_operator", "POST", "/disputes/40014/resolve", {"outcome": "AMEND", "operatorId": "OPS9999"},
     "dispute"),
    ("s26_resolve_amend", "POST", "/disputes/40014/resolve",
     {"outcome": "AMEND", "operatorId": "OPS0002", "statusCd": "0", "balancePence": 0}, "dispute"),
    ("s27_tradeline_after_amend", "SOAP", "/ws/TradelineMaintenance", 7000016, "creditfile"),
    ("s28_resolve_already_closed", "POST", "/disputes/40014/resolve", {"outcome": "NOCHANGE", "operatorId": "OPS0002"},
     "dispute"),
    ("s29_resolve_not_found", "POST", "/disputes/99999/resolve", {"outcome": "NOCHANGE", "operatorId": "OPS0002"},
     "dispute"),
    ("s30_resolve_public_record_nochange", "POST", "/disputes/40016/resolve",
     {"outcome": "NOCHANGE", "operatorId": "OPS0003"}, "dispute"),
    ("s31_public_record_flag_after_resolve", "GET", "/creditfile/100014", None, "creditfile"),
    ("s32_resolve_delete", "POST", "/disputes/40015/resolve", {"outcome": "DELETE", "operatorId": "OPS0001"},
     "dispute"),
    ("s33_tradeline_after_delete", "SOAP", "/ws/TradelineMaintenance", 7000012, "creditfile"),
    ("s34_resolve_inactive_operator", "POST", "/disputes/40017/resolve",
     {"outcome": "NOCHANGE", "operatorId": "OPS0099"}, "dispute"),
    ("s35_resolve_seeded_case", "POST", "/disputes/40001/resolve", {"outcome": "NOCHANGE", "operatorId": "OPS0002"},
     "dispute"),
    ("s36_get_after_resolve", "GET", "/disputes/40001", None, "dispute"),
    ("s37_score_history_triggers", "GET", "/score/100012/history", None, "score"),
]

_captured = []
_lock = threading.Lock()


def _handler(upstream, label):
    class H(BaseHTTPRequestHandler):
        def _proxy(self):
            n = int(self.headers.get("Content-Length") or 0)
            body = self.rfile.read(n) if n else b""
            with _lock:
                _captured.append({"to": label, "method": self.command, "path": self.path,
                                  "headers": {h: self.headers.get(h) for h in CAPTURED_HEADERS if self.headers.get(h)},
                                  "body": body.decode("utf-8")})
            req = urllib.request.Request(upstream + self.path, data=body if self.command == "POST" else None,
                                         method=self.command)
            for h in ("Content-Type", "SOAPAction", "Accept"):
                if self.headers.get(h):
                    req.add_header(h, self.headers.get(h))
            try:
                with urllib.request.urlopen(req, timeout=30) as r:
                    status, data, ctype = r.status, r.read(), r.headers.get("Content-Type")
            except urllib.error.HTTPError as e:
                status, data, ctype = e.code, e.read(), e.headers.get("Content-Type")
            self.send_response(status)
            if ctype:
                self.send_header("Content-Type", ctype)
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        do_GET = do_POST = _proxy

        def log_message(self, *a):
            pass
    return H


def _start_proxy(port, upstream, label):
    srv = ThreadingHTTPServer(("127.0.0.1", port), _handler(upstream, label))
    threading.Thread(target=srv.serve_forever, daemon=True).start()
    return srv


def _call(base, method, path, body):
    headers = {}
    data = None
    if method == "SOAP":
        method, data = "POST", SOAP.format(body).encode()
        headers = {"Content-Type": "text/xml;charset=UTF-8", "SOAPAction": "urn:ukcredit:tradeline:v1:GetTradeline"}
    elif body is not None:
        data = (body if isinstance(body, str) else json.dumps(body)).encode()
        headers = {"Content-Type": "application/json"}
    req = urllib.request.Request(base + path, data=data, method=method, headers=headers)
    try:
        with urllib.request.urlopen(req, timeout=30) as r:
            return r.status, r.headers.get("Content-Type"), r.read().decode("utf-8", "replace")
    except urllib.error.HTTPError as e:
        return e.code, e.headers.get("Content-Type"), e.read().decode("utf-8", "replace")


def _normalise(v, today):
    if isinstance(v, dict):
        return {k: _normalise(x, today) for k, x in v.items()}
    if isinstance(v, list):
        return [_normalise(x, today) for x in v]
    if isinstance(v, str) and re.match(r"^\d{4}-\d{2}-\d{2}[ T]\d{2}:\d{2}", v) and v[:10] == today:
        return "<now>"
    return v


def record(args):
    os.makedirs(args.out, exist_ok=True)
    today = datetime.date.today().isoformat()
    proxies = [_start_proxy(18081, args.creditfile, "credit-file-service"), _start_proxy(18082, args.score, "score-service")]
    bases = {"dispute": args.dispute, "creditfile": args.creditfile, "score": args.score}
    for name, method, path, body, target in SCENARIOS:
        with _lock:
            del _captured[:]
        status, ctype, text = _call(bases[target], method, path, body)
        try:
            parsed = _normalise(json.loads(text), today)
        except ValueError:
            parsed = None
        with _lock:
            outbound = list(_captured)
        fx = {"request": {"method": method, "path": path, "body": body, "target": target},
              "status": status, "contentType": ctype,
              "json": parsed, "nonJsonBody": None if parsed is not None else text,
              "outbound": outbound}
        with open(os.path.join(args.out, name + ".json"), "w", encoding="utf-8") as f:
            json.dump(fx, f, indent=2, ensure_ascii=False)
            f.write("\n")
        print("%-40s %s %s" % (name, status, "(%d outbound)" % len(outbound) if outbound else ""))
    for p in proxies:
        p.shutdown()


def _media(ct):
    return (ct or "").split(";")[0].strip().lower()


def _is_html_error_page(rec):
    return rec["json"] is None and (rec["contentType"] or "").startswith("text/html") and int(rec["status"]) >= 400


def compare(args):
    """Status, body and every outbound call (path, headers, SOAP/JSON body) must match exactly.

    The only tolerated difference is a container-generated HTML error page (legacy Jetty) becoming
    Spring Boot's JSON error body with the same status; it is counted separately as intentional."""
    rows, failures, intentional = [], 0, 0
    for fn in sorted(os.listdir(args.expected)):
        if not fn.endswith(".json"):
            continue
        with open(os.path.join(args.expected, fn), encoding="utf-8") as f:
            exp = json.load(f)
        path = os.path.join(args.actual, fn)
        if not os.path.exists(path):
            rows.append((fn[:-5], exp["status"], "-", "missing", "missing", "missing"))
            failures += 1
            continue
        with open(path, encoding="utf-8") as f:
            act = json.load(f)
        status = "same" if exp["status"] == act["status"] else "DIFF"
        if exp["json"] is not None or act["json"] is not None:
            body = "same" if exp["json"] == act["json"] else "DIFF"
        else:
            body = "same (XML)" if exp["nonJsonBody"] == act["nonJsonBody"] else "DIFF"
        if body == "DIFF" and status == "same" and _is_html_error_page(exp) and act["json"] is not None:
            body = "Jetty HTML error page -> Boot JSON error (intentional)"
            intentional += 1
        out = "same" if exp["outbound"] == act["outbound"] else "DIFF"
        if not exp["outbound"] and not act["outbound"]:
            out = "none"
        if status == "DIFF" or body == "DIFF" or out == "DIFF":
            failures += 1
        rows.append((fn[:-5], exp["status"], act["status"], status, body, out))
    print("| Scenario | Legacy | Boot | Status | Body | Outbound calls |")
    print("|---|---|---|---|---|---|")
    for r in rows:
        print("| %s | %s | %s | %s | %s | %s |" % r)
    print("\n%d scenario(s), %d unexpected difference(s), %d intentional" % (len(rows), failures, intentional))
    return 1 if failures else 0


def main():
    p = argparse.ArgumentParser()
    sub = p.add_subparsers(dest="cmd", required=True)
    r = sub.add_parser("record")
    r.add_argument("--dispute", default="http://localhost:8083")
    r.add_argument("--creditfile", default="http://localhost:8081")
    r.add_argument("--score", default="http://localhost:8082")
    r.add_argument("--out", required=True)
    c = sub.add_parser("compare")
    c.add_argument("expected")
    c.add_argument("actual")
    a = p.parse_args()
    sys.exit(record(a) if a.cmd == "record" else compare(a))


if __name__ == "__main__":
    main()
