package com.ukcredit.characterization;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.Test;
import org.junit.experimental.categories.Category;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.List;

import static org.junit.Assert.assertEquals;

/**
 * Quirk (a): status 'X' means DEFAULT when the status date is before 2014-04-01 and ARRANGEMENT on/after it.
 * The cutoff is hard-coded; SYS_PARAM.TRDLN_X_CUTOFF_DT (seeded as 2015-01-01) is ignored. If it were honoured,
 * the 2014-04-01 and 2014-06-01 tradelines below would map to DEFAULT.
 */
public class StatusXCutoffTest {

    static String mapped(long cnsmrId, long trdlnId) {
        JsonNode file = Http.getJson(Http.creditFileUrl() + "/creditfile/" + cnsmrId);
        for (JsonNode t : file.get("tradelines")) {
            if (t.get("trdlnId").asLong() == trdlnId) {
                return t.get("statusCd").asText() + "@" + t.get("statusDate").asText() + "=" + t.get("mappedStatus").asText();
            }
        }
        throw new AssertionError("tradeline " + trdlnId + " not on credit file " + cnsmrId);
    }

    static List<String> reasons(long cnsmrId) {
        JsonNode s = Http.getJson(Http.scoreUrl() + "/score/" + cnsmrId + "?asOf=2024-12-31");
        List<String> l = new ArrayList<String>();
        for (JsonNode r : s.get("reasons")) {
            l.add(r.asText());
        }
        return l;
    }

    @Test
    public void statusXMapsByHardCodedCutoff20140401InCreditFile() {
        assertEquals("X@2013-11-15=DEFAULT", mapped(100001, 7000002));
        assertEquals("X@2016-06-01=ARRANGEMENT", mapped(100002, 7000003));
        assertEquals("X@2014-03-31=DEFAULT", mapped(100003, 7000005));
        assertEquals("X@2014-04-01=ARRANGEMENT", mapped(100003, 7000006));
        assertEquals("X@2014-06-01=ARRANGEMENT", mapped(100004, 7000007));
    }

    @Test
    @Category(ScoreApi.class)
    public void statusXScoredByHardCodedCutoffIgnoringStaleSysParam() {
        assertEquals(Arrays.asList("DEFAULT", "UTIL_50"), reasons(100001));
        assertEquals(Arrays.asList("ARRANGEMENT", "UTIL_75"), reasons(100002));
        assertEquals("boundary day 2014-04-01 is ARRANGEMENT, 2014-03-31 is DEFAULT",
                Arrays.asList("ARRANGEMENT", "DEFAULT"), reasons(100003));
        assertEquals("2014-06-01 is before the stale SYS_PARAM 2015-01-01 but still ARRANGEMENT",
                Arrays.asList("ARRANGEMENT"), reasons(100004));
    }
}
