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

## 2. Scope

New module `credit-file-service-boot` (port 9081), built standalone (`mvn -f credit-file-service-boot/pom.xml package`,
JDK 21). It sits alongside the legacy module and replaces it at runtime. Unchanged: `credit-file-service`
(still needed by batch-ingest), `shared-db`, `score-service`, `dispute-service`, `batch-ingest`, the root reactor
(still Java 8), and the schema and seed data. No CI workflows were added.

## 3. Dependency / API mapping

| Legacy | Boot module |
|--------|-------------|
| Java 8 | Java 21 (`java.version=21`) |
| Spring 4.3.30 (context, webmvc, jdbc, tx) | Spring Boot 3.5.16 / Spring Framework 6.2: `spring-boot-starter-web`, `-jdbc`, `-actuator` |
| Embedded Jetty 9.4 (`EmbeddedServer`) | Embedded Tomcat 10.1 (Boot default) |
| `javax.servlet` | `jakarta.servlet` (only used in tests; the main code uses no servlet API) |
| commons-dbcp 1.4 `BasicDataSource` | HikariCP (Boot default); pool size `DB_POOL_MAX` / `jdbc.pool.maxActive` |
| `PropertyPlaceholderConfigurer` + `db.properties` | `application.yml` + profiles `h2` (default) and `postgres` |
| H2 1.4.197 | H2 1.4.197, pinned (`h2.version`): H2 2.x cannot open the 1.4 file that the legacy estate writes |
| postgresql 42.2.27 | postgresql managed by Boot (42.7.x) |
| JUnit 4 | JUnit 5 (`spring-boot-starter-test`) |
| `@RequestMapping(method=GET/POST)` + `@ResponseBody` | `@GetMapping` / `@PostMapping` on `@RestController` |
| Spring 4 suffix pattern match (`/creditfile/1.json`) | explicit `{id}.json` / `match.json` mappings (Spring 6 removed suffix matching) |
| Spring 4 trailing-slash match | `UrlHandlerFilter.trailingSlashHandler` (`WebConfig`) |
| `@RequestBody String` decoded by `StringHttpMessageConverter` (charset from Content-Type, else ISO-8859-1) | `@RequestBody byte[]`, decoded with the same rule (`TradelineMaintenanceEndpoint.requestCharset`); Boot's `CharacterEncodingFilter` is disabled because the legacy Jetty had none |
| `javax.xml.parsers` (JDK) | unchanged (JDK API, no Jakarta move) |

Configuration (env first, then the legacy `-Djdbc.*` system property, then the profile default):

| Setting | Env | Legacy property | Default |
|---------|-----|-----------------|---------|
| JDBC URL | `DB_URL` | `jdbc.url` | h2: `jdbc:h2:file:./data/h2/ukcredit;MODE=PostgreSQL;AUTO_SERVER=TRUE`; postgres: `jdbc:postgresql://${DB_HOST:127.0.0.1}:${DB_PORT:5432}/${DB_NAME:ukcredit}` |
| User / password | `DB_USERNAME` / `DB_PASSWORD` | `jdbc.username` / `jdbc.password` | `ukcredit` / `ukcredit` |
| Pool size | `DB_POOL_MAX` | `jdbc.pool.maxActive` | 10 |
| Port | `PORT` | - | 9081 |
| Profile | `SPRING_PROFILES_ACTIVE` | - | `h2` (image default `postgres`) |

The driver is picked from the URL, so `. scripts/env-postgres.sh` (`$JDBC_OPTS`) works unchanged. credit-file-service
has no outbound peer calls, so there are no peer URLs to configure. Consumers keep configuring
`-Dcreditfile.url` (now `http://localhost:9081` or `http://credit-file-service:9081` in-cluster).

## 4. XML bean → `@Bean` mapping

| XML bean | Boot |
|----------|------|
| `dbProperties` | `application.yml` / profiles |
| `dataSource` (DBCP) | auto-configured `HikariDataSource` (`spring.datasource.*`) |
| `jdbcTemplate`, `transactionManager`, `<tx:annotation-driven>` | auto-configured `JdbcTemplate`, `DataSourceTransactionManager`, `@EnableTransactionManagement` |
| `tradelineStatusMapper`, `nameMatcher`, `addressHistoryMerger` | `CreditFileConfig` `@Bean`s of the same name |
| `consumerDao`, `tradelineDao`, `addressHistoryDao` | `CreditFileConfig` `@Bean`s, constructor `JdbcTemplate` |
| `creditFileAssembler`, `consumerMatchService`, `tradelineMaintenanceService` | `CreditFileConfig` `@Bean`s, constructor injection; `@Transactional` kept on `TradelineMaintenanceService` |
| component-scan `web` | `@SpringBootApplication` scan; controllers use constructor injection |
| - | Actuator `/actuator/health/liveness` (no DB) and `/actuator/health/readiness` (`readinessState` + `db`) |

DAO, domain, rules and service code is copied as-is; the only change is setter injection → final fields with a constructor.
`NameNormaliser` is copied from `shared-db` so the Boot module does not pull the Spring 4 / Jetty / DBCP stack in.

## 5. Rules preserved (unchanged code, covered by parity)

- Status `X` with status date before 2014-04-01 → `DEFAULT`, otherwise `ARRANGEMENT` (`TradelineStatusMapper`; unit test + seeded consumers).
- Name matching: diacritics, punctuation, apostrophes, hyphens stripped; initials and short forms (`NameNormaliser`, `NameMatcher`; Ó Briain, Dubois-Marchand, Wiśniewski, Strauß cases).
- Duplicate addresses: older `dtFrom`, then earlier creation timestamp, then lower history id (`AddressHistoryMerger`).
- Balances in pence; whole-pound display with `HALF_EVEN` (`CreditFileAssembler` `balanceDisplay`).
- Audit rows: `AUD_SEQ` id, `SRC_SVC=credit-file-service`, same `DTL_TXT` wording (checked row by row).
- Bank-holiday working days belong to dispute-service and are unchanged. The parity run drives dispute open/resolve through the Boot service.
- SOAP: same envelope prefixes and namespace declarations, same element order, same `text/xml;charset=UTF-8`,
  faults still HTTP 200 `soapenv:Client` with the same `faultstring`s, namespace-then-plain-tag lookup, and
  `tradelineId` still parsed before dispatch.

## 6. Parity results

Harness: `credit-file-service-boot/parity/` (`cases.json`, `parity.py`, `run-parity.sh`). Each run resets the seeded DB
(`scripts/db-reset.sh`), starts one credit-file implementation plus the **legacy** score-service and dispute-service pointed
at it, and replays 88 cases: every endpoint, each seeded consumer, SOAP happy paths, faults and malformed input, mutations, the
downstream score and dispute flows, and the resulting `AUDIT_LOG` / `ACCOUNT_TRADELINE` rows. The compare covers status,
Content-Type and the exact body. The only masking is the current date written by amends (`<TODAY>`) and the timing lines from the DB shell. `asOf=2024-12-31` is fixed.

```
credit-file-service-boot/parity/run-parity.sh legacy capture   # JDK 8 legacy -> fixtures/legacy-baseline.json
credit-file-service-boot/parity/run-parity.sh boot compare     # JDK 21 Boot  -> parity-report.md
```

| DB | Cases | Match | Intentional | Fail |
|----|-------|-------|-------------|------|
| H2 (seeded file DB) | 88 | 79 | 9 | 0 |
| Postgres 15 (`docker compose`, `. scripts/env-postgres.sh`) | 88 | 79 | 9 | 0 |

Full tables: `credit-file-service-boot/parity/parity-report.md` (H2) and `parity-report-postgres.md`.

Also checked:
- Unit and slice tests (`mvn test`, 11 tests): rules, byte-exact SOAP responses and faults, the request charset rule, DOCTYPE rejection, and the probes.
- Container image (`docker run --read-only`, `postgres` profile, seeded Postgres): runs as uid 10001, liveness and readiness 200,
  `/creditfile/100001` 200 `application/json;charset=UTF-8`, SOAP fault byte-identical. With Postgres stopped,
  liveness stays 200 and readiness goes to 503.

## 7. Intentional changes

| Case(s) | Legacy | Boot | Why |
|---------|--------|------|-----|
| Framework error pages (bad id 400, wrong method 405, missing/bad `dob` 400/500, SOAP missing/non-numeric `tradelineId` 500, malformed XML 500, GET on SOAP path 405) | Jetty HTML error page | Spring Boot JSON error body (`timestamp,status,error,path`) | Status codes are unchanged. No consumer reads these bodies: `CreditFileClient` maps 404 → null, and `TradelineMaintenanceClient` only checks for `>OK<`. |
| SOAP request containing a `<!DOCTYPE>` | DTD processed, so entities expand (XXE) | HTTP 500, as for other unparseable input | SOAP 1.1 §3 forbids DTDs. Closes XXE. No legitimate caller sends one. |

## 8. GKE deployment

Manifests: `deploy/gke/credit-file-service/` (kustomize: ConfigMap, Deployment + ServiceAccount, Service, HPA;
`secret.example.yaml` documents the Secret).

```
docker build -f credit-file-service-boot/Dockerfile \
  [--build-arg MAVEN_MIRROR_URL=https://maven-central.storage-download.googleapis.com/maven2/] \
  -t REGION-docker.pkg.dev/PROJECT_ID/ukcredit/credit-file-service-boot:TAG .
docker push REGION-docker.pkg.dev/PROJECT_ID/ukcredit/credit-file-service-boot:TAG
kubectl create secret generic credit-file-service-db --from-literal=DB_USERNAME=... --from-literal=DB_PASSWORD=...
# set the image tag in deployment.yaml (or `kustomize edit set image`), then
kubectl apply -k deploy/gke/credit-file-service/
```

- Image: multi-stage build (`maven:3.9-eclipse-temurin-21` → `eclipse-temurin:21-jre`) with layered jar. Runs as uid 10001 and exposes 9081.
- Pod: non-root, read-only root filesystem, all capabilities dropped, seccomp `RuntimeDefault`, `/tmp` on an emptyDir.
  Requests 250m CPU / 512Mi, limit 768Mi. The JVM uses `MaxRAMPercentage=75`.
- Probes: startup + liveness `/actuator/health/liveness`, readiness `/actuator/health/readiness` (includes DB). Graceful shutdown plus a 10 s preStop.
- HPA: 2–6 replicas at 70% CPU. Rolling update with `maxUnavailable: 0`.
- Cloud SQL: uncomment the `cloud-sql-proxy` sidecar, set `PROJECT_ID:REGION:INSTANCE`, keep `DB_HOST=127.0.0.1`,
  and bind the KSA to a GSA with `roles/cloudsql.client` (Workload Identity annotation in `deployment.yaml`).
  Without the proxy, set `DB_HOST` to the instance private IP.
- Schema: the service does not migrate. The schema stays owned by `shared-db` `DbMigrate`, run as a separate job, as today.
- Cut-over: point score-service and dispute-service `creditfile.url` at `http://credit-file-service:9081`.

## 9. Rollback

The legacy module and jar are untouched and the schema has not changed, so rollback is configuration only. Set
`creditfile.url` back to the legacy instance (`:8081`) and scale the Boot Deployment to 0 (or `kubectl delete -k`).
Both services write the same rows in the same format, so data written by either is readable by the other.

## 10. Open risks

- H2 is pinned to 1.4.197 for file compatibility. It has known CVEs, so use it for local/dev only. Prod uses the `postgres` profile.
- Error bodies for non-SOAP failures changed (section 7). Any external caller that scrapes Jetty error HTML would notice.
- Tomcat replaces Jetty: header casing and the `Date`/`Server` headers differ. These were not compared, and no consumer reads them.
- batch-ingest still compiles against the legacy module, so rule changes have to be made in both modules until batch-ingest is migrated.
- The Postgres parity run used Postgres 15 via docker-compose. Cloud SQL itself was not exercised, and neither was the image on a real GKE cluster.
