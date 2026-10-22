# uk-credit-legacy build spec (WIP handoff)

Synthetic legacy UK credit-bureau estate for a customer demo. Everything is fictional. Java 8, Spring 4.3 XML config,
Maven multi-module, embedded Jetty 9.4 via `com.ukcredit.common.EmbeddedServer` (shared-db). H2 file DB
(`./data/h2/ukcredit`, MODE=PostgreSQL, AUTO_SERVER=TRUE) by default; Postgres via docker-compose with `-Djdbc.*` overrides.

DONE: parent pom, shared-db (Flyway V1-V7, ~29 tables, DbMigrate, SeedDataGenerator, NameNormaliser, MoneyUtil,
AccountHash, EmbeddedServer, shared-datasource.xml), credit-file-service partial (pom, XML, domain, rules).
NOT YET COMPILED (Maven Central was blocked on the authoring VM) - fix compile errors first.

## Ports
credit-file-service 8081, score-service 8082, dispute-service 8083. batch-ingest is a CLI.

## Business quirks (must exist exactly as described; they are the demo)
1. **Status X cutoff** - `TradelineStatusMapper` (credit-file) and a duplicated `LegacyStatusTranslator` in score-service
   ("keep in step with credit-file TradelineStatusMapper"). X with ACCT_STS_DT before **2014-04-01** (hard-coded) => DEFAULT;
   on/after => ARRANGEMENT. The comment claims the cutoff is read from SYS_PARAM.TRDLN_X_CUTOFF_DT, which says
   2015-01-01 and is never read (misleading on purpose). TRADELINE_STATUS_REF describes X as "Account in query" (stale).
2. **Dispute SLA skips UK bank holidays** - dispute-service `SlaCalculator`, java.util.Calendar based. If received after
   17:30 (SYS_PARAM DSPT_CUTOFF_TM, which IS read) or on a non-working day, clock starts next working day. Due date = start
   + 20 working days (start day not counted), skipping Sat/Sun and BANK_HOLIDAY rows for the region. Region = SC if the
   consumer's current postcode area is Scottish (AB, DD, DG, EH, FK, G, HS, IV, KA, KW, KY, ML, PA, PH, TD, ZE), else EW
   (NI "BT" falls back to EW - quirk). Holidays cached statically on first use. Comment says "SLA is DSPT_SLA_DAYS (28)
   calendar days" (misleading; code uses constant 20 working days). Seeded open dispute 40001: received 2024-12-20 10:15,
   EW => due 2025-01-22.
3. **Pence rounding** - `MoneyUtil.penceToWholePounds` uses HALF_EVEN (comment says "rounds up"). score-service sums
   revolving (CC, SC, CA; open, limit > 0, not disputed) balances in pence FIRST, then converts to whole pounds, then
   util% = pounds*100/limitPounds with integer (truncating) division. Dispute amendments: `poundsToPence` HALF_UP.
4. **Name matching with diacritics** - `NameNormaliser` (NFD strip marks + special cases ß Æ Œ Ø Ł Đ, drop non A-Z so
   O'Brien == O Brien == OBRIEN). `NameMatcher`: DOB equal, normalised surname equal, forename equal OR one is an initial
   OR both >= 3 chars and one is a prefix of the other. CONSUMER.MATCH_KEY = SURNAME|yyyyMMdd|initial, candidates by prefix.
   Lender files are **ISO-8859-1** (batch must read with that charset).
5. **Address-history merge keeps the older record on ties** - `AddressHistoryMerger`: same ADDR_ID + overlapping periods
   collapse; earlier DT_FROM wins; same DT_FROM => earlier CRTD_TS (then lower ADDR_HIST_ID) wins; winner DT_TO = later
   of both (null = open). Class comment says "most recent report wins" (misleading). Used at read time in credit-file and
   at write time in batch-ingest (losers physically deleted).

## credit-file-service (remaining)
- DAOs (JdbcTemplate, setter-injected in creditfile-servlet.xml): ConsumerDao, TradelineDao, AddressHistoryDao.
- `CreditFileAssembler.build(id)` -> JSON map: consumer, addresses (merged, with line1/town/postcode, source, addrHistId),
  tradelines (DEL_FLG='N'; raw statusCd + statusDate + mappedStatus, balancePence, balanceDisplay, creditLimit, revolving,
  disputed), publicRecords (with disputed), searches, electoralRoll, aliases, notices. Dates ISO strings.
- REST: `GET /creditfile/{id}`, `GET /consumers/match?firstName&surname&dob`.
- SOAP-style: `POST /ws/TradelineMaintenance` (text/xml envelope, ns urn:ukcredit:tradeline:v1) with
  SetDisputeFlagRequest(tradelineId, flag), AmendTradelineRequest(tradelineId, statusCd?, balancePence?, delete, operatorId;
  status change sets ACCT_STS_DT = today; writes AUDIT_LOG), GetTradelineRequest. DOM parsing, string responses.

## score-service (UKS3 model, params in SCORE_MODEL_PARAM)
- Gets credit file over REST from credit-file-service (RestTemplate), but ALSO reads ACCOUNT_TRADELINE.DSPT_FLG directly
  from the DB to exclude disputed tradelines ("perf fix 2017"). Writes SCORE_HISTORY.
- score = BASE(600); UP_TO_DATE: count, + min(count*UTD_PER_ACCT, UTD_CAP); ARREARS_n: n*ARREARS_PER_MTH; DEFAULT;
  ARRANGEMENT = 2*ARREARS_PER_MTH; SETTLED; others 0. Utilisation (quirk 3): >=90 UTIL_90, >=75 UTIL_75, >=50 UTIL_50,
  <30 UTIL_LOW. Public records (not disputed): CCJ/DEC unsatisfied within 6y CCJ_UNSAT, satisfied CCJ_SAT, BKY/IVA
  INSOLVENCY. Hard searches in last 12 months: (count - HARD_SRCH_FREE) * HARD_SRCH_EACH if positive. ER at current
  address => ER_REGISTERED else ER_NOT_REGISTERED. Current address DT_FROM >= 3y ago => TENURE_3Y. Clamp 0..999.
  No scorable tradelines => SCR_VAL null, band NOSCORE. Bands: <450 VPOOR, <550 POOR, <650 FAIR, <720 GOOD, else EXCELLENT.
  Top-4 reason codes by impact.
- REST: `GET /score/{id}?asOf=yyyy-MM-dd` (no persist), `POST /score/{id}/recalculate?trigger=..&asOf=` (persist),
  `GET /score/{id}/history`. Golden masters use asOf=2024-12-31.

## dispute-service
- `POST /disputes` {cnsmrId, trdlnId | pubRecId, reasonCd, channelCd, receivedTs}: SLA (quirk 2), DISPUTE_CASE OPEN,
  DISPUTE_EVENT OPENED, DISPUTE_CORRESPONDENCE ACK01; SOAP SetDisputeFlag Y on credit-file (tradeline) or direct JDBC
  update of PUBLIC_RECORD.DSPT_FLG (inconsistent on purpose); REST call score-service recalculate trigger=DISPUTE_OPEN.
- `POST /disputes/{id}/resolve` {outcome AMEND|DELETE|NOCHANGE, operatorId, newStatusCd?, newBalance (pounds string)?}:
  SOAP AmendTradeline, SetDisputeFlag N, score recalc trigger=DISPUTE_CLOSE, CLOSED + events + RES01/RES02.
- `GET /disputes/{id}`, `GET /disputes/sla?receivedTs=..&postcode=..` (helper).

## batch-ingest (CLI, Spring XML ClassPathXmlApplicationContext; depends on credit-file-service jar for rules)
- Fixed-width 240-char records, ISO-8859-1. HDR(3) LNDR_REF_CD(6) FILE_DT(8) SEQ(6). TRL(3) count 9(8).
  DTL layout (1-based): 1-3 'DTL', 4-23 acct no, 24-25 acct type, 26-55 surname, 56-75 forename, 76-83 DOB, 84-93
  postcode, 94-101 open dt, 102-109 close dt (00000000 = none), 110-117 limit 9(8) pounds, 118 sign, 119-129 balance
  9(11) pence, 130 status, 131-138 status dt, 139-162 payment profile, 163-170 address-since, 171-210 line1, 211-240 town.
- Per DTL: hash = AccountHash(lender, acctNo); existing tradeline => TRADELINE_HISTORY snapshot then update, unless
  DSPT_FLG='Y' => BATCH_REJECT 'DSPT_HOLD'. New => match consumer (MATCH_KEY prefix + NameMatcher) or create consumer;
  insert tradeline. Address differs from current => new ADDRESS + ADDRESS_HISTORY (CAI), close previous, run merger.
  Bad fields => BATCH_REJECT. BATCH_RUN_LOG with counts; trailer mismatch => WARN. Afterwards POST score recalculate
  trigger=BATCH for touched consumers if score-service reachable (log and continue otherwise).
- Sample file generated by `SeedDataGenerator data/inbound/BKA001_20250101.dat` (commit it).

## Edge-case consumers (seed)
100001 X pre-cutoff; 100002 X post; 100003 X on 2014-03-31 and 2014-04-01; 100004 X on 2014-06-01 (between code
cutoff and SYS_PARAM); 100005 util 749.50/1000 => 75%; 100006 two cards 300.50 + 449.00 (sum-then-round 750 vs
per-account 749); 100007 500.50/1002 (HALF_EVEN 500 => 49% vs HALF_UP 501 => 50%); 100008-100010 diacritic names
(Siobhán Ó Briain/Belfast, Renée Dubois-Marchand, Łukasz Wiśniewski); 100011 Margaret Strauß address-history tie;
100012 Edinburgh (SC); 100013 Bristol (EW); 100014 CCJs; 100015 thin file; 100016 open dispute 40001 on BKA001 card.

## Still to add
scripts/ (build.sh, db-reset.sh = DbMigrate clean + seed, run-all.sh, run-batch.sh, env-postgres.sh), docker-compose.yml
(postgres:12), sparse README.md, thin tests (1-2 per module), a couple more misleading comments. Do NOT add CI.
