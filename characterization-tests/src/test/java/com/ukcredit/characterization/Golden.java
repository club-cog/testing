package com.ukcredit.characterization;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.SerializationFeature;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.JsonNodeFactory;
import com.fasterxml.jackson.databind.node.ObjectNode;

import java.io.File;
import java.io.IOException;
import java.util.ArrayList;
import java.util.Iterator;
import java.util.List;
import java.util.Map;
import java.util.TreeSet;

/** Golden-master files (src/test/resources/golden) and field-level JSON diffs. */
final class Golden {

    static final long SEED = 20241231L;

    private Golden() {
    }

    static boolean recording() {
        return Boolean.getBoolean("golden.record");
    }

    static File file(String name) {
        return new File(System.getProperty("golden.dir", "src/test/resources/golden"), name);
    }

    static ObjectNode read(String name) throws IOException {
        File f = file(name);
        if (!f.exists()) {
            throw new AssertionError(f + " missing - run with -Dgolden.record=true against the legacy estate");
        }
        return (ObjectNode) Http.JSON.readTree(f);
    }

    static void write(String name, ObjectNode doc) throws IOException {
        File f = file(name);
        f.getParentFile().mkdirs();
        Http.JSON.writer().with(SerializationFeature.INDENT_OUTPUT).writeValue(f, doc);
    }

    static ObjectNode meta(String endpoint, int count) {
        ObjectNode m = JsonNodeFactory.instance.objectNode();
        m.put("seed", SEED);
        m.put("reset", "scripts/db-reset.sh");
        m.put("endpoint", endpoint);
        m.put("count", count);
        return m;
    }

    /** Field-level differences between expected and actual, as "path: expected -> actual" entries. */
    static List<String> diff(JsonNode expected, JsonNode actual) {
        List<String> out = new ArrayList<String>();
        diff("$", expected, actual, out);
        return out;
    }

    private static void diff(String path, JsonNode e, JsonNode a, List<String> out) {
        if (e == null || e.isMissingNode()) {
            out.add(path + ": <absent> -> " + a);
            return;
        }
        if (a == null || a.isMissingNode()) {
            out.add(path + ": " + e + " -> <absent>");
            return;
        }
        if (e.isObject() && a.isObject()) {
            TreeSet<String> names = new TreeSet<String>();
            names.addAll(fieldNames(e));
            names.addAll(fieldNames(a));
            for (String n : names) {
                diff(path + "." + n, e.get(n), a.get(n), out);
            }
        } else if (e.isArray() && a.isArray() && e.size() == a.size()) {
            for (int i = 0; i < e.size(); i++) {
                diff(path + "[" + i + "]", e.get(i), a.get(i), out);
            }
        } else if (!e.equals(a)) {
            out.add(path + ": " + e + " -> " + a);
        }
    }

    private static List<String> fieldNames(JsonNode n) {
        List<String> l = new ArrayList<String>();
        for (Iterator<String> it = n.fieldNames(); it.hasNext(); ) {
            l.add(it.next());
        }
        return l;
    }

    /** Writes target/characterization/{target}/{name} so the parity report can show per-record diffs. */
    static void writeDiffs(String name, int checked, Map<String, List<String>> diffs) throws IOException {
        ObjectNode doc = JsonNodeFactory.instance.objectNode();
        doc.put("target", Http.target());
        doc.put("checked", checked);
        doc.put("differed", diffs.size());
        ObjectNode recs = doc.putObject("diffs");
        for (Map.Entry<String, List<String>> e : diffs.entrySet()) {
            ArrayNode arr = recs.putArray(e.getKey());
            for (String s : e.getValue()) {
                arr.add(s);
            }
        }
        File f = new File(System.getProperty("results.dir", "target/characterization/" + Http.target()), name);
        f.getParentFile().mkdirs();
        Http.JSON.writer().with(SerializationFeature.INDENT_OUTPUT).writeValue(f, doc);
    }

    static String summarise(Map<String, List<String>> diffs, int checked) {
        StringBuilder sb = new StringBuilder(diffs.size() + " of " + checked + " records differ from golden");
        int shown = 0;
        for (Map.Entry<String, List<String>> e : diffs.entrySet()) {
            if (shown++ == 10) {
                sb.append("\n  ...");
                break;
            }
            sb.append("\n  ").append(e.getKey()).append(": ").append(e.getValue());
        }
        return sb.toString();
    }
}
