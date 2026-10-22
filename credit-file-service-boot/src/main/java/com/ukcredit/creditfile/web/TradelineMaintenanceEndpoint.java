package com.ukcredit.creditfile.web;

import com.ukcredit.creditfile.domain.Tradeline;
import com.ukcredit.creditfile.service.TradelineMaintenanceService;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestHeader;
import org.springframework.web.bind.annotation.RestController;
import org.w3c.dom.Document;
import org.w3c.dom.Element;
import org.w3c.dom.Node;
import org.w3c.dom.NodeList;

import javax.xml.XMLConstants;
import javax.xml.parsers.DocumentBuilderFactory;
import java.io.ByteArrayInputStream;
import java.nio.charset.Charset;
import java.nio.charset.StandardCharsets;

/**
 * SOAP 1.1 style endpoint (hand-rolled; the CXF stack was removed in 2016 to cut startup time).
 * Namespace urn:ukcredit:tradeline:v1. Operations: SetDisputeFlag, AmendTradeline, GetTradeline.
 */
@RestController
public class TradelineMaintenanceEndpoint {

    static final String NS = "urn:ukcredit:tradeline:v1";

    private final TradelineMaintenanceService tradelineMaintenanceService;

    public TradelineMaintenanceEndpoint(TradelineMaintenanceService tradelineMaintenanceService) {
        this.tradelineMaintenanceService = tradelineMaintenanceService;
    }

    @PostMapping(value = "/ws/TradelineMaintenance", produces = "text/xml;charset=UTF-8")
    public String invoke(@RequestBody byte[] body,
                         @RequestHeader(value = HttpHeaders.CONTENT_TYPE, required = false) String contentType)
            throws Exception {
        String envelope = new String(body, requestCharset(contentType));
        DocumentBuilderFactory f = DocumentBuilderFactory.newInstance();
        f.setNamespaceAware(true);
        f.setFeature("http://apache.org/xml/features/disallow-doctype-decl", true);
        f.setFeature(XMLConstants.FEATURE_SECURE_PROCESSING, true);
        f.setXIncludeAware(false);
        f.setExpandEntityReferences(false);
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

    /** As Spring 4's StringHttpMessageConverter: charset from Content-Type, else ISO-8859-1. */
    static Charset requestCharset(String contentType) {
        if (contentType != null) {
            try {
                Charset cs = MediaType.parseMediaType(contentType).getCharset();
                if (cs != null) {
                    return cs;
                }
            } catch (RuntimeException ignored) {
                // fall through to the default, as the legacy converter did
            }
        }
        return StandardCharsets.ISO_8859_1;
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
