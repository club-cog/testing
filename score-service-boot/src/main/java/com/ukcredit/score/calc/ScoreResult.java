package com.ukcredit.score.calc;

import java.util.ArrayList;
import java.util.List;

public class ScoreResult {
    public long cnsmrId;
    public Integer score;
    public String band;
    public String modelVer;
    public String asOf;
    public List<String> reasons = new ArrayList<String>();
    /** Whole pounds after rounding; null when the consumer has no revolving credit. */
    public Long revolvingBalance;
    public Integer revolvingLimit;
    public Integer utilisationPct;
}
