package com.ukcredit.characterization;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.Test;
import org.junit.experimental.categories.Category;

import java.time.LocalDate;
import java.util.LinkedHashMap;
import java.util.Map;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertFalse;
import static org.junit.Assert.assertTrue;

/**
 * Dispute -> score flow: opening a dispute flags the tradeline and recalculates the score with trigger
 * DISPUTE_OPEN; resolving it clears the flag and recalculates with DISPUTE_CLOSE. The recalculation is
 * as of the score service's current date (not 2024-12-31). Consumer 100013 has a single revolving tradeline,
 * so the open dispute suppresses the score entirely. Self-restoring: the credit file and the 2024-12-31
 * score are unchanged afterwards (NOCHANGE outcome); only dispute and score-history rows are added.
 */
@Category(ScoreApi.class)
public class DisputeScoreFlowTest {

    static final long CNSMR = 100013L;
    static final long TRDLN = 7000017L;

    static JsonNode history() {
        return Http.getJson(Http.scoreUrl() + "/score/" + CNSMR + "/history");
    }

    static JsonNode last(JsonNode history) {
        return history.get(history.size() - 1);
    }

    static boolean disputed() {
        for (JsonNode t : Http.getJson(Http.creditFileUrl() + "/creditfile/" + CNSMR).get("tradelines")) {
            if (t.get("trdlnId").asLong() == TRDLN) {
                return t.get("disputed").asBoolean();
            }
        }
        throw new AssertionError("tradeline " + TRDLN + " missing");
    }

    @Test
    public void disputeOpenAndCloseWriteScoreHistoryTriggers() {
        JsonNode before = Http.getJson(Http.scoreUrl() + "/score/" + CNSMR + "?asOf=2024-12-31");
        int n = history().size();
        String today = LocalDate.now().toString();

        Map<String, Object> open = new LinkedHashMap<String, Object>();
        open.put("cnsmrId", CNSMR);
        open.put("trdlnId", TRDLN);
        open.put("rsnCd", "WRONGBAL");
        open.put("chnlCd", "PST");
        open.put("rcvdTs", "2025-03-24T09:00:00");
        Http.Response opened = Http.post(Http.disputeUrl() + "/disputes", open);
        assertEquals(opened.body, 201, opened.status);
        JsonNode d = opened.json();
        assertEquals("OPEN", d.get("stsCd").asText());
        assertEquals("2025-04-23", d.get("slaDueDt").asText());
        assertEquals("ACK01", d.get("correspondence").get(0).get("tmplCd").asText());
        assertTrue(disputed());

        JsonNode h = history();
        assertEquals("one score-history row per dispute event", n + 1, h.size());
        JsonNode onOpen = last(h);
        assertEquals("DISPUTE_OPEN", onOpen.get("trigger").asText());
        assertEquals("NOSCORE", onOpen.get("band").asText());
        assertTrue(onOpen.get("score").isNull());
        assertEquals("DSPT_SUPPRESSED,THIN_FILE", onOpen.get("reasons").asText());
        assertEquals("UKS3", onOpen.get("modelVer").asText());
        assertEquals(today, onOpen.get("asOf").asText());

        Map<String, Object> resolve = new LinkedHashMap<String, Object>();
        resolve.put("outcome", "NOCHANGE");
        resolve.put("operatorId", "OPS0002");
        Http.Response resolved = Http.post(Http.disputeUrl() + "/disputes/" + d.get("dsptId").asLong() + "/resolve", resolve);
        assertEquals(resolved.body, 200, resolved.status);
        JsonNode r = resolved.json();
        assertEquals("CLOSED", r.get("stsCd").asText());
        assertEquals("NOCHANGE", r.get("outcomeCd").asText());
        assertEquals("RES02", r.get("correspondence").get(1).get("tmplCd").asText());
        assertFalse(disputed());

        h = history();
        assertEquals(n + 2, h.size());
        JsonNode onClose = last(h);
        assertEquals("DISPUTE_CLOSE", onClose.get("trigger").asText());
        assertFalse(onClose.get("score").isNull());
        assertFalse(onClose.get("reasons").asText().contains("DSPT_SUPPRESSED"));
        assertEquals(today, onClose.get("asOf").asText());

        assertEquals(before, Http.getJson(Http.scoreUrl() + "/score/" + CNSMR + "?asOf=2024-12-31"));
    }
}
