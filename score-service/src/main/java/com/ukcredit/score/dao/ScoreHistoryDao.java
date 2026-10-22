package com.ukcredit.score.dao;

import com.ukcredit.score.calc.ScoreResult;
import org.springframework.jdbc.core.JdbcTemplate;

import java.sql.Date;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.util.List;
import java.util.Map;

public class ScoreHistoryDao {

    private JdbcTemplate jdbcTemplate;

    public void insert(ScoreResult r, String trigger) {
        Long id = jdbcTemplate.queryForObject("SELECT nextval('SCR_HIST_SEQ')", Long.class);
        String rsn = String.join(",", r.reasons);
        jdbcTemplate.update("INSERT INTO SCORE_HISTORY (SCR_HIST_ID, CNSMR_ID, SCR_VAL, SCR_BAND_CD, MODEL_VER, AS_OF_DT,"
                        + " CALC_TS, TRIGGER_CD, RSN_CDS) VALUES (?,?,?,?,?,?,?,?,?)",
                id, r.cnsmrId, r.score, r.band, r.modelVer, Date.valueOf(LocalDate.parse(r.asOf)),
                new Timestamp(System.currentTimeMillis()), trigger, rsn.length() > 200 ? rsn.substring(0, 200) : rsn);
    }

    public List<Map<String, Object>> history(long cnsmrId) {
        return jdbcTemplate.queryForList("SELECT SCR_HIST_ID AS \"id\", SCR_VAL AS \"score\", SCR_BAND_CD AS \"band\","
                + " MODEL_VER AS \"modelVer\", CAST(AS_OF_DT AS VARCHAR(10)) AS \"asOf\", TRIGGER_CD AS \"trigger\","
                + " RSN_CDS AS \"reasons\" FROM SCORE_HISTORY WHERE CNSMR_ID = ? ORDER BY SCR_HIST_ID", cnsmrId);
    }

    public int openDisputedTradelines(long cnsmrId) {
        return jdbcTemplate.queryForObject("SELECT COUNT(*) FROM ACCOUNT_TRADELINE WHERE CNSMR_ID = ? AND DSPT_FLG = 'Y'"
                + " AND DEL_FLG = 'N'", Integer.class, cnsmrId);
    }

    public void setJdbcTemplate(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }
}
