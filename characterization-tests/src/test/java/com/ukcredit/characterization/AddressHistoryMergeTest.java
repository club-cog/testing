package com.ukcredit.characterization;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.Test;

import static org.junit.Assert.assertEquals;

/**
 * Quirk (e): duplicate address-history rows for the same address are merged, keeping the OLDER record: earliest
 * DT_FROM, then earliest CRTD_TS on a DT_FROM tie, then lowest ADDR_HIST_ID. Consumer 100011 has both cases.
 */
public class AddressHistoryMergeTest {

    static String row(JsonNode a) {
        return a.get("addrId").asText() + " id=" + a.get("addrHistId").asText() + " " + a.get("from").asText()
                + ".." + a.get("to").asText() + " " + a.get("source").asText();
    }

    @Test
    public void addressHistoryMergeKeepsOlderRecordOnTies() {
        JsonNode addrs = Http.getJson(Http.creditFileUrl() + "/creditfile/100011").get("addresses");
        assertEquals(2, addrs.size());
        // 500011: rows 13 (2019-05-01, open, ERL, created 2019-06-01) and 14 (2019-05-01..2023-01-01, CAI,
        // created 2021-03-10) tie on DT_FROM -> older CRTD_TS wins, so the address stays current.
        assertEquals("500011 id=13 2019-05-01..null ERL", row(addrs.get(0)));
        // 500012: rows 11 (from 2012-08-01, CAI) and 12 (from 2012-09-15, MAN) -> earlier DT_FROM wins.
        assertEquals("500012 id=11 2012-08-01..2019-04-30 CAI", row(addrs.get(1)));
    }
}
