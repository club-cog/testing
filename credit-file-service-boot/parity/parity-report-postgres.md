88 cases: 79 match, 9 intentional, 0 fail, 0 new

| Case | Legacy | Boot | Result | Note |
|------|--------|------|--------|------|
| GET /creditfile/100001 | 200 | 200 | MATCH |  |
| GET /creditfile/100002 | 200 | 200 | MATCH |  |
| GET /creditfile/100003 | 200 | 200 | MATCH |  |
| GET /creditfile/100004 | 200 | 200 | MATCH |  |
| GET /creditfile/100005 | 200 | 200 | MATCH |  |
| GET /creditfile/100006 | 200 | 200 | MATCH |  |
| GET /creditfile/100007 | 200 | 200 | MATCH |  |
| GET /creditfile/100008 | 200 | 200 | MATCH |  |
| GET /creditfile/100009 | 200 | 200 | MATCH |  |
| GET /creditfile/100010 | 200 | 200 | MATCH |  |
| GET /creditfile/100011 | 200 | 200 | MATCH |  |
| GET /creditfile/100012 | 200 | 200 | MATCH |  |
| GET /creditfile/100013 | 200 | 200 | MATCH |  |
| GET /creditfile/100014 | 200 | 200 | MATCH |  |
| GET /creditfile/100015 | 200 | 200 | MATCH |  |
| GET /creditfile/100016 | 200 | 200 | MATCH |  |
| GET /creditfile/100020 | 200 | 200 | MATCH |  |
| GET /creditfile/999999 (unknown) | 404 | 404 | MATCH |  |
| GET /creditfile/abc (bad id) | 400 | 400 | INTENTIONAL | framework error page: Jetty HTML -> Spring Boot JSON error body; status unchanged |
| GET /creditfile/100001/ (trailing slash) | 200 | 200 | MATCH |  |
| GET /creditfile/100001.json (suffix match) | 200 | 200 | MATCH |  |
| POST /creditfile/100001 (wrong method) | 405 | 405 | INTENTIONAL | framework error page: Jetty HTML -> Spring Boot JSON error body; status unchanged |
| GET /creditfile/100001 Accept: application/xml | 406 | 406 | MATCH |  |
| GET /consumers/match Siobhan O Briain (unaccented) | 200 | 200 | MATCH |  |
| GET /consumers/match Siobhan OBriain (no space) | 200 | 200 | MATCH |  |
| GET /consumers/match Siobhan O'Briain (apostrophe) | 200 | 200 | MATCH |  |
| GET /consumers/match Siobhán Ó Briain (accented) | 200 | 200 | MATCH |  |
| GET /consumers/match Renee Dubois Marchand | 200 | 200 | MATCH |  |
| GET /consumers/match Lukasz Wisniewski | 200 | 200 | MATCH |  |
| GET /consumers/match Margaret Strauss (sharp s) | 200 | 200 | MATCH |  |
| GET /consumers/match Margaret STRAUSS upper | 200 | 200 | MATCH |  |
| GET /consumers/match X Pryce (initial) | 200 | 200 | MATCH |  |
| GET /consumers/match Xan Pryce (short form) | 200 | 200 | MATCH |  |
| GET /consumers/match Xa Pryce (2-char, no match) | 200 | 200 | MATCH |  |
| GET /consumers/match Xander Pryce wrong dob | 200 | 200 | MATCH |  |
| GET /consumers/match missing dob | 400 | 400 | INTENTIONAL | framework error page: Jetty HTML -> Spring Boot JSON error body; status unchanged |
| GET /consumers/match bad dob | 500 | 500 | INTENTIONAL | framework error page: Jetty HTML -> Spring Boot JSON error body; status unchanged |
| SOAP GetTradeline 7000002 | 200 | 200 | MATCH |  |
| SOAP GetTradeline 7000019 (disputed) | 200 | 200 | MATCH |  |
| SOAP GetTradeline no Header element | 200 | 200 | MATCH |  |
| SOAP GetTradeline default namespace | 200 | 200 | MATCH |  |
| SOAP GetTradeline un-namespaced children | 200 | 200 | MATCH |  |
| SOAP GetTradeline with SOAPAction, no charset | 200 | 200 | MATCH |  |
| SOAP GetTradeline 1 (fault not found) | 200 | 200 | MATCH |  |
| SOAP unknown operation (fault) | 200 | 200 | MATCH |  |
| SOAP empty Body (fault) | 200 | 200 | MATCH |  |
| SOAP no Body element (fault) | 200 | 200 | MATCH |  |
| SOAP unknown operation without tradelineId (500) | 500 | 500 | INTENTIONAL | framework error page: Jetty HTML -> Spring Boot JSON error body; status unchanged |
| SOAP GetTradeline missing tradelineId (500) | 500 | 500 | INTENTIONAL | framework error page: Jetty HTML -> Spring Boot JSON error body; status unchanged |
| SOAP malformed XML (500) | 500 | 500 | INTENTIONAL | framework error page: Jetty HTML -> Spring Boot JSON error body; status unchanged |
| SOAP GetTradeline with DOCTYPE (XXE hardening) | 200 | 500 | INTENTIONAL | DTDs rejected (XXE hardening; SOAP 1.1 forbids a DOCTYPE) - legacy resolved the entity, Boot returns 500 |
| GET /ws/TradelineMaintenance (405) | 405 | 405 | INTENTIONAL | framework error page: Jetty HTML -> Spring Boot JSON error body; status unchanged |
| SOAP SetDisputeFlag 7000001 Y | 200 | 200 | MATCH |  |
| SOAP SetDisputeFlag 1 (NOT_FOUND) | 200 | 200 | MATCH |  |
| SOAP GetTradeline 7000001 after SetDisputeFlag | 200 | 200 | MATCH |  |
| SOAP AmendTradeline 7000004 status+balance | 200 | 200 | MATCH |  |
| SOAP GetTradeline 7000004 after amend | 200 | 200 | MATCH |  |
| SOAP AmendTradeline 7000008 same status (no-op) | 200 | 200 | MATCH |  |
| SOAP AmendTradeline 7000005 delete | 200 | 200 | MATCH |  |
| GET /creditfile/100003 after delete | 200 | 200 | MATCH |  |
| SOAP AmendTradeline 9 (NOT_FOUND) | 200 | 200 | MATCH |  |
| SOAP AmendTradeline 7000010 non-ASCII operator, UTF-8 | 200 | 200 | MATCH |  |
| SOAP AmendTradeline 7000011 non-ASCII operator, latin-1 body no charset | 200 | 200 | MATCH |  |
| GET /creditfile/100002 after amend | 200 | 200 | MATCH |  |
| score-service GET /score/100001 (via credit-file) | 200 | 200 | MATCH |  |
| score-service GET /score/100002 (via credit-file) | 200 | 200 | MATCH |  |
| score-service GET /score/100003 (via credit-file) | 200 | 200 | MATCH |  |
| score-service GET /score/100004 (via credit-file) | 200 | 200 | MATCH |  |
| score-service GET /score/100005 (via credit-file) | 200 | 200 | MATCH |  |
| score-service GET /score/100006 (via credit-file) | 200 | 200 | MATCH |  |
| score-service GET /score/100007 (via credit-file) | 200 | 200 | MATCH |  |
| score-service GET /score/100008 (via credit-file) | 200 | 200 | MATCH |  |
| score-service GET /score/100009 (via credit-file) | 200 | 200 | MATCH |  |
| score-service GET /score/100010 (via credit-file) | 200 | 200 | MATCH |  |
| score-service GET /score/100011 (via credit-file) | 200 | 200 | MATCH |  |
| score-service GET /score/100012 (via credit-file) | 200 | 200 | MATCH |  |
| score-service GET /score/100013 (via credit-file) | 200 | 200 | MATCH |  |
| score-service GET /score/100014 (via credit-file) | 200 | 200 | MATCH |  |
| score-service GET /score/100015 (via credit-file) | 200 | 200 | MATCH |  |
| score-service GET /score/100016 (via credit-file) | 200 | 200 | MATCH |  |
| dispute-service POST /disputes (SetDisputeFlag Y) | 201 | 201 | MATCH |  |
| dispute-service POST /disputes/40001/resolve AMEND | 200 | 200 | MATCH |  |
| SOAP GetTradeline 7000012 after dispute open | 200 | 200 | MATCH |  |
| SOAP GetTradeline 7000019 after dispute resolve | 200 | 200 | MATCH |  |
| GET /creditfile/100016 after dispute resolve | 200 | 200 | MATCH |  |
| score-service GET /score/100016 after resolve | 200 | 200 | MATCH |  |
| DB AUDIT_LOG rows | 0 | 0 | MATCH |  |
| DB ACCOUNT_TRADELINE touched rows | 0 | 0 | MATCH |  |
