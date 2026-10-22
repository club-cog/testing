package com.ukcredit.score.calc;

import com.ukcredit.score.client.CreditFileClient;
import com.ukcredit.score.dao.ScoreHistoryDao;
import com.ukcredit.score.dao.ScoreModelDao;

import java.time.LocalDate;
import java.util.Map;

public class ScoreService {

    private CreditFileClient creditFileClient;
    private ScoreModelDao scoreModelDao;
    private ScoreHistoryDao scoreHistoryDao;
    private ScoreCalculator scoreCalculator;

    public ScoreResult score(long cnsmrId, LocalDate asOf) {
        Map<String, Object> file = creditFileClient.getCreditFile(cnsmrId);
        if (file == null) {
            return null;
        }
        String ver = scoreModelDao.activeModel();
        ScoreResult r = scoreCalculator.calculate(cnsmrId, file, scoreModelDao.params(ver), ver, asOf);
        // belt and braces: the credit file can lag behind a just-opened dispute
        if (scoreHistoryDao.openDisputedTradelines(cnsmrId) > 0 && !r.reasons.contains("DSPT_SUPPRESSED")) {
            r.reasons.add("DSPT_SUPPRESSED");
        }
        return r;
    }

    public ScoreResult recalculate(long cnsmrId, LocalDate asOf, String trigger) {
        ScoreResult r = score(cnsmrId, asOf);
        if (r != null) {
            scoreHistoryDao.insert(r, trigger);
        }
        return r;
    }

    public java.util.List<Map<String, Object>> history(long cnsmrId) {
        return scoreHistoryDao.history(cnsmrId);
    }

    public void setCreditFileClient(CreditFileClient creditFileClient) {
        this.creditFileClient = creditFileClient;
    }

    public void setScoreModelDao(ScoreModelDao scoreModelDao) {
        this.scoreModelDao = scoreModelDao;
    }

    public void setScoreHistoryDao(ScoreHistoryDao scoreHistoryDao) {
        this.scoreHistoryDao = scoreHistoryDao;
    }

    public void setScoreCalculator(ScoreCalculator scoreCalculator) {
        this.scoreCalculator = scoreCalculator;
    }
}
