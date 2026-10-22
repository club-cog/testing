package com.ukcredit.creditfile.web;

import com.ukcredit.creditfile.domain.Consumer;
import com.ukcredit.creditfile.service.ConsumerMatchService;
import com.ukcredit.creditfile.service.CreditFileAssembler;
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
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@Controller
public class CreditFileController {

    @Autowired
    private CreditFileAssembler creditFileAssembler;

    @Autowired
    private ConsumerMatchService consumerMatchService;

    @RequestMapping(value = "/creditfile/{id}", method = RequestMethod.GET, produces = "application/json")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> get(@PathVariable("id") long id) {
        Map<String, Object> file = creditFileAssembler.build(id);
        if (file == null) {
            return new ResponseEntity<Map<String, Object>>(HttpStatus.NOT_FOUND);
        }
        return new ResponseEntity<Map<String, Object>>(file, HttpStatus.OK);
    }

    @RequestMapping(value = "/consumers/match", method = RequestMethod.GET, produces = "application/json")
    @ResponseBody
    public List<Map<String, Object>> match(@RequestParam("firstName") String firstName,
                                           @RequestParam("surname") String surname,
                                           @RequestParam("dob") String dob) {
        List<Map<String, Object>> out = new ArrayList<Map<String, Object>>();
        for (Consumer c : consumerMatchService.match(firstName, surname, LocalDate.parse(dob))) {
            Map<String, Object> m = new LinkedHashMap<String, Object>();
            m.put("cnsmrId", c.cnsmrId);
            m.put("firstName", c.firstName);
            m.put("surname", c.surname);
            m.put("dob", c.dob.toString());
            out.add(m);
        }
        return out;
    }
}
