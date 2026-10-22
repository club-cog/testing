package com.ukcredit.characterization;

import org.junit.Test;

import static org.junit.Assert.assertEquals;

/**
 * Quirk (b): dispute SLA = 20 working days, skipping weekends and the region's bank holidays (EW vs SC), with
 * day 1 being the next working day when received on or before 17:30 (minute precision - seconds are ignored),
 * otherwise the clock starts a day later. Unknown regions get no bank holidays at all.
 */
public class DisputeSlaTest {

    static String sla(String received, String region) {
        return Http.getJson(Http.disputeUrl() + "/disputes/sla?received=" + received + "&region=" + region)
                .get("slaDueDt").asText();
    }

    @Test
    public void slaSkipsUkBankHolidaysPerRegionWith1730Cutoff() {
        // Christmas/New Year: SC also loses 2 Jan
        assertEquals("2025-01-22", sla("2024-12-20T10:15:00", "EW"));
        assertEquals("2025-01-23", sla("2024-12-20T10:15:00", "SC"));
        assertEquals("2025-01-29", sla("2024-12-31T09:00:00", "EW"));
        assertEquals("2025-01-30", sla("2024-12-31T09:00:00", "SC"));
        // St Andrew's Day (SC, Sat 30 Nov -> Mon 2 Dec) on an after-cutoff Friday receipt
        assertEquals("2025-01-02", sla("2024-11-29T18:00:00", "EW"));
        assertEquals("2025-01-06", sla("2024-11-29T18:00:00", "SC"));
        // Easter: EW loses Easter Monday, SC does not
        assertEquals("2025-04-23", sla("2025-03-24T09:00:00", "EW"));
        assertEquals("2025-04-22", sla("2025-03-24T09:00:00", "SC"));
        // August: EW late summer (25 Aug) vs SC summer (4 Aug) - same due date
        assertEquals("2025-08-26", sla("2025-07-28T09:00:00", "EW"));
        assertEquals("2025-08-26", sla("2025-07-28T09:00:00", "SC"));

        // 17:30 cutoff, minute precision
        assertEquals("2025-01-22", sla("2024-12-20T17:30:00", "EW"));
        assertEquals("2025-01-22", sla("2024-12-20T17:30:59", "EW"));
        assertEquals("2025-01-23", sla("2024-12-20T17:31:00", "EW"));
        // weekend receipt behaves like after-cutoff on the Friday
        assertEquals("2025-01-23", sla("2024-12-21T10:00:00", "EW"));

        // unrecognised region: no holidays at all
        assertEquals("2025-01-17", sla("2024-12-20T10:15:00", "NI"));
    }
}
