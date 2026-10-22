package com.ukcredit.creditfile.web;

import com.ukcredit.creditfile.domain.Consumer;
import com.ukcredit.creditfile.service.ConsumerMatchService;
import com.ukcredit.creditfile.service.CreditFileAssembler;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.time.LocalDate;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
public class CreditFileController {

    /* The ".json" paths replace Spring 4 suffix pattern matching, which Spring 6 removed. */

    /** Spring 4 sent the charset parameter; kept so the Content-Type header is unchanged. */
    static final String JSON = "application/json;charset=UTF-8";

    private final CreditFileAssembler creditFileAssembler;
    private final ConsumerMatchService consumerMatchService;

    public CreditFileController(CreditFileAssembler creditFileAssembler, ConsumerMatchService consumerMatchService) {
        this.creditFileAssembler = creditFileAssembler;
        this.consumerMatchService = consumerMatchService;
    }

    @GetMapping(value = {"/creditfile/{id}", "/creditfile/{id}.json"}, produces = JSON)
    public ResponseEntity<Map<String, Object>> get(@PathVariable("id") long id) {
        Map<String, Object> file = creditFileAssembler.build(id);
        if (file == null) {
            return new ResponseEntity<>(HttpStatus.NOT_FOUND);
        }
        return new ResponseEntity<>(file, HttpStatus.OK);
    }

    @GetMapping(value = {"/consumers/match", "/consumers/match.json"}, produces = JSON)
    public List<Map<String, Object>> match(@RequestParam("firstName") String firstName,
                                           @RequestParam("surname") String surname,
                                           @RequestParam("dob") String dob) {
        List<Map<String, Object>> out = new ArrayList<>();
        for (Consumer c : consumerMatchService.match(firstName, surname, LocalDate.parse(dob))) {
            Map<String, Object> m = new LinkedHashMap<>();
            m.put("cnsmrId", c.cnsmrId);
            m.put("firstName", c.firstName);
            m.put("surname", c.surname);
            m.put("dob", c.dob.toString());
            out.add(m);
        }
        return out;
    }
}
