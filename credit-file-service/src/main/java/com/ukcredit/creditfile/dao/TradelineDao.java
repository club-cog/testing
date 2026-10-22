package com.ukcredit.creditfile.dao;

import com.ukcredit.creditfile.domain.Tradeline;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;

public class TradelineDao {

    private JdbcTemplate jdbcTemplate;

    private static final String SELECT = "SELECT t.TRDLN_ID, t.CNSMR_ID, t.LNDR_REF_CD, l.LNDR_NM, t.ACCT_TYP_CD, r.RVLVNG_FLG,"
            + " t.OPEN_DT, t.CLOSE_DT, t.CR_LMT_AMT, t.CURR_BAL_PNC, t.ACCT_STS_CD, t.ACCT_STS_DT, t.PYMT_PRFL,"
            + " t.DSPT_FLG, t.DEL_FLG"
            + " FROM ACCOUNT_TRADELINE t"
            + " JOIN LENDER l ON l.LNDR_REF_CD = t.LNDR_REF_CD"
            + " JOIN ACCOUNT_TYPE_REF r ON r.ACCT_TYP_CD = t.ACCT_TYP_CD";

    private static final RowMapper<Tradeline> MAPPER = new RowMapper<Tradeline>() {
        public Tradeline mapRow(ResultSet rs, int i) throws SQLException {
            Tradeline t = new Tradeline();
            t.trdlnId = rs.getLong("TRDLN_ID");
            t.cnsmrId = rs.getLong("CNSMR_ID");
            t.lndrRefCd = JdbcUtil.trim(rs.getString("LNDR_REF_CD"));
            t.lndrNm = rs.getString("LNDR_NM");
            t.acctTypCd = JdbcUtil.trim(rs.getString("ACCT_TYP_CD"));
            t.revolving = "Y".equals(JdbcUtil.trim(rs.getString("RVLVNG_FLG")));
            t.openDt = JdbcUtil.date(rs, "OPEN_DT");
            t.closeDt = JdbcUtil.date(rs, "CLOSE_DT");
            t.crLmtAmt = JdbcUtil.intOrNull(rs, "CR_LMT_AMT");
            t.currBalPnc = rs.getLong("CURR_BAL_PNC");
            t.acctStsCd = JdbcUtil.trim(rs.getString("ACCT_STS_CD"));
            t.acctStsDt = JdbcUtil.date(rs, "ACCT_STS_DT");
            t.pymtPrfl = rs.getString("PYMT_PRFL");
            t.dsptFlg = JdbcUtil.trim(rs.getString("DSPT_FLG"));
            t.delFlg = JdbcUtil.trim(rs.getString("DEL_FLG"));
            return t;
        }
    };

    public List<Tradeline> findLiveByConsumer(long cnsmrId) {
        return jdbcTemplate.query(SELECT + " WHERE t.CNSMR_ID = ? AND t.DEL_FLG = 'N' ORDER BY t.OPEN_DT, t.TRDLN_ID",
                MAPPER, cnsmrId);
    }

    public Tradeline findById(long trdlnId) {
        List<Tradeline> l = jdbcTemplate.query(SELECT + " WHERE t.TRDLN_ID = ?", MAPPER, trdlnId);
        return l.isEmpty() ? null : l.get(0);
    }

    public int updateDisputeFlag(long trdlnId, String flag) {
        return jdbcTemplate.update("UPDATE ACCOUNT_TRADELINE SET DSPT_FLG = ?, UPD_TS = CURRENT_TIMESTAMP WHERE TRDLN_ID = ?",
                flag, trdlnId);
    }

    public void setJdbcTemplate(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }
}
