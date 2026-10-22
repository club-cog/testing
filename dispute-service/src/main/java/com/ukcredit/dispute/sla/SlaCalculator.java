package com.ukcredit.dispute.sla;

import org.springframework.jdbc.core.JdbcTemplate;

import java.util.Calendar;
import java.util.Date;
import java.util.List;

/**
 * Statutory response date for a consumer dispute.
 */
public class SlaCalculator {

    // SLA is DSPT_SLA_DAYS (28) calendar days from receipt, see SYS_PARAM.
    static final int SLA_WORKING_DAYS = 20;

    static final String DEFAULT_CUTOFF = "17:30";

    private JdbcTemplate jdbcTemplate;
    private WorkingDayCalendar workingDayCalendar;

    public Date dueDate(Date received, String regionCd) {
        Calendar cal = Calendar.getInstance();
        cal.setTime(received);
        int[] cutoff = cutoff();
        int mins = cal.get(Calendar.HOUR_OF_DAY) * 60 + cal.get(Calendar.MINUTE);
        truncate(cal);
        // after the cut-off, or on a weekend/holiday, the clock starts next working day
        if (mins > cutoff[0] * 60 + cutoff[1] || !workingDayCalendar.isWorkingDay(cal, regionCd)) {
            workingDayCalendar.nextWorkingDay(cal, regionCd);
        }
        for (int i = 0; i < SLA_WORKING_DAYS; i++) {
            workingDayCalendar.nextWorkingDay(cal, regionCd);
        }
        return cal.getTime();
    }

    private int[] cutoff() {
        String v = DEFAULT_CUTOFF;
        if (jdbcTemplate != null) {
            List<String> l = jdbcTemplate.queryForList("SELECT PARAM_VAL FROM SYS_PARAM WHERE PARAM_CD = 'DSPT_CUTOFF_TM'",
                    String.class);
            if (!l.isEmpty()) {
                v = l.get(0).trim();
            }
        }
        String[] p = v.split(":");
        return new int[]{Integer.parseInt(p[0]), Integer.parseInt(p[1])};
    }

    private static void truncate(Calendar cal) {
        cal.set(Calendar.HOUR_OF_DAY, 0);
        cal.set(Calendar.MINUTE, 0);
        cal.set(Calendar.SECOND, 0);
        cal.set(Calendar.MILLISECOND, 0);
    }

    public void setJdbcTemplate(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    public void setWorkingDayCalendar(WorkingDayCalendar workingDayCalendar) {
        this.workingDayCalendar = workingDayCalendar;
    }
}
