package com.ukcredit.dispute.dao;

import org.springframework.jdbc.core.JdbcTemplate;

import java.sql.Timestamp;
import java.util.List;
import java.util.Map;

public class DisputeDao {

    private JdbcTemplate jdbcTemplate;

    public long insertCase(long cnsmrId, Long trdlnId, Long pubRecId, String rsnCd, String chnlCd, Timestamp rcvdTs,
                           java.sql.Date slaDueDt) {
        long id = nextval("DSPT_SEQ");
        jdbcTemplate.update("INSERT INTO DISPUTE_CASE (DSPT_ID, CNSMR_ID, TRDLN_ID, PUB_REC_ID, RSN_CD, CHNL_CD, RCVD_TS,"
                        + " SLA_DUE_DT, STS_CD) VALUES (?,?,?,?,?,?,?,?,'OPEN')",
                id, cnsmrId, trdlnId, pubRecId, rsnCd, chnlCd, rcvdTs, slaDueDt);
        return id;
    }

    public void insertEvent(long dsptId, String evtTypCd, String oprId, String note) {
        jdbcTemplate.update("INSERT INTO DISPUTE_EVENT (DSPT_EVT_ID, DSPT_ID, EVT_TYP_CD, EVT_TS, OPR_ID, NOTE_TXT)"
                + " VALUES (?,?,?,?,?,?)", nextval("DSPT_EVT_SEQ"), dsptId, evtTypCd, now(), oprId, note);
    }

    public void insertCorrespondence(long dsptId, String tmplCd, String chnlCd) {
        jdbcTemplate.update("INSERT INTO DISPUTE_CORRESPONDENCE (CORR_ID, DSPT_ID, LTR_TMPL_CD, SENT_TS, CHNL_CD)"
                + " VALUES (?,?,?,?,?)", nextval("CORR_SEQ"), dsptId, tmplCd, now(), chnlCd);
    }

    public void close(long dsptId, String outcomeCd, String oprId) {
        jdbcTemplate.update("UPDATE DISPUTE_CASE SET STS_CD = 'CLOSED', OUTCOME_CD = ?, RSLVD_TS = ?, RSLVD_BY = ?"
                + " WHERE DSPT_ID = ?", outcomeCd, now(), oprId, dsptId);
    }

    /** Public records are not owned by credit-file-service, so the flag is set here directly. */
    public boolean operatorExists(String oprId) {
        return jdbcTemplate.queryForObject("SELECT COUNT(*) FROM OPERATOR WHERE OPR_ID = ?", Integer.class, oprId) > 0;
    }

    public int setPublicRecordDisputeFlag(long pubRecId, String flag) {
        return jdbcTemplate.update("UPDATE PUBLIC_RECORD SET DSPT_FLG = ? WHERE PUB_REC_ID = ?", flag, pubRecId);
    }

    public Map<String, Object> findCase(long dsptId) {
        List<Map<String, Object>> l = jdbcTemplate.queryForList("SELECT DSPT_ID AS \"dsptId\", CNSMR_ID AS \"cnsmrId\","
                + " TRDLN_ID AS \"trdlnId\", PUB_REC_ID AS \"pubRecId\", RSN_CD AS \"rsnCd\", CHNL_CD AS \"chnlCd\","
                + " CAST(RCVD_TS AS VARCHAR(30)) AS \"rcvdTs\", CAST(SLA_DUE_DT AS VARCHAR(10)) AS \"slaDueDt\","
                + " STS_CD AS \"stsCd\", OUTCOME_CD AS \"outcomeCd\", CAST(RSLVD_TS AS VARCHAR(30)) AS \"rslvdTs\","
                + " RSLVD_BY AS \"rslvdBy\" FROM DISPUTE_CASE WHERE DSPT_ID = ?", dsptId);
        return l.isEmpty() ? null : l.get(0);
    }

    public List<Map<String, Object>> findEvents(long dsptId) {
        return jdbcTemplate.queryForList("SELECT DSPT_EVT_ID AS \"evtId\", EVT_TYP_CD AS \"evtTypCd\","
                + " CAST(EVT_TS AS VARCHAR(30)) AS \"evtTs\", OPR_ID AS \"oprId\", NOTE_TXT AS \"note\""
                + " FROM DISPUTE_EVENT WHERE DSPT_ID = ? ORDER BY DSPT_EVT_ID", dsptId);
    }

    public List<Map<String, Object>> findCorrespondence(long dsptId) {
        return jdbcTemplate.queryForList("SELECT LTR_TMPL_CD AS \"tmplCd\", CAST(SENT_TS AS VARCHAR(30)) AS \"sentTs\","
                + " CHNL_CD AS \"chnlCd\" FROM DISPUTE_CORRESPONDENCE WHERE DSPT_ID = ? ORDER BY CORR_ID", dsptId);
    }

    private long nextval(String seq) {
        return jdbcTemplate.queryForObject("SELECT nextval('" + seq + "')", Long.class);
    }

    private static Timestamp now() {
        return new Timestamp(System.currentTimeMillis());
    }

    public void setJdbcTemplate(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }
}
