package com.ukcredit.characterization;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.Test;
import org.junit.experimental.categories.Category;

import java.util.Iterator;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertTrue;
import static org.junit.Assert.fail;

/**
 * Golden master for GET /score/{id}?asOf=2024-12-31 over every seeded consumer (100001 upwards until the
 * first 404). Regenerate with -Dgolden.record=true straight after scripts/db-reset.sh.
 */
@Category(ScoreApi.class)
public class ScoreGoldenMasterTest {

    static final String FILE = "score-uks3.json";
    static final String AS_OF = "2024-12-31";
    static final long FIRST_ID = 100001L;

    static String url(long id) {
        return Http.scoreUrl() + "/score/" + id + "?asOf=" + AS_OF;
    }

    @Test
    public void scoreUks3MatchesGoldenForEverySeededConsumer() throws Exception {
        if (Golden.recording()) {
            record();
            return;
        }
        ObjectNode golden = Golden.read(FILE);
        JsonNode responses = golden.get("responses");
        Map<String, List<String>> diffs = new LinkedHashMap<String, List<String>>();
        for (Iterator<Map.Entry<String, JsonNode>> it = responses.fields(); it.hasNext(); ) {
            Map.Entry<String, JsonNode> e = it.next();
            Http.Response r = Http.get(url(Long.parseLong(e.getKey())));
            JsonNode actual = r.status == 200 ? r.json() : JsonNodeFactory.instance.textNode("HTTP " + r.status);
            List<String> d = Golden.diff(e.getValue(), actual);
            if (!d.isEmpty()) {
                diffs.put(e.getKey(), d);
            }
        }
        Golden.writeDiffs("score-golden-diff.json", responses.size(), diffs);
        if (!diffs.isEmpty()) {
            fail(Golden.summarise(diffs, responses.size()));
        }
    }

    @Test
    public void noScoreBeyondLastSeededConsumer() throws Exception {
        if (Golden.recording()) {
            return;
        }
        int count = Golden.read(FILE).get("responses").size();
        assertTrue(count > 16);
        assertEquals("consumer after the last seeded one must be 404",
                404, Http.get(url(FIRST_ID + count)).status);
    }

    private void record() throws Exception {
        ObjectNode responses = JsonNodeFactory.instance.objectNode();
        for (long id = FIRST_ID; ; id++) {
            Http.Response r = Http.get(url(id));
            if (r.status == 404) {
                break;
            }
            assertEquals("GET " + url(id), 200, r.status);
            responses.set(Long.toString(id), r.json());
        }
        ObjectNode doc = JsonNodeFactory.instance.objectNode();
        doc.set("meta", Golden.meta("GET /score/{id}?asOf=" + AS_OF, responses.size()));
        doc.set("responses", responses);
        Golden.write(FILE, doc);
    }
}
