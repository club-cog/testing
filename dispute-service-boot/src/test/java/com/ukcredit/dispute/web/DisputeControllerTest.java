package com.ukcredit.dispute.web;

import com.ukcredit.dispute.service.DisputeService;
import org.junit.jupiter.api.Test;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.http.MediaType;
import org.springframework.test.web.servlet.MockMvc;

import java.util.LinkedHashMap;
import java.util.Map;

import static org.mockito.ArgumentMatchers.any;
import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.eq;
import static org.mockito.Mockito.never;
import static org.mockito.Mockito.verify;
import static org.mockito.Mockito.when;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.jsonPath;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

@WebMvcTest(DisputeController.class)
class DisputeControllerTest {

    @Autowired
    private MockMvc mvc;

    @MockBean
    private DisputeService disputeService;

    @Test
    void openRequiresConsumerReasonAndItem() throws Exception {
        mvc.perform(post("/disputes").contentType(MediaType.APPLICATION_JSON).content("{\"cnsmrId\":100012}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("cnsmrId, rsnCd and one of trdlnId/pubRecId are required"));
        verify(disputeService, never()).open(anyLong(), any(), any(), any(), any(), any());
    }

    @Test
    void openDefaultsChannelToWebAndAcceptsStringIds() throws Exception {
        when(disputeService.open(eq(100013L), eq(7000017L), eq(null), eq("FRAUD"), eq("WEB"), any())).thenReturn(40017L);
        Map<String, Object> c = new LinkedHashMap<>();
        c.put("dsptId", 40017L);
        when(disputeService.get(40017L)).thenReturn(c);
        mvc.perform(post("/disputes").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"cnsmrId\":\"100013\",\"trdlnId\":\"7000017\",\"rsnCd\":\"FRAUD\",\"rcvdTs\":\"2024-12-24T16:00:00\"}"))
                .andExpect(status().isCreated())
                .andExpect(jsonPath("$.dsptId").value(40017));
    }

    @Test
    void resolveValidatesOutcomeThenOperatorThenCase() throws Exception {
        mvc.perform(post("/disputes/40014/resolve").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"outcome\":\"UPHELD\",\"operatorId\":\"OPS0002\"}"))
                .andExpect(status().isBadRequest());
        mvc.perform(post("/disputes/40014/resolve").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"outcome\":\"AMEND\",\"operatorId\":\"OPS9999\"}"))
                .andExpect(status().isBadRequest())
                .andExpect(jsonPath("$.error").value("unknown operator OPS9999"));
        when(disputeService.isKnownOperator("OPS0002")).thenReturn(true);
        mvc.perform(post("/disputes/99999/resolve").contentType(MediaType.APPLICATION_JSON)
                        .content("{\"outcome\":\"NOCHANGE\",\"operatorId\":\"OPS0002\"}"))
                .andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error").value("dispute 99999 not found or already closed"));
    }

    @Test
    void getSupportsTrailingSlashLikeLegacy() throws Exception {
        when(disputeService.get(40001L)).thenReturn(new LinkedHashMap<>(Map.of("dsptId", 40001L)));
        when(disputeService.get(99999L)).thenReturn(null);
        mvc.perform(get("/disputes/40001/")).andExpect(status().isOk());
        mvc.perform(get("/disputes/99999")).andExpect(status().isNotFound())
                .andExpect(jsonPath("$.error").value("dispute 99999 not found"));
    }

    @Test
    void slaDefaultsRegionAndRequiresReceived() throws Exception {
        when(disputeService.slaDueDate(any(), eq("EW"))).thenReturn(java.sql.Date.valueOf("2025-01-22"));
        mvc.perform(get("/disputes/sla").param("received", "2024-12-20T10:15:00"))
                .andExpect(status().isOk())
                .andExpect(jsonPath("$.region").value("EW"))
                .andExpect(jsonPath("$.slaDueDt").value("2025-01-22"));
        mvc.perform(get("/disputes/sla")).andExpect(status().isBadRequest());
    }
}
