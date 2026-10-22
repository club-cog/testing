# score-service → score-service-boot (Spring Boot 3 / Java 21 / GKE)

## Scope

- Migrated: `score-service` only. New module `score-service-boot`; the legacy `score-service` module is unchanged and still builds on JDK 8.
- Not migrated: `shared-db` (reused as a jar for schema/seed tooling only), `credit-file-service`, `dispute-service`, `batch-ingest`.
- Root `pom.xml` registers `score-service-boot` in a `boot3` profile that activates on JDK 21+, so `scripts/build.sh` on JDK 8 is unaffected.

| | Legacy `score-service` | `score-service-boot` |
|---|---|---|
| Runtime | Java 8, embedded Jetty 9, Spring 4.3 XML | Java 21, Spring Boot 3.3.5 (Tomcat) |
| Port | `8082` (hard-coded) | `${PORT:9082}` |
| Wiring | `META-INF/spring/score-servlet.xml` + `shared-datasource.xml` | `ScoreServiceConfig` (`@Bean`, constructor injection) |
| Datasource | `db.properties` / `-Djdbc.*` | `DB_URL`, `DB_USERNAME`, `DB_PASSWORD`, `DB_POOL_MAX`, `DB_POOL_MIN_IDLE` (Hikari) |
| Credit-file URL | `-Dcreditfile.url`, default `http://localhost:8081` | `CREDITFILE_URL` (default `http://localhost:8081`), `CREDITFILE_TIMEOUT_MS` (default 5000) |
| Profiles | n/a | `h2` (default, shared `./data/h2/ukcredit` file), `postgres` |
| Health | none | `/actuator/health/liveness`, `/actuator/health/readiness` (includes `db`) |

## Service map

### Endpoints (all preserved, same paths, JSON fields, and status codes)

| Method | Path | Response | Notes |
|---|---|---|---|
| GET | `/score/{id}?asOf=yyyy-MM-dd` | `ScoreResult` | `asOf` optional (defaults to today); 404 with empty body when the credit file is missing |
| POST | `/score/{id}/recalculate?trigger=` | `ScoreResult` | Writes a `SCORE_HISTORY` row; `trigger` defaults to `MANUAL` |
| GET | `/score/{id}/history` | `[{id, score, band, modelVer, asOf, trigger, reasons}]` | Newest first |

Spring 4 also matched `/score/{id}/` and `/score/{id}.json` (trailing-slash and suffix matching). Boot 3 removed both, so the controller maps them explicitly to keep old clients working.

`ScoreResult` JSON fields: `cnsmrId`, `score`, `band`, `modelVer`, `asOf`, `reasons`, `revolvingBalance`, `revolvingLimit`, `utilisationPct`.

### XML beans → Java config

| `score-servlet.xml` bean | Boot replacement |
|---|---|
| `dataSource` (shared-datasource.xml, DBCP) | Spring Boot auto-configured Hikari `DataSource` + `JdbcTemplate` |
| `creditFileClient` | `CreditFileClient(RestTemplate, CreditFileProperties)` |
| `scoreModelDao` | `ScoreModelDao(JdbcTemplate)` |
| `scoreHistoryDao` | `ScoreHistoryDao(JdbcTemplate)` |
| `legacyStatusTranslator` | `LegacyStatusTranslator` |
| `scoreCalculator` (setter `statusTranslator`) | `ScoreCalculator(LegacyStatusTranslator)` |
| `scoreService` | `ScoreService(CreditFileClient, ScoreModelDao, ScoreHistoryDao, ScoreCalculator)` |
| `<mvc:annotation-driven>` / `ScoreController` | `@RestController ScoreController` |

### Tables and SQL (unchanged statements)

| Table / object | Access | Used for |
|---|---|---|
| `SYS_PARAM` (`SCORE_MODEL_VER`) | read | Active model version (`UKS3`) |
| `SCORE_MODEL_PARAM` | read | Model weights/cut-offs per `MODEL_VER` |
| `SCORE_HISTORY`, sequence `SCR_HIST_SEQ` | read/write | Recalculate inserts, history endpoint |
| `ACCOUNT_TRADELINE.DSPT_FLG` | read | Open-dispute count → `DSPT_SUPPRESSED` |

The schema is still owned by `shared-db` Flyway migrations; the Boot module does not run Flyway.

### Dependencies

- Upstream: `credit-file-service` `GET /creditfile/{id}` (404 → score 404).
- Downstream: `dispute-service` calls score-service via `ScoreClient` (`-Dscore.url`, default `http://localhost:8082`). Checked with `-Dscore.url=http://localhost:9082`: opening a dispute writes the same `DISPUTE_OPEN` history row through Boot.

## Business rules (moved over unchanged, covered by tests)

- Legacy status `X` means default only before `2014-04-01`, otherwise arrangement (`LegacyStatusTranslator`; `ScoreCalculatorTest` checks the boundary date exactly).
- Revolving balances are summed in pence and rounded HALF_EVEN to whole pounds (`ScoreCalculatorTest`).
- Diacritic name normalisation, older-wins address tie-break, and bank-holiday-aware working days are in `credit-file-service`/`shared-db`. Boot reads their output over HTTP, so they behave the same.
- Thin file → `NOSCORE`/`THIN_FILE`; an open dispute adds `DSPT_SUPPRESSED`.

## Parity

Baseline: `scripts/db-reset.sh` (256 seeded consumers: edge cases 100001–100016 and generated 100017–100256), then legacy run with `scripts/run-all.sh`. Each side gets a fresh reset, so `SCORE_HISTORY` ids and sequence values line up.

```
scripts/score-parity.sh capture http://localhost:8082 data/parity/legacy
scripts/score-parity.sh capture http://localhost:9082 data/parity/boot
scripts/score-parity.sh compare data/parity/legacy data/parity/boot
```

Captured per consumer 100001–100256 plus unknown 999999: `GET ?asOf=2024-12-31` (`get`), `GET` with no `asOf` (`get-today`), `POST recalculate` (`recalc`), `POST recalculate?trigger=BATCH` (`recalc-trigger`), `GET history` after both POSTs (`history`). The script compares status code and byte-for-byte body.

| Fixture | H2: compared / identical / diff | PostgreSQL 15 (Boot from Docker image): compared / identical / diff |
|---|---|---|
| get | 257 / 257 / 0 | 257 / 257 / 0 |
| get-today | 257 / 257 / 0 | 257 / 257 / 0 |
| recalc | 257 / 257 / 0 | 257 / 257 / 0 |
| recalc-trigger | 257 / 257 / 0 | 257 / 257 / 0 |
| history | 257 / 257 / 0 | 257 / 257 / 0 |
| status codes | identical (1281×200, 4×404) | identical (1281×200, 4×404) |

`ScoreControllerParityTest` (in `mvn verify`) replays the legacy captures for edge cases 100001–100016 and 999999 against the Boot controller, using credit-file responses captured from legacy.

## Intentional differences

- Error bodies for requests that never reach a handler (`/score/abc` → 400, malformed `asOf` → 500, unknown path → 404) are now Boot's JSON error body (`timestamp,status,error,path`) instead of Jetty's HTML error page. Status codes are the same, and so are unsupported methods (405). The old HTML page exposed exception class names.
- Port default `9082` instead of `8082`, so both can run side by side. In GKE the Service still exposes port `8082`.

## Build and run locally

```
# JDK 21
mvn -f score-service-boot/pom.xml verify        # needs shared-db installed: run scripts/build.sh on JDK 8 first
java -jar score-service-boot/target/score-service-boot-*.jar                 # h2 profile, port 9082
PORT=9182 SPRING_PROFILES_ACTIVE=postgres DB_URL=jdbc:postgresql://localhost:5432/ukcredit \
  DB_USERNAME=ukcredit DB_PASSWORD=ukcredit java -jar score-service-boot/target/score-service-boot-*.jar
```

If Maven Central is blocked, add a `<mirror>` for `https://maven-central.storage-download.googleapis.com/maven2/` in `~/.m2/settings.xml`. The Dockerfile takes `--build-arg MAVEN_MIRROR_URL=...`.

## Container

`score-service-boot/Dockerfile`: multi-stage (`maven:3.9-eclipse-temurin-21` → `eclipse-temurin:21-jre`). It runs as non-root UID/GID 10001 with `-XX:MaxRAMPercentage=75`. Build from the repo root:

```
docker build -f score-service-boot/Dockerfile -t score-service-boot:dev .
```

## GKE deployment (`deploy/gke/score-service`)

1. Create the namespace and secret (`secret.example.yaml` is a template and is **not** in the kustomization):
   `kubectl create secret generic score-service-db --from-literal=DB_USERNAME=... --from-literal=DB_PASSWORD=...`
2. Push the image to Artifact Registry and replace `REGION`/`PROJECT_ID`/`TAG` in the `deployment.yaml` image, or use `kustomize edit set image REGION-docker.pkg.dev/PROJECT_ID/uk-credit/score-service-boot=<your image>`.
3. Set `DB_URL` / `CREDITFILE_URL` in `configmap.yaml`.
4. `kubectl apply -k deploy/gke/score-service`

Resources: ServiceAccount (Workload Identity annotation commented), ConfigMap, Deployment (2 replicas, RollingUpdate maxUnavailable 0, non-root/read-only root FS, startup/liveness/readiness probes on actuator), Service (ClusterIP `8082` → container `9082`), HPA (2–6 replicas at 70% CPU). Manifests pass `kubeconform -strict`.

### Cloud SQL

The Deployment has a commented `cloud-sql-proxy` sidecar (`gcr.io/cloud-sql-connectors/cloud-sql-proxy:2.x`, `--private-ip`, `--port=5432`). To enable it: uncomment the sidecar, set the instance connection name, bind the KSA to a GSA with `roles/cloudsql.client` through Workload Identity, and set `DB_URL=jdbc:postgresql://127.0.0.1:5432/ukcredit`.

## Cutover and rollback

1. Run Boot side by side with legacy against the same DB. Re-run `scripts/score-parity.sh` against production-like data.
2. Point `dispute-service` (`score.url`) and other callers at the Boot Service. Callers that keep `:8082` need no change in GKE.
3. Rollback: point callers back at legacy (`score.url` / Service selector). No schema changes were made, and both versions write the same `SCORE_HISTORY` rows, so rolling back needs no data migration. Then `kubectl rollout undo deployment/score-service` or scale the Boot Deployment to 0.

## Open risks

- `SCR_HIST_SEQ` is shared. History ids interleave if both versions take recalculations during side-by-side running. Values stay valid; only ordering by id mixes the two writers.
- `shared-db` stays on Java 8 / Flyway 4.2 and owns the schema. Upgrading Flyway is a separate change. Flyway 4.2 `clean` breaks on new PostgreSQL, which is why `DbMigrate` drops the schema instead.
- `README.md` lists credit-file on `8080`, but the scripts and code use `8081`. Boot defaults to `8081`.
