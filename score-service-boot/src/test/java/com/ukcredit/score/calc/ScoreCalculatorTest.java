package com.ukcredit.score.calc;

import static org.assertj.core.api.Assertions.assertThat;

import com.ukcredit.common.MoneyUtil;
import org.junit.jupiter.api.Test;

import java.time.LocalDate;

class ScoreCalculatorTest {

    private final LegacyStatusTranslator translator = new LegacyStatusTranslator();

    @Test
    void bands() {
        assertThat(ScoreCalculator.band(420)).isEqualTo("VPOOR");
        assertThat(ScoreCalculator.band(500)).isEqualTo("VPOOR");
        assertThat(ScoreCalculator.band(580)).isEqualTo("POOR");
        assertThat(ScoreCalculator.band(600)).isEqualTo("FAIR");
        assertThat(ScoreCalculator.band(700)).isEqualTo("GOOD");
        assertThat(ScoreCalculator.band(750)).isEqualTo("EXCELLENT");
    }

    @Test
    void statusXCutoffIsTheCodeDateNotSysParam() {
        assertThat(translator.category("X", LocalDate.of(2014, 3, 31))).isEqualTo(LegacyStatusTranslator.Cat.DEFAULT);
        assertThat(translator.category("X", LocalDate.of(2014, 4, 1))).isEqualTo(LegacyStatusTranslator.Cat.ARRANGEMENT);
        // SYS_PARAM TRDLN_X_CUTOFF_DT says 2015-01-01; the scorer has always used 2014-04-01
        assertThat(translator.category("X", LocalDate.of(2014, 6, 1))).isEqualTo(LegacyStatusTranslator.Cat.ARRANGEMENT);
        assertThat(translator.category("X", null)).isEqualTo(LegacyStatusTranslator.Cat.ARRANGEMENT);
    }

    @Test
    void summedPenceRoundHalfEven() {
        assertThat(MoneyUtil.penceToWholePounds(50050)).isEqualTo(500);
        assertThat(MoneyUtil.penceToWholePounds(30050 + 44900)).isEqualTo(750);
        assertThat(MoneyUtil.penceToWholePounds(74950)).isEqualTo(750);
    }
}
