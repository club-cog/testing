package com.ukcredit.creditfile.dao;

import com.ukcredit.creditfile.domain.Consumer;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.jdbc.core.RowMapper;

import java.sql.ResultSet;
import java.sql.SQLException;
import java.util.List;

public class ConsumerDao {

    private final JdbcTemplate jdbcTemplate;

    public ConsumerDao(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    private static final String COLS = "CNSMR_ID, TITLE_CD, FRST_NM, MID_NM, SURNM, DOB, GNDR_CD, MATCH_KEY, STS_CD";

    private static final RowMapper<Consumer> MAPPER = new RowMapper<Consumer>() {
        public Consumer mapRow(ResultSet rs, int i) throws SQLException {
            Consumer c = new Consumer();
            c.cnsmrId = rs.getLong("CNSMR_ID");
            c.titleCd = JdbcUtil.trim(rs.getString("TITLE_CD"));
            c.firstName = rs.getString("FRST_NM");
            c.middleName = rs.getString("MID_NM");
            c.surname = rs.getString("SURNM");
            c.dob = JdbcUtil.date(rs, "DOB");
            c.genderCd = JdbcUtil.trim(rs.getString("GNDR_CD"));
            c.matchKey = rs.getString("MATCH_KEY");
            c.stsCd = JdbcUtil.trim(rs.getString("STS_CD"));
            return c;
        }
    };

    public Consumer findById(long id) {
        List<Consumer> l = jdbcTemplate.query("SELECT " + COLS + " FROM CONSUMER WHERE CNSMR_ID = ?", MAPPER, id);
        return l.isEmpty() ? null : l.get(0);
    }

    /** Candidates share SURNAME|DOB; the forename initial is checked by NameMatcher. */
    public List<Consumer> findCandidates(String matchKeyPrefix) {
        return jdbcTemplate.query("SELECT " + COLS + " FROM CONSUMER WHERE MATCH_KEY LIKE ? AND STS_CD = 'A' ORDER BY CNSMR_ID",
                MAPPER, matchKeyPrefix + "%");
    }
}
