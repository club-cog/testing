package com.ukcredit.common;

import java.math.BigDecimal;
import java.math.RoundingMode;
import java.text.NumberFormat;
import java.util.Locale;

/**
 * All balances are held in pence (BIGINT). Credit limits are whole pounds.
 */
public final class MoneyUtil {

    private MoneyUtil() {
    }

    /** "123.455" -> 12346. Used for operator-keyed amendments. */
    public static long poundsToPence(String pounds) {
        return new BigDecimal(pounds.trim()).setScale(2, RoundingMode.HALF_UP).movePointRight(2).longValueExact();
    }

    /** Rounds up to the nearest whole pound. */
    public static long penceToWholePounds(long pence) {
        return BigDecimal.valueOf(pence).movePointLeft(2).setScale(0, RoundingMode.HALF_EVEN).longValue();
    }

    public static String formatPounds(long pence) {
        NumberFormat nf = NumberFormat.getCurrencyInstance(Locale.UK);
        return nf.format(BigDecimal.valueOf(pence).movePointLeft(2));
    }
}
