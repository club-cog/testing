package com.ukcredit.creditfile.config;

import com.ukcredit.creditfile.dao.AddressHistoryDao;
import com.ukcredit.creditfile.dao.ConsumerDao;
import com.ukcredit.creditfile.dao.TradelineDao;
import com.ukcredit.creditfile.rules.AddressHistoryMerger;
import com.ukcredit.creditfile.rules.NameMatcher;
import com.ukcredit.creditfile.rules.TradelineStatusMapper;
import com.ukcredit.creditfile.service.ConsumerMatchService;
import com.ukcredit.creditfile.service.CreditFileAssembler;
import com.ukcredit.creditfile.service.TradelineMaintenanceService;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.jdbc.core.JdbcTemplate;

/** Replaces creditfile-rules.xml and the bean definitions in creditfile-servlet.xml. */
@Configuration(proxyBeanMethods = false)
public class CreditFileConfig {

    @Bean
    TradelineStatusMapper tradelineStatusMapper() {
        return new TradelineStatusMapper();
    }

    @Bean
    NameMatcher nameMatcher() {
        return new NameMatcher();
    }

    @Bean
    AddressHistoryMerger addressHistoryMerger() {
        return new AddressHistoryMerger();
    }

    @Bean
    ConsumerDao consumerDao(JdbcTemplate jdbcTemplate) {
        return new ConsumerDao(jdbcTemplate);
    }

    @Bean
    TradelineDao tradelineDao(JdbcTemplate jdbcTemplate) {
        return new TradelineDao(jdbcTemplate);
    }

    @Bean
    AddressHistoryDao addressHistoryDao(JdbcTemplate jdbcTemplate) {
        return new AddressHistoryDao(jdbcTemplate);
    }

    @Bean
    CreditFileAssembler creditFileAssembler(JdbcTemplate jdbcTemplate, ConsumerDao consumerDao, TradelineDao tradelineDao,
                                            AddressHistoryDao addressHistoryDao, TradelineStatusMapper statusMapper,
                                            AddressHistoryMerger addressMerger) {
        return new CreditFileAssembler(jdbcTemplate, consumerDao, tradelineDao, addressHistoryDao, statusMapper, addressMerger);
    }

    @Bean
    ConsumerMatchService consumerMatchService(ConsumerDao consumerDao, NameMatcher nameMatcher) {
        return new ConsumerMatchService(consumerDao, nameMatcher);
    }

    @Bean
    TradelineMaintenanceService tradelineMaintenanceService(JdbcTemplate jdbcTemplate, TradelineDao tradelineDao) {
        return new TradelineMaintenanceService(jdbcTemplate, tradelineDao);
    }
}
