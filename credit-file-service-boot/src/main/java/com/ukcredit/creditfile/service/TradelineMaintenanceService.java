package com.ukcredit.creditfile.service;

import com.ukcredit.creditfile.dao.TradelineDao;
import com.ukcredit.creditfile.domain.Tradeline;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.annotation.Transactional;

import java.sql.Date;
import java.sql.Timestamp;
import java.time.LocalDate;

/**
 * Operator / dispute-driven changes to tradelines. All changes are audited.
 */
public class TradelineMaintenanceService {

    private final JdbcTemplate jdbcTemplate;
    private final TradelineDao tradelineDao;

    public TradelineMaintenanceService(JdbcTemplate jdbcTemplate, TradelineDao tradelineDao) {
        this.jdbcTemplate = jdbcTemplate;
        this.tradelineDao = tradelineDao;
    }

    @Transactional
    public boolean setDisputeFlag(long trdlnId, String flag) {
        int n = tradelineDao.updateDisputeFlag(trdlnId, flag);
        if (n > 0) {
            audit(trdlnId, "DSPT_FLG", "DSPT_FLG=" + flag);
        }
        return n > 0;
    }

    @Transactional
    public boolean amend(long trdlnId, String statusCd, Long balancePence, boolean delete, String operatorId) {
        Tradeline t = tradelineDao.findById(trdlnId);
        if (t == null) {
            return false;
        }
        StringBuilder dtl = new StringBuilder("opr=" + operatorId);
        if (delete) {
            jdbcTemplate.update("UPDATE ACCOUNT_TRADELINE SET DEL_FLG = 'Y', UPD_TS = CURRENT_TIMESTAMP WHERE TRDLN_ID = ?",
                    trdlnId);
            dtl.append(" DEL_FLG=Y");
        }
        if (statusCd != null && !statusCd.equals(t.acctStsCd)) {
            // status date moves to today so the new status is "as reported"
            jdbcTemplate.update("UPDATE ACCOUNT_TRADELINE SET ACCT_STS_CD = ?, ACCT_STS_DT = ?, UPD_TS = CURRENT_TIMESTAMP"
                    + " WHERE TRDLN_ID = ?", statusCd, Date.valueOf(LocalDate.now()), trdlnId);
            dtl.append(" ACCT_STS_CD ").append(t.acctStsCd).append("->").append(statusCd);
        }
        if (balancePence != null && balancePence != t.currBalPnc) {
            jdbcTemplate.update("UPDATE ACCOUNT_TRADELINE SET CURR_BAL_PNC = ?, UPD_TS = CURRENT_TIMESTAMP WHERE TRDLN_ID = ?",
                    balancePence, trdlnId);
            dtl.append(" CURR_BAL_PNC ").append(t.currBalPnc).append("->").append(balancePence);
        }
        audit(trdlnId, "AMEND", dtl.toString());
        return true;
    }

    public Tradeline get(long trdlnId) {
        return tradelineDao.findById(trdlnId);
    }

    private void audit(long trdlnId, String action, String detail) {
        Long id = jdbcTemplate.queryForObject("SELECT nextval('AUD_SEQ')", Long.class);
        jdbcTemplate.update("INSERT INTO AUDIT_LOG (AUD_ID, ENTITY_NM, ENTITY_ID, ACTN_CD, ACTN_TS, SRC_SVC, DTL_TXT)"
                        + " VALUES (?,?,?,?,?,?,?)", id, "ACCOUNT_TRADELINE", String.valueOf(trdlnId), action,
                new Timestamp(System.currentTimeMillis()), "credit-file-service", detail);
    }
}
