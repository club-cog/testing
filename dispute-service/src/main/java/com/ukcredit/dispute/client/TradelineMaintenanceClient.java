package com.ukcredit.dispute.client;

import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.http.client.SimpleClientHttpRequestFactory;
import org.springframework.web.client.RestTemplate;

/**
 * Calls credit-file-service TradelineMaintenance (SOAP 1.1, urn:ukcredit:tradeline:v1).
 * Envelopes are built by hand - same as the old CXF client generated, minus the WS-Addressing headers.
 */
public class TradelineMaintenanceClient {

    private static final Logger LOG = LoggerFactory.getLogger(TradelineMaintenanceClient.class);
    private static final String NS = "urn:ukcredit:tradeline:v1";

    private String baseUrl;
    private int timeoutMs = 5000;
    private RestTemplate restTemplate;

    public boolean setDisputeFlag(long trdlnId, String flag) {
        String resp = call("SetDisputeFlag", "<tl:SetDisputeFlagRequest><tl:tradelineId>" + trdlnId + "</tl:tradelineId>"
                + "<tl:flag>" + flag + "</tl:flag></tl:SetDisputeFlagRequest>");
        return resp.contains(">OK<");
    }

    public boolean amendTradeline(long trdlnId, String statusCd, Long balancePence, boolean delete, String operatorId) {
        StringBuilder sb = new StringBuilder("<tl:AmendTradelineRequest><tl:tradelineId>").append(trdlnId)
                .append("</tl:tradelineId>");
        if (statusCd != null) {
            sb.append("<tl:statusCd>").append(statusCd).append("</tl:statusCd>");
        }
        if (balancePence != null) {
            sb.append("<tl:balancePence>").append(balancePence).append("</tl:balancePence>");
        }
        sb.append("<tl:delete>").append(delete).append("</tl:delete>");
        sb.append("<tl:operatorId>").append(operatorId).append("</tl:operatorId></tl:AmendTradelineRequest>");
        return call("AmendTradeline", sb.toString()).contains(">OK<");
    }

    private String call(String action, String body) {
        String env = "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:tl=\"" + NS
                + "\"><soapenv:Header/><soapenv:Body>" + body + "</soapenv:Body></soapenv:Envelope>";
        HttpHeaders h = new HttpHeaders();
        h.setContentType(MediaType.valueOf("text/xml;charset=UTF-8"));
        h.set("SOAPAction", NS + ":" + action);
        String resp = rest().postForObject(url() + "/ws/TradelineMaintenance", new HttpEntity<String>(env, h), String.class);
        LOG.debug("{} -> {}", action, resp);
        return resp == null ? "" : resp;
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
