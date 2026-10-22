package com.ukcredit.batch;

import com.ukcredit.common.AccountHash;
import com.ukcredit.common.NameNormaliser;
import com.ukcredit.creditfile.domain.Consumer;
import com.ukcredit.creditfile.service.ConsumerMatchService;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.transaction.TransactionStatus;
import org.springframework.transaction.support.TransactionCallback;
import org.springframework.transaction.support.TransactionTemplate;

import java.io.BufferedReader;
import java.io.File;
import java.io.FileInputStream;
import java.io.InputStreamReader;
import java.nio.charset.Charset;
import java.sql.Date;
import java.sql.Timestamp;
import java.time.LocalDate;
import java.time.format.DateTimeFormatter;
import java.util.List;
import java.util.Map;

/**
 * Loads a lender file into ACCOUNT_TRADELINE. One transaction per record so a bad record
 * cannot roll back the rest of the file.
 */
public class LenderFileLoader {

    private static final Logger LOG = LoggerFactory.getLogger(LenderFileLoader.class);
    static final Charset LENDER_CHARSET = Charset.forName("ISO-8859-1");

    static final String HELD_REASON = "HELD: tradeline under dispute";

    private JdbcTemplate jdbcTemplate;
    private TransactionTemplate transactionTemplate;
    private LenderFileParser parser;
    private ConsumerMatchService consumerMatchService;

    private enum Outcome { UPDATED, CREATED, HELD }

    public boolean load(File file) throws Exception {
        final long batchId = nextval("BATCH_SEQ");
        jdbcTemplate.update("INSERT INTO BATCH_RUN_LOG (BATCH_ID, FILE_NM, START_TS, STS_CD) VALUES (?,?,?,'RUNNING')",
                batchId, file.getName(), now());
        LOG.info("batch {} loading {}", batchId, file);

        int read = 0, loaded = 0, rejected = 0, held = 0, created = 0, lineNo = 0;
        Integer trailerCount = null;
        String lender = null;
        LocalDate fileDt = null;
        BufferedReader in = new BufferedReader(new InputStreamReader(new FileInputStream(file), LENDER_CHARSET));
        try {
            String line;
            while ((line = in.readLine()) != null) {
                lineNo++;
                if (line.startsWith("HDR")) {
                    lender = line.substring(3, 9).trim();
                    fileDt = LocalDate.parse(line.substring(9, 17), DateTimeFormatter.BASIC_ISO_DATE);
                    jdbcTemplate.update("UPDATE BATCH_RUN_LOG SET SRC_LNDR_REF_CD = ? WHERE BATCH_ID = ?", lender, batchId);
                    continue;
                }
                if (line.startsWith("TRL")) {
                    trailerCount = Integer.valueOf(line.substring(3, 11));
                    continue;
                }
                if (!line.startsWith("DTL")) {
                    if (line.trim().length() > 0) {
                        reject(batchId, lineNo, line, "unknown record type");
                        rejected++;
                    }
                    continue;
                }
                read++;
                if (lender == null) {
                    reject(batchId, lineNo, line, "DTL before HDR");
                    rejected++;
                    continue;
                }
                final LenderRecord rec;
                try {
                    rec = parser.parseDetail(line);
                } catch (LenderFileParser.RecordException e) {
                    reject(batchId, lineNo, line, e.getMessage());
                    rejected++;
                    continue;
                }
                try {
                    Outcome o = apply(batchId, lender, fileDt, rec);
                    if (o == Outcome.HELD) {
                        reject(batchId, lineNo, line, HELD_REASON);
                        held++;
                        rejected++;
                    } else {
                        loaded++;
                        if (o == Outcome.CREATED) {
                            created++;
                        }
                    }
                } catch (RejectException e) {
                    reject(batchId, lineNo, line, e.getMessage());
                    rejected++;
                } catch (RuntimeException e) {
                    LOG.error("line {} failed", lineNo, e);
                    reject(batchId, lineNo, line, "load error: " + e.getMessage());
                    rejected++;
                }
            }
        } finally {
            in.close();
        }

        String sts = "COMPLETE";
        if (trailerCount == null) {
            LOG.warn("batch {}: no trailer record", batchId);
            sts = "WARN";
        } else if (trailerCount != read) {
            LOG.warn("batch {}: trailer count {} does not match {} detail records", batchId, trailerCount, read);
            sts = "WARN";
        }
        jdbcTemplate.update("UPDATE BATCH_RUN_LOG SET END_TS = ?, REC_READ = ?, REC_LOADED = ?, REC_REJECTED = ?, STS_CD = ?"
                + " WHERE BATCH_ID = ?", now(), read, loaded, rejected, sts, batchId);
        LOG.info("batch {} {}: read={} loaded={} (new tradelines={}) rejected={} (held={}) trailer={}",
                batchId, sts, read, loaded, created, rejected, held, trailerCount);
        return lender != null;
    }

    private Outcome apply(final long batchId, final String lender, final LocalDate fileDt, final LenderRecord r) {
        return transactionTemplate.execute(new TransactionCallback<Outcome>() {
            public Outcome doInTransaction(TransactionStatus status) {
                String hash = AccountHash.hash(lender, r.acctNo);
                List<Map<String, Object>> existing = jdbcTemplate.queryForList("SELECT TRDLN_ID, CNSMR_ID, DSPT_FLG,"
                        + " ACCT_STS_CD, CURR_BAL_PNC, CR_LMT_AMT FROM ACCOUNT_TRADELINE WHERE LNDR_REF_CD = ? AND ACCT_NO_HASH = ?",
                        lender, hash);
                if (!existing.isEmpty()) {
                    Map<String, Object> t = existing.get(0);
                    if ("Y".equals(String.valueOf(t.get("DSPT_FLG")).trim())) {
                        return Outcome.HELD;
                    }
                    long trdlnId = ((Number) t.get("TRDLN_ID")).longValue();
                    jdbcTemplate.update("INSERT INTO TRADELINE_HISTORY (TRDLN_HIST_ID, TRDLN_ID, SNAP_DT, ACCT_STS_CD,"
                                    + " CURR_BAL_PNC, CR_LMT_AMT, BATCH_ID) VALUES (?,?,?,?,?,?,?)",
                            nextval("TRDLN_HIST_SEQ"), trdlnId, Date.valueOf(fileDt), t.get("ACCT_STS_CD"),
                            t.get("CURR_BAL_PNC"), t.get("CR_LMT_AMT"), batchId);
                    jdbcTemplate.update("UPDATE ACCOUNT_TRADELINE SET ACCT_STS_CD = ?, ACCT_STS_DT = ?, CURR_BAL_PNC = ?,"
                                    + " CR_LMT_AMT = ?, PYMT_PRFL = ?, LAST_UPD_BATCH_ID = ?, UPD_TS = ? WHERE TRDLN_ID = ?",
                            r.statusCd, Date.valueOf(r.statusDt), r.balancePence, limit(r), r.paymentProfile, batchId, now(),
                            trdlnId);
                    addressCheck(((Number) t.get("CNSMR_ID")).longValue(), r);
                    return Outcome.UPDATED;
                }

                long cnsmrId = matchOrCreateConsumer(r);
                jdbcTemplate.update("INSERT INTO ACCOUNT_TRADELINE (TRDLN_ID, CNSMR_ID, LNDR_REF_CD, ACCT_NO_HASH, ACCT_TYP_CD,"
                                + " OPEN_DT, CLOSE_DT, CR_LMT_AMT, CURR_BAL_PNC, ACCT_STS_CD, ACCT_STS_DT, PYMT_PRFL, DEL_FLG,"
                                + " LAST_UPD_BATCH_ID, CRTD_TS, DSPT_FLG) VALUES (?,?,?,?,?,?,?,?,?,?,?,?,'N',?,?,'N')",
                        nextval("TRDLN_SEQ"), cnsmrId, lender, hash, r.acctTyp, Date.valueOf(r.openDt),
                        r.closeDt == null ? null : Date.valueOf(r.closeDt), limit(r), r.balancePence, r.statusCd,
                        Date.valueOf(r.statusDt), r.paymentProfile, batchId, now());
                addressCheck(cnsmrId, r);
                return Outcome.CREATED;
            }
        });
    }

    private long matchOrCreateConsumer(LenderRecord r) {
        List<Consumer> matches = consumerMatchService.match(r.firstName, r.surname, r.dob);
        if (matches.size() == 1) {
            return matches.get(0).cnsmrId;
        }
        if (matches.size() > 1) {
            throw new RejectException("multiple consumer matches (" + matches.size() + ")");
        }
        long id = nextval("CNSMR_SEQ");
        jdbcTemplate.update("INSERT INTO CONSUMER (CNSMR_ID, FRST_NM, SURNM, DOB, MATCH_KEY, STS_CD, CRTD_TS)"
                        + " VALUES (?,?,?,?,?,'A',?)", id, r.firstName, r.surname, Date.valueOf(r.dob),
                NameNormaliser.matchKey(r.surname, r.dob, r.firstName), now());
        LOG.info("created consumer {} for {} {}", id, r.firstName, r.surname);
        return id;
    }

    /** New address for the consumer => ADDRESS + ADDRESS_HISTORY (CAI). Earlier open entries are closed off. */
    private void addressCheck(long cnsmrId, LenderRecord r) {
        List<Map<String, Object>> known = jdbcTemplate.queryForList("SELECT a.LINE1, a.PSTCD FROM ADDRESS_HISTORY h"
                + " JOIN ADDRESS a ON a.ADDR_ID = h.ADDR_ID WHERE h.CNSMR_ID = ?", cnsmrId);
        for (Map<String, Object> k : known) {
            if (squash((String) k.get("PSTCD")).equals(squash(r.postcode))
                    && String.valueOf(k.get("LINE1")).trim().equalsIgnoreCase(r.line1)) {
                return;
            }
        }
        long addrId = nextval("ADDR_SEQ");
        jdbcTemplate.update("INSERT INTO ADDRESS (ADDR_ID, LINE1, TOWN, PSTCD, CRTD_TS) VALUES (?,?,?,?,?)",
                addrId, r.line1, r.town, r.postcode, now());
        jdbcTemplate.update("UPDATE ADDRESS_HISTORY SET DT_TO = ? WHERE CNSMR_ID = ? AND DT_TO IS NULL AND DT_FROM < ?",
                Date.valueOf(r.addressFrom.minusDays(1)), cnsmrId, Date.valueOf(r.addressFrom));
        jdbcTemplate.update("INSERT INTO ADDRESS_HISTORY (ADDR_HIST_ID, CNSMR_ID, ADDR_ID, DT_FROM, DT_TO, ADDR_SRC_CD, CRTD_TS)"
                + " VALUES (?,?,?,?,NULL,'CAI',?)", nextval("ADDR_HIST_SEQ"), cnsmrId, addrId, Date.valueOf(r.addressFrom), now());
    }

    private void reject(long batchId, int lineNo, String raw, String reason) {
        LOG.warn("line {} rejected: {}", lineNo, reason);
        jdbcTemplate.update("INSERT INTO BATCH_REJECT (REJ_ID, BATCH_ID, LINE_NO, RAW_REC, RJCT_RSN) VALUES (?,?,?,?,?)",
                nextval("BATCH_REJ_SEQ"), batchId, lineNo, raw, reason);
    }

    /** Non-revolving accounts are sent with a zero limit. */
    private static Integer limit(LenderRecord r) {
        return r.creditLimit == 0 ? null : r.creditLimit;
    }

    private static String squash(String pc) {
        return pc == null ? "" : pc.replace(" ", "").toUpperCase();
    }

    private long nextval(String seq) {
        return jdbcTemplate.queryForObject("SELECT nextval('" + seq + "')", Long.class);
    }

    private static Timestamp now() {
        return new Timestamp(System.currentTimeMillis());
    }

    static class RejectException extends RuntimeException {
        RejectException(String msg) {
            super(msg);
        }
    }

    public void setJdbcTemplate(JdbcTemplate jdbcTemplate) {
        this.jdbcTemplate = jdbcTemplate;
    }

    public void setTransactionTemplate(TransactionTemplate transactionTemplate) {
        this.transactionTemplate = transactionTemplate;
    }

    public void setParser(LenderFileParser parser) {
        this.parser = parser;
    }

    public void setConsumerMatchService(ConsumerMatchService consumerMatchService) {
        this.consumerMatchService = consumerMatchService;
    }
}
