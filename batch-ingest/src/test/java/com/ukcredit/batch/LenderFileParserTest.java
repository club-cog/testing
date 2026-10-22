package com.ukcredit.batch;

import org.junit.Test;

import java.time.LocalDate;

import static org.junit.Assert.assertEquals;
import static org.junit.Assert.assertNull;

public class LenderFileParserTest {

    private static final String DTL = pad("DTL" + pad("4000000000900099", 20) + "CC" + pad("PENROSE", 30) + pad("OLIVIA", 20)
            + "19990101" + pad("EX1 2LU", 10) + "20241215" + "00000000" + "00001000" + "+" + "00000015000" + "0"
            + "20241231" + "000000000000000000000000" + "20230601" + pad("3 BAMPFYLDE STREET", 40) + pad("EXETER", 30), 240);

    @Test
    public void parsesDetail() throws Exception {
        LenderRecord r = new LenderFileParser().parseDetail(DTL);
        assertEquals("4000000000900099", r.acctNo);
        assertEquals("PENROSE", r.surname);
        assertEquals(LocalDate.of(1999, 1, 1), r.dob);
        assertNull(r.closeDt);
        assertEquals(1000, r.creditLimit);
        assertEquals(15000L, r.balancePence);
        assertEquals("EXETER", r.town);
    }

    @Test(expected = LenderFileParser.RecordException.class)
    public void rejectsBadStatusDate() throws Exception {
        new LenderFileParser().parseDetail(DTL.substring(0, 130) + "20241340" + DTL.substring(138));
    }

    private static String pad(String s, int n) {
        StringBuilder sb = new StringBuilder(s);
        while (sb.length() < n) {
            sb.append(' ');
        }
        return sb.toString();
    }
}
