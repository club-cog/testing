# dispute-service → Java 21 / Spring Boot 3 on GKE

## Scope

- New module `dispute-service-boot` (Java 21, Spring Boot 3.3.5, `jakarta.*`), default port **9083**.
- The legacy `dispute-service` module (Java 8, Spring 4.3 XML, Jetty, port 8083) is **unchanged**; both run side by side against the same database.
- `score-service`, `credit-file-service`, `shared-db` and `batch-ingest` are not modified. The only shared change is a root
  `pom.xml` profile (`boot3`, activated on JDK ≥ 21) that adds the new module to the reactor; on JDK 8 the legacy build is identical.
- Container image (`dispute-service-boot/Dockerfile`) and GKE manifests (`deploy/gke/dispute-service/`). No CI workflows.

## Service map (legacy)

### Inbound API (unchanged in Boot)

| Method | Path | Success | Errors |
|---|---|---|---|
| GET | `/disputes/{id}` (numeric; trailing slash accepted) | 200 case + `events` + `correspondence` | 404 `{"error":"dispute N not found"}` |
| GET | `/disputes/sla?received=yyyy-MM-ddTHH:mm:ss&region=EW\|SC` (region defaults EW) | 200 `{received, region, slaDueDt}` | 400 missing `received`, 500 unparsable `received` |
| POST | `/disputes` `{cnsmrId, trdlnId\|pubRecId, rsnCd, chnlCd?=WEB, rcvdTs?}` | 201 full case | 400 `{"error":"cnsmrId, rsnCd and one of trdlnId/pubRecId are required"}`, 400 malformed JSON |
| POST | `/disputes/{id}/resolve` `{outcome: AMEND\|DELETE\|NOCHANGE, operatorId, statusCd?, balancePence?}` | 200 full case | 400 bad outcome / `unknown operator X`, 404 `dispute N not found or already closed` |

### Outbound calls

| Peer | Call | When |
|---|---|---|
| credit-file-service | SOAP 1.1 `POST /ws/TradelineMaintenance`, ns `urn:ukcredit:tradeline:v1`, `SOAPAction: urn:ukcredit:tradeline:v1:<Op>`, hand-built envelope | `SetDisputeFlag` Y on open / N on close (tradeline disputes); `AmendTradeline` on AMEND/DELETE |
| score-service | `POST /score/{cnsmrId}/recalculate?trigger=DISPUTE_OPEN\|DISPUTE_CLOSE` | after every open/resolve; failures are logged and ignored |

Callers of dispute-service: none in this repo (web/telephony front ends, out of scope). score-service reads `DSPT_FLG` directly from the DB.

### Database

| Table | Access | Columns |
|---|---|---|
| DISPUTE_CASE | R/W | DSPT_ID, CNSMR_ID, TRDLN_ID, PUB_REC_ID, RSN_CD, CHNL_CD, RCVD_TS, SLA_DUE_DT, STS_CD, OUTCOME_CD, RSLVD_TS, RSLVD_BY |
| DISPUTE_EVENT | R/W | DSPT_EVT_ID, DSPT_ID, EVT_TYP_CD, EVT_TS, OPR_ID, NOTE_TXT |
| DISPUTE_CORRESPONDENCE | R/W | CORR_ID, DSPT_ID, LTR_TMPL_CD, SENT_TS, CHNL_CD |
| PUBLIC_RECORD | W | DSPT_FLG (public-record disputes; tradeline flag goes via SOAP) |
| OPERATOR | R | OPR_ID (existence only) |
| ADDRESS_HISTORY, ADDRESS | R | CNSMR_ID, DT_FROM, DT_TO, ADDR_HIST_ID / PSTCD (region) |
| BANK_HOLIDAY | R | HOL_DT, REGION_CD |
| SYS_PARAM | R | PARAM_VAL for `DSPT_CUTOFF_TM` |
| sequences | R | DSPT_SEQ, DSPT_EVT_SEQ, CORR_SEQ via `nextval('...')` |

## Dependency mapping

| Legacy | Boot |
|---|---|
| Java 8, Spring 4.3.30 (context, webmvc, jdbc) | Java 21, Spring Boot 3.3.5 / Spring 6.1 |
| `com.ukcredit.common.EmbeddedServer` (Jetty 9, javax.servlet) | `spring-boot-starter-web` (embedded Tomcat, jakarta.servlet) |
| `shared-datasource.xml` (DBCP + `db.properties`, `-Djdbc.*`) | `spring-boot-starter-jdbc` (Hikari) + `application-{h2,postgres}.yml` (env vars) |
| Jackson 2.9 | Jackson 2.17 (Boot managed) |
| H2 1.4.197 / Postgres 42.2 | H2 **1.4.197 pinned** (the shared `data/h2` file is 1.4 format; 2.x cannot open it) / Postgres driver Boot managed |
| none | `spring-boot-starter-actuator` (liveness/readiness) |
| JUnit 4 | JUnit 5 + MockMvc |

The module uses `spring-boot-starter-parent` rather than the legacy parent (which pins Spring 4 / Java 8). It does not depend on
`shared-db`: none of its classes are used by dispute-service except via XML, and DbConfig would drag Spring 4 onto the classpath.

### XML bean → @Bean (`DisputeConfig`)

| `dispute-servlet.xml` / `shared-datasource.xml` | Boot |
|---|---|
| `dataSource`, `jdbcTemplate` (shared-datasource.xml) | Boot auto-configuration (`spring.datasource.*`) |
| `disputeDao` (property `jdbcTemplate`) | `@Bean DisputeDao disputeDao(JdbcTemplate)` |
| `workingDayCalendar` | `@Bean WorkingDayCalendar workingDayCalendar(JdbcTemplate)` |
| `slaCalculator` (jdbcTemplate, workingDayCalendar) | `@Bean SlaCalculator slaCalculator(JdbcTemplate, WorkingDayCalendar)` |
| `regionResolver` | `@Bean RegionResolver regionResolver(JdbcTemplate)` |
| `tradelineMaintenanceClient` baseUrl=http://localhost:8081, timeoutMs=5000 | `@Bean` from `creditfile.url` / `creditfile.timeout-ms` (`CREDITFILE_URL`, `CREDITFILE_TIMEOUT_MS`) |
| `scoreClient` baseUrl=http://localhost:8082, timeoutMs=10000 | `@Bean` from `score.url` / `score.timeout-ms` (`SCORE_URL`, `SCORE_TIMEOUT_MS`) |
| `disputeService` (5 property refs) | `@Bean DisputeService` (constructor injection) |
| `<mvc:annotation-driven/>` + component-scan of `web` | `@SpringBootApplication`, `@RestController DisputeController(DisputeService)` |
| Spring 4 default trailing-slash match | `WebConfig.configurePathMatch` → `setUseTrailingSlashMatch(true)` (Spring 6 turned it off) |

Setter injection was replaced by final fields + constructors throughout; SQL strings, column aliases and SOAP templates are copied verbatim.

### Configuration

| Env var | Default | Notes |
|---|---|---|
| `PORT` (or `-Dport`) | 9083 | |
| `SPRING_PROFILES_ACTIVE` | `h2` locally, `postgres` in the image | |
| `DB_URL` | profile-specific | overrides everything below |
| `H2_PATH` | `./data/h2/ukcredit` | h2 profile, same file as `scripts/db-reset.sh` |
| `DB_HOST` / `DB_PORT` / `DB_NAME` | localhost / 5432 / ukcredit | postgres profile (127.0.0.1 with the Cloud SQL proxy) |
| `DB_USER` / `DB_PASSWORD` | ukcredit / ukcredit | Secret on GKE |
| `DB_POOL_MAX` | 10 | |
| `CREDITFILE_URL`, `SCORE_URL` | http://localhost:8081, :8082 | |
| `CREDITFILE_TIMEOUT_MS`, `SCORE_TIMEOUT_MS` | 5000, 10000 | same as the XML |

Probes: `/actuator/health/liveness`, `/actuator/health/readiness` (readiness includes the DB). Only `health` and `info` are exposed.

## Business rules preserved

All copied as-is (behaviour verified by the parity run and `SlaCalculatorTest`):

- **SLA = 20 working days** from receipt, skipping weekends and region bank holidays (`BANK_HOLIDAY`, cached per region).
- **Cut-off 17:30** from `SYS_PARAM.DSPT_CUTOFF_TM` (fallback 17:30): received after the cut-off, or on a non-working day, starts the next working day; exactly 17:30 counts as same day.
- **Region**: Scottish postcode areas → SC, everything else (including **BT / Northern Ireland**) → EW; no address → EW.
- **Current address** for the region: `DT_TO IS NULL ORDER BY DT_FROM DESC, ADDR_HIST_ID` (on a DT_FROM tie the older history row wins).
- Disputed items flagged `DSPT_FLG='Y'` while open and cleared on close (tradeline via SOAP, public record via SQL); ACK01 letter on open, RES01/RES02 on close.
- Operator check is existence only: `ACTV_FLG` is **not** checked, so the leaver `OPS0099` can still resolve (scenario s34).
- Score recalculation failures are swallowed (nightly batch catches up).

The estate-wide rules named in the playbook — status-X cut-off 2014-04-01, HALF_EVEN pence rounding of summed balances, diacritic
name normalisation (`MoneyUtil`, `NameNormaliser`) — are implemented in credit-file-service / score-service / shared-db and are not
used by dispute-service. They are untouched; dispute-service only calls those services over HTTP/SOAP, and the parity run reads
their responses after dispute actions (s19, s22, s27, s31, s33, s37) to confirm the end-to-end effect is identical.

## Parity results

Harness: `dispute-service-boot/parity/parity.py`. It replays 37 fixed scenarios (all four endpoints, validation errors, SLA edge cases,
open/resolve flows, and peer read-backs) and runs capturing proxies in front of credit-file (:18081) and score (:18082) so every
outbound call (path, query, headers and exact SOAP/JSON body) is recorded and compared too. Timestamps from "today" are normalised.

```
scripts/db-reset.sh && <start credit-file + score>          # legacy peers, same seeded DB
java -Dcreditfile.url=http://localhost:18081 -Dscore.url=http://localhost:18082 -jar <dispute jar>
python3 dispute-service-boot/parity/parity.py record --dispute http://localhost:9083 --out /tmp/boot
python3 dispute-service-boot/parity/parity.py compare dispute-service-boot/parity/baseline /tmp/boot
```

Legacy baseline (H2, committed in `parity/baseline/`) vs Boot on a freshly reset H2:

| Scenario | Legacy | Boot | Status | Body | Outbound calls |
|---|---|---|---|---|---|
| s01_get_seeded_open | 200 | 200 | same | same | none |
| s02_get_historic_closed | 200 | 200 | same | same | none |
| s03_get_not_found | 404 | 404 | same | same | none |
| s04_get_non_numeric_id | 404 | 404 | same | Jetty HTML error page -> Boot JSON error (intentional) | none |
| s05_get_trailing_slash | 200 | 200 | same | same | none |
| s06_sla_before_cutoff_ew | 200 | 200 | same | same | none |
| s07_sla_after_cutoff_ew | 200 | 200 | same | same | none |
| s08_sla_after_cutoff_sc | 200 | 200 | same | same | none |
| s09_sla_exactly_cutoff | 200 | 200 | same | same | none |
| s10_sla_one_minute_after | 200 | 200 | same | same | none |
| s11_sla_saturday_default_region | 200 | 200 | same | same | none |
| s12_sla_easter_ew | 200 | 200 | same | same | none |
| s13_sla_easter_sc | 200 | 200 | same | same | none |
| s14_sla_missing_received | 400 | 400 | same | Jetty HTML error page -> Boot JSON error (intentional) | none |
| s15_sla_bad_received | 500 | 500 | same | Jetty HTML error page -> Boot JSON error (intentional) | none |
| s16_open_missing_fields | 400 | 400 | same | same | none |
| s17_open_malformed_json | 400 | 400 | same | Jetty HTML error page -> Boot JSON error (intentional) | none |
| s18_open_scotland_after_cutoff | 201 | 201 | same | same | same |
| s19_tradeline_flag_after_open | 200 | 200 | same | same (XML) | none |
| s20_open_bt_postcode_default_channel | 201 | 201 | same | same | same |
| s21_open_public_record | 201 | 201 | same | same | same |
| s22_public_record_flag_after_open | 200 | 200 | same | same | none |
| s23_open_string_ids | 201 | 201 | same | same | same |
| s24_resolve_bad_outcome | 400 | 400 | same | same | none |
| s25_resolve_unknown_operator | 400 | 400 | same | same | none |
| s26_resolve_amend | 200 | 200 | same | same | same |
| s27_tradeline_after_amend | 200 | 200 | same | same (XML) | none |
| s28_resolve_already_closed | 404 | 404 | same | same | none |
| s29_resolve_not_found | 404 | 404 | same | same | none |
| s30_resolve_public_record_nochange | 200 | 200 | same | same | same |
| s31_public_record_flag_after_resolve | 200 | 200 | same | same | none |
| s32_resolve_delete | 200 | 200 | same | same | same |
| s33_tradeline_after_delete | 200 | 200 | same | same (XML) | none |
| s34_resolve_inactive_operator | 200 | 200 | same | same | same |
| s35_resolve_seeded_case | 200 | 200 | same | same | same |
| s36_get_after_resolve | 200 | 200 | same | same | none |
| s37_score_history_triggers | 200 | 200 | same | same | none |

**37 scenarios, 0 unexpected differences, 4 intentional.** All outbound SOAP envelopes, `SOAPAction` headers and score
recalculation calls are byte-identical. The same run on Postgres 15 (`docker compose up`, `. scripts/env-postgres.sh`, Boot with
the `postgres` profile) gave the same result: 0 unexpected, the same 4 intentional; legacy-on-Postgres also matched the H2 baseline.

## Intentional changes

1. **Container-generated error bodies.** When the request fails before the controller (non-numeric id → 404, missing/unparsable
   `received` → 400/500, malformed JSON → 400), legacy Jetty returns an HTML error page (the 500 page contains the exception
   message). Boot returns Spring Boot's standard JSON error `{timestamp, status, error, path}` with the **same status code**, and no
   exception detail. Controller-produced errors (`{"error": "..."}`) are unchanged. (s04, s14, s15, s17)
2. Embedded Tomcat instead of Jetty; Hikari instead of DBCP. Not observable in the API.
3. Default port 9083 (legacy 8083) so both run side by side; `-Dport` / `PORT` still override.
4. New `/actuator/health/**` endpoints.

## GKE deployment guide

```
# image (build context is the module; Maven downloads go through the GCS Maven Central mirror by default)
docker build -t REGION-docker.pkg.dev/PROJECT_ID/uk-credit/dispute-service-boot:TAG dispute-service-boot
docker push REGION-docker.pkg.dev/PROJECT_ID/uk-credit/dispute-service-boot:TAG

# DB credentials (do not apply the CHANGE_ME template in configmap.yaml to a real cluster)
kubectl create secret generic dispute-service-db --from-literal=DB_USER=... --from-literal=DB_PASSWORD=...
kubectl create serviceaccount dispute-service      # bind to a GSA with roles/cloudsql.client if using the proxy

# edit image tag, DB_HOST, peer URLs; optionally uncomment the Cloud SQL Auth Proxy sidecar
kubectl apply -k deploy/gke/dispute-service
kubectl rollout status deploy/dispute-service
```

- Image: multi-stage `eclipse-temurin:21-jdk` build → `eclipse-temurin:21-jre` runtime, layered jar, runs as uid 10001.
- Deployment: 2 replicas, rolling update with maxUnavailable 0, startup/liveness/readiness probes, requests 250m/512Mi, limit 768Mi,
  non-root, read-only root FS, all capabilities dropped. Env from `dispute-service-config` ConfigMap and `dispute-service-db` Secret.
- Service: ClusterIP `dispute-service:9083`. HPA: 2–6 replicas at 70% CPU.
- Cloud SQL: either set `DB_HOST` to the private IP, or uncomment the `cloud-sql-proxy` sidecar (DB_HOST 127.0.0.1) and use Workload Identity.
- Peers: the ConfigMap points at `credit-file-service:8081` and `score-service:8082`; they must be reachable from the cluster
  (in-cluster Services or an internal LB/ExternalName for the legacy hosts).
- Verified locally: the image builds, starts with the h2 profile, reports UP on both probes and serves `/disputes/40001` as uid 10001.
  The manifests were YAML-validated only; they were not applied to a cluster.

## Rollback plan

- No schema changes: both implementations read and write the same tables with the same SQL, so traffic can move either way at any time.
- Cut over by pointing callers (or the ingress / LB) from legacy :8083 to `dispute-service:9083`. To roll back, point them back; the
  legacy module and its jar are unchanged and can keep running throughout.
- On GKE: `kubectl rollout undo deploy/dispute-service` for a bad image; `kubectl scale deploy/dispute-service --replicas=0` to stop it.
- Avoid running both against the same DB with live write traffic for long; they share sequences so IDs will not clash, but callers
  would see two sources of truth for in-flight cases.

## Open risks / questions

- **SLA days**: `SYS_PARAM.DSPT_SLA_DAYS = 28` and a legacy comment say 28 calendar days, but the code uses 20 working days
  (ignoring the parameter). Preserved; needs a business decision.
- **Inactive operators** can resolve disputes (`ACTV_FLG` not checked). Preserved; likely a bug.
- **Northern Ireland**: BT postcodes use EW holidays (NI holidays not loaded). Preserved, as per the legacy TODO.
- **Holiday cache** is per JVM and never refreshed (same as legacy); with several pods each loads its own copy. Restart pods after
  `BANK_HOLIDAY` changes.
- **Error bodies** change for framework-level errors (see Intentional changes); any client that scraped the Jetty HTML would notice.
- **H2 1.4.197** is pinned for the local profile to share the legacy file; it is old and has known CVEs. Only used locally — the image
  defaults to Postgres — but drop the pin once the estate moves to H2 2.x.
- **Peer timeouts / retries** unchanged (5 s / 10 s, no retries, no circuit breaker). Outbound SOAP failures on open/resolve behave
  exactly as legacy (logged, request still succeeds).
- No DB migrations run from this service; schema ownership stays with shared-db `DbMigrate`.
- Not exercised: a real GKE cluster and Cloud SQL.
