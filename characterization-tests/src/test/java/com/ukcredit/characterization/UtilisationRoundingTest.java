package com.ukcredit.characterization;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.Test;
import org.junit.experimental.categories.Category;

import static org.junit.Assert.assertEquals;

/**
 * Quirk (c): revolving balances are summed in pence, the SUM is rounded to whole pounds HALF_EVEN, and
 * utilisation is computed from the rounded pounds (truncated to a whole percent).
 */
@Category(ScoreApi.class)
public class UtilisationRoundingTest {

    static String util(long id) {
        JsonNode s = Http.getJson(Http.scoreUrl() + "/score/" + id + "?asOf=2024-12-31");
        return s.get("revolvingBalance").asText() + "/" + s.get("revolvingLimit").asText() + "="
                + s.get("utilisationPct").asText() + "%";
    }

    @Test
    public void utilisationUsesHalfEvenRoundingOfSummedPence() {
        assertEquals("750/1000=75%", util(100005));
        assertEquals("75% not 74%: per-tradeline rounding would lose a pound", "750/1000=75%", util(100006));
        assertEquals("49% not 50%: 500.50 rounds HALF_EVEN down to 500", "500/1002=49%", util(100007));
    }
}
