package com.ukcredit.dispute.sla;

import org.junit.jupiter.api.BeforeAll;
import org.junit.jupiter.api.Test;

import java.text.SimpleDateFormat;
import java.util.Set;

import static org.junit.jupiter.api.Assertions.assertEquals;

/** Ported unchanged from dispute-service SlaCalculatorTest, plus cut-off edge cases. */
class SlaCalculatorTest {

    private final SlaCalculator calc = new SlaCalculator(null, new WorkingDayCalendar(null));

    @BeforeAll
    static void holidays() {
        WorkingDayCalendar.preload("EW", Set.of("20241225", "20241226", "20250101"));
        WorkingDayCalendar.preload("SC", Set.of("20241225", "20241226", "20250101", "20250102"));
    }

    @Test
    void beforeCutoffStartsSameDay() throws Exception {
        assertEquals("2025-01-22", due("2024-12-20 10:15", "EW"));
    }

    @Test
    void afterCutoffScotlandLosesSecondJanuary() throws Exception {
        assertEquals("2025-01-23", due("2024-12-20 18:00", "EW"));
        assertEquals("2025-01-24", due("2024-12-20 18:00", "SC"));
    }

    @Test
    void cutoffIsInclusive() throws Exception {
        assertEquals("2025-01-22", due("2024-12-20 17:30", "EW"));
        assertEquals("2025-01-23", due("2024-12-20 17:31", "EW"));
    }

    @Test
    void weekendReceiptStartsNextWorkingDay() throws Exception {
        assertEquals("2025-01-23", due("2024-12-21 09:00", "EW"));
    }

    @Test
    void btPostcodeIsTreatedAsEnglandAndWales() {
        assertEquals("EW", RegionResolver.regionForPostcode("BT7 1NN"));
        assertEquals("SC", RegionResolver.regionForPostcode("G12 8QQ"));
        assertEquals("EW", RegionResolver.regionForPostcode("GU1 1AA"));
        assertEquals("EW", RegionResolver.regionForPostcode(null));
    }

    private String due(String received, String region) throws Exception {
        SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd HH:mm");
        return new SimpleDateFormat("yyyy-MM-dd").format(calc.dueDate(f.parse(received), region));
    }
}
