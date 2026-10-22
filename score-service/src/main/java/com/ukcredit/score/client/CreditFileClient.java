package com.ukcredit.score.client;

import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import java.util.Map;

/** REST client for credit-file-service GET /creditfile/{id}. */
public class CreditFileClient {

    private String baseUrl;
    private int timeoutMs = 5000;
    private RestTemplate restTemplate;

    @SuppressWarnings("unchecked")
    public Map<String, Object> getCreditFile(long cnsmrId) {
        try {
            return rest().getForObject(url() + "/creditfile/{id}", Map.class, cnsmrId);
        } catch (HttpClientErrorException e) {
            if (e.getRawStatusCode() == 404) {
                return null;
            }
            throw e;
        }
    }

    private String url() {
        String sys = System.getProperty("creditfile.url");
        return sys != null ? sys : baseUrl;
    }

    private synchronized RestTemplate rest() {
        if (restTemplate == null) {
            SimpleClientHttpRequestFactory f = new SimpleClientHttpRequestFactory();
            f.setConnectTimeout(timeoutMs);
            f.setReadTimeout(timeoutMs);
            restTemplate = new RestTemplate(f);
        }
        return restTemplate;
    }

    public void setBaseUrl(String baseUrl) {
        this.baseUrl = baseUrl;
    }

    public void setTimeoutMs(int timeoutMs) {
        this.timeoutMs = timeoutMs;
    }
}
