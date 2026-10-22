package com.ukcredit.creditfile.rules;

import com.ukcredit.common.NameNormaliser;

import java.time.LocalDate;

/**
 * Exact match on surname + date of birth, loose match on forename.
 */
public class NameMatcher {

    public boolean matches(String first1, String surname1, LocalDate dob1,
                           String first2, String surname2, LocalDate dob2) {
        if (dob1 == null || !dob1.equals(dob2)) {
            return false;
        }
        if (!NameNormaliser.normalise(surname1).equals(NameNormaliser.normalise(surname2))) {
            return false;
        }
        return forenameCompatible(NameNormaliser.normalise(first1), NameNormaliser.normalise(first2));
    }

    boolean forenameCompatible(String a, String b) {
        if (a.isEmpty() || b.isEmpty()) {
            return false;
        }
        if (a.equals(b)) {
            return true;
        }
        // initial only: J == JAMES
        if (a.length() == 1 || b.length() == 1) {
            return a.charAt(0) == b.charAt(0);
        }
        // short forms: CATH == CATHERINE, but not JO == JOSEPH
        if (a.length() >= 3 && b.length() >= 3) {
            return a.startsWith(b) || b.startsWith(a);
        }
        return false;
    }
}
