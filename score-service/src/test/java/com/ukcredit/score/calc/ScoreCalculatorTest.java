package com.ukcredit.score.calc;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class ScoreCalculatorTest {

    @Test
    public void bands() {
        assertEquals("VPOOR", ScoreCalculator.band(420));
        assertEquals("FAIR", ScoreCalculator.band(600));
        assertEquals("EXCELLENT", ScoreCalculator.band(750));
    }
}
