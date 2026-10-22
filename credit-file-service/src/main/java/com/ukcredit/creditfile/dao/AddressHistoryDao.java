package com.ukcredit.creditfile.dao;

import com.ukcredit.creditfile.domain.AddressHistoryEntry;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;

public class AddressHistoryDao {

    private JdbcTemplate jdbcTemplate;

    public static final RowMapper<AddressHistoryEntry> MAPPER = new RowMapper<AddressHistoryEntry>() {
        public AddressHistoryEntry mapRow(ResultSet rs, int i) throws SQLException {
            AddressHistoryEntry e = new AddressHistoryEntry();
            e.addrHistId = rs.getLong("ADDR_HIST_ID");
            e.cnsmrId = rs.getLong("CNSMR_ID");
            e.addrId = rs.getLong("ADDR_ID");
            e.dtFrom = JdbcUtil.date(rs, "DT_FROM");
            e.dtTo = JdbcUtil.date(rs, "DT_TO");
            e.srcCd = JdbcUtil.trim(rs.getString("ADDR_SRC_CD"));
            e.crtdTs = JdbcUtil.ts(rs, "CRTD_TS");
            e.line1 = rs.getString("LINE1");
            e.town = rs.getString("TOWN");
            e.postcode = rs.getString("PSTCD");
            return e;
        }
    };

    public List<AddressHistoryEntry> findByConsumer(long cnsmrId) {
        return jdbcTemplate.query("SELECT h.ADDR_HIST_ID, h.CNSMR_ID, h.ADDR_ID, h.DT_FROM, h.DT_TO, h.ADDR_SRC_CD, h.CRTD_TS,"
                + " a.LINE1, a.TOWN, a.PSTCD FROM ADDRESS_HISTORY h JOIN ADDRESS a ON a.ADDR_ID = h.ADDR_ID"
                + " WHERE h.CNSMR_ID = ? ORDER BY h.ADDR_HIST_ID", MAPPER, cnsmrId);
    }

    public void setJdbcTemplate(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }
}
