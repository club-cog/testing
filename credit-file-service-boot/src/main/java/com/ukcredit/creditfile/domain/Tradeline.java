package com.ukcredit.creditfile.domain;

import java.time.LocalDate;

public class Tradeline {
    public long trdlnId;
    public long cnsmrId;
    public String lndrRefCd;
    public String lndrNm;
    public String acctTypCd;
    public boolean revolving;
    public LocalDate openDt;
    public LocalDate closeDt;
    public Integer crLmtAmt;      // pounds
    public long currBalPnc;       // pence
    public String acctStsCd;
    public LocalDate acctStsDt;
    public String pymtPrfl;
    public String dsptFlg;
    public String delFlg;
}
