package com.ukcredit.creditfile.rules;

import static org.junit.Assert.assertEquals;

import java.time.LocalDate;

import org.junit.Test;

public class TradelineStatusMapperTest {

    private final TradelineStatusMapper mapper = new TradelineStatusMapper();

    @Test
    public void upToDate() {
        assertEquals("UP_TO_DATE", mapper.map("0", LocalDate.of(2024, 1, 1)));
    }

    @Test
    public void arrears() {
        assertEquals("ARREARS_3", mapper.map("3", LocalDate.of(2024, 1, 1)));
    }
}
