# batch-ingest

Loads a lender (CAIS-style) monthly file into ACCOUNT_TRADELINE.

    java -jar target/batch-ingest-<version>-exec.jar <file>

Files are fixed width, 240 bytes per record, ISO-8859-1. Offsets below are 0-based, end exclusive.

HDR

| Field | Offset |
|-------|--------|
| 'HDR' | 0-3 |
| Lender ref | 3-9 |
| File date yyyyMMdd | 9-17 |

DTL

| Field | Offset | Notes |
|-------|--------|-------|
| 'DTL' | 0-3 | |
| Account number | 3-23 | hashed with AccountHash, never stored |
| Account type | 23-25 | ACCOUNT_TYPE_REF |
| Surname | 25-55 | |
| Forename | 55-75 | |
| Date of birth | 75-83 | yyyyMMdd |
| Postcode | 83-93 | |
| Open date | 93-101 | |
| Close date | 101-109 | 00000000 = open |
| Credit limit | 109-117 | whole pounds, 0 = none |
| Balance sign | 117 | + or - |
| Balance | 118-129 | pence |
| Status | 129 | |
| Status date | 130-138 | |
| Payment profile | 138-162 | 24 months, most recent first |
| Address since | 162-170 | |
| Address line 1 | 170-210 | |
| Town | 210-240 | |

TRL

| Field | Offset |
|-------|--------|
| 'TRL' | 0-3 |
| DTL count | 3-11 |

Processing

- Existing account (lender ref + account hash): snapshot to TRADELINE_HISTORY then update. If the account is
  under dispute (DSPT_FLG = 'Y') the update is held and written to BATCH_REJECT.
- New account: consumer matched with the credit-file matching rules; no match creates a consumer, more than one
  match rejects the record.
- New address for the consumer is added to ADDRESS / ADDRESS_HISTORY with source CAI.
- Records that fail to parse go to BATCH_REJECT. Run totals in BATCH_RUN_LOG; a trailer count mismatch sets STS_CD WARN.
