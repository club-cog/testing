package com.ukcredit.common;

import java.text.Normalizer;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.Locale;

/**
 * Normalises names for matching. Accents are stripped so lender files that arrive without
 * diacritics still match the bureau record.
 */
public final class NameNormaliser {

    private NameNormaliser() {
    }

    public static String normalise(String name) {
        if (name == null) {
            return "";
        }
        String upper = name.trim().toUpperCase(Locale.UK);
        StringBuilder sb = new StringBuilder(upper.length());
        for (char ch : upper.toCharArray()) {
            switch (ch) {
                case '\u00DF': // sharp s (only if toUpperCase did not already expand it)
                    sb.append("SS");
                    break;
                case '\u00C6':
                    sb.append("AE");
                    break;
                case '\u0152':
                    sb.append("OE");
                    break;
                case '\u00D8':
                    sb.append('O');
                    break;
                case '\u0141':
                    sb.append('L');
                    break;
                case '\u0110':
                    sb.append('D');
                    break;
                default:
                    sb.append(ch);
            }
        }
        String decomposed = Normalizer.normalize(sb, Normalizer.Form.NFD);
        // drops combining marks, then apostrophes, hyphens and spaces: O'Brien == OBRIEN == O BRIEN
        return decomposed.replaceAll("\\p{M}", "").replaceAll("[^A-Z]", "");
    }

    /** SURNAME|yyyyMMdd|first initial, stored in CONSUMER.MATCH_KEY. */
    public static String matchKey(String surname, LocalDate dob, String firstName) {
        String first = normalise(firstName);
        return normalise(surname) + "|" + dob.format(DateTimeFormatter.BASIC_ISO_DATE) + "|"
                + (first.isEmpty() ? "" : first.substring(0, 1));
    }

    public static String matchKeyPrefix(String surname, LocalDate dob) {
        return normalise(surname) + "|" + dob.format(DateTimeFormatter.BASIC_ISO_DATE) + "|";
    }
}
