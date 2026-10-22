package com.ukcredit.characterization;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;

import java.io.ByteArrayOutputStream;
import java.io.IOException;
import java.io.InputStream;
import java.io.OutputStream;
import java.net.HttpURLConnection;
import java.net.URL;
import java.net.URLEncoder;
import java.nio.charset.StandardCharsets;

/** Minimal HTTP/JSON client. Base URLs come from -Dscore.url, -Dcreditfile.url and -Ddispute.url. */
final class Http {

    static final ObjectMapper JSON = new ObjectMapper();

    static final class Response {
        final int status;
        final String body;

        Response(int status, String body) {
            this.status = status;
            this.body = body;
        }

        JsonNode json() {
            try {
                return JSON.readTree(body);
            } catch (IOException e) {
                throw new AssertionError("not JSON (HTTP " + status + "): " + body, e);
            }
        }
    }

    private Http() {
    }

    static String scoreUrl() {
        return base("score.url", "http://localhost:8082");
    }

    static String creditFileUrl() {
        return base("creditfile.url", "http://localhost:8081");
    }

    static String disputeUrl() {
        return base("dispute.url", "http://localhost:8083");
    }

    static String target() {
        return System.getProperty("suite.target", "legacy");
    }

    private static String base(String prop, String def) {
        String v = System.getProperty(prop);
        v = v == null || v.trim().isEmpty() ? def : v.trim();
        return v.endsWith("/") ? v.substring(0, v.length() - 1) : v;
    }

    static String enc(String s) {
        try {
            return URLEncoder.encode(s, "UTF-8");
        } catch (IOException e) {
            throw new IllegalStateException(e);
        }
    }

    static Response get(String url) {
        return call("GET", url, null);
    }

    static Response post(String url, Object body) {
        return call("POST", url, body);
    }

    static JsonNode getJson(String url) {
        Response r = get(url);
        if (r.status != 200) {
            throw new AssertionError("GET " + url + " -> HTTP " + r.status + ": " + r.body);
        }
        return r.json();
    }

    private static Response call(String method, String url, Object body) {
        try {
            HttpURLConnection c = (HttpURLConnection) new URL(url).openConnection();
            c.setRequestMethod(method);
            c.setConnectTimeout(5000);
            c.setReadTimeout(30000);
            c.setRequestProperty("Accept", "application/json");
            if (body != null) {
                c.setDoOutput(true);
                c.setRequestProperty("Content-Type", "application/json;charset=UTF-8");
                OutputStream out = c.getOutputStream();
                out.write(JSON.writeValueAsBytes(body));
                out.close();
            }
            int status = c.getResponseCode();
            InputStream in = status >= 400 ? c.getErrorStream() : c.getInputStream();
            return new Response(status, in == null ? "" : read(in));
        } catch (IOException e) {
            throw new AssertionError(method + " " + url + " failed: " + e, e);
        }
    }

    private static String read(InputStream in) throws IOException {
        ByteArrayOutputStream buf = new ByteArrayOutputStream();
        byte[] b = new byte[8192];
        int n;
        while ((n = in.read(b)) > 0) {
            buf.write(b, 0, n);
        }
        in.close();
        return new String(buf.toByteArray(), StandardCharsets.UTF_8);
    }
}
