package com.ukcredit.characterization;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;
import org.junit.Test;

import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.fail;

/** Golden master for GET /creditfile/{id}, consumers 100001-100016 (the documented edge cases). */
public class CreditFileGoldenMasterTest {

    static final String FILE = "creditfile-edge-cases.json";

    @Test
    public void creditFileMatchesGoldenForEdgeCaseConsumers() throws Exception {
        ObjectNode responses = JsonNodeFactory.instance.objectNode();
        for (long id = 100001L; id <= 100016L; id++) {
            responses.set(Long.toString(id), Http.getJson(Http.creditFileUrl() + "/creditfile/" + id));
        }
        if (Golden.recording()) {
            ObjectNode doc = JsonNodeFactory.instance.objectNode();
            doc.set("meta", Golden.meta("GET /creditfile/{id}", responses.size()));
            doc.set("responses", responses);
            Golden.write(FILE, doc);
            return;
        }
        JsonNode golden = Golden.read(FILE).get("responses");
        assertEquals(16, golden.size());
        Map<String, List<String>> diffs = new LinkedHashMap<String, List<String>>();
        for (long id = 100001L; id <= 100016L; id++) {
            String k = Long.toString(id);
            List<String> d = Golden.diff(golden.get(k), responses.get(k));
            if (!d.isEmpty()) {
                diffs.put(k, d);
            }
        }
        Golden.writeDiffs("creditfile-golden-diff.json", 16, diffs);
        if (!diffs.isEmpty()) {
            fail(Golden.summarise(diffs, 16));
        }
    }
}
