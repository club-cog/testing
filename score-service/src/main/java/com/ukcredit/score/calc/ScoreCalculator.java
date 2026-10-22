package com.ukcredit.score.calc;

import com.ukcredit.common.MoneyUtil;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * UKS3 scorecard. Range 0-999.
 * Utilisation uses whole pounds, rounded per account (see MoneyUtil).
 */
public class ScoreCalculator {

    private LegacyStatusTranslator statusTranslator;

    @SuppressWarnings("unchecked")
    public ScoreResult calculate(long cnsmrId, Map<String, Object> file, Map<String, Integer> p, String modelVer,
                                 LocalDate asOf) {
        ScoreResult r = new ScoreResult();
        r.cnsmrId = cnsmrId;
        r.modelVer = modelVer;
        r.asOf = asOf.toString();

        List<Map<String, Object>> tls = (List<Map<String, Object>>) file.get("tradelines");
        int scored = 0;
        int score = p.get("BASE");
        int utd = 0;
        long revPence = 0;
        int revLimit = 0;
        LocalDate oldestOpen = null;
        for (Map<String, Object> t : tls) {
            if (Boolean.TRUE.equals(t.get("disputed"))) {
                // items under dispute are suppressed until the case closes
                add(r, "DSPT_SUPPRESSED");
                continue;
            }
            scored++;
            LocalDate open = date(t.get("openDate"));
            if (t.get("closeDate") == null && (oldestOpen == null || open.isBefore(oldestOpen))) {
                oldestOpen = open;
            }
            String sts = (String) t.get("statusCd");
            switch (statusTranslator.category(sts, date(t.get("statusDate")))) {
                case UP_TO_DATE:
                    utd += p.get("UTD_PER_ACCT");
                    break;
                case ARREARS:
                    score += statusTranslator.monthsInArrears(sts) * p.get("ARREARS_PER_MTH");
                    add(r, "ARREARS");
                    break;
                case DEFAULT:
                    score += p.get("DEFAULT");
                    add(r, "DEFAULT");
                    break;
                case ARRANGEMENT:
                    // arrangement to pay scores as 2 months down (credit policy CP-114)
                    score += 2 * p.get("ARREARS_PER_MTH");
                    add(r, "ARRANGEMENT");
                    break;
                case SETTLED:
                    score += p.get("SETTLED");
                    break;
                default:
                    break;
            }
            Number lim = (Number) t.get("creditLimit");
            if (Boolean.TRUE.equals(t.get("revolving")) && t.get("closeDate") == null && lim != null
                    && lim.intValue() > 0) {
                revPence += ((Number) t.get("balancePence")).longValue();
                revLimit += lim.intValue();
            }
        }
        if (scored == 0) {
            r.band = "NOSCORE";
            add(r, "THIN_FILE");
            return r;
        }
        score += Math.min(utd, p.get("UTD_CAP"));

        if (revLimit > 0) {
            long pounds = MoneyUtil.penceToWholePounds(revPence);
            int pct = (int) (pounds * 100 / revLimit);
            r.revolvingBalance = pounds;
            r.revolvingLimit = revLimit;
            r.utilisationPct = pct;
            if (pct >= 90) {
                score += p.get("UTIL_90");
                add(r, "UTIL_90");
            } else if (pct >= 75) {
                score += p.get("UTIL_75");
                add(r, "UTIL_75");
            } else if (pct >= 50) {
                score += p.get("UTIL_50");
                add(r, "UTIL_50");
            } else {
                score += p.get("UTIL_LOW");
            }
        }

        for (Map<String, Object> pr : (List<Map<String, Object>>) file.get("publicRecords")) {
            if (Boolean.TRUE.equals(pr.get("disputed"))) {
                add(r, "DSPT_SUPPRESSED");
                continue;
            }
            String typ = (String) pr.get("type");
            LocalDate jd = date(pr.get("judgmentDate"));
            if (jd != null && !jd.isAfter(asOf.minusYears(6))) {
                continue;
            }
            if ("CCJ".equals(typ) || "DEC".equals(typ)) {
                boolean sat = pr.get("satisfiedDate") != null;
                score += sat ? p.get("CCJ_SAT") : p.get("CCJ_UNSAT");
                add(r, sat ? "CCJ_SAT" : "CCJ_UNSAT");
            } else if ("IVA".equals(typ) || "BKY".equals(typ)) {
                score += p.get("INSOLVENCY");
                add(r, "INSOLVENCY");
            }
        }

        int hard = 0;
        for (Map<String, Object> s : (List<Map<String, Object>>) file.get("searches")) {
            LocalDate sd = date(s.get("date"));
            if ("H".equals(s.get("type")) && sd.isAfter(asOf.minusMonths(12)) && !sd.isAfter(asOf)) {
                hard++;
            }
        }
        if (hard == 0) {
            score += p.get("HARD_SRCH_FREE");
        } else {
            score += hard * p.get("HARD_SRCH_EACH");
            add(r, "HARD_SEARCHES");
        }

        boolean registered = false;
        for (Map<String, Object> er : (List<Map<String, Object>>) file.get("electoralRoll")) {
            LocalDate from = date(er.get("from"));
            if (er.get("to") == null && from != null && !from.isAfter(asOf)) {
                registered = true;
            }
        }
        if (registered) {
            score += p.get("ER_REGISTERED");
        } else {
            score += p.get("ER_NOT_REGISTERED");
            add(r, "NOT_ON_ER");
        }

        if (oldestOpen != null && !oldestOpen.isAfter(asOf.minusYears(3))) {
            score += p.get("TENURE_3Y");
        }

        r.score = Math.max(0, Math.min(999, score));
        r.band = band(r.score);
        return r;
    }

    static String band(int s) {
        if (s <= 500) {
            return "VPOOR";
        }
        if (s <= 580) {
            return "POOR";
        }
        if (s <= 640) {
            return "FAIR";
        }
        if (s <= 700) {
            return "GOOD";
        }
        return "EXCELLENT";
    }

    private static void add(ScoreResult r, String code) {
        if (!r.reasons.contains(code)) {
            r.reasons.add(code);
        }
    }

    private static LocalDate date(Object o) {
        return o == null ? null : LocalDate.parse(o.toString());
    }

    public void setStatusTranslator(LegacyStatusTranslator statusTranslator) {
        this.statusTranslator = statusTranslator;
    }
}
