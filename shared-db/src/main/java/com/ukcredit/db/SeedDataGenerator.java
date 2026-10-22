package com.ukcredit.db;

import com.ukcredit.common.AccountHash;
import com.ukcredit.common.NameNormaliser;

import java.io.File;
import java.io.FileOutputStream;
import java.io.OutputStreamWriter;
import java.io.Writer;
import java.math.BigDecimal;
import java.nio.charset.Charset;
import java.sql.Connection;
import java.sql.PreparedStatement;
import java.sql.ResultSet;
import java.sql.SQLException;
import java.sql.Statement;
import java.sql.Timestamp;
import java.sql.Types;
import java.time.LocalDate;
import java.time.LocalDateTime;
import java.time.format.DateTimeFormatter;
import java.util.ArrayList;
import java.util.List;
import java.util.Random;

/**
 * Loads deterministic synthetic data (fixed seed, as-of 2024-12-31). All people, lenders and
 * addresses are fictional. Consumers 100001-100016 are hand-built edge cases, see docs/seed-data.md.
 *
 * Usage: SeedDataGenerator [sample-file-path]
 */
public class SeedDataGenerator {

    static final LocalDate AS_OF = LocalDate.of(2024, 12, 31);
    static final LocalDateTime LOAD_TS = LocalDateTime.of(2024, 12, 31, 23, 0);
    static final DateTimeFormatter YMD = DateTimeFormatter.BASIC_ISO_DATE;

    private static final String[] MALE = {"James", "Oliver", "Harry", "George", "Thomas", "William", "Jack",
            "Daniel", "Samuel", "Joseph", "David", "Matthew", "Ryan", "Liam", "Adam", "Mohammed", "Arjun", "Kieran",
            "Gareth", "Rhys", "Euan", "Fraser", "Connor", "Stephen", "Paul", "Andrew", "Mark", "Jos\u00e9", "Andr\u00e9"};
    private static final String[] FEMALE = {"Olivia", "Amelia", "Isla", "Emily", "Sophie", "Charlotte", "Grace",
            "Lucy", "Hannah", "Emma", "Rachel", "Sarah", "Laura", "Megan", "Aisha", "Priya", "Niamh", "Catrin",
            "Eilidh", "Morag", "Fiona", "Claire", "Joanne", "Helen", "Zo\u00eb", "Chlo\u00eb", "Ren\u00e9e", "Ana\u00efs"};
    private static final String[] SURNAMES = {"Smith", "Jones", "Taylor", "Brown", "Williams", "Wilson", "Johnson",
            "Davies", "Robinson", "Wright", "Thompson", "Evans", "Walker", "White", "Roberts", "Green", "Hall",
            "Wood", "Jackson", "Clarke", "Patel", "Khan", "Lewis", "Morgan", "Hughes", "Campbell", "Stewart",
            "MacDonald", "McKenzie", "O'Neill", "O'Connor", "Fitzgerald", "Ahmed", "Begum", "Nowak", "Kowalski",
            "Ellis-Grant", "Price-Owen", "Ferreira", "M\u00fcller", "Br\u00e4ndstr\u00f6m", "Le Fevre", "St John",
            "Okafor", "Singh", "Chowdhury", "Murray", "Reid", "Fletcher", "Harrington"};
    private static final String[] STREETS = {"High Street", "Station Road", "Church Lane", "Victoria Road",
            "Mill Lane", "Park Avenue", "Queens Road", "The Crescent", "Orchard Close", "Kings Drive",
            "Meadow View", "Albert Terrace", "Brook Street", "Chapel Row", "Elm Grove"};
    // town, county, postcode area, district range
    private static final String[][] TOWNS = {
            {"Reading", "Berkshire", "RG", "1", "31"}, {"Leeds", "West Yorkshire", "LS", "1", "29"},
            {"Bristol", "", "BS", "1", "41"}, {"Manchester", "", "M", "1", "40"},
            {"Birmingham", "West Midlands", "B", "1", "99"}, {"Cardiff", "", "CF", "3", "24"},
            {"Norwich", "Norfolk", "NR", "1", "35"}, {"Exeter", "Devon", "EX", "1", "39"},
            {"Edinburgh", "", "EH", "1", "17"}, {"Glasgow", "", "G", "1", "84"},
            {"Aberdeen", "", "AB", "10", "25"}, {"Dundee", "", "DD", "1", "5"},
            {"Belfast", "County Antrim", "BT", "1", "17"}, {"Swansea", "", "SA", "1", "9"},
            {"Newcastle upon Tyne", "", "NE", "1", "15"}, {"Brighton", "East Sussex", "BN", "1", "3"}};
    private static final String[][] LENDERS_BY_TYPE = {
            {"CC", "CCX220", "BKA001", "CCX301"}, {"SC", "RTL031"}, {"CA", "BKA001", "BKB014"},
            {"UL", "BKA001", "BKB014"}, {"HP", "RTL031"}, {"MG", "MTG005", "BKB014"}, {"MO", "TEL009"},
            {"UT", "UTL112"}};

    private final Connection conn;
    private final Random rnd = new Random(20241231L);

    private long cnsmrSeq = 100001;
    private long addrSeq = 500001;
    private long addrHistSeq = 1;
    private long trdlnSeq = 7000001;
    private long trdlnHistSeq = 1;
    private long pubRecSeq = 1;
    private long aliasSeq = 1;
    private long ntcSeq = 1;
    private long srchSeq = 1;
    private long erSeq = 1;
    private long dsptSeq = 40001;
    private long dsptEvtSeq = 1;
    private long corrSeq = 1;
    private long acctCounter = 1000;

    /** BKA001 accounts, used to build the sample nightly file. */
    private final List<Acct> bka001Accounts = new ArrayList<Acct>();
    private final List<Long> randomConsumers = new ArrayList<Long>();

    static final class Acct {
        long cnsmrId;
        String first;
        String surname;
        LocalDate dob;
        String acctNo;
        String acctTyp;
        LocalDate openDt;
        int limit;
        long balPence;
        char sts;
        String line1;
        String town;
        String pstcd;
        LocalDate addrFrom;
    }

    public SeedDataGenerator(Connection conn) {
        this.conn = conn;
    }

    public static void main(String[] args) throws Exception {
        DbConfig cfg = new DbConfig();
        Connection c = cfg.open();
        try {
            c.setAutoCommit(false);
            if (count(c, "SELECT COUNT(*) FROM CONSUMER") > 0) {
                System.err.println("CONSUMER is not empty - run scripts/db-reset.sh to start from a clean schema");
                System.exit(2);
            }
            SeedDataGenerator g = new SeedDataGenerator(c);
            g.seedEdgeCases();
            g.seedRandomConsumers(240);
            g.seedHistoricDisputes(12);
            g.bumpSequences();
            c.commit();
            if (args.length > 0) {
                g.writeSampleFile(new File(args[0]));
                System.out.println("Sample lender file written to " + args[0]);
            }
            for (String t : new String[]{"CONSUMER", "ADDRESS", "ADDRESS_HISTORY", "ACCOUNT_TRADELINE",
                    "TRADELINE_HISTORY", "PUBLIC_RECORD", "SEARCH_FOOTPRINT", "ELECTORAL_ROLL", "DISPUTE_CASE"}) {
                System.out.println(String.format("  %-20s %6d", t, count(c, "SELECT COUNT(*) FROM " + t)));
            }
        } finally {
            c.close();
        }
    }

    // ------------------------------------------------------------------ edge cases

    void seedEdgeCases() throws SQLException {
        // 100001 status X reported before the cutoff
        long c1 = consumer("MR", "Xander", null, "Pryce", d(1975, 3, 12), 'M');
        long a1 = address("14", "Wellmeadow Road", "Reading", "Berkshire", "RG1 4QT");
        addrHist(c1, a1, d(2010, 2, 1), null, "ERL", ts(2010, 3, 1));
        er(c1, a1, d(2010, 2, 1), null);
        tradeline(c1, "CCX220", "CC", d(2011, 5, 1), null, 2000, 45000, '0', d(2024, 11, 30), 'N');
        tradeline(c1, "CCX301", "CC", d(2009, 4, 1), null, 1500, 132000, 'X', d(2013, 11, 15), 'N');

        // 100002 status X reported after the cutoff
        long c2 = consumer("MS", "Yasmin", null, "Achterberg", d(1981, 7, 30), 'F');
        long a2 = address("3", "Orchard Close", "Norwich", "Norfolk", "NR2 3HP");
        addrHist(c2, a2, d(2014, 9, 1), null, "CAI", ts(2014, 10, 2));
        er(c2, a2, d(2015, 1, 1), null);
        tradeline(c2, "RTL031", "SC", d(2015, 3, 1), null, 800, 61000, 'X', d(2016, 6, 1), 'N');
        tradeline(c2, "TEL009", "MO", d(2019, 1, 10), null, null, 2400, '0', d(2024, 11, 30), 'N');

        // 100003 status X either side of the boundary (day before / day of)
        long c3 = consumer("MR", "Owen", "Llyr", "Castellane", d(1969, 11, 2), 'M');
        long a3 = address("88", "Victoria Road", "Cardiff", "", "CF5 1JR");
        addrHist(c3, a3, d(2005, 6, 1), null, "ERL", ts(2008, 1, 5));
        er(c3, a3, d(2005, 6, 1), null);
        tradeline(c3, "TEL009", "MO", d(2012, 2, 1), null, null, 18000, 'X', d(2014, 3, 31), 'N');
        tradeline(c3, "UTL112", "UT", d(2010, 9, 1), null, null, 9500, 'X', d(2014, 4, 1), 'N');

        // 100004 status X between the code cutoff and the SYS_PARAM value
        long c4 = consumer("MRS", "Priya", null, "Kandasamy", d(1988, 1, 19), 'F');
        long a4 = address("27", "Kings Drive", "Birmingham", "West Midlands", "B15 2TT");
        addrHist(c4, a4, d(2012, 4, 1), null, "CAI", ts(2012, 4, 20));
        er(c4, a4, d(2012, 4, 1), null);
        tradeline(c4, "CCX220", "CC", d(2010, 8, 1), null, 3000, 120000, 'X', d(2014, 6, 1), 'N');

        // 100005 utilisation exactly on a band edge after rounding (749.50 -> 750 of 1000)
        long c5 = consumer("MR", "Daniel", null, "Okonkwo-Hart", d(1979, 5, 5), 'M');
        long a5 = address("5", "Brook Street", "Leeds", "West Yorkshire", "LS2 7EW");
        addrHist(c5, a5, d(2016, 3, 1), null, "ERL", ts(2016, 4, 1));
        er(c5, a5, d(2016, 3, 1), null);
        tradeline(c5, "CCX220", "CC", d(2017, 1, 15), null, 1000, 74950, '0', d(2024, 11, 30), 'N');

        // 100006 rounding of the summed balance vs per-account rounding
        long c6 = consumer("MS", "Harriet", null, "Lindqvist", d(1990, 9, 14), 'F');
        long a6 = address("41", "Park Avenue", "Bristol", "", "BS8 1TH");
        addrHist(c6, a6, d(2018, 7, 1), null, "CAI", ts(2018, 7, 9));
        er(c6, a6, d(2018, 7, 1), null);
        tradeline(c6, "CCX220", "CC", d(2018, 9, 1), null, 500, 30050, '0', d(2024, 11, 30), 'N');
        tradeline(c6, "BKA001", "CC", d(2019, 2, 1), null, 500, 44900, '0', d(2024, 11, 30), 'N');

        // 100007 half-pence-of-a-pound case: 500.50 rounds to even (500), not up (501)
        long c7 = consumer("MR", "Tomasz", null, "Brennan", d(1972, 12, 1), 'M');
        long a7 = address("9", "Mill Lane", "Exeter", "Devon", "EX4 4QJ");
        addrHist(c7, a7, d(2009, 1, 1), null, "ERL", ts(2009, 2, 1));
        er(c7, a7, d(2009, 1, 1), null);
        tradeline(c7, "CCX220", "CC", d(2013, 6, 1), null, 1002, 50050, '0', d(2024, 11, 30), 'N');

        // 100008-100011 names with diacritics; the lender file sends them without
        long c8 = consumer("MS", "Siobh\u00e1n", null, "\u00d3 Briain", d(1984, 2, 29), 'F');
        long a8 = address("12", "Chapel Row", "Belfast", "County Antrim", "BT7 1NN");
        addrHist(c8, a8, d(2017, 10, 1), null, "ERL", ts(2017, 11, 1));
        er(c8, a8, d(2017, 10, 1), null);
        tradeline(c8, "BKB014", "CA", d(2017, 11, 1), null, 500, 12000, '0', d(2024, 11, 30), 'N');

        long c9 = consumer("MRS", "Ren\u00e9e", null, "Dubois-Marchand", d(1966, 4, 21), 'F');
        long a9 = address("70", "Queens Road", "Brighton", "East Sussex", "BN1 3XE");
        addrHist(c9, a9, d(2003, 5, 1), null, "ERL", ts(2005, 1, 1));
        er(c9, a9, d(2003, 5, 1), null);
        tradeline(c9, "MTG005", "MG", d(2003, 5, 1), null, null, 8650000, '0', d(2024, 11, 30), 'N');
        alias(c9, "Ren\u00e9e", "Dubois", "MN");

        long c10 = consumer("MR", "\u0141ukasz", null, "Wi\u015bniewski", d(1992, 8, 8), 'M');
        long a10 = address("101", "Station Road", "Manchester", "", "M14 5RQ");
        addrHist(c10, a10, d(2020, 1, 15), null, "CAI", ts(2020, 2, 1));
        tradeline(c10, "TEL009", "MO", d(2020, 2, 1), null, null, 3500, '0', d(2024, 11, 30), 'N');

        // 100011 address history: same address reported twice with the same from-date
        long c11 = consumer("MRS", "Margaret", "Anne", "Strau\u00df", d(1958, 10, 10), 'F');
        long a11a = address("12", "Elm Grove", "Leeds", "West Yorkshire", "LS6 2AB");
        long a11b = address("4", "Albert Terrace", "Leeds", "West Yorkshire", "LS4 2HR");
        addrHist(c11, a11b, d(2012, 8, 1), d(2019, 4, 30), "CAI", ts(2012, 9, 3));
        addrHist(c11, a11b, d(2012, 9, 15), d(2019, 4, 30), "MAN", ts(2013, 2, 11));
        addrHist(c11, a11a, d(2019, 5, 1), null, "ERL", ts(2019, 6, 1));
        addrHist(c11, a11a, d(2019, 5, 1), d(2023, 1, 1), "CAI", ts(2021, 3, 10));
        er(c11, a11a, d(2019, 5, 1), null);
        tradeline(c11, "BKB014", "CA", d(1990, 4, 1), null, 250, 0, '0', d(2024, 11, 30), 'N');

        // 100012 Scottish address (SC bank holidays apply to disputes)
        long c12 = consumer("MR", "Callum", null, "MacLeod", d(1983, 3, 3), 'M');
        long a12 = address("22", "The Crescent", "Edinburgh", "", "EH3 9QG");
        addrHist(c12, a12, d(2011, 8, 1), null, "ERL", ts(2011, 9, 1));
        er(c12, a12, d(2011, 8, 1), null);
        tradeline(c12, "CCX220", "CC", d(2012, 1, 1), null, 5000, 64000, '1', d(2024, 11, 30), 'N');

        // 100013 English address (EW bank holidays)
        long c13 = consumer("MS", "Grace", null, "Whitfield", d(1995, 6, 25), 'F');
        long a13 = address("6", "Meadow View", "Bristol", "", "BS1 5TR");
        addrHist(c13, a13, d(2021, 9, 1), null, "CAI", ts(2021, 9, 20));
        er(c13, a13, d(2021, 9, 1), null);
        tradeline(c13, "RTL031", "SC", d(2022, 3, 1), null, 1200, 30000, '0', d(2024, 11, 30), 'N');

        // 100014 public records: one unsatisfied, one satisfied CCJ
        long c14 = consumer("MR", "Kevin", null, "Doyle", d(1970, 1, 15), 'M');
        long a14 = address("19", "Church Lane", "Swansea", "", "SA1 2BX");
        addrHist(c14, a14, d(2015, 2, 1), null, "CAI", ts(2015, 2, 20));
        tradeline(c14, "UTL112", "UT", d(2015, 2, 1), null, null, 21000, '3', d(2024, 11, 30), 'N');
        pubRec(c14, "CCJ", "CCMC", "K9QZ12A4", d(2021, 8, 10), new BigDecimal("1240.00"), null);
        pubRec(c14, "CCJ", "CRDF", "F2CF55B1", d(2019, 2, 1), new BigDecimal("560.00"), d(2019, 5, 1));

        // 100015 thin file, no tradelines at all
        long c15 = consumer("MISS", "Amelia", null, "Hart", d(2003, 10, 10), 'F');
        long a15 = address("2", "Orchard Close", "Exeter", "Devon", "EX2 8LB");
        addrHist(c15, a15, d(2022, 9, 1), null, "ERL", ts(2022, 10, 1));
        er(c15, a15, d(2022, 9, 1), null);

        // 100016 tradeline under an open dispute (lender updates are held)
        long c16 = consumer("MR", "Rajesh", null, "Menon", d(1977, 2, 14), 'M');
        long a16 = address("55", "High Street", "Reading", "Berkshire", "RG4 8AA");
        addrHist(c16, a16, d(2013, 3, 1), null, "ERL", ts(2013, 4, 1));
        er(c16, a16, d(2013, 3, 1), null);
        Acct disputed = new Acct();
        long t16 = tradeline(c16, "BKA001", "CC", d(2014, 7, 1), null, 4000, 250000, '2', d(2024, 11, 30), 'Y');
        disputed.cnsmrId = c16;
        long d16 = dsptSeq++;
        exec("INSERT INTO DISPUTE_CASE (DSPT_ID, CNSMR_ID, TRDLN_ID, PUB_REC_ID, RSN_CD, CHNL_CD, RCVD_TS, SLA_DUE_DT, "
                        + "STS_CD, OUTCOME_CD, RSLVD_TS, RSLVD_BY) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                d16, c16, t16, null, "WRONGSTS", "WEB", ts(2024, 12, 20, 10, 15), sqlDate(d(2025, 1, 22)),
                "OPEN", null, null, null);
        dsptEvent(d16, "OPENED", ts(2024, 12, 20, 10, 15), null, "Customer says arrears were cleared in October");
        corr(d16, "ACK01", ts(2024, 12, 20, 18, 0), "WEB");
    }

    // ------------------------------------------------------------------ random population

    void seedRandomConsumers(int n) throws SQLException {
        for (int i = 0; i < n; i++) {
            boolean male = rnd.nextBoolean();
            String first = male ? pick(MALE) : pick(FEMALE);
            String surname = pick(SURNAMES);
            LocalDate dob = d(1945 + rnd.nextInt(60), 1 + rnd.nextInt(12), 1 + rnd.nextInt(28));
            String title = male ? "MR" : (rnd.nextInt(3) == 0 ? "MS" : (rnd.nextBoolean() ? "MRS" : "MISS"));
            long cid = consumer(title, first, rnd.nextInt(4) == 0 ? (male ? pick(MALE) : pick(FEMALE)) : null,
                    surname, dob, male ? 'M' : 'F');
            randomConsumers.add(cid);

            // address history: 1-3 addresses, most recent open-ended
            int addrCount = 1 + rnd.nextInt(3);
            LocalDate from = AS_OF.minusDays(200 + rnd.nextInt(4000));
            LocalDate to = null;
            long currentAddr = 0;
            String[] currentTown = null;
            String currentLine1 = null;
            String currentPstcd = null;
            LocalDate currentFrom = null;
            for (int a = 0; a < addrCount; a++) {
                String[] town = TOWNS[rnd.nextInt(TOWNS.length)];
                String no = String.valueOf(1 + rnd.nextInt(180));
                String street = pick(STREETS);
                String pc = postcode(town);
                long addr = address(no, street, town[0], town[1], pc);
                String src = rnd.nextInt(3) == 0 ? "CAI" : "ERL";
                LocalDateTime crtd = from.plusDays(5 + rnd.nextInt(60)).atTime(2, 0);
                addrHist(cid, addr, from, to, src, Timestamp.valueOf(crtd));
                if (a == 0) {
                    currentAddr = addr;
                    currentTown = town;
                    currentLine1 = no + " " + street;
                    currentPstcd = pc;
                    currentFrom = from;
                    if (rnd.nextInt(12) == 0) {
                        // duplicate report of the same move from the other source
                        LocalDate dupFrom = rnd.nextBoolean() ? from : from.plusDays(1 + rnd.nextInt(40));
                        addrHist(cid, addr, dupFrom, null, "CAI".equals(src) ? "ERL" : "CAI",
                                Timestamp.valueOf(crtd.plusDays(30 + rnd.nextInt(400))));
                    }
                    if (rnd.nextInt(10) < 8) {
                        er(cid, addr, from, null);
                    }
                }
                to = from.minusDays(1);
                from = to.minusDays(300 + rnd.nextInt(2500));
            }

            // tradelines
            int tlCount = rnd.nextInt(10) == 0 ? 0 : 1 + rnd.nextInt(6);
            for (int t = 0; t < tlCount; t++) {
                String[] lt = LENDERS_BY_TYPE[weightedType()];
                String typ = lt[0];
                String lndr = lt[1 + rnd.nextInt(lt.length - 1)];
                LocalDate open = AS_OF.minusDays(90 + rnd.nextInt(5000));
                Integer limit = null;
                long bal;
                if ("CC".equals(typ) || "SC".equals(typ) || "CA".equals(typ)) {
                    limit = ("CA".equals(typ) ? 100 : 250) * (1 + rnd.nextInt(30));
                    bal = (long) (rnd.nextDouble() * limit * 100 * 1.05);
                } else if ("MG".equals(typ)) {
                    bal = 2000000L * 100 / 20 + rnd.nextInt(30000000);
                } else if ("UL".equals(typ) || "HP".equals(typ)) {
                    bal = rnd.nextInt(1500000);
                } else {
                    bal = rnd.nextInt(30000);
                }
                char sts = status();
                LocalDate stsDt = d(2024, 11, 30);
                LocalDate close = null;
                if (sts == 'S') {
                    bal = 0;
                    close = AS_OF.minusDays(30 + rnd.nextInt(1500));
                    stsDt = close;
                } else if (sts == 'X' || sts == '8') {
                    stsDt = d(2010 + rnd.nextInt(11), 1 + rnd.nextInt(12), 1 + rnd.nextInt(28));
                    if (stsDt.isBefore(open)) {
                        open = stsDt.minusDays(400);
                    }
                }
                char del = rnd.nextInt(100) == 0 ? 'Y' : 'N';
                String acctNo = acctNo(lndr);
                long tid = tradeline(cid, lndr, acctNo, typ, open, close, limit, bal, sts, stsDt, 'N', del);
                for (int m = 3; m >= 1; m--) {
                    tlHist(tid, AS_OF.withDayOfMonth(1).minusMonths(m).minusDays(1), sts == 'S' ? '0' : sts,
                            Math.max(0, bal + (rnd.nextInt(20000) - 10000)), limit);
                }
                if ("BKA001".equals(lndr) && close == null && del == 'N') {
                    Acct acct = new Acct();
                    acct.cnsmrId = cid;
                    acct.first = first;
                    acct.surname = surname;
                    acct.dob = dob;
                    acct.acctNo = acctNo;
                    acct.acctTyp = typ;
                    acct.openDt = open;
                    acct.limit = limit == null ? 0 : limit;
                    acct.balPence = bal;
                    acct.sts = sts;
                    acct.line1 = currentLine1;
                    acct.town = currentTown[0];
                    acct.pstcd = currentPstcd;
                    acct.addrFrom = currentFrom;
                    bka001Accounts.add(acct);
                }
            }

            int searches = rnd.nextInt(6);
            for (int s = 0; s < searches; s++) {
                search(cid, LENDERS_BY_TYPE[rnd.nextInt(LENDERS_BY_TYPE.length)][1], rnd.nextInt(3) == 0 ? 'S' : 'H',
                        AS_OF.minusDays(rnd.nextInt(720)));
            }
            if (rnd.nextInt(25) == 0) {
                boolean sat = rnd.nextBoolean();
                LocalDate jd = AS_OF.minusDays(100 + rnd.nextInt(2000));
                boolean scot = "EH".equals(currentTown[2]) || "G".equals(currentTown[2]) || "AB".equals(currentTown[2])
                        || "DD".equals(currentTown[2]);
                pubRec(cid, scot ? "DEC" : "CCJ", scot ? "GLSH" : "CCMC", caseRef(), jd,
                        new BigDecimal(200 + rnd.nextInt(8000)).setScale(2), sat ? jd.plusDays(60 + rnd.nextInt(300)) : null);
            } else if (rnd.nextInt(80) == 0) {
                pubRec(cid, rnd.nextBoolean() ? "IVA" : "BKY", "INSV", caseRef(), AS_OF.minusDays(rnd.nextInt(1800)),
                        null, null);
            }
            if (!male && rnd.nextInt(20) == 0) {
                alias(cid, first, pick(SURNAMES), "MN");
            }
            if (rnd.nextInt(60) == 0) {
                notice(cid, "The account with " + "Kestrel Card Services" + " was opened fraudulently in my name.");
            }
            if (currentAddr == 0) {
                throw new IllegalStateException("no address");
            }
        }
    }

    void seedHistoricDisputes(int n) throws SQLException {
        String[] reasons = {"NOTMINE", "WRONGBAL", "WRONGSTS", "PAIDOFF"};
        String[] outcomes = {"AMEND", "DELETE", "NOCHANGE", "NOCHANGE"};
        for (int i = 0; i < n; i++) {
            long cid = randomConsumers.get(rnd.nextInt(randomConsumers.size()));
            Long tid = firstTradeline(cid);
            LocalDateTime rcvd = LocalDateTime.of(2019 + rnd.nextInt(5), 1 + rnd.nextInt(12), 1 + rnd.nextInt(28),
                    8 + rnd.nextInt(10), rnd.nextInt(60));
            // back-filled from the old case system as received + 28 days
            LocalDate due = rcvd.toLocalDate().plusDays(28);
            LocalDateTime rslvd = rcvd.plusDays(3 + rnd.nextInt(25));
            String opr = rnd.nextBoolean() ? "OPS0002" : "OPS0003";
            long id = dsptSeq++;
            exec("INSERT INTO DISPUTE_CASE (DSPT_ID, CNSMR_ID, TRDLN_ID, PUB_REC_ID, RSN_CD, CHNL_CD, RCVD_TS, SLA_DUE_DT, "
                            + "STS_CD, OUTCOME_CD, RSLVD_TS, RSLVD_BY) VALUES (?,?,?,?,?,?,?,?,?,?,?,?)",
                    id, cid, tid, null, pick(reasons), rnd.nextBoolean() ? "WEB" : "TEL", Timestamp.valueOf(rcvd),
                    sqlDate(due), "CLOSED", pick(outcomes), Timestamp.valueOf(rslvd), opr);
            dsptEvent(id, "OPENED", Timestamp.valueOf(rcvd), null, null);
            dsptEvent(id, "CLOSED", Timestamp.valueOf(rslvd), opr, null);
            corr(id, "ACK01", Timestamp.valueOf(rcvd.plusHours(2)), "PST");
            corr(id, "RES01", Timestamp.valueOf(rslvd.plusHours(1)), "PST");
        }
    }

    void bumpSequences() throws SQLException {
        restart("CNSMR_SEQ", cnsmrSeq);
        restart("ADDR_SEQ", addrSeq);
        restart("ADDR_HIST_SEQ", addrHistSeq);
        restart("TRDLN_SEQ", trdlnSeq);
        restart("TRDLN_HIST_SEQ", trdlnHistSeq);
        restart("PUB_REC_SEQ", pubRecSeq);
        restart("ALIAS_SEQ", aliasSeq);
        restart("NTC_SEQ", ntcSeq);
        restart("SRCH_SEQ", srchSeq);
        restart("ER_SEQ", erSeq);
        restart("DSPT_SEQ", dsptSeq);
        restart("DSPT_EVT_SEQ", dsptEvtSeq);
        restart("CORR_SEQ", corrSeq);
    }

    // ------------------------------------------------------------------ sample nightly lender file

    void writeSampleFile(File f) throws Exception {
        f.getParentFile().mkdirs();
        // lender files are ISO-8859-1, not UTF-8
        Writer w = new OutputStreamWriter(new FileOutputStream(f), Charset.forName("ISO-8859-1"));
        try {
            int count = 0;
            w.write(pad("HDR" + "BKA001" + "20250101" + "000417", 240) + "\n");
            int updates = Math.min(25, bka001Accounts.size());
            for (int i = 0; i < updates; i++) {
                Acct a = bka001Accounts.get(i);
                long newBal = a.limit > 0 ? Math.max(0, a.balPence + (i % 3 == 0 ? -5000 : 2750))
                        : Math.max(0, a.balPence - 12000);
                char sts = a.sts == 'S' ? '0' : (i % 7 == 3 && a.sts == '0' ? '1' : a.sts);
                w.write(detail(a.acctNo, a.acctTyp, a.surname, a.first, a.dob, a.pstcd, a.openDt, null, a.limit,
                        newBal, sts, d(2024, 12, 31), a.addrFrom, a.line1, a.town) + "\n");
                count++;
            }
            // update for the tradeline under dispute (100016): must be held, not applied
            w.write(detail("4000000000000016", "CC", "MENON", "RAJESH", d(1977, 2, 14), "RG4 8AA", d(2014, 7, 1), null,
                    4000, 0, '0', d(2024, 12, 31), d(2013, 3, 1), "55 High Street", "Reading") + "\n");
            count++;
            // new accounts for existing consumers, names sent without (or with Latin-1) accents
            w.write(detail("4000000000900008", "CC", "O'BRIAIN", "SIOBHAN", d(1984, 2, 29), "BT7 1NN", d(2024, 12, 1),
                    null, 1500, 22000, '0', d(2024, 12, 31), d(2017, 10, 1), "12 Chapel Row", "Belfast") + "\n");
            w.write(detail("4000000000900009", "UL", "DUBOIS MARCHAND", "REN\u00c9E", d(1966, 4, 21), "BN1 3XE",
                    d(2024, 11, 20), null, 0, 750000, '0', d(2024, 12, 31), d(2003, 5, 1), "70 Queens Road", "Brighton")
                    + "\n");
            w.write(detail("4000000000900010", "CA", "WISNIEWSKI", "LUKASZ", d(1992, 8, 8), "M14 5RQ", d(2024, 12, 5),
                    null, 300, 4599, '0', d(2024, 12, 31), d(2020, 1, 15), "101 Station Road", "Manchester") + "\n");
            // existing consumer reporting a new address
            w.write(detail("4000000000900011", "CC", "STRAUSS", "MARGARET", d(1958, 10, 10), "LS17 6PE",
                    d(2024, 12, 10), null, 2000, 0, '0', d(2024, 12, 31), d(2024, 11, 1), "8 Harewood Avenue", "Leeds")
                    + "\n");
            // brand-new consumer
            w.write(detail("4000000000900099", "CC", "PENROSE", "OLIVIA", d(1999, 1, 1), "EX1 2LU", d(2024, 12, 15),
                    null, 1000, 15000, '0', d(2024, 12, 31), d(2023, 6, 1), "3 Bampfylde Street", "Exeter") + "\n");
            count += 5;
            // malformed record (bad status date) -> BATCH_REJECT
            String bad = detail("4000000000900666", "CC", "BLOGGS", "JOE", d(1980, 1, 1), "B1 1AA", d(2024, 12, 1),
                    null, 500, 100, '0', d(2024, 12, 31), d(2020, 1, 1), "1 Test Street", "Birmingham");
            w.write(bad.substring(0, 130) + "20241340" + bad.substring(138) + "\n");
            count++;
            w.write(pad("TRL" + String.format("%08d", count), 240) + "\n");
        } finally {
            w.close();
        }
    }

    /** Field layout: see batch-ingest/README.md. */
    static String detail(String acctNo, String typ, String surname, String first, LocalDate dob, String pstcd,
                         LocalDate open, LocalDate close, int limit, long balPence, char sts, LocalDate stsDt,
                         LocalDate addrFrom, String line1, String town) {
        StringBuilder sb = new StringBuilder();
        sb.append("DTL");
        sb.append(pad(acctNo, 20));
        sb.append(pad(typ, 2));
        sb.append(pad(surname.toUpperCase(), 30));
        sb.append(pad(first.toUpperCase(), 20));
        sb.append(dob.format(YMD));
        sb.append(pad(pstcd, 10));
        sb.append(open.format(YMD));
        sb.append(close == null ? "00000000" : close.format(YMD));
        sb.append(String.format("%08d", limit));
        sb.append(balPence < 0 ? '-' : '+');
        sb.append(String.format("%011d", Math.abs(balPence)));
        sb.append(sts);
        sb.append(stsDt.format(YMD));
        sb.append(pad(sts == '0' ? "000000000000000000000000" : sts + "00000000000000000000000", 24));
        sb.append(addrFrom.format(YMD));
        sb.append(pad(line1.toUpperCase(), 40));
        sb.append(pad(town.toUpperCase(), 30));
        return sb.toString();
    }

    // ------------------------------------------------------------------ inserts

    long consumer(String title, String first, String mid, String sur, LocalDate dob, char gender) throws SQLException {
        long id = cnsmrSeq++;
        exec("INSERT INTO CONSUMER (CNSMR_ID, TITLE_CD, FRST_NM, MID_NM, SURNM, DOB, GNDR_CD, MATCH_KEY, STS_CD, CRTD_TS)"
                        + " VALUES (?,?,?,?,?,?,?,?,?,?)",
                id, title, first, mid, sur, sqlDate(dob), String.valueOf(gender), NameNormaliser.matchKey(sur, dob, first),
                "A", Timestamp.valueOf(LOAD_TS));
        return id;
    }

    long address(String no, String line1, String town, String county, String pstcd) throws SQLException {
        long id = addrSeq++;
        exec("INSERT INTO ADDRESS (ADDR_ID, BLDG_NO, BLDG_NM, LINE1, LINE2, TOWN, CNTY, PSTCD, UDPRN, CRTD_TS)"
                        + " VALUES (?,?,?,?,?,?,?,?,?,?)",
                id, no, null, no + " " + line1, null, town, county.isEmpty() ? null : county, pstcd,
                String.valueOf(10000000 + id), Timestamp.valueOf(LOAD_TS));
        return id;
    }

    void addrHist(long cnsmr, long addr, LocalDate from, LocalDate to, String src, Timestamp crtd) throws SQLException {
        exec("INSERT INTO ADDRESS_HISTORY (ADDR_HIST_ID, CNSMR_ID, ADDR_ID, DT_FROM, DT_TO, ADDR_SRC_CD, CRTD_TS)"
                + " VALUES (?,?,?,?,?,?,?)", addrHistSeq++, cnsmr, addr, sqlDate(from), sqlDate(to), src, crtd);
    }

    long tradeline(long cnsmr, String lndr, String typ, LocalDate open, LocalDate close, Integer limit, long bal,
                   char sts, LocalDate stsDt, char dspt) throws SQLException {
        String acctNo = cnsmr == 100016 ? "4000000000000016" : acctNo(lndr);
        return tradeline(cnsmr, lndr, acctNo, typ, open, close, limit, bal, sts, stsDt, dspt, 'N');
    }

    long tradeline(long cnsmr, String lndr, String acctNo, String typ, LocalDate open, LocalDate close, Integer limit,
                   long bal, char sts, LocalDate stsDt, char dspt, char del) throws SQLException {
        long id = trdlnSeq++;
        exec("INSERT INTO ACCOUNT_TRADELINE (TRDLN_ID, CNSMR_ID, LNDR_REF_CD, ACCT_NO_HASH, ACCT_TYP_CD, OPEN_DT, CLOSE_DT,"
                        + " CR_LMT_AMT, CURR_BAL_PNC, ACCT_STS_CD, ACCT_STS_DT, PYMT_PRFL, DEL_FLG, LAST_UPD_BATCH_ID,"
                        + " CRTD_TS, DSPT_FLG) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,?,?,?,?)",
                id, cnsmr, lndr, AccountHash.hash(lndr, acctNo), typ, sqlDate(open), sqlDate(close), limit, bal,
                String.valueOf(sts), sqlDate(stsDt), profile(sts), String.valueOf(del), null, Timestamp.valueOf(LOAD_TS),
                String.valueOf(dspt));
        return id;
    }

    void tlHist(long trdln, LocalDate snap, char sts, long bal, Integer limit) throws SQLException {
        exec("INSERT INTO TRADELINE_HISTORY (TRDLN_HIST_ID, TRDLN_ID, SNAP_DT, ACCT_STS_CD, CURR_BAL_PNC, CR_LMT_AMT, BATCH_ID)"
                + " VALUES (?,?,?,?,?,?,?)", trdlnHistSeq++, trdln, sqlDate(snap), String.valueOf(sts), bal, limit, null);
    }

    void pubRec(long cnsmr, String typ, String crt, String ref, LocalDate jdgmt, BigDecimal amt, LocalDate sat)
            throws SQLException {
        exec("INSERT INTO PUBLIC_RECORD (PUB_REC_ID, CNSMR_ID, REC_TYP_CD, CRT_CD, CASE_REF, JDGMT_DT, JDGMT_AMT, SATSFD_DT)"
                + " VALUES (?,?,?,?,?,?,?,?)", pubRecSeq++, cnsmr, typ, crt, ref, sqlDate(jdgmt), amt, sqlDate(sat));
    }

    void search(long cnsmr, String lndr, char typ, LocalDate dt) throws SQLException {
        exec("INSERT INTO SEARCH_FOOTPRINT (SRCH_ID, CNSMR_ID, LNDR_REF_CD, SRCH_TYP_CD, SRCH_DT) VALUES (?,?,?,?,?)",
                srchSeq++, cnsmr, lndr, String.valueOf(typ), sqlDate(dt));
    }

    void er(long cnsmr, long addr, LocalDate from, LocalDate to) throws SQLException {
        exec("INSERT INTO ELECTORAL_ROLL (ER_ID, CNSMR_ID, ADDR_ID, DT_FROM, DT_TO) VALUES (?,?,?,?,?)",
                erSeq++, cnsmr, addr, sqlDate(from), sqlDate(to));
    }

    void alias(long cnsmr, String first, String sur, String typ) throws SQLException {
        exec("INSERT INTO CONSUMER_ALIAS (ALIAS_ID, CNSMR_ID, FRST_NM, SURNM, ALIAS_TYP_CD, CRTD_TS) VALUES (?,?,?,?,?,?)",
                aliasSeq++, cnsmr, first, sur, typ, Timestamp.valueOf(LOAD_TS));
    }

    void notice(long cnsmr, String txt) throws SQLException {
        exec("INSERT INTO CONSUMER_NOTICE (NTC_ID, CNSMR_ID, NTC_TXT, CRTD_DT, EXP_DT) VALUES (?,?,?,?,?)",
                ntcSeq++, cnsmr, txt, sqlDate(AS_OF.minusDays(rnd.nextInt(700))), null);
    }

    void dsptEvent(long dspt, String typ, Timestamp at, String opr, String note) throws SQLException {
        exec("INSERT INTO DISPUTE_EVENT (DSPT_EVT_ID, DSPT_ID, EVT_TYP_CD, EVT_TS, OPR_ID, NOTE_TXT) VALUES (?,?,?,?,?,?)",
                dsptEvtSeq++, dspt, typ, at, opr, note);
    }

    void corr(long dspt, String tmpl, Timestamp at, String chnl) throws SQLException {
        exec("INSERT INTO DISPUTE_CORRESPONDENCE (CORR_ID, DSPT_ID, LTR_TMPL_CD, SENT_TS, CHNL_CD) VALUES (?,?,?,?,?)",
                corrSeq++, dspt, tmpl, at, chnl);
    }

    // ------------------------------------------------------------------ helpers

    private Long firstTradeline(long cnsmr) throws SQLException {
        PreparedStatement ps = conn.prepareStatement(
                "SELECT MIN(TRDLN_ID) FROM ACCOUNT_TRADELINE WHERE CNSMR_ID = ?");
        try {
            ps.setLong(1, cnsmr);
            ResultSet rs = ps.executeQuery();
            rs.next();
            long v = rs.getLong(1);
            return rs.wasNull() ? null : v;
        } finally {
            ps.close();
        }
    }

    private void restart(String seq, long next) throws SQLException {
        Statement st = conn.createStatement();
        try {
            st.execute("ALTER SEQUENCE " + seq + " RESTART WITH " + next);
        } finally {
            st.close();
        }
    }

    private void exec(String sql, Object... params) throws SQLException {
        PreparedStatement ps = conn.prepareStatement(sql);
        try {
            for (int i = 0; i < params.length; i++) {
                Object p = params[i];
                if (p == null) {
                    ps.setNull(i + 1, Types.NULL);
                } else {
                    ps.setObject(i + 1, p);
                }
            }
            ps.executeUpdate();
        } finally {
            ps.close();
        }
    }

    static long count(Connection c, String sql) throws SQLException {
        Statement st = c.createStatement();
        try {
            ResultSet rs = st.executeQuery(sql);
            rs.next();
            return rs.getLong(1);
        } finally {
            st.close();
        }
    }

    private String acctNo(String lndr) {
        acctCounter++;
        String prefix = lndr.startsWith("CC") ? "4929" : lndr.startsWith("BK") ? "4000" : "8800";
        return prefix + String.format("%012d", acctCounter * 7919 % 1000000000000L);
    }

    private int weightedType() {
        int r = rnd.nextInt(100);
        if (r < 35) {
            return 0;
        } else if (r < 45) {
            return 1;
        } else if (r < 60) {
            return 2;
        } else if (r < 70) {
            return 3;
        } else if (r < 75) {
            return 4;
        } else if (r < 83) {
            return 5;
        } else if (r < 93) {
            return 6;
        }
        return 7;
    }

    private char status() {
        int r = rnd.nextInt(100);
        if (r < 70) {
            return '0';
        } else if (r < 78) {
            return (char) ('1' + rnd.nextInt(3));
        } else if (r < 81) {
            return (char) ('4' + rnd.nextInt(3));
        } else if (r < 85) {
            return '8';
        } else if (r < 92) {
            return 'S';
        } else if (r < 97) {
            return 'X';
        }
        return rnd.nextBoolean() ? 'D' : 'U';
    }

    private static String profile(char sts) {
        StringBuilder sb = new StringBuilder();
        sb.append(sts);
        for (int i = 1; i < 24; i++) {
            sb.append(sts == '0' || sts == 'S' ? '0' : (i < 3 ? sts : '0'));
        }
        return sb.toString();
    }

    private String postcode(String[] town) {
        int lo = Integer.parseInt(town[3]);
        int hi = Integer.parseInt(town[4]);
        String letters = "ABDEFGHJLNPQRSTUWXYZ";
        return town[2] + (lo + rnd.nextInt(hi - lo + 1)) + " " + rnd.nextInt(10)
                + letters.charAt(rnd.nextInt(letters.length())) + letters.charAt(rnd.nextInt(letters.length()));
    }

    private String caseRef() {
        String chars = "ABCDEFGHJKLMNPQRSTUVWXYZ0123456789";
        StringBuilder sb = new StringBuilder();
        for (int i = 0; i < 8; i++) {
            sb.append(chars.charAt(rnd.nextInt(chars.length())));
        }
        return sb.toString();
    }

    private <T> T pick(T[] arr) {
        return arr[rnd.nextInt(arr.length)];
    }

    static String pad(String s, int len) {
        if (s.length() >= len) {
            return s.substring(0, len);
        }
        StringBuilder sb = new StringBuilder(s);
        while (sb.length() < len) {
            sb.append(' ');
        }
        return sb.toString();
    }

    static LocalDate d(int y, int m, int day) {
        return LocalDate.of(y, m, day);
    }

    static Timestamp ts(int y, int m, int day) {
        return Timestamp.valueOf(LocalDateTime.of(y, m, day, 2, 0));
    }

    static Timestamp ts(int y, int m, int day, int h, int min) {
        return Timestamp.valueOf(LocalDateTime.of(y, m, day, h, min));
    }

    static java.sql.Date sqlDate(LocalDate d) {
        return d == null ? null : java.sql.Date.valueOf(d);
    }
}
