package com.ukcredit.dispute.client;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestClientException;
import org.springframework.web.client.RestTemplate;

/** score-service POST /score/{id}/recalculate. Failures are logged, the nightly batch rescores anyway. */
public class ScoreClient {

    private static final Logger LOG = LoggerFactory.getLogger(ScoreClient.class);

    private final String baseUrl;
    private final RestTemplate restTemplate;

    public ScoreClient(String baseUrl, int timeoutMs) {
        this.baseUrl = baseUrl;
        SimpleClientHttpRequestFactory f = new SimpleClientHttpRequestFactory();
        f.setConnectTimeout(timeoutMs);
        f.setReadTimeout(timeoutMs);
        this.restTemplate = new RestTemplate(f);
    }

    public void recalculate(long cnsmrId, String trigger) {
        try {
            restTemplate.postForObject(baseUrl + "/score/{id}/recalculate?trigger={t}", null, String.class, cnsmrId, trigger);
        } catch (RestClientException e) {
            LOG.warn("score recalculation failed for consumer {} ({}): {}", cnsmrId, trigger, e.getMessage());
        }
    }
}
