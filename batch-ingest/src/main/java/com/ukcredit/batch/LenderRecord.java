package com.ukcredit.batch;

import java.time.LocalDate;

/** One DTL record from a lender (CAIS-style) file. */
public class LenderRecord {
    public String acctNo;
    public String acctTyp;
    public String surname;
    public String firstName;
    public LocalDate dob;
    public String postcode;
    public LocalDate openDt;
    public LocalDate closeDt;
    public int creditLimit;
    public long balancePence;
    public String statusCd;
    public LocalDate statusDt;
    public String paymentProfile;
    public LocalDate addressFrom;
    public String line1;
    public String town;
}
