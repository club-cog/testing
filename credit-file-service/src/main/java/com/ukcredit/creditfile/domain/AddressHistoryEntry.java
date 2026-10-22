package com.ukcredit.creditfile.domain;

import java.time.LocalDate;
import java.time.LocalDateTime;

public class AddressHistoryEntry {
    public long addrHistId;
    public long cnsmrId;
    public long addrId;
    public LocalDate dtFrom;
    public LocalDate dtTo;
    public String srcCd;
    public LocalDateTime crtdTs;

    // denormalised from ADDRESS for display
    public String line1;
    public String town;
    public String postcode;

    public AddressHistoryEntry copy() {
        AddressHistoryEntry e = new AddressHistoryEntry();
        e.addrHistId = addrHistId;
        e.cnsmrId = cnsmrId;
        e.addrId = addrId;
        e.dtFrom = dtFrom;
        e.dtTo = dtTo;
        e.srcCd = srcCd;
        e.crtdTs = crtdTs;
        e.line1 = line1;
        e.town = town;
        e.postcode = postcode;
        return e;
    }
}
