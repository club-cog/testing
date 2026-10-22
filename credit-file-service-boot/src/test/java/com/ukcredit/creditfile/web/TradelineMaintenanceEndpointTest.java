package com.ukcredit.creditfile.web;

import com.ukcredit.creditfile.domain.Tradeline;
import com.ukcredit.creditfile.service.TradelineMaintenanceService;
import jakarta.servlet.ServletException;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.test.context.bean.override.mockito.MockitoBean;
import org.springframework.test.web.servlet.MockMvc;

import java.nio.charset.StandardCharsets;

import static org.junit.jupiter.api.Assertions.assertEquals;
import static org.junit.jupiter.api.Assertions.assertThrows;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.header;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

/** Byte-level wire contract of /ws/TradelineMaintenance, as emitted by the legacy service. */
@WebMvcTest(TradelineMaintenanceEndpoint.class)
class TradelineMaintenanceEndpointTest {

    private static final String ENV_OPEN = "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\""
            + " xmlns:tl=\"urn:ukcredit:tradeline:v1\"><soapenv:Body>";
    private static final String ENV_CLOSE = "</soapenv:Body></soapenv:Envelope>";

    @Autowired
    MockMvc mvc;

    @MockitoBean
    TradelineMaintenanceService service;

    private String call(String body) throws Exception {
        return mvc.perform(post("/ws/TradelineMaintenance").contentType("text/xml;charset=UTF-8")
                        .content(ENV_OPEN + body + ENV_CLOSE))
                .andExpect(status().isOk())
                .andExpect(header().string("Content-Type", "text/xml;charset=UTF-8"))
                .andReturn().getResponse().getContentAsString(StandardCharsets.UTF_8);
    }

    @Test
    void getTradeline() throws Exception {
        Tradeline t = new Tradeline();
        t.trdlnId = 7000002;
        t.cnsmrId = 100001;
        t.acctStsCd = "0";
        t.currBalPnc = 123456;
        t.dsptFlg = "N";
        when(service.get(7000002L)).thenReturn(t);
        assertEquals(ENV_OPEN + "<tl:GetTradelineResponse><tl:tradelineId>7000002</tl:tradelineId>"
                        + "<tl:consumerId>100001</tl:consumerId><tl:statusCd>0</tl:statusCd>"
                        + "<tl:balancePence>123456</tl:balancePence><tl:disputeFlag>N</tl:disputeFlag>"
                        + "</tl:GetTradelineResponse>" + ENV_CLOSE,
                call("<tl:GetTradelineRequest><tl:tradelineId>7000002</tl:tradelineId></tl:GetTradelineRequest>"));
    }

    @Test
    void unknownTradelineIsSoapFault() throws Exception {
        assertEquals(ENV_OPEN + "<soapenv:Fault><faultcode>soapenv:Client</faultcode>"
                        + "<faultstring>Tradeline 1 not found</faultstring></soapenv:Fault>" + ENV_CLOSE,
                call("<tl:GetTradelineRequest><tl:tradelineId>1</tl:tradelineId></tl:GetTradelineRequest>"));
    }

    @Test
    void emptyBodyIsSoapFault() throws Exception {
        assertEquals(ENV_OPEN + "<soapenv:Fault><faultcode>soapenv:Client</faultcode>"
                + "<faultstring>No operation in SOAP body</faultstring></soapenv:Fault>" + ENV_CLOSE, call(""));
    }

    @Test
    void unknownOperationIsSoapFault() throws Exception {
        assertEquals(ENV_OPEN + "<soapenv:Fault><faultcode>soapenv:Client</faultcode>"
                        + "<faultstring>Unknown operation PurgeRequest</faultstring></soapenv:Fault>" + ENV_CLOSE,
                call("<tl:PurgeRequest><tl:tradelineId>1</tl:tradelineId></tl:PurgeRequest>"));
    }

    @Test
    void amendAndDisputeResults() throws Exception {
        when(service.amend(7000004L, "1", 12345L, false, "OPS0002")).thenReturn(true);
        assertEquals(ENV_OPEN + "<tl:AmendTradelineResponse><tl:result>OK</tl:result></tl:AmendTradelineResponse>"
                + ENV_CLOSE, call("<tl:AmendTradelineRequest><tl:tradelineId>7000004</tl:tradelineId>"
                + "<tl:statusCd>1</tl:statusCd><tl:balancePence>12345</tl:balancePence>"
                + "<tl:operatorId>OPS0002</tl:operatorId></tl:AmendTradelineRequest>"));
        assertEquals(ENV_OPEN + "<tl:SetDisputeFlagResponse><tl:result>NOT_FOUND</tl:result></tl:SetDisputeFlagResponse>"
                + ENV_CLOSE, call("<SetDisputeFlagRequest xmlns=\"urn:ukcredit:tradeline:v1\"><tradelineId>9</tradelineId>"
                + "<flag>Y</flag></SetDisputeFlagRequest>"));
        verify(service).setDisputeFlag(9L, "Y");
    }

    @Test
    void bodyWithoutCharsetIsReadAsIso88591LikeSpring4() throws Exception {
        String body = ENV_OPEN + "<tl:AmendTradelineRequest><tl:tradelineId>7000011</tl:tradelineId>"
                + "<tl:operatorId>OPÉ02</tl:operatorId></tl:AmendTradelineRequest>" + ENV_CLOSE;
        mvc.perform(post("/ws/TradelineMaintenance").contentType("text/xml")
                .content(body.getBytes(StandardCharsets.ISO_8859_1))).andExpect(status().isOk());
        verify(service).amend(7000011L, null, null, false, "OPÉ02");
    }

    /** SOAP 1.1 forbids a DTD; rejecting it closes XXE. Surfaces as HTTP 500 like other parse errors. */
    @Test
    void doctypeIsRejected() throws Exception {
        assertThrows(ServletException.class, () -> mvc.perform(post("/ws/TradelineMaintenance")
                .contentType("text/xml;charset=UTF-8").content("<!DOCTYPE x [<!ENTITY id \"7000002\">]>" + ENV_OPEN
                        + "<tl:GetTradelineRequest><tl:tradelineId>&id;</tl:tradelineId></tl:GetTradelineRequest>"
                        + ENV_CLOSE)));
    }
}
