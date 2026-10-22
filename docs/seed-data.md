# Seed data

`SeedDataGenerator` loads a fixed set of fictional consumers, lenders and accounts (as-of 2024-12-31) and
writes the sample lender file `data/inbound/BKA001_20250101.dat`. Consumers above 100016 are random filler.
Use asOf=2024-12-31 when comparing scores.

| Consumer | Case |
|----------|------|
| 100001 | Status X dated before the 2014-04-01 cutoff - scores as DEFAULT |
| 100002 | Status X after the cutoff - scores as ARRANGEMENT |
| 100003 | Status X on 2014-03-31 and on 2014-04-01 (either side of the cutoff) |
| 100004 | Status X on 2014-06-01 (after the code cutoff, before SYS_PARAM TRDLN_X_CUTOFF_DT) |
| 100005 | Utilisation 749.50 / 1000 - 75% |
| 100006 | Two cards 300.50 + 449.00 - balances summed in pence before rounding, 750 / 1000 = 75% |
| 100007 | 500.50 / 1002 - HALF_EVEN gives 500 = 49% (HALF_UP would give 50%) |
| 100008 | Siobhán Ó Briain, Belfast (BT postcode, disputes treated as EW) |
| 100009 | Renée Dubois-Marchand |
| 100010 | Łukasz Wiśniewski |
| 100011 | Margaret Strauß - two address history rows that tie on DT_FROM |
| 100012 | Edinburgh (SC region for dispute SLA) |
| 100013 | Bristol (EW region for dispute SLA) |
| 100014 | County court judgments |
| 100015 | Thin file - no scorable accounts |
| 100016 | Open dispute 40001 on a BKA001 card (received 2024-12-20 10:15, due 2025-01-22) |

The BKA001 sample file includes updates for 100008-100010 under unaccented names (should match),
an update for 100016 (held - account under dispute), a new consumer PENROSE and one record with a
bad status date (rejected).
