package com.ukcredit.score.client;

import org.springframework.web.client.HttpClientErrorException;
import org.springframework.web.client.RestTemplate;

import java.util.Map;

/** REST client for credit-file-service GET /creditfile/{id}. */
public class CreditFileClient {

    private final RestTemplate restTemplate;

    public CreditFileClient(RestTemplate restTemplate) {
        this.restTemplate = restTemplate;
    }

    @SuppressWarnings("unchecked")
    public Map<String, Object> getCreditFile(long cnsmrId) {
        try {
            return restTemplate.getForObject("/creditfile/{id}", Map.class, cnsmrId);
        } catch (HttpClientErrorException.NotFound e) {
            return null;
        }
    }
}
