package com.ukcredit.dispute.sla;

import org.springframework.jdbc.core.JdbcTemplate;

import java.util.List;
import java.util.Set;

/**
 * Bank holiday region from the consumer's current postcode. SC for Scottish postcode areas, otherwise EW.
 */
public class RegionResolver {

    private static final Set<String> SCOTTISH_AREAS = Set.of(
            "AB", "DD", "DG", "EH", "FK", "G", "HS", "IV", "KA", "KW", "KY", "ML", "PA", "PH", "TD", "ZE");

    private final JdbcTemplate jdbcTemplate;

    public RegionResolver(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    public String regionForConsumer(long cnsmrId) {
        List<String> pc = jdbcTemplate.queryForList("SELECT a.PSTCD FROM ADDRESS_HISTORY h JOIN ADDRESS a ON a.ADDR_ID = h.ADDR_ID"
                + " WHERE h.CNSMR_ID = ? AND h.DT_TO IS NULL ORDER BY h.DT_FROM DESC, h.ADDR_HIST_ID", String.class, cnsmrId);
        return regionForPostcode(pc.isEmpty() ? null : pc.get(0));
    }

    public static String regionForPostcode(String postcode) {
        if (postcode == null) {
            return "EW";
        }
        String pc = postcode.trim().toUpperCase();
        int i = 0;
        while (i < pc.length() && Character.isLetter(pc.charAt(i))) {
            i++;
        }
        // TODO NI holidays not loaded, BT falls through to EW for now (kept from legacy)
        return SCOTTISH_AREAS.contains(pc.substring(0, i)) ? "SC" : "EW";
    }
}
