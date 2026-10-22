package com.ukcredit.batch;

import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.time.format.DateTimeParseException;

/**
 * Fixed width, 240 bytes, ISO-8859-1. Layout in batch-ingest/README.md.
 */
public class LenderFileParser {

    public static final int RECORD_LEN = 240;
    private static final DateTimeFormatter YMD = DateTimeFormatter.BASIC_ISO_DATE;

    public static class RecordException extends Exception {
        public RecordException(String msg) {
            super(msg);
        }
    }

    public LenderRecord parseDetail(String line) throws RecordException {
        if (line.length() != RECORD_LEN) {
            throw new RecordException("bad record length " + line.length());
        }
        LenderRecord r = new LenderRecord();
        r.acctNo = required(line, 3, 23, "account number");
        r.acctTyp = required(line, 23, 25, "account type");
        r.surname = required(line, 25, 55, "surname");
        r.firstName = required(line, 55, 75, "forename");
        r.dob = date(line, 75, 83, "date of birth");
        r.postcode = required(line, 83, 93, "postcode");
        r.openDt = date(line, 93, 101, "open date");
        r.closeDt = "00000000".equals(line.substring(101, 109)) ? null : date(line, 101, 109, "close date");
        r.creditLimit = (int) number(line, 109, 117, "credit limit");
        char sign = line.charAt(117);
        if (sign != '+' && sign != '-') {
            throw new RecordException("bad balance sign '" + sign + "'");
        }
        long bal = number(line, 118, 129, "balance");
        r.balancePence = sign == '-' ? -bal : bal;
        r.statusCd = required(line, 129, 130, "status");
        r.statusDt = date(line, 130, 138, "status date");
        r.paymentProfile = line.substring(138, 162).trim();
        r.addressFrom = date(line, 162, 170, "address date");
        r.line1 = required(line, 170, 210, "address line 1");
        r.town = required(line, 210, 240, "town");
        return r;
    }

    private static String required(String line, int from, int to, String name) throws RecordException {
        String s = line.substring(from, to).trim();
        if (s.isEmpty()) {
            throw new RecordException("missing " + name);
        }
        return s;
    }

    private static LocalDate date(String line, int from, int to, String name) throws RecordException {
        String s = line.substring(from, to);
        try {
            return LocalDate.parse(s, YMD);
        } catch (DateTimeParseException e) {
            throw new RecordException("bad " + name + " '" + s + "'");
        }
    }

    private static long number(String line, int from, int to, String name) throws RecordException {
        String s = line.substring(from, to);
        for (int i = 0; i < s.length(); i++) {
            if (!Character.isDigit(s.charAt(i))) {
                throw new RecordException("bad " + name + " '" + s + "'");
            }
        }
        return Long.parseLong(s);
    }
}
