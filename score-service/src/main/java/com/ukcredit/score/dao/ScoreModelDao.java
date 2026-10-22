package com.ukcredit.score.dao;

import org.springframework.jdbc.core.JdbcTemplate;

import java.util.HashMap;
import java.util.Map;

public class ScoreModelDao {

    private JdbcTemplate jdbcTemplate;

    public String activeModel() {
        return jdbcTemplate.queryForObject("SELECT PARAM_VAL FROM SYS_PARAM WHERE PARAM_CD = 'SCORE_MODEL_VER'",
                String.class).trim();
    }

    public Map<String, Integer> params(String modelVer) {
        Map<String, Integer> m = new HashMap<String, Integer>();
        for (Map<String, Object> r : jdbcTemplate.queryForList(
                "SELECT PARAM_CD, PARAM_VAL FROM SCORE_MODEL_PARAM WHERE MODEL_VER = ?", modelVer)) {
            m.put(((String) r.get("PARAM_CD")).trim(), ((Number) r.get("PARAM_VAL")).intValue());
        }
        return m;
    }

    public void setJdbcTemplate(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }
}
