package com.ukcredit.dispute.sla;

import org.junit.BeforeClass;
import org.junit.Test;

import java.text.SimpleDateFormat;
import java.util.Arrays;
import java.util.HashSet;

import static org.junit.Assert.assertEquals;

public class SlaCalculatorTest {

    private final SlaCalculator calc = new SlaCalculator();

    @BeforeClass
    public static void holidays() {
        WorkingDayCalendar.preload("EW", new HashSet<String>(Arrays.asList("20241225", "20241226", "20250101")));
        WorkingDayCalendar.preload("SC", new HashSet<String>(Arrays.asList("20241225", "20241226", "20250101", "20250102")));
    }

    public SlaCalculatorTest() {
        calc.setWorkingDayCalendar(new WorkingDayCalendar());
    }

    @Test
    public void beforeCutoffStartsSameDay() throws Exception {
        assertEquals("2025-01-22", due("2024-12-20 10:15", "EW"));
    }

    @Test
    public void afterCutoffScotlandLosesSecondJanuary() throws Exception {
        assertEquals("2025-01-23", due("2024-12-20 18:00", "EW"));
        assertEquals("2025-01-24", due("2024-12-20 18:00", "SC"));
    }

    @Test
    public void btPostcodeIsTreatedAsEnglandAndWales() {
        assertEquals("EW", RegionResolver.regionForPostcode("BT7 1NN"));
        assertEquals("SC", RegionResolver.regionForPostcode("G12 8QQ"));
        assertEquals("EW", RegionResolver.regionForPostcode("GU1 1AA"));
    }

    private String due(String received, String region) throws Exception {
        SimpleDateFormat f = new SimpleDateFormat("yyyy-MM-dd HH:mm");
        return new SimpleDateFormat("yyyy-MM-dd").format(calc.dueDate(f.parse(received), region));
    }
}
