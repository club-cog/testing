package com.ukcredit.score.web;

import com.ukcredit.score.calc.ScoreResult;
import com.ukcredit.score.calc.ScoreService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;

import java.time.LocalDate;
import java.util.List;
import java.util.Map;

@Controller
public class ScoreController {

    @Autowired
    private ScoreService scoreService;

    @RequestMapping(value = "/score/{id}", method = RequestMethod.GET, produces = "application/json")
    @ResponseBody
    public ResponseEntity<ScoreResult> get(@PathVariable("id") long id,
                                           @RequestParam(value = "asOf", required = false) String asOf) {
        return wrap(scoreService.score(id, asOf(asOf)));
    }

    @RequestMapping(value = "/score/{id}/recalculate", method = RequestMethod.POST, produces = "application/json")
    @ResponseBody
    public ResponseEntity<ScoreResult> recalc(@PathVariable("id") long id,
                                              @RequestParam(value = "asOf", required = false) String asOf,
                                              @RequestParam(value = "trigger", defaultValue = "ADHOC") String trigger) {
        return wrap(scoreService.recalculate(id, asOf(asOf), trigger));
    }

    @RequestMapping(value = "/score/{id}/history", method = RequestMethod.GET, produces = "application/json")
    @ResponseBody
    public List<Map<String, Object>> history(@PathVariable("id") long id) {
        return scoreService.history(id);
    }

    private static LocalDate asOf(String s) {
        return s == null || s.isEmpty() ? LocalDate.now() : LocalDate.parse(s);
    }

    private static ResponseEntity<ScoreResult> wrap(ScoreResult r) {
        return r == null ? new ResponseEntity<ScoreResult>(HttpStatus.NOT_FOUND)
                : new ResponseEntity<ScoreResult>(r, HttpStatus.OK);
    }
}
