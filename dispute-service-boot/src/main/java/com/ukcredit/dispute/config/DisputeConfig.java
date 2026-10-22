package com.ukcredit.dispute.config;

import com.ukcredit.dispute.client.ScoreClient;
import com.ukcredit.dispute.client.TradelineMaintenanceClient;
import com.ukcredit.dispute.dao.DisputeDao;
import com.ukcredit.dispute.service.DisputeService;
import com.ukcredit.dispute.sla.RegionResolver;
import com.ukcredit.dispute.sla.SlaCalculator;
import com.ukcredit.dispute.sla.WorkingDayCalendar;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;

/** Replaces dispute-servlet.xml. DataSource / JdbcTemplate come from Boot auto-configuration. */
@Configuration(proxyBeanMethods = false)
public class DisputeConfig {

    @Bean
    DisputeDao disputeDao(JdbcTemplate jdbcTemplate) {
        return new DisputeDao(jdbcTemplate);
    }

    @Bean
    WorkingDayCalendar workingDayCalendar(JdbcTemplate jdbcTemplate) {
        return new WorkingDayCalendar(jdbcTemplate);
    }

    @Bean
    SlaCalculator slaCalculator(JdbcTemplate jdbcTemplate, WorkingDayCalendar workingDayCalendar) {
        return new SlaCalculator(jdbcTemplate, workingDayCalendar);
    }

    @Bean
    RegionResolver regionResolver(JdbcTemplate jdbcTemplate) {
        return new RegionResolver(jdbcTemplate);
    }

    @Bean
    TradelineMaintenanceClient tradelineMaintenanceClient(@Value("${creditfile.url}") String baseUrl,
                                                          @Value("${creditfile.timeout-ms:5000}") int timeoutMs) {
        return new TradelineMaintenanceClient(baseUrl, timeoutMs);
    }

    @Bean
    ScoreClient scoreClient(@Value("${score.url}") String baseUrl, @Value("${score.timeout-ms:10000}") int timeoutMs) {
        return new ScoreClient(baseUrl, timeoutMs);
    }

    @Bean
    DisputeService disputeService(DisputeDao disputeDao, SlaCalculator slaCalculator, RegionResolver regionResolver,
                                  TradelineMaintenanceClient tradelineClient, ScoreClient scoreClient) {
        return new DisputeService(disputeDao, slaCalculator, regionResolver, tradelineClient, scoreClient);
    }
}
