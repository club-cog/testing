package com.ukcredit.score.web;

import static org.mockito.ArgumentMatchers.anyLong;
import static org.mockito.ArgumentMatchers.anyString;
import static org.mockito.BDDMockito.given;
import static org.springframework.test.web.servlet.request.MockMvcRequestBuilders.get;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.content;
import static org.springframework.test.web.servlet.result.MockMvcResultMatchers.status;

import com.fasterxml.jackson.databind.ObjectMapper;
import com.ukcredit.score.client.CreditFileClient;
import com.ukcredit.score.config.ScoreServiceConfig;
import com.ukcredit.score.dao.ScoreHistoryDao;
import com.ukcredit.score.dao.ScoreModelDao;
import org.junit.jupiter.api.BeforeEach;
import org.junit.jupiter.params.ParameterizedTest;
import org.junit.jupiter.params.provider.ValueSource;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.boot.test.autoconfigure.web.servlet.WebMvcTest;
import org.springframework.boot.test.mock.mockito.MockBean;
import org.springframework.context.annotation.Import;
import org.springframework.core.io.ClassPathResource;
import org.springframework.test.web.servlet.MockMvc;

import java.io.IOException;
import java.nio.charset.StandardCharsets;
import java.util.HashMap;
import java.util.List;
import java.util.Map;
import java.util.regex.Matcher;
import java.util.regex.Pattern;

/**
 * Replays the credit files recorded from legacy credit-file-service for the hand-built seed consumers
 * and checks the Boot JSON is byte-identical to the legacy score-service response (parity/get/*.json,
 * asOf=2024-12-31). Model weights come from the shared-db V6 migration.
 */
@WebMvcTest(ScoreController.class)
@Import(ScoreServiceConfig.class)
class ScoreControllerParityTest {

    private static final Pattern PARAM = Pattern.compile("'UKS3', '(\\w+)', (-?\\d+)\\)");

    @Autowired
    private MockMvc mvc;

    @Autowired
    private ObjectMapper objectMapper;

    @MockBean
    private CreditFileClient creditFileClient;

    @MockBean
    private ScoreModelDao scoreModelDao;

    @MockBean
    private ScoreHistoryDao scoreHistoryDao;

    @BeforeEach
    void modelParams() throws IOException {
        Map<String, Integer> params = new HashMap<>();
        Matcher m = PARAM.matcher(read("db/migration/V6__score_model_uks3.sql"));
        while (m.find()) {
            params.put(m.group(1), Integer.valueOf(m.group(2)));
        }
        given(scoreModelDao.activeModel()).willReturn("UKS3");
        given(scoreModelDao.params(anyString())).willReturn(params);
    }

    @ParameterizedTest
    @ValueSource(longs = {100001, 100002, 100003, 100004, 100005, 100006, 100007, 100008, 100009, 100010, 100011,
            100012, 100013, 100014, 100015, 100016})
    @SuppressWarnings("unchecked")
    void scoreMatchesLegacyBaseline(long id) throws Exception {
        Map<String, Object> file = objectMapper.readValue(read("parity/creditfile/" + id + ".json"), Map.class);
        long disputed = ((List<Map<String, Object>>) file.get("tradelines")).stream()
                .filter(t -> Boolean.TRUE.equals(t.get("disputed"))).count();
        given(creditFileClient.getCreditFile(id)).willReturn(file);
        given(scoreHistoryDao.openDisputedTradelines(id)).willReturn((int) disputed);

        mvc.perform(get("/score/{id}", id).param("asOf", "2024-12-31"))
                .andExpect(status().isOk())
                .andExpect(content().string(read("parity/get/" + id + ".json")));
    }

    @ParameterizedTest
    @ValueSource(strings = {"/score/999999", "/score/999999/recalculate"})
    void unknownConsumerIs404WithEmptyBody(String path) throws Exception {
        given(creditFileClient.getCreditFile(anyLong())).willReturn(null);
        var req = path.endsWith("recalculate")
                ? org.springframework.test.web.servlet.request.MockMvcRequestBuilders.post(path)
                : get(path);
        mvc.perform(req.param("asOf", "2024-12-31"))
                .andExpect(status().isNotFound())
                .andExpect(content().string(""));
    }

    private static String read(String path) throws IOException {
        return new ClassPathResource(path).getContentAsString(StandardCharsets.UTF_8);
    }
}
