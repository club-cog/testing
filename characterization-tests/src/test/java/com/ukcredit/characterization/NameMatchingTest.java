package com.ukcredit.characterization;

import com.fasterxml.jackson.databind.JsonNode;
import org.junit.Test;

import java.util.ArrayList;
import java.util.Arrays;
import java.util.Collections;
import java.util.List;

import static org.junit.Assert.assertEquals;

/**
 * Quirk (d): /consumers/match normalises diacritics (Á->A, É->E, Ł->L, ß->SS), case, apostrophes, hyphens and
 * spaces before an exact surname + DOB match; forenames may be initials or prefixes.
 */
public class NameMatchingTest {

    static List<Long> match(String first, String surname, String dob) {
        JsonNode arr = Http.getJson(Http.creditFileUrl() + "/consumers/match?firstName=" + Http.enc(first)
                + "&surname=" + Http.enc(surname) + "&dob=" + dob);
        List<Long> ids = new ArrayList<Long>();
        for (JsonNode n : arr) {
            ids.add(n.get("cnsmrId").asLong());
        }
        return ids;
    }

    @Test
    public void diacriticsAndPunctuationAreNormalisedForMatching() {
        List<Long> siobhan = Collections.singletonList(100008L);
        assertEquals(siobhan, match("Siobhán", "Ó Briain", "1984-02-29"));
        assertEquals(siobhan, match("SIOBHAN", "O'BRIAIN", "1984-02-29"));
        assertEquals(siobhan, match("SIOBHAN", "O BRIAIN", "1984-02-29"));
        assertEquals(siobhan, match("SIOBHAN", "OBRIAIN", "1984-02-29"));

        List<Long> renee = Collections.singletonList(100009L);
        assertEquals(renee, match("Renée", "Dubois-Marchand", "1966-04-21"));
        assertEquals(renee, match("RENEE", "DUBOIS MARCHAND", "1966-04-21"));

        List<Long> lukasz = Collections.singletonList(100010L);
        assertEquals(lukasz, match("Łukasz", "Wiśniewski", "1992-08-08"));
        assertEquals(lukasz, match("LUKASZ", "WISNIEWSKI", "1992-08-08"));

        List<Long> strauss = Collections.singletonList(100011L);
        assertEquals(strauss, match("Margaret", "Strauß", "1958-10-10"));
        assertEquals(strauss, match("MARGARET", "STRAUSS", "1958-10-10"));
        assertEquals("initial", strauss, match("M", "STRAUSS", "1958-10-10"));
        assertEquals("prefix", strauss, match("MARG", "STRAUSS", "1958-10-10"));
    }

    @Test
    public void surnameAndDobMustStillMatchExactlyAfterNormalising() {
        List<Long> none = Collections.emptyList();
        assertEquals("ß is SS, not S", none, match("MARGARET", "STRAUS", "1958-10-10"));
        assertEquals("maiden-name alias (Dubois) is not used for matching", none, match("RENEE", "DUBOIS", "1966-04-21"));
        assertEquals("wrong DOB", none, match("SIOBHAN", "O'BRIAIN", "1984-02-28"));
        assertEquals(Arrays.asList(100008L), match("siobhan", "o'briain", "1984-02-29"));
    }
}
