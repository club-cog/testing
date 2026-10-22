package com.ukcredit.creditfile.web;

import com.ukcredit.creditfile.domain.Tradeline;
import com.ukcredit.creditfile.service.TradelineMaintenanceService;
import org.springframework.beans.factory.annotation.Autowired;
import org.springframework.stereotype.Controller;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestMethod;
import org.springframework.web.bind.annotation.ResponseBody;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

import javax.xml.parsers.DocumentBuilderFactory;
import java.io.ByteArrayInputStream;
import java.nio.charset.StandardCharsets;

/**
 * SOAP 1.1 style endpoint (hand-rolled; the CXF stack was removed in 2016 to cut startup time).
 * Namespace urn:ukcredit:tradeline:v1. Operations: SetDisputeFlag, AmendTradeline, GetTradeline.
 */
@Controller
public class TradelineMaintenanceEndpoint {

    static final String NS = "urn:ukcredit:tradeline:v1";

    @Autowired
    private TradelineMaintenanceService tradelineMaintenanceService;

    @RequestMapping(value = "/ws/TradelineMaintenance", method = RequestMethod.POST,
            produces = "text/xml;charset=UTF-8")
    @ResponseBody
    public String invoke(@RequestBody String envelope) throws Exception {
        DocumentBuilderFactory f = DocumentBuilderFactory.newInstance();
        f.setNamespaceAware(true);
        Document doc = f.newDocumentBuilder().parse(new ByteArrayInputStream(envelope.getBytes(StandardCharsets.UTF_8)));
        Element req = firstOp(doc);
        if (req == null) {
            return fault("No operation in SOAP body");
        }
        String op = req.getLocalName();
        long trdlnId = Long.parseLong(text(req, "tradelineId"));
        if ("SetDisputeFlagRequest".equals(op)) {
            boolean ok = tradelineMaintenanceService.setDisputeFlag(trdlnId, text(req, "flag"));
            return wrap("<tl:SetDisputeFlagResponse><tl:result>" + (ok ? "OK" : "NOT_FOUND")
                    + "</tl:result></tl:SetDisputeFlagResponse>");
        }
        if ("AmendTradelineRequest".equals(op)) {
            String bal = text(req, "balancePence");
            boolean ok = tradelineMaintenanceService.amend(trdlnId, text(req, "statusCd"),
                    bal == null ? null : Long.valueOf(bal), "true".equals(text(req, "delete")), text(req, "operatorId"));
            return wrap("<tl:AmendTradelineResponse><tl:result>" + (ok ? "OK" : "NOT_FOUND")
                    + "</tl:result></tl:AmendTradelineResponse>");
        }
        if ("GetTradelineRequest".equals(op)) {
            Tradeline t = tradelineMaintenanceService.get(trdlnId);
            if (t == null) {
                return fault("Tradeline " + trdlnId + " not found");
            }
            return wrap("<tl:GetTradelineResponse><tl:tradelineId>" + t.trdlnId + "</tl:tradelineId>"
                    + "<tl:consumerId>" + t.cnsmrId + "</tl:consumerId><tl:statusCd>" + t.acctStsCd + "</tl:statusCd>"
                    + "<tl:balancePence>" + t.currBalPnc + "</tl:balancePence><tl:disputeFlag>" + t.dsptFlg
                    + "</tl:disputeFlag></tl:GetTradelineResponse>");
        }
        return fault("Unknown operation " + op);
    }

    private static Element firstOp(Document doc) {
        NodeList bodies = doc.getElementsByTagNameNS("http://schemas.xmlsoap.org/soap/envelope/", "Body");
        if (bodies.getLength() == 0) {
            return null;
        }
        NodeList kids = bodies.item(0).getChildNodes();
        for (int i = 0; i < kids.getLength(); i++) {
            if (kids.item(i).getNodeType() == Node.ELEMENT_NODE) {
                return (Element) kids.item(i);
            }
        }
        return null;
    }

    private static String text(Element parent, String name) {
        NodeList l = parent.getElementsByTagNameNS(NS, name);
        if (l.getLength() == 0) {
            l = parent.getElementsByTagName(name);
        }
        if (l.getLength() == 0) {
            return null;
        }
        String s = l.item(0).getTextContent();
        return s == null || s.trim().isEmpty() ? null : s.trim();
    }

    private static String wrap(String body) {
        return "<soapenv:Envelope xmlns:soapenv=\"http://schemas.xmlsoap.org/soap/envelope/\" xmlns:tl=\"" + NS + "\">"
                + "<soapenv:Body>" + body + "</soapenv:Body></soapenv:Envelope>";
    }

    private static String fault(String msg) {
        return wrap("<soapenv:Fault><faultcode>soapenv:Client</faultcode><faultstring>" + msg
                + "</faultstring></soapenv:Fault>");
    }
}
