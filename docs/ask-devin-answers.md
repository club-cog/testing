# Ask Devin answers (demo fallback)

Answers worked out from the code and Flyway SQL on the `uk-credit-legacy` branch. Every reference is `path:line`.
Paths are abbreviated as follows:

| Prefix | Expands to |
|---|---|
| `mig/` | `shared-db/src/main/resources/db/migration/` |
| `cf/` | `credit-file-service/src/main/java/com/ukcredit/creditfile/` |
| `sc/` | `score-service/src/main/java/com/ukcredit/score/` |
| `ds/` | `dispute-service/src/main/java/com/ukcredit/dispute/` |
| `bi/` | `batch-ingest/src/main/java/com/ukcredit/batch/` |
| `sh/` | `shared-db/src/main/java/com/ukcredit/` |

Ports (from code, not the README): credit-file-service 8081 (`cf/CreditFileServiceMain.java:8`), score-service 8082
(`sc/ScoreServiceMain.java:8`), dispute-service 8083 (`ds/DisputeServiceMain.java:8`). All four modules share one
database through `shared-db/src/main/resources/META-INF/spring/shared-datasource.xml:20-30`, so nothing at the DB
level stops a module from reaching past another module's API.

---

## 1. Which services read or write ACCOUNT_TRADELINE, and through which columns?

Table definition: `mig/V1__base_schema.sql:113-136`. `DSPT_FLG` was added later at `mig/V3__disputes.sql:65`.

| Service / module | Class (path:line) | R/W | Columns | Path |
|---|---|---|---|---|
| credit-file-service | `TradelineDao.SELECT` / `findLiveByConsumer` (`cf/dao/TradelineDao.java:15-20, 44-47`) | Read | TRDLN_ID, CNSMR_ID, LNDR_REF_CD, ACCT_TYP_CD, OPEN_DT, CLOSE_DT, CR_LMT_AMT, CURR_BAL_PNC, ACCT_STS_CD, ACCT_STS_DT, PYMT_PRFL, DSPT_FLG, DEL_FLG (joins LENDER, ACCOUNT_TYPE_REF). Filter: CNSMR_ID, DEL_FLG='N' | Owner, direct JDBC. Exposed over REST `GET /creditfile/{id}` (`cf/web/CreditFileController.java:31-39` → `cf/service/CreditFileAssembler.java:64-84`) |
| credit-file-service | `TradelineDao.findById` (`cf/dao/TradelineDao.java:49-52`) | Read | Same columns, filtered by TRDLN_ID | Owner. Exposed over SOAP `GetTradeline` (`cf/web/TradelineMaintenanceEndpoint.java:57-66`) and used inside `amend` |
| credit-file-service | `TradelineDao.updateDisputeFlag` (`cf/dao/TradelineDao.java:54-57`), called by `TradelineMaintenanceService.setDisputeFlag` (`cf/service/TradelineMaintenanceService.java:20-27`) | Write | DSPT_FLG, UPD_TS (+ AUDIT_LOG row) | Owner. Exposed over SOAP `SetDisputeFlag` (`TradelineMaintenanceEndpoint.java:45-49`) |
| credit-file-service | `TradelineMaintenanceService.amend` (`cf/service/TradelineMaintenanceService.java:29-54`) | Write | DEL_FLG (l.37), ACCT_STS_CD + ACCT_STS_DT (set to today, l.43-44), CURR_BAL_PNC (l.48), UPD_TS (+ AUDIT_LOG row, l.60-65) | Owner. Exposed over SOAP `AmendTradeline` (`TradelineMaintenanceEndpoint.java:50-56`) |
| score-service | `CreditFileClient.getCreditFile` (`sc/client/CreditFileClient.java:17-26`) | Read (indirect) | The JSON fields from `CreditFileAssembler.java:67-81`: balancePence, creditLimit, statusCd, statusDate, openDate, closeDate, revolving, disputed | REST `GET :8081/creditfile/{id}` (sanctioned path) |
| score-service | **`ScoreHistoryDao.openDisputedTradelines`** (`sc/dao/ScoreHistoryDao.java:31-34`), called from `ScoreService.score` (`sc/calc/ScoreService.java:24-27`) | **Read** | COUNT(*) WHERE CNSMR_ID, **DSPT_FLG='Y'**, DEL_FLG='N' | **Direct JDBC. Bypasses credit-file-service.** |
| dispute-service | `TradelineMaintenanceClient.setDisputeFlag` / `amendTradeline` (`ds/client/TradelineMaintenanceClient.java:24-42`) | Write (indirect) | DSPT_FLG; ACCT_STS_CD/ACCT_STS_DT, CURR_BAL_PNC, DEL_FLG | SOAP `POST :8081/ws/TradelineMaintenance` (sanctioned path) |
| dispute-service | `DisputeDao.insertCase` (`ds/dao/DisputeDao.java:13-20`) | FK only | DISPUTE_CASE.TRDLN_ID → ACCOUNT_TRADELINE.TRDLN_ID (`mig/V3__disputes.sql:38`) | Direct JDBC on its own table |
| batch-ingest | **`LenderFileLoader.apply`: lookup** (`bi/LenderFileLoader.java:134-141`) | **Read** | TRDLN_ID, CNSMR_ID, **DSPT_FLG**, ACCT_STS_CD, CURR_BAL_PNC, CR_LMT_AMT WHERE LNDR_REF_CD, ACCT_NO_HASH | **Direct JDBC. Bypasses credit-file-service.** |
| batch-ingest | **`LenderFileLoader.apply`: update** (`bi/LenderFileLoader.java:147-150`) | **Write** | ACCT_STS_CD, ACCT_STS_DT, CURR_BAL_PNC, CR_LMT_AMT, PYMT_PRFL, LAST_UPD_BATCH_ID, UPD_TS | **Direct JDBC, no AUDIT_LOG** |
| batch-ingest | **`LenderFileLoader.apply`: insert** (`bi/LenderFileLoader.java:156-161`) | **Write** | Every column except UPD_TS (DEL_FLG='N', DSPT_FLG='N') | **Direct JDBC, no AUDIT_LOG** |
| shared-db tooling | `SeedDataGenerator.tradeline` (`sh/db/SeedDataGenerator.java:558-568`), `firstTradeline` (l.613-625) | Write / Read | Insert every column incl. DSPT_FLG, DEL_FLG; reads MIN(TRDLN_ID) | Direct JDBC (test data only, run by `scripts/db-reset.sh:11`) |

### Access that bypasses the service boundaries

- **score-service DSPT_FLG check.** `ScoreService.score` already receives `disputed` for each tradeline over REST and
  suppresses those tradelines (`sc/calc/ScoreCalculator.java:32-37`). It then queries `ACCOUNT_TRADELINE.DSPT_FLG`
  directly anyway (`sc/dao/ScoreHistoryDao.java:31-34`). The table belongs to credit-file-service and the query lives
  in a DAO named for SCORE_HISTORY. The result only appends a `DSPT_SUPPRESSED` reason code and never changes the score
  (`ScoreService.java:25-27`).
- **batch-ingest writes.** batch-ingest reads, updates and inserts ACCOUNT_TRADELINE (plus CONSUMER, ADDRESS and
  ADDRESS_HISTORY) directly (`bi/LenderFileLoader.java:134-200`). It never calls the SOAP `TradelineMaintenance` API,
  and no AUDIT_LOG row is written, even though `TradelineMaintenanceService` says "All changes are audited"
  (`cf/service/TradelineMaintenanceService.java:13`). It reimplements the "held while disputed" rule by reading
  DSPT_FLG itself (l.139-141). It also links credit-file-service's DAO and match classes as a jar dependency
  (`batch-ingest/pom.xml:14`, `batch-context.xml:14-20`).
- **The existing-account update never sets CLOSE_DT or DEL_FLG** (`bi/LenderFileLoader.java:147-150`). As a result:
  - An account a lender reports as closed stays open on the file.
  - A tradeline that a dispute DELETEd keeps receiving balance updates while still hidden.
- **Same pattern on PUBLIC_RECORD.** dispute-service writes `PUBLIC_RECORD.DSPT_FLG` directly
  (`ds/dao/DisputeDao.java:42-44`), with no audit. credit-file-service reads that table
  (`CreditFileAssembler.java:86-89`).
- **Columns written but never read by any service:**
  - LAST_UPD_BATCH_ID, CRTD_TS and UPD_TS are only ever written.
  - ACCT_NO_HASH is only used as the batch lookup key.

---

## 2. Trace a dispute from intake to the score recalculation

Example: seeded case 40001 (consumer 100016, BKA001 card), `sh/db/SeedDataGenerator.java:253-267`.

1. **Intake (HTTP).** `POST :8083/disputes` with `{cnsmrId, trdlnId|pubRecId, rsnCd, chnlCd?, rcvdTs?}` is handled
   by `DisputeController.open` (`ds/web/DisputeController.java:29-44`). It returns 400 unless cnsmrId, rsnCd and one
   of trdlnId/pubRecId are present (l.37-39). rcvdTs defaults to now (l.40-41). It then calls `DisputeService.open`
   (`ds/service/DisputeService.java:29-45`).
2. **Region.** `RegionResolver.regionForConsumer` (`ds/sla/RegionResolver.java:20-24`) reads the open address
   (`ADDRESS_HISTORY` JOIN `ADDRESS`, `DT_TO IS NULL`, l.21-22). The postcode area decides the region: Scottish areas
   give `SC` (l.15-16, 36), everything else gives `EW`. **Northern Ireland (BT) falls through to EW** (l.35), because NI
   holidays were never loaded (`mig/V7__bank_holidays.sql:2`, and the `NI` code at `mig/V3__disputes.sql:16` is unused).
3. **SLA due date.** `SlaCalculator.dueDate` (`ds/sla/SlaCalculator.java:22-36`) works as follows:
   - It reads `SYS_PARAM.DSPT_CUTOFF_TM` (17:30), l.38-49.
   - If the dispute arrives after the cut-off, or on a non-working day, the clock starts on the next working day
     (l.28-31).
   - It then adds **20 working days** (`SLA_WORKING_DAYS`, l.15, 32-34).

   Working days come from `WorkingDayCalendar` (`ds/sla/WorkingDayCalendar.java:24-37`): Monday to Friday minus
   `BANK_HOLIDAY` rows for the region (`SELECT HOL_DT FROM BANK_HOLIDAY WHERE REGION_CD = ?`, l.44-45). The holidays
   are cached in a static map for the life of the JVM (l.16, 20, 39-52). For case 40001, received 2024-12-20 10:15 in
   EW, this gives a due date of 2025-01-22, which matches the seed data.
4. **Persist case.** `DisputeDao` writes three rows (called from `DisputeService.java:32-34`):
   - `insertCase` → `DISPUTE_CASE` (STS_CD='OPEN', SLA_DUE_DT), `ds/dao/DisputeDao.java:13-20`
   - `insertEvent("OPENED", "region=..")` → `DISPUTE_EVENT`, l.22-25
   - `insertCorrespondence("ACK01")` → `DISPUTE_CORRESPONDENCE`, l.27-30
5. **Dispute flag (SOAP).** `TradelineMaintenanceClient.setDisputeFlag(trdlnId, "Y")` (`ds/client/TradelineMaintenanceClient.java:24-28, 44-53`)
   sends `POST :8081/ws/TradelineMaintenance` with SOAPAction `urn:ukcredit:tradeline:v1:SetDisputeFlag` (base URL
   in `dispute-servlet.xml:31-34`). The call chain on the credit-file side is:
   - `TradelineMaintenanceEndpoint.invoke` (`cf/web/TradelineMaintenanceEndpoint.java:32-49`)
   - `TradelineMaintenanceService.setDisputeFlag` (`cf/service/TradelineMaintenanceService.java:20-27`)
   - `TradelineDao.updateDisputeFlag`: `UPDATE ACCOUNT_TRADELINE SET DSPT_FLG='Y'` (`cf/dao/TradelineDao.java:54-57`)
   - an `AUDIT_LOG` insert (`TradelineMaintenanceService.java:60-65`)

   If the dispute is about a public record instead, dispute-service runs `UPDATE PUBLIC_RECORD SET DSPT_FLG='Y'`
   directly (`DisputeService.java:39-41`, `DisputeDao.java:42-44`).
   - Side effect from then on: the nightly batch **holds** lender updates for this account. It writes them to
     `BATCH_REJECT` with "HELD: tradeline under dispute" instead (`bi/LenderFileLoader.java:35, 92-95, 139-141, 203-207`).
6. **Score recalculation on open (REST).** `ScoreClient.recalculate(cnsmrId, "DISPUTE_OPEN")` (`DisputeService.java:42`,
   `ds/client/ScoreClient.java:18-24`) sends `POST :8082/score/{id}/recalculate?trigger=DISPUTE_OPEN`. The call chain is:
   - `ScoreController.recalc` (`sc/web/ScoreController.java:32-38`)
   - `ScoreService.recalculate` (`sc/calc/ScoreService.java:31-37`)
   - `ScoreService.score` (l.17-29), which does the following:
     - **REST** `GET :8081/creditfile/{id}` (`sc/client/CreditFileClient.java:17-26`) → `CreditFileController.get`
       → `CreditFileAssembler.build` (`cf/service/CreditFileAssembler.java:33-98`). This reads CONSUMER,
       ADDRESS_HISTORY+ADDRESS, ACCOUNT_TRADELINE+LENDER+ACCOUNT_TYPE_REF, PUBLIC_RECORD, SEARCH_FOOTPRINT,
       ELECTORAL_ROLL, CONSUMER_ALIAS and CONSUMER_NOTICE. It sets `disputed` from DSPT_FLG (l.81, 114-116).
     - `ScoreModelDao` reads `SYS_PARAM.SCORE_MODEL_VER` and `SCORE_MODEL_PARAM` (`sc/dao/ScoreModelDao.java:12-24`).
     - `ScoreCalculator.calculate` skips disputed tradelines and public records, adding the reason code
       `DSPT_SUPPRESSED` (`sc/calc/ScoreCalculator.java:32-37, 101-105`).
     - Direct `ACCOUNT_TRADELINE.DSPT_FLG` count (`sc/dao/ScoreHistoryDao.java:31-34`, see Q1).
   - `ScoreHistoryDao.insert` writes a `SCORE_HISTORY` row with TRIGGER_CD='DISPUTE_OPEN' (`ScoreHistoryDao.java:16-23`).
   - `asOf` is not passed, so the score is calculated as of today (`ScoreController.java:46-48`).
   - A failure here is only logged (`ScoreClient.java:21-23`).
7. **Resolution (HTTP).** `POST :8083/disputes/{id}/resolve` with `{outcome: AMEND|DELETE|NOCHANGE, operatorId,
   statusCd?, balancePence?}` is handled by `DisputeController.resolve` (`ds/web/DisputeController.java:46-61`).
   The operator is checked with `SELECT COUNT(*) FROM OPERATOR` (`ds/dao/DisputeDao.java:38-40`). Then
   `DisputeService.resolve` (`ds/service/DisputeService.java:52-76`) runs:
   - `findCase` reads `DISPUTE_CASE` (l.53-55) and returns false if the case is missing or already CLOSED.
   - On AMEND or DELETE, it calls **SOAP** `AmendTradeline` (l.63-65). This lands in
     `TradelineMaintenanceService.amend` (`cf/service/TradelineMaintenanceService.java:29-54`), which updates
     `ACCOUNT_TRADELINE` (DEL_FLG / ACCT_STS_CD + ACCT_STS_DT=today / CURR_BAL_PNC) and writes `AUDIT_LOG` 'AMEND'.
   - It calls **SOAP** `SetDisputeFlag N` (l.66-67), or for a public record `UPDATE PUBLIC_RECORD SET DSPT_FLG='N'` (l.68-70).
   - `DisputeDao.close` sets `DISPUTE_CASE` to STS_CD='CLOSED', OUTCOME_CD, RSLVD_TS, RSLVD_BY (`DisputeDao.java:32-35`).
   - It writes a `DISPUTE_EVENT` 'CLOSED' row, then `DISPUTE_CORRESPONDENCE` RES01 if the record changed or RES02 if
     not (`DisputeService.java:72-73`).
8. **Score recalculation on close.** `ScoreClient.recalculate(cnsmrId, "DISPUTE_CLOSE")` (`DisputeService.java:74`)
   runs the same path as hop 6. The tradeline is no longer suppressed, and a `SCORE_HISTORY` row is written with
   TRIGGER_CD='DISPUTE_CLOSE'.

**Gaps in this flow:**
- Nothing is transactional across the services.
- `TradelineMaintenanceClient.call` does not catch `RestClientException` (`ds/client/TradelineMaintenanceClient.java:44-53`).
  If credit-file-service is down, `open()` throws after the case rows are already committed, and no score
  recalculation happens.
- The result of `amendTradeline` is ignored (`DisputeService.java:64`).

```mermaid
sequenceDiagram
    autonumber
    actor C as Consumer / agent
    participant DS as dispute-service :8083
    participant CF as credit-file-service :8081
    participant SS as score-service :8082
    participant DB as Shared DB
    C->>DS: POST /disputes (DisputeController.open)
    DS->>DB: SELECT ADDRESS_HISTORY+ADDRESS (RegionResolver -> EW/SC, BT->EW)
    DS->>DB: SELECT SYS_PARAM DSPT_CUTOFF_TM, BANK_HOLIDAY by region (SlaCalculator / WorkingDayCalendar)
    DS->>DB: INSERT DISPUTE_CASE (OPEN, SLA_DUE_DT), DISPUTE_EVENT OPENED, DISPUTE_CORRESPONDENCE ACK01
    alt tradeline dispute
        DS->>CF: SOAP SetDisputeFlag(Y) /ws/TradelineMaintenance
        CF->>DB: UPDATE ACCOUNT_TRADELINE DSPT_FLG=Y; INSERT AUDIT_LOG
    else public record dispute
        DS->>DB: UPDATE PUBLIC_RECORD DSPT_FLG=Y (direct)
    end
    DS->>SS: POST /score/{id}/recalculate?trigger=DISPUTE_OPEN
    SS->>CF: GET /creditfile/{id}
    CF->>DB: SELECT CONSUMER, ACCOUNT_TRADELINE, PUBLIC_RECORD, ...
    CF-->>SS: credit file (disputed=true)
    SS->>DB: SELECT SYS_PARAM, SCORE_MODEL_PARAM
    SS->>DB: SELECT COUNT ACCOUNT_TRADELINE DSPT_FLG=Y (direct, bypass)
    SS->>DB: INSERT SCORE_HISTORY (DISPUTE_OPEN, DSPT_SUPPRESSED)
    Note over DB: nightly batch-ingest holds updates for DSPT_FLG=Y -> BATCH_REJECT
    C->>DS: POST /disputes/{id}/resolve (AMEND|DELETE|NOCHANGE)
    DS->>DB: SELECT OPERATOR, DISPUTE_CASE
    opt AMEND / DELETE
        DS->>CF: SOAP AmendTradeline
        CF->>DB: UPDATE ACCOUNT_TRADELINE (ACCT_STS_CD/DT, CURR_BAL_PNC, DEL_FLG); INSERT AUDIT_LOG
    end
    DS->>CF: SOAP SetDisputeFlag(N)
    CF->>DB: UPDATE ACCOUNT_TRADELINE DSPT_FLG=N; INSERT AUDIT_LOG
    DS->>DB: UPDATE DISPUTE_CASE CLOSED; INSERT DISPUTE_EVENT CLOSED, DISPUTE_CORRESPONDENCE RES01/RES02
    DS->>SS: POST /score/{id}/recalculate?trigger=DISPUTE_CLOSE
    SS->>CF: GET /creditfile/{id}
    SS->>DB: INSERT SCORE_HISTORY (DISPUTE_CLOSE)
```

---

## 3. Which tables are unused?

Method: every `CREATE TABLE` in `mig/V1`-`V7` was grepped for as a whole word across all `*.java`, `*.sh`, `*.xml`
and `*.properties` files. The `scripts/*.sh` files contain no SQL; they only call the jars. Tests contain no SQL.

### Not read or written by anything

| Table | Defined | Notes |
|---|---|---|
| **CONSUMER_MARKETING_PREF** | `mig/V4__marketing_and_archive.sql:2-10` | No reference anywhere outside the migration. FK to CONSUMER only. |
| **TRADELINE_ARCHIVE_2012** | `mig/V4__marketing_and_archive.sql:12-22` | No reference anywhere. Comment says "Keep until audit sign-off" (l.12). Its columns (LNDR_ID, clear ACCT_NO, BAL_AMT in pounds) predate the current model. |

### Reference-only: seeded by migrations, never queried by code

| Table | Defined / seeded | Notes |
|---|---|---|
| TRADELINE_STATUS_REF | `mig/V1__base_schema.sql:101-106`, `mig/V5__reference_data.sql:20-32` | Never queried. Status logic is hard-coded twice instead (`cf/rules/TradelineStatusMapper.java:13-43`, `sc/calc/LegacyStatusTranslator.java:15-36`), and **disagrees** with it. The ref table has X = 'Account in query', ADVRS_FLG='N' (V5:32). The code maps X to DEFAULT/ARRANGEMENT, and `isAdverse` treats both as adverse (`TradelineStatusMapper.java:34-39, 45-47`). |
| COURT_REF | `mig/V1__base_schema.sql:154-159`, `mig/V5__reference_data.sql:34-41` | Only an FK target (`PUBLIC_RECORD.CRT_CD`, V1:171). The credit file returns the raw CRT_CD without joining (`CreditFileAssembler.java:86`). |

### Read-only at runtime (data comes only from migrations or the seed)

| Table | Read by | Written by |
|---|---|---|
| LENDER | JOIN in `cf/dao/TradelineDao.java:19` | V5 only |
| ACCOUNT_TYPE_REF | JOIN in `cf/dao/TradelineDao.java:20` | V5 only |
| OPERATOR | `ds/dao/DisputeDao.java:38-40` | V5 only |
| BANK_HOLIDAY | `ds/sla/WorkingDayCalendar.java:44-45` | V7 only (EW+SC 2010-2030, no NI) |
| SCORE_MODEL_PARAM | `sc/dao/ScoreModelDao.java:17-24` | V6 only |
| SYS_PARAM | `ScoreModelDao.java:13` (SCORE_MODEL_VER), `SlaCalculator.java:41` (DSPT_CUTOFF_TM) | V5 only. 3 of its 5 rows are never read (see below). |
| CONSUMER_ALIAS, CONSUMER_NOTICE, SEARCH_FOOTPRINT, ELECTORAL_ROLL | `CreditFileAssembler.java:90-97` | `SeedDataGenerator` only (l.582-599). No runtime writer. |
| PUBLIC_RECORD | `CreditFileAssembler.java:86-89` | Inserted only by `SeedDataGenerator.java:577`. dispute-service updates DSPT_FLG only (`DisputeDao.java:42-44`). |

### Write-only: written, never read by any service

| Table | Writer | Notes |
|---|---|---|
| AUDIT_LOG | `cf/service/TradelineMaintenanceService.java:60-65` | Nothing reads it. Batch and dispute-service direct writes are not audited at all. |
| TRADELINE_HISTORY | `bi/LenderFileLoader.java:143-146`, `SeedDataGenerator.java:571` | Snapshot before each batch update. Never read, so it is not in the credit file or the score. |
| BATCH_RUN_LOG | `bi/LenderFileLoader.java:46, 62, 123-124` | Run totals and status. No reader. |
| BATCH_REJECT | `bi/LenderFileLoader.java:205-206` | Includes "HELD: tradeline under dispute" rows. Nothing replays held updates once the dispute closes. |

### Fully used (read and written)

CONSUMER, ADDRESS, ADDRESS_HISTORY, ACCOUNT_TRADELINE, SCORE_HISTORY, DISPUTE_CASE, DISPUTE_EVENT and
DISPUTE_CORRESPONDENCE are all used. SCORE_HISTORY.TRIGGER_CD lists `BATCH` (`mig/V2__batch_and_scoring.sql:44`),
but nothing ever writes that value.

### SYS_PARAM.TRDLN_X_CUTOFF_DT is unused and misleading

- Seeded as `'2015-01-01'`, "Date after which status X means arrangement-to-pay" (`mig/V5__reference_data.sql:50`).
- **No code reads it.** Both status mappers hard-code `LocalDate.of(2014, 4, 1)`
  (`cf/rules/TradelineStatusMapper.java:11`, `sc/calc/LegacyStatusTranslator.java:11`).
- Both mappers have comments claiming otherwise:
  - "cutoff is read from SYS_PARAM.TRDLN_X_CUTOFF_DT" (`TradelineStatusMapper.java:10`)
  - "Kept in sync with SYS_PARAM.TRDLN_X_CUTOFF_DT" (`LegacyStatusTranslator.java:6`)
- **Practical impact:** an X status dated between 2014-04-01 and 2014-12-31 scores as ARRANGEMENT (-30) in code, but
  as DEFAULT (-120) if you believe the parameter. Seed consumer 100004 (X on 2014-06-01,
  `SeedDataGenerator.java:166-171`, `docs/seed-data.md:12`) exists to show this. Changing the parameter changes nothing.
- The other SYS_PARAM rows that are never read:
  - `DSPT_SLA_DAYS` = 28 (V5:51). The code uses 20 working days.
  - `RETENTION_YRS` = 6 (V5:53). The 6-year CCJ window is hard-coded at `ScoreCalculator.java:108`.

---

## Misleading comments (the code contradicts the comment)

| # | Where | Comment says | Code does |
|---|---|---|---|
| 1 | `cf/rules/TradelineStatusMapper.java:10` | "cutoff is read from SYS_PARAM.TRDLN_X_CUTOFF_DT" | Hard-coded 2014-04-01 (l.11). The param is 2015-01-01 and is never read. |
| 2 | `sc/calc/LegacyStatusTranslator.java:6` | "Kept in sync with SYS_PARAM.TRDLN_X_CUTOFF_DT" | Hard-coded 2014-04-01 (l.11), so it is not in sync. |
| 3 | `cf/rules/TradelineStatusMapper.java:35` and `mig/V5__reference_data.sql:32` | "X = account in query", non-adverse | Mapped to DEFAULT/ARRANGEMENT and treated as adverse (l.36-39, 45-47). It scores -120 or -30. |
| 4 | `ds/sla/SlaCalculator.java:14` | "SLA is DSPT_SLA_DAYS (28) calendar days from receipt, see SYS_PARAM" | 20 **working** days, excluding regional bank holidays (l.15, 32-34). SYS_PARAM.DSPT_SLA_DAYS is never read. |
| 5 | `sc/calc/ScoreCalculator.java:11` | "Utilisation uses whole pounds, rounded per account" | Balances are summed in pence across accounts and rounded once (l.119, 131). Consumer 100006 tests this. |
| 6 | `sh/common/MoneyUtil.java:21` | `penceToWholePounds` "Rounds up to the nearest whole pound" | `RoundingMode.HALF_EVEN` (l.23): 500.50 gives 500, not 501 (consumer 100007). |
| 7 | `cf/rules/AddressHistoryMerger.java:12-13` | "the most recent report wins so that lender corrections take effect" | `pick()` keeps the **earliest** DT_FROM, then the earliest CRTD_TS ("keep the record we had first", l.66-77). |
| 8 | `ds/client/ScoreClient.java:9` | "Failures are logged, the nightly batch rescores anyway" | batch-ingest never calls score-service and never writes SCORE_HISTORY. TRIGGER_CD 'BATCH' is never produced. |
| 9 | `sc/calc/ScoreService.java:24` | "belt and braces: the credit file can lag behind a just-opened dispute" | The credit file reads DSPT_FLG live from the same DB with no cache (`TradelineDao.java:17`). The direct check only adds a reason code and never changes the score. |
| 10 | `ds/service/DisputeService.java:16-17` | "if credit-file-service is down the case is still recorded and ops re-send the flag from the admin screen" | The SOAP client does not catch the connection error, so `open()` fails with an exception after the insert and the recalculation never runs. No admin screen or re-send exists in the repo. |
| 11 | `cf/service/TradelineMaintenanceService.java:13` | "All changes are audited" | True only for this class. The batch-ingest and dispute-service (PUBLIC_RECORD) writes to the same data are not audited, and AUDIT_LOG is never read. |
| 12 | `ds/dao/DisputeDao.java:37` | Javadoc "Public records are not owned by credit-file-service, so the flag is set here directly" | It sits on `operatorExists` (l.38), not on `setPublicRecordDisputeFlag` (l.42). credit-file-service is also the reader of PUBLIC_RECORD (`CreditFileAssembler.java:86`). |
| 13 | `README.md:17` | credit-file-service at `http://localhost:8080/...` | It listens on 8081 (`CreditFileServiceMain.java:8`, `scripts/run-all.sh:2`, both client configs). |
| 14 | `mig/V4__marketing_and_archive.sql:1, 12` | Dated 2012-11 / 2012-12 | Runs after V3 (dated 2013-09), so the migration order is not chronological. Cosmetic, but it confuses archaeology. |
