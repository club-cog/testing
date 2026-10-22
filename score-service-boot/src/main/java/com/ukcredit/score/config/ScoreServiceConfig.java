package com.ukcredit.score.config;

import com.ukcredit.score.calc.LegacyStatusTranslator;
import com.ukcredit.score.calc.ScoreCalculator;
import com.ukcredit.score.calc.ScoreService;
import com.ukcredit.score.client.CreditFileClient;
import com.ukcredit.score.dao.ScoreHistoryDao;
import com.ukcredit.score.dao.ScoreModelDao;
import org.springframework.boot.web.client.RestTemplateBuilder;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;

import java.time.Duration;

/** Replaces META-INF/spring/score-servlet.xml (one @Bean per legacy bean). */
@Configuration(proxyBeanMethods = false)
public class ScoreServiceConfig {

    @Bean
    public CreditFileClient creditFileClient(RestTemplateBuilder builder, CreditFileProperties props) {
        Duration timeout = Duration.ofMillis(props.timeoutMs());
        return new CreditFileClient(builder.rootUri(props.url()).setConnectTimeout(timeout).setReadTimeout(timeout)
                .build());
    }

    @Bean
    public ScoreModelDao scoreModelDao(JdbcTemplate jdbcTemplate) {
        return new ScoreModelDao(jdbcTemplate);
    }

    @Bean
    public ScoreHistoryDao scoreHistoryDao(JdbcTemplate jdbcTemplate) {
        return new ScoreHistoryDao(jdbcTemplate);
    }

    @Bean
    public LegacyStatusTranslator legacyStatusTranslator() {
        return new LegacyStatusTranslator();
    }

    @Bean
    public ScoreCalculator scoreCalculator(LegacyStatusTranslator legacyStatusTranslator) {
        return new ScoreCalculator(legacyStatusTranslator);
    }

    @Bean
    public ScoreService scoreService(CreditFileClient creditFileClient, ScoreModelDao scoreModelDao,
                                     ScoreHistoryDao scoreHistoryDao, ScoreCalculator scoreCalculator) {
        return new ScoreService(creditFileClient, scoreModelDao, scoreHistoryDao, scoreCalculator);
    }
}
