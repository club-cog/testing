package com.ukcredit.score.calc;

import com.ukcredit.score.client.CreditFileClient;
import com.ukcredit.score.dao.ScoreHistoryDao;
import com.ukcredit.score.dao.ScoreModelDao;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

public class ScoreService {

    private final CreditFileClient creditFileClient;
    private final ScoreModelDao scoreModelDao;
    private final ScoreHistoryDao scoreHistoryDao;
    private final ScoreCalculator scoreCalculator;

    public ScoreService(CreditFileClient creditFileClient, ScoreModelDao scoreModelDao,
                        ScoreHistoryDao scoreHistoryDao, ScoreCalculator scoreCalculator) {
        this.creditFileClient = creditFileClient;
        this.scoreModelDao = scoreModelDao;
        this.scoreHistoryDao = scoreHistoryDao;
        this.scoreCalculator = scoreCalculator;
    }

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

    public List<Map<String, Object>> history(long cnsmrId) {
        return scoreHistoryDao.history(cnsmrId);
    }
}
