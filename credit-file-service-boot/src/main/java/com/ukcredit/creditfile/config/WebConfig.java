package com.ukcredit.creditfile.config;

import org.springframework.boot.web.servlet.FilterRegistrationBean;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.core.Ordered;
import org.springframework.web.filter.UrlHandlerFilter;

@Configuration(proxyBeanMethods = false)
public class WebConfig {

    /** Spring 4 matched "/creditfile/1/" as "/creditfile/1"; Spring 6 no longer does by default. */
    @Bean
    FilterRegistrationBean<UrlHandlerFilter> trailingSlashFilter() {
        FilterRegistrationBean<UrlHandlerFilter> reg = new FilterRegistrationBean<>(
                UrlHandlerFilter.trailingSlashHandler("/creditfile/**", "/consumers/**", "/ws/**").wrapRequest().build());
        reg.setOrder(Ordered.HIGHEST_PRECEDENCE);
        return reg;
    }
}
