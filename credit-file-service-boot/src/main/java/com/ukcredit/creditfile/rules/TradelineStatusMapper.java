package com.ukcredit.creditfile.rules;

import java.time.LocalDate;

/**
 * Maps raw lender status codes (ACCT_STS_CD) to the bureau's canonical status.
 */
public class TradelineStatusMapper {

    // cutoff is read from SYS_PARAM.TRDLN_X_CUTOFF_DT
    static final LocalDate X_CUTOFF = LocalDate.of(2014, 4, 1);

    public String map(String stsCd, LocalDate stsDt) {
        if (stsCd == null || stsCd.trim().isEmpty()) {
            return "UNCLASSIFIED";
        }
        char c = stsCd.trim().charAt(0);
        switch (c) {
            case '0':
                return "UP_TO_DATE";
            case '1':
            case '2':
            case '3':
            case '4':
            case '5':
            case '6':
                return "ARREARS_" + c;
            case '8':
                return "DEFAULT";
            case 'S':
                return "SETTLED";
            case 'D':
                return "DORMANT";
            case 'X':
                // X = account in query
                if (stsDt != null && stsDt.isBefore(X_CUTOFF)) {
                    return "DEFAULT";
                }
                return "ARRANGEMENT";
            default:
                return "UNCLASSIFIED";
        }
    }

    public boolean isAdverse(String mapped) {
        return mapped.startsWith("ARREARS") || "DEFAULT".equals(mapped) || "ARRANGEMENT".equals(mapped);
    }
}
