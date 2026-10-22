package com.ukcredit.dispute.client;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

/** score-service POST /score/{id}/recalculate. Failures are logged, the nightly batch rescores anyway. */
public class ScoreClient {

    private static final Logger LOG = LoggerFactory.getLogger(ScoreClient.class);

    private String baseUrl;
    private int timeoutMs = 10000;
    private RestTemplate restTemplate;

    public void recalculate(long cnsmrId, String trigger) {
        try {
            rest().postForObject(url() + "/score/{id}/recalculate?trigger={t}", null, String.class, cnsmrId, trigger);
        } catch (RestClientException e) {
            LOG.warn("score recalculation failed for consumer {} ({}): {}", cnsmrId, trigger, e.getMessage());
        }
    }

    private String url() {
        String sys = System.getProperty("score.url");
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
