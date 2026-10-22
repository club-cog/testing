package com.ukcredit.dispute.web;

import com.ukcredit.dispute.service.DisputeService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.http.HttpStatus;
import org.springframework.http.ResponseEntity;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.ResponseBody;

import java.sql.Timestamp;
import java.text.SimpleDateFormat;
import java.time.LocalDateTime;
import java.util.Arrays;
import java.util.Date;
import java.util.LinkedHashMap;
import java.util.Map;

@Controller
public class DisputeController {

    @Autowired
    private DisputeService disputeService;

    @RequestMapping(value = "/disputes", method = RequestMethod.POST, produces = "application/json")
    @ResponseBody
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
        return new ResponseEntity<Map<String, Object>>(disputeService.get(id), HttpStatus.CREATED);
    }

    @RequestMapping(value = "/disputes/{id:[0-9]+}/resolve", method = RequestMethod.POST, produces = "application/json")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> resolve(@PathVariable("id") long id, @RequestBody Map<String, Object> req) {
        String outcome = (String) req.get("outcome");
        String operatorId = (String) req.get("operatorId");
        if (outcome == null || operatorId == null || !Arrays.asList("AMEND", "DELETE", "NOCHANGE").contains(outcome)) {
            return error(HttpStatus.BAD_REQUEST, "outcome (AMEND|DELETE|NOCHANGE) and operatorId are required");
        }
        if (!disputeService.isKnownOperator(operatorId)) {
            return error(HttpStatus.BAD_REQUEST, "unknown operator " + operatorId);
        }
        if (!disputeService.resolve(id, outcome, operatorId, (String) req.get("statusCd"), longVal(req.get("balancePence")))) {
            return error(HttpStatus.NOT_FOUND, "dispute " + id + " not found or already closed");
        }
        return new ResponseEntity<Map<String, Object>>(disputeService.get(id), HttpStatus.OK);
    }

    @RequestMapping(value = "/disputes/{id:[0-9]+}", method = RequestMethod.GET, produces = "application/json")
    @ResponseBody
    public ResponseEntity<Map<String, Object>> get(@PathVariable("id") long id) {
        Map<String, Object> c = disputeService.get(id);
        return c == null ? error(HttpStatus.NOT_FOUND, "dispute " + id + " not found")
                : new ResponseEntity<Map<String, Object>>(c, HttpStatus.OK);
    }

    @RequestMapping(value = "/disputes/sla", method = RequestMethod.GET, produces = "application/json")
    @ResponseBody
    public Map<String, Object> sla(@RequestParam("received") String received,
                                   @RequestParam(value = "region", defaultValue = "EW") String region) {
        Date due = disputeService.slaDueDate(Timestamp.valueOf(LocalDateTime.parse(received)), region);
        Map<String, Object> m = new LinkedHashMap<String, Object>();
        m.put("received", received);
        m.put("region", region);
        m.put("slaDueDt", new SimpleDateFormat("yyyy-MM-dd").format(due));
        return m;
    }

    private static Long longVal(Object o) {
        if (o == null) {
            return null;
        }
        return o instanceof Number ? ((Number) o).longValue() : Long.valueOf(o.toString().trim());
    }

    private static ResponseEntity<Map<String, Object>> error(HttpStatus st, String msg) {
        Map<String, Object> m = new LinkedHashMap<String, Object>();
        m.put("error", msg);
        return new ResponseEntity<Map<String, Object>>(m, st);
    }
}
