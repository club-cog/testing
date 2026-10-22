package com.ukcredit.score.web;

import com.ukcredit.score.calc.ScoreResult;
import com.ukcredit.score.calc.ScoreService;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

/**
 * Same URLs as legacy. The "/" and ".json" variants are listed explicitly because Spring 6 no longer does
 * trailing-slash or suffix-pattern matching, which the legacy Spring 4.3 dispatcher accepted.
 */
@RestController
public class ScoreController {

    private final ScoreService scoreService;

    public ScoreController(ScoreService scoreService) {
        this.scoreService = scoreService;
    }

    @GetMapping(value = {"/score/{id}", "/score/{id}/", "/score/{id}.json"}, produces = "application/json")
    public ResponseEntity<ScoreResult> get(@PathVariable("id") long id,
                                           @RequestParam(value = "asOf", required = false) String asOf) {
        return wrap(scoreService.score(id, asOf(asOf)));
    }

    @PostMapping(value = {"/score/{id}/recalculate", "/score/{id}/recalculate/", "/score/{id}/recalculate.json"},
            produces = "application/json")
    public ResponseEntity<ScoreResult> recalc(@PathVariable("id") long id,
                                              @RequestParam(value = "asOf", required = false) String asOf,
                                              @RequestParam(value = "trigger", defaultValue = "ADHOC") String trigger) {
        return wrap(scoreService.recalculate(id, asOf(asOf), trigger));
    }

    @GetMapping(value = {"/score/{id}/history", "/score/{id}/history/", "/score/{id}/history.json"},
            produces = "application/json")
    public List<Map<String, Object>> history(@PathVariable("id") long id) {
        return scoreService.history(id);
    }

    private static LocalDate asOf(String s) {
        return s == null || s.isEmpty() ? LocalDate.now() : LocalDate.parse(s);
    }

    private static ResponseEntity<ScoreResult> wrap(ScoreResult r) {
        return r == null ? ResponseEntity.notFound().build() : ResponseEntity.ok(r);
    }
}
