package com.ukcredit.dispute.sla;

import org.springframework.jdbc.core.JdbcTemplate;

import java.text.SimpleDateFormat;
import java.util.Calendar;
import java.util.Date;
import java.util.HashMap;
import java.util.HashSet;
import java.util.List;
import java.util.Map;
import java.util.Set;

/**
 * Mon-Fri, excluding BANK_HOLIDAY rows for the region (EW / SC).
 * Holidays are loaded once per region and kept for the life of the JVM - restart after loading a new year.
 */
public class WorkingDayCalendar {

    private static final Map<String, Set<String>> HOLIDAYS = new HashMap<String, Set<String>>();

    private JdbcTemplate jdbcTemplate;

    public boolean isWorkingDay(Calendar day, String regionCd) {
        int dow = day.get(Calendar.DAY_OF_WEEK);
        if (dow == Calendar.SATURDAY || dow == Calendar.SUNDAY) {
            return false;
        }
        return !holidays(regionCd).contains(key(day.getTime()));
    }

    /** Moves cal forward to the next working day (always moves at least one day). */
    public void nextWorkingDay(Calendar cal, String regionCd) {
        do {
            cal.add(Calendar.DAY_OF_MONTH, 1);
        } while (!isWorkingDay(cal, regionCd));
    }

    private Set<String> holidays(String regionCd) {
        synchronized (HOLIDAYS) {
            Set<String> s = HOLIDAYS.get(regionCd);
            if (s == null) {
                s = new HashSet<String>();
                List<Date> rows = jdbcTemplate.queryForList(
                        "SELECT HOL_DT FROM BANK_HOLIDAY WHERE REGION_CD = ?", Date.class, regionCd);
                for (Date d : rows) {
                    s.add(key(d));
                }
                HOLIDAYS.put(regionCd, s);
            }
            return s;
        }
    }

    /** Test hook. */
    static void preload(String regionCd, Set<String> yyyyMMdd) {
        synchronized (HOLIDAYS) {
            HOLIDAYS.put(regionCd, yyyyMMdd);
        }
    }

    static String key(Date d) {
        return new SimpleDateFormat("yyyyMMdd").format(d);
    }

    public void setJdbcTemplate(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }
}
