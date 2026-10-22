# characterization-tests

Black-box HTTP tests that pin what the legacy estate **actually does today** (not what comments or docs say),
so a re-implementation of score-service can be checked for parity before cutover. JUnit 4, Java 8.

Skipped in the normal build; they need the services running against a freshly reset database:

```sh
scripts/build.sh && . scripts/env-postgres.sh && scripts/db-reset.sh && scripts/run-all.sh
mvn -B -pl characterization-tests test -Dcharacterization=true
```

| Property | Default | |
|---|---|---|
| `score.url` | `http://localhost:8082` | score-service under test |
| `creditfile.url` | `http://localhost:8081` | |
| `dispute.url` | `http://localhost:8083` | |
| `suite.target` | `legacy` | label for `target/characterization/<target>/` diff output |
| `golden.record` | `false` | `true` rewrites `src/test/resources/golden/*` (run right after `db-reset.sh`, on legacy only) |
| `groups` | all | `com.ukcredit.characterization.ScoreApi` = only checks that go through score-service |

| Test | Pins |
|---|---|
| `ScoreGoldenMasterTest` | `GET /score/{id}?asOf=2024-12-31` for all 256 seeded consumers → `golden/score-uks3.json` |
| `CreditFileGoldenMasterTest` | `GET /creditfile/{id}` for 100001-100016 → `golden/creditfile-edge-cases.json` |
| `StatusXCutoffTest` | status X: DEFAULT before 2014-04-01, ARRANGEMENT on/after; stale `SYS_PARAM` 2015-01-01 ignored |
| `DisputeSlaTest` | 20 working days, EW vs SC bank holidays, 17:30 cutoff at minute precision, unknown region = no holidays |
| `UtilisationRoundingTest` | HALF_EVEN on the summed pence (100005 75%, 100006 75%, 100007 49%) |
| `NameMatchingTest` | `/consumers/match` diacritic/punctuation normalisation (Siobhán, Renée, Łukasz, Strauß) |
| `AddressHistoryMergeTest` | duplicate address rows keep the older record on ties (100011) |
| `DisputeScoreFlowTest` | open → `SCORE_HISTORY` `DISPUTE_OPEN`, resolve → `DISPUTE_CLOSE` (self-restoring, consumer 100013) |

`parity/parity_report.py` turns a legacy run and a candidate run into
`docs/cutover/score-service-parity-report.md`; root causes and approved intentional changes live in
`docs/cutover/parity-findings.json`.
