package com.ukcredit.common;

import static org.junit.jupiter.api.Assertions.assertEquals;

import org.junit.jupiter.api.Test;

public class NameNormaliserTest {

    @Test
    public void stripsApostrophe() {
        assertEquals("OBRIEN", NameNormaliser.normalise("O'Brien"));
    }
}
