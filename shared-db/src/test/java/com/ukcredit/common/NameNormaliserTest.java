package com.ukcredit.common;

import static org.junit.Assert.assertEquals;

import org.junit.Test;

public class NameNormaliserTest {

    @Test
    public void stripsApostrophe() {
        assertEquals("OBRIEN", NameNormaliser.normalise("O'Brien"));
    }
}
