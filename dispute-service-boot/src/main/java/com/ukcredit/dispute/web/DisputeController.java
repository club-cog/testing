package com.ukcredit.dispute.web;

import com.ukcredit.dispute.service.DisputeService;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import java.sql.Timestamp;
import java.text.SimpleDateFormat;
import java.time.LocalDateTime;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;

@RestController
public class DisputeController {

    private static final List<String> OUTCOMES = List.of("AMEND", "DELETE", "NOCHANGE");

    private final DisputeService disputeService;

    public DisputeController(DisputeService disputeService) {
        this.disputeService = disputeService;
    }

    @PostMapping(value = "/disputes", produces = "application/json")
    public ResponseEntity<Map<String, Object>> open(@RequestBody Map<String, Object> req) {
        Long cnsmrId = longVal(req.get("cnsmrId"));
        Long trdlnId = longVal(req.get("trdlnId"));
        Long pubRecId = longVal(req.get("pubRecId"));
        String rsnCd = (String) req.get("rsnCd");
        String chnlCd = req.get("chnlCd") == null ? "WEB" : (String) req.get("chnlCd");
        if (cnsmrId == null || rsnCd == null || (trdlnId == null && pubRecId == null)) {
            return error(HttpStatus.BAD_REQUEST, "cnsmrId, rsnCd and one of trdlnId/pubRecId are required");
        }
        Timestamp rcvd = req.get("rcvdTs") == null ? new Timestamp(System.currentTimeMillis())
                : Timestamp.valueOf(LocalDateTime.parse((String) req.get("rcvdTs")));
        long id = disputeService.open(cnsmrId, trdlnId, pubRecId, rsnCd, chnlCd, rcvd);
        return new ResponseEntity<>(disputeService.get(id), HttpStatus.CREATED);
    }

    @PostMapping(value = "/disputes/{id:[0-9]+}/resolve", produces = "application/json")
    public ResponseEntity<Map<String, Object>> resolve(@PathVariable("id") long id, @RequestBody Map<String, Object> req) {
        String outcome = (String) req.get("outcome");
        String operatorId = (String) req.get("operatorId");
        if (outcome == null || operatorId == null || !OUTCOMES.contains(outcome)) {
            return error(HttpStatus.BAD_REQUEST, "outcome (AMEND|DELETE|NOCHANGE) and operatorId are required");
        }
        if (!disputeService.isKnownOperator(operatorId)) {
            return error(HttpStatus.BAD_REQUEST, "unknown operator " + operatorId);
        }
        if (!disputeService.resolve(id, outcome, operatorId, (String) req.get("statusCd"), longVal(req.get("balancePence")))) {
            return error(HttpStatus.NOT_FOUND, "dispute " + id + " not found or already closed");
        }
        return new ResponseEntity<>(disputeService.get(id), HttpStatus.OK);
    }

    @GetMapping(value = "/disputes/{id:[0-9]+}", produces = "application/json")
    public ResponseEntity<Map<String, Object>> get(@PathVariable("id") long id) {
        Map<String, Object> c = disputeService.get(id);
        return c == null ? error(HttpStatus.NOT_FOUND, "dispute " + id + " not found")
                : new ResponseEntity<>(c, HttpStatus.OK);
    }

    @GetMapping(value = "/disputes/sla", produces = "application/json")
    public Map<String, Object> sla(@RequestParam("received") String received,
                                   @RequestParam(value = "region", defaultValue = "EW") String region) {
        Date due = disputeService.slaDueDate(Timestamp.valueOf(LocalDateTime.parse(received)), region);
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("received", received);
        m.put("region", region);
        m.put("slaDueDt", new SimpleDateFormat("yyyy-MM-dd").format(due));
        return m;
    }

    private static Long longVal(Object o) {
        if (o == null) {
            return null;
        }
        return o instanceof Number n ? n.longValue() : Long.valueOf(o.toString().trim());
    }

    private static ResponseEntity<Map<String, Object>> error(HttpStatus st, String msg) {
        Map<String, Object> m = new LinkedHashMap<>();
        m.put("error", msg);
        return new ResponseEntity<>(m, st);
    }
}
