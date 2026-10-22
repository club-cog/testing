package com.ukcredit.dispute.service;

import com.ukcredit.dispute.client.ScoreClient;
import com.ukcredit.dispute.client.TradelineMaintenanceClient;
import com.ukcredit.dispute.dao.DisputeDao;
import com.ukcredit.dispute.sla.RegionResolver;
import com.ukcredit.dispute.sla.SlaCalculator;
import org.slf4j.Logger;
import org.slf4j.LoggerFactory;

import java.sql.Timestamp;
import java.util.Date;
import java.util.Map;

/**
 * Open / resolve consumer disputes. Not transactional across services: if credit-file-service is down
 * the case is still recorded and ops re-send the flag from the admin screen.
 */
public class DisputeService {

    private static final Logger LOG = LoggerFactory.getLogger(DisputeService.class);

    private final DisputeDao disputeDao;
    private final SlaCalculator slaCalculator;
    private final RegionResolver regionResolver;
    private final TradelineMaintenanceClient tradelineClient;
    private final ScoreClient scoreClient;

    public DisputeService(DisputeDao disputeDao, SlaCalculator slaCalculator, RegionResolver regionResolver,
                          TradelineMaintenanceClient tradelineClient, ScoreClient scoreClient) {
        this.disputeDao = disputeDao;
        this.slaCalculator = slaCalculator;
        this.regionResolver = regionResolver;
        this.tradelineClient = tradelineClient;
        this.scoreClient = scoreClient;
    }

    public long open(long cnsmrId, Long trdlnId, Long pubRecId, String rsnCd, String chnlCd, Timestamp rcvdTs) {
        String region = regionResolver.regionForConsumer(cnsmrId);
        Date due = slaCalculator.dueDate(rcvdTs, region);
        long id = disputeDao.insertCase(cnsmrId, trdlnId, pubRecId, rsnCd, chnlCd, rcvdTs, new java.sql.Date(due.getTime()));
        disputeDao.insertEvent(id, "OPENED", null, "region=" + region);
        disputeDao.insertCorrespondence(id, "ACK01", chnlCd);
        if (trdlnId != null) {
            if (!tradelineClient.setDisputeFlag(trdlnId, "Y")) {
                LOG.warn("dispute {}: SetDisputeFlag Y not applied to tradeline {}", id, trdlnId);
            }
        } else if (pubRecId != null) {
            disputeDao.setPublicRecordDisputeFlag(pubRecId, "Y");
        }
        scoreClient.recalculate(cnsmrId, "DISPUTE_OPEN");
        LOG.info("dispute {} opened for consumer {} region {} due {}", id, cnsmrId, region, due);
        return id;
    }

    public boolean isKnownOperator(String operatorId) {
        return disputeDao.operatorExists(operatorId);
    }

    /** @return false if the case does not exist or is already closed */
    public boolean resolve(long dsptId, String outcome, String operatorId, String statusCd, Long balancePence) {
        Map<String, Object> c = disputeDao.findCase(dsptId);
        if (c == null || "CLOSED".equals(c.get("stsCd"))) {
            return false;
        }
        long cnsmrId = ((Number) c.get("cnsmrId")).longValue();
        Long trdlnId = c.get("trdlnId") == null ? null : ((Number) c.get("trdlnId")).longValue();
        Long pubRecId = c.get("pubRecId") == null ? null : ((Number) c.get("pubRecId")).longValue();
        String chnlCd = String.valueOf(c.get("chnlCd")).trim();

        boolean changed = "AMEND".equals(outcome) || "DELETE".equals(outcome);
        if (changed && trdlnId != null) {
            tradelineClient.amendTradeline(trdlnId, statusCd, balancePence, "DELETE".equals(outcome), operatorId);
        }
        if (trdlnId != null) {
            tradelineClient.setDisputeFlag(trdlnId, "N");
        } else if (pubRecId != null) {
            disputeDao.setPublicRecordDisputeFlag(pubRecId, "N");
        }
        disputeDao.close(dsptId, outcome, operatorId);
        disputeDao.insertEvent(dsptId, "CLOSED", operatorId, "outcome=" + outcome);
        disputeDao.insertCorrespondence(dsptId, changed ? "RES01" : "RES02", chnlCd);
        scoreClient.recalculate(cnsmrId, "DISPUTE_CLOSE");
        return true;
    }

    public Map<String, Object> get(long dsptId) {
        Map<String, Object> c = disputeDao.findCase(dsptId);
        if (c != null) {
            c.put("events", disputeDao.findEvents(dsptId));
            c.put("correspondence", disputeDao.findCorrespondence(dsptId));
        }
        return c;
    }

    public Date slaDueDate(Date received, String region) {
        return slaCalculator.dueDate(received, region);
    }
}
