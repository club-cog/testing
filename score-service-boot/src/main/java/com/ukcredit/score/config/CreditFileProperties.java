package com.ukcredit.score.config;

import org.springframework.boot.context.properties.ConfigurationProperties;

/** credit-file-service connection. Legacy -Dcreditfile.url=... still binds to {@code url}. */
@ConfigurationProperties("creditfile")
public record CreditFileProperties(String url, int timeoutMs) {
}
