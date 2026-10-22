package com.ukcredit.creditfile.service;

import com.ukcredit.creditfile.dao.AddressHistoryDao;
import com.ukcredit.creditfile.dao.ConsumerDao;
import com.ukcredit.creditfile.dao.TradelineDao;
import com.ukcredit.creditfile.domain.AddressHistoryEntry;
import com.ukcredit.creditfile.domain.Consumer;
import com.ukcredit.creditfile.domain.Tradeline;
import com.ukcredit.creditfile.rules.AddressHistoryMerger;
import com.ukcredit.creditfile.rules.TradelineStatusMapper;
import org.springframework.jdbc.core.JdbcTemplate;

import java.math.BigDecimal;
import java.sql.Date;
import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

/**
 * Builds the full consumer credit file. Used by the bureau portal and by score-service.
 */
public class CreditFileAssembler {

    private final JdbcTemplate jdbcTemplate;
    private final ConsumerDao consumerDao;
    private final TradelineDao tradelineDao;
    private final AddressHistoryDao addressHistoryDao;
    private final TradelineStatusMapper statusMapper;
    private final AddressHistoryMerger addressMerger;

    public CreditFileAssembler(JdbcTemplate jdbcTemplate, ConsumerDao consumerDao, TradelineDao tradelineDao, AddressHistoryDao addressHistoryDao, TradelineStatusMapper statusMapper, AddressHistoryMerger addressMerger) {
        this.jdbcTemplate = jdbcTemplate;
        this.consumerDao = consumerDao;
        this.tradelineDao = tradelineDao;
        this.addressHistoryDao = addressHistoryDao;
        this.statusMapper = statusMapper;
        this.addressMerger = addressMerger;
    }

    public Map<String, Object> build(long cnsmrId) {
        Consumer c = consumerDao.findById(cnsmrId);
        if (c == null) {
            return null;
        }
        Map<String, Object> file = new LinkedHashMap<String, Object>();
        Map<String, Object> cm = new LinkedHashMap<String, Object>();
        cm.put("cnsmrId", c.cnsmrId);
        cm.put("title", c.titleCd);
        cm.put("firstName", c.firstName);
        cm.put("middleName", c.middleName);
        cm.put("surname", c.surname);
        cm.put("dob", iso(c.dob));
        cm.put("matchKey", c.matchKey);
        file.put("consumer", cm);

        List<Map<String, Object>> addrs = new ArrayList<Map<String, Object>>();
        for (AddressHistoryEntry e : addressMerger.merge(addressHistoryDao.findByConsumer(cnsmrId)).kept) {
            Map<String, Object> m = new LinkedHashMap<String, Object>();
            m.put("addrHistId", e.addrHistId);
            m.put("addrId", e.addrId);
            m.put("line1", e.line1);
            m.put("town", e.town);
            m.put("postcode", e.postcode);
            m.put("from", iso(e.dtFrom));
            m.put("to", iso(e.dtTo));
            m.put("source", e.srcCd);
            addrs.add(m);
        }
        file.put("addresses", addrs);

        List<Map<String, Object>> tls = new ArrayList<Map<String, Object>>();
        for (Tradeline t : tradelineDao.findLiveByConsumer(cnsmrId)) {
            Map<String, Object> m = new LinkedHashMap<String, Object>();
            m.put("trdlnId", t.trdlnId);
            m.put("lender", t.lndrRefCd);
            m.put("lenderName", t.lndrNm);
            m.put("accountType", t.acctTypCd);
            m.put("revolving", t.revolving);
            m.put("openDate", iso(t.openDt));
            m.put("closeDate", iso(t.closeDt));
            m.put("creditLimit", t.crLmtAmt);
            m.put("balancePence", t.currBalPnc);
            m.put("balanceDisplay", BigDecimal.valueOf(t.currBalPnc).movePointLeft(2).toPlainString());
            m.put("statusCd", t.acctStsCd);
            m.put("statusDate", iso(t.acctStsDt));
            m.put("mappedStatus", statusMapper.map(t.acctStsCd, t.acctStsDt));
            m.put("paymentProfile", t.pymtPrfl);
            m.put("disputed", "Y".equals(t.dsptFlg));
            tls.add(m);
        }
        file.put("tradelines", tls);

        file.put("publicRecords", rows("SELECT PUB_REC_ID AS \"pubRecId\", REC_TYP_CD AS \"type\", CRT_CD AS \"court\","
                + " CASE_REF AS \"caseRef\", JDGMT_DT AS \"judgmentDate\", JDGMT_AMT AS \"amount\","
                + " SATSFD_DT AS \"satisfiedDate\", DSPT_FLG AS \"disputed\" FROM PUBLIC_RECORD WHERE CNSMR_ID = ?"
                + " ORDER BY PUB_REC_ID", cnsmrId));
        file.put("searches", rows("SELECT SRCH_ID AS \"srchId\", LNDR_REF_CD AS \"lender\", SRCH_TYP_CD AS \"type\","
                + " SRCH_DT AS \"date\" FROM SEARCH_FOOTPRINT WHERE CNSMR_ID = ? ORDER BY SRCH_DT DESC, SRCH_ID", cnsmrId));
        file.put("electoralRoll", rows("SELECT ER_ID AS \"erId\", ADDR_ID AS \"addrId\", DT_FROM AS \"from\","
                + " DT_TO AS \"to\" FROM ELECTORAL_ROLL WHERE CNSMR_ID = ? ORDER BY ER_ID", cnsmrId));
        file.put("aliases", rows("SELECT FRST_NM AS \"firstName\", SURNM AS \"surname\", ALIAS_TYP_CD AS \"type\""
                + " FROM CONSUMER_ALIAS WHERE CNSMR_ID = ? ORDER BY ALIAS_ID", cnsmrId));
        file.put("notices", rows("SELECT NTC_TXT AS \"text\", CRTD_DT AS \"created\" FROM CONSUMER_NOTICE"
                + " WHERE CNSMR_ID = ? ORDER BY NTC_ID", cnsmrId));
        return file;
    }

    private List<Map<String, Object>> rows(String sql, long id) {
        List<Map<String, Object>> out = new ArrayList<Map<String, Object>>();
        for (Map<String, Object> r : jdbcTemplate.queryForList(sql, id)) {
            Map<String, Object> m = new LinkedHashMap<String, Object>();
            for (Map.Entry<String, Object> e : r.entrySet()) {
                Object v = e.getValue();
                if (v instanceof Date) {
                    v = ((Date) v).toLocalDate().toString();
                } else if (v instanceof BigDecimal) {
                    v = ((BigDecimal) v).toPlainString();
                } else if (v instanceof String) {
                    v = ((String) v).trim();
                }
                if ("disputed".equals(e.getKey())) {
                    v = "Y".equals(v);
                }
                m.put(e.getKey(), v);
            }
            out.add(m);
        }
        return out;
    }

    private static String iso(LocalDate d) {
        return d == null ? null : d.toString();
    }
}
