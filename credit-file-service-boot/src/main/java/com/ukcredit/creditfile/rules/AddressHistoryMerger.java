package com.ukcredit.creditfile.rules;

import com.ukcredit.creditfile.domain.AddressHistoryEntry;

import java.util.ArrayList;
import java.util.Collections;
import java.util.Comparator;
import java.util.List;

/**
 * Collapses duplicate reports of the same address (lender feed, electoral roll, manual).
 * When two sources report the same address, the most recent report wins so that lender
 * corrections take effect.
 */
public class AddressHistoryMerger {

    public static class Result {
        public final List<AddressHistoryEntry> kept = new ArrayList<AddressHistoryEntry>();
        public final List<AddressHistoryEntry> removed = new ArrayList<AddressHistoryEntry>();
    }

    public Result merge(List<AddressHistoryEntry> entries) {
        List<AddressHistoryEntry> work = new ArrayList<AddressHistoryEntry>();
        for (AddressHistoryEntry e : entries) {
            work.add(e.copy());
        }
        Collections.sort(work, new Comparator<AddressHistoryEntry>() {
            public int compare(AddressHistoryEntry a, AddressHistoryEntry b) {
                if (a.addrId != b.addrId) {
                    return a.addrId < b.addrId ? -1 : 1;
                }
                return a.dtFrom.compareTo(b.dtFrom);
            }
        });

        Result r = new Result();
        for (AddressHistoryEntry e : work) {
            AddressHistoryEntry match = null;
            for (AddressHistoryEntry k : r.kept) {
                if (k.addrId == e.addrId && overlaps(k, e)) {
                    match = k;
                    break;
                }
            }
            if (match == null) {
                r.kept.add(e);
                continue;
            }
            AddressHistoryEntry winner = pick(match, e);
            AddressHistoryEntry loser = winner == match ? e : match;
            winner.dtTo = laterOf(match.dtTo, e.dtTo);
            if (winner != match) {
                r.kept.set(r.kept.indexOf(match), winner);
            }
            r.removed.add(loser);
        }

        Collections.sort(r.kept, new Comparator<AddressHistoryEntry>() {
            public int compare(AddressHistoryEntry a, AddressHistoryEntry b) {
                return b.dtFrom.compareTo(a.dtFrom);
            }
        });
        return r;
    }

    private AddressHistoryEntry pick(AddressHistoryEntry a, AddressHistoryEntry b) {
        int c = a.dtFrom.compareTo(b.dtFrom);
        if (c != 0) {
            return c < 0 ? a : b;
        }
        // same from-date: keep the record we had first
        c = a.crtdTs.compareTo(b.crtdTs);
        if (c != 0) {
            return c < 0 ? a : b;
        }
        return a.addrHistId <= b.addrHistId ? a : b;
    }

    private static boolean overlaps(AddressHistoryEntry a, AddressHistoryEntry b) {
        boolean aEndsBeforeB = a.dtTo != null && a.dtTo.isBefore(b.dtFrom);
        boolean bEndsBeforeA = b.dtTo != null && b.dtTo.isBefore(a.dtFrom);
        return !aEndsBeforeB && !bEndsBeforeA;
    }

    private static java.time.LocalDate laterOf(java.time.LocalDate a, java.time.LocalDate b) {
        if (a == null || b == null) {
            return null;
        }
        return a.isAfter(b) ? a : b;
    }
}
