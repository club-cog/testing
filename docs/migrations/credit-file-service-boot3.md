# credit-file-service: Java 21 / Spring Boot 3 on GKE

## 1. Service map (legacy `credit-file-service`, as found on `uk-credit-legacy`)

Runtime: Java 8, Spring 4.3.30 XML config, embedded Jetty 9.4 via `shared-db` `EmbeddedServer`, DBCP 1.4 pool,
H2 1.4.197 file DB (PostgreSQL mode, `AUTO_SERVER=TRUE`) or Postgres via `-Djdbc.*`. Port 8081 (`-Dport`).
Main class `com.ukcredit.creditfile.CreditFileServiceMain`.

### Endpoints

| Method | Path | Params | Responses |
|--------|------|--------|-----------|
| GET | `/creditfile/{id}` | `id` long | 200 JSON credit file; 404 empty body if no consumer; 400 if `id` not numeric |
| GET | `/consumers/match` | `firstName`, `surname`, `dob` (ISO date), all required | 200 JSON array `[{cnsmrId, firstName, surname, dob}]`; 400 if a param is missing; 500 if `dob` unparseable |
| POST | `/ws/TradelineMaintenance` | SOAP 1.1 envelope, ns `urn:ukcredit:tradeline:v1` | 200 `text/xml;charset=UTF-8`; faults are also HTTP 200 with `soapenv:Client` |

SOAP-style operations (hand-rolled DOM parsing, no CXF): `SetDisputeFlagRequest(tradelineId, flag)` → `OK|NOT_FOUND`;
`AmendTradelineRequest(tradelineId, statusCd?, balancePence?, delete?, operatorId)` → `OK|NOT_FOUND`;
`GetTradelineRequest(tradelineId)` → tradeline or fault `Tradeline {id} not found`.
Other faults: `No operation in SOAP body`, `Unknown operation {localName}`. `tradelineId` is parsed before the
operation is dispatched, so a missing/non-numeric `tradelineId` gives HTTP 500 even for an unknown operation.
Child elements are looked up by namespace first, then by plain tag name.

### Spring XML beans

| XML file | Bean | Class | Wiring |
|----------|------|-------|--------|
| shared-datasource.xml (shared-db) | `dbProperties` | PropertyPlaceholderConfigurer | `db.properties`, `service.properties`, system props override |
| shared-datasource.xml | `dataSource` | commons-dbcp BasicDataSource | `jdbc.*` |
| shared-datasource.xml | `jdbcTemplate`, `transactionManager` + `<tx:annotation-driven>` | JdbcTemplate, DataSourceTransactionManager | dataSource |
| creditfile-rules.xml (also imported by batch-ingest) | `tradelineStatusMapper`, `nameMatcher`, `addressHistoryMerger` | rules.* | none |
| creditfile-servlet.xml | `consumerDao`, `tradelineDao`, `addressHistoryDao` | dao.* | jdbcTemplate (setter) |
| creditfile-servlet.xml | `creditFileAssembler` | service.CreditFileAssembler | jdbcTemplate, 3 DAOs, statusMapper, addressMerger (setter) |
| creditfile-servlet.xml | `consumerMatchService` | service.ConsumerMatchService | consumerDao, nameMatcher (setter) |
| creditfile-servlet.xml | `tradelineMaintenanceService` | service.TradelineMaintenanceService (`@Transactional`) | jdbcTemplate, tradelineDao (setter) |
| `<context:component-scan web>` | `creditFileController`, `tradelineMaintenanceEndpoint` | web.* | `@Autowired` fields |

### Tables and columns

| Table | Read | Written |
|-------|------|---------|
| CONSUMER | CNSMR_ID, TITLE_CD, FRST_NM, MID_NM, SURNM, DOB, GNDR_CD, MATCH_KEY, STS_CD | - |
| ADDRESS_HISTORY ⨝ ADDRESS | ADDR_HIST_ID, CNSMR_ID, ADDR_ID, DT_FROM, DT_TO, ADDR_SRC_CD, CRTD_TS; LINE1, TOWN, PSTCD | - |
| ACCOUNT_TRADELINE ⨝ LENDER ⨝ ACCOUNT_TYPE_REF | TRDLN_ID, CNSMR_ID, LNDR_REF_CD, ACCT_TYP_CD, OPEN_DT, CLOSE_DT, CR_LMT_AMT, CURR_BAL_PNC, ACCT_STS_CD, ACCT_STS_DT, PYMT_PRFL, DSPT_FLG, DEL_FLG; LNDR_NM; RVLVNG_FLG | DSPT_FLG, DEL_FLG, ACCT_STS_CD, ACCT_STS_DT, CURR_BAL_PNC, UPD_TS |
| PUBLIC_RECORD | PUB_REC_ID, REC_TYP_CD, CRT_CD, CASE_REF, JDGMT_DT, JDGMT_AMT, SATSFD_DT, DSPT_FLG | - |
| SEARCH_FOOTPRINT | SRCH_ID, LNDR_REF_CD, SRCH_TYP_CD, SRCH_DT | - |
| ELECTORAL_ROLL | ER_ID, ADDR_ID, DT_FROM, DT_TO | - |
| CONSUMER_ALIAS | FRST_NM, SURNM, ALIAS_TYP_CD | - |
| CONSUMER_NOTICE | NTC_TXT, CRTD_DT | - |
| AUDIT_LOG (+ `AUD_SEQ`) | - | AUD_ID, ENTITY_NM, ENTITY_ID, ACTN_CD, ACTN_TS, SRC_SVC=`credit-file-service`, DTL_TXT |

### Calls in / out

- Outbound: none (DB only).
- score-service → `GET /creditfile/{id}` (`CreditFileClient`, `-Dcreditfile.url`, default `http://localhost:8081`; 404 → null).
- dispute-service → `POST /ws/TradelineMaintenance` SetDisputeFlag / AmendTradeline (`TradelineMaintenanceClient`,
  `-Dcreditfile.url`; success = response contains `>OK<`).
- batch-ingest → compile-time dependency on the `credit-file-service` jar (`creditfile-rules.xml`, `ConsumerDao`,
  `ConsumerMatchService`). The legacy module therefore has to stay published as it is.
