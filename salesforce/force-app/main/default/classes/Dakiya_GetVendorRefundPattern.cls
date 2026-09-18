/** Agent action: what this seller has actually done with past refunds. */
public with sharing class Dakiya_GetVendorRefundPattern {

    public class Request {
        @InvocableVariable(label='Vendor Name' required=true) public String vendorName;
    }

    public class Response {
        @InvocableVariable(label='Summary') public String summary;
        @InvocableVariable(label='Known') public Boolean known;
    }

    @InvocableMethod(
        label='Dakiya: Get Vendor Refund Pattern'
        description='Reports how a seller has handled refunds in the past: typical days to refund, whether it comes back to the original payment method or as store credit, and a short history. Use for "how long does Myntra usually take", "does Nykaa give store credit".'
        category='Dakiya'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            Response r = new Response();
            r.known = false;
            try {
                Vendor__c v = DakiyaParserRegistry.findByName(req.vendorName);
                if (v == null) {
                    r.summary = 'No seller called "' + req.vendorName + '" on file, so there is no history to go on.';
                    out.add(r);
                    continue;
                }
                Vendor__c full = [
                    SELECT Name, Typical_Refund_Days__c, Usual_Refund_Mode__c,
                           Refund_History_Summary__c, Return_Window_Days__c
                    FROM Vendor__c WHERE Id = :v.Id LIMIT 1
                ];
                List<String> lines = new List<String>{ full.Name + ':' };
                if (full.Typical_Refund_Days__c != null) {
                    r.known = true;
                    lines.add('- Refunds have taken about ' + full.Typical_Refund_Days__c.intValue() + ' days.');
                } else {
                    lines.add('- No completed refunds recorded yet, so I have no timing to go on.');
                }
                if (full.Usual_Refund_Mode__c != null && full.Usual_Refund_Mode__c != 'Unknown') {
                    r.known = true;
                    lines.add('- Usually refunds as: ' + full.Usual_Refund_Mode__c + '.');
                }
                if (String.isNotBlank(full.Refund_History_Summary__c)) {
                    lines.add('- History: ' + full.Refund_History_Summary__c);
                }
                if (full.Return_Window_Days__c != null) {
                    lines.add('- Return window: ' + full.Return_Window_Days__c.intValue() + ' days after delivery.');
                }
                r.summary = String.join(lines, '\n');
            } catch (Exception e) {
                r.summary = DakiyaAgentFormat.problem(e);
            }
            out.add(r);
        }
        return out;
    }
}
