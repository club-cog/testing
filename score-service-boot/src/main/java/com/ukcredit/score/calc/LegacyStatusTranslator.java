package com.ukcredit.score.calc;

import java.time.LocalDate;

/**
 * Score-side view of the CAIS account status. Kept in sync with SYS_PARAM.TRDLN_X_CUTOFF_DT.
 * (Duplicated from credit-file-service so the scorer does not depend on its mapped labels.)
 */
public class LegacyStatusTranslator {

    private static final LocalDate X_CUTOFF = LocalDate.of(2014, 4, 1);

    public enum Cat { UP_TO_DATE, ARREARS, DEFAULT, ARRANGEMENT, SETTLED, OTHER }

    public Cat category(String stsCd, LocalDate stsDt) {
        if (stsCd == null || stsCd.trim().isEmpty()) {
            return Cat.OTHER;
        }
        char c = stsCd.trim().charAt(0);
        if (c == '0') {
            return Cat.UP_TO_DATE;
        }
        if (c >= '1' && c <= '6') {
            return Cat.ARREARS;
        }
        if (c == '8') {
            return Cat.DEFAULT;
        }
        if (c == 'S') {
            return Cat.SETTLED;
        }
        if (c == 'X') {
            return stsDt != null && stsDt.isBefore(X_CUTOFF) ? Cat.DEFAULT : Cat.ARRANGEMENT;
        }
        return Cat.OTHER;
    }

    public int monthsInArrears(String stsCd) {
        char c = stsCd.trim().charAt(0);
        return c >= '1' && c <= '6' ? c - '0' : 0;
    }
}
