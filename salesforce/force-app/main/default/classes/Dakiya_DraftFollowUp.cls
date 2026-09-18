/**
 * Agent action: draft a chase message. Drafting only - Dakiya never sends.
 */
public with sharing class Dakiya_DraftFollowUp {

    public class Request {
        @InvocableVariable(label='Purchase Id' required=true) public String purchaseId;
        @InvocableVariable(label='Tone' description='polite (default), firm, or escalate.') public String tone;
    }

    public class Response {
        @InvocableVariable(label='Draft' description='Message text for the user to copy and send herself.')
        public String draft;
        @InvocableVariable(label='Summary') public String summary;
    }

    @InvocableMethod(
        label='Dakiya: Draft Follow Up Message'
        description='Writes a message the user can send to a seller or courier about a late, missing or unrefunded order, using only details already on file. It returns text for the user to send herself - it never sends anything. Use for "chase this seller", "write a message about my missing parcel", "draft a complaint".'
        category='Dakiya'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            Response r = new Response();
            try {
                Id pid = (Id) req.purchaseId;
                List<Purchase__c> found = Database.query(
                    'SELECT ' + DakiyaApi.PURCHASE_FIELDS + ' FROM Purchase__c WHERE Id = :pid LIMIT 1'
                );
                if (found.isEmpty()) {
                    r.summary = 'No order with that id.';
                    out.add(r);
                    continue;
                }
                Purchase__c p = found[0];
                List<Shipment__c> ships = [
                    SELECT Courier__c, AWB__c, Delivered_At__c, Status__c
                    FROM Shipment__c WHERE Purchase__c = :pid ORDER BY CreatedDate DESC LIMIT 1
                ];
                Shipment__c s = ships.isEmpty() ? null : ships[0];
                String tone = String.isBlank(req.tone) ? 'polite' : req.tone.toLowerCase();
                String vendor = p.Vendor__r == null ? 'there' : p.Vendor__r.Name;

                // Only facts already recorded go into the draft. Anything unknown is
                // left out rather than filled in with a plausible-looking value.
                List<String> facts = new List<String>();
                if (String.isNotBlank(p.External_Order_Id__c)) { facts.add('Order ' + p.External_Order_Id__c); }
                if (p.Order_Date__c != null)                   { facts.add('placed ' + DakiyaAgentFormat.day(p.Order_Date__c)); }
                if (p.Total_Amount__c != null)                 { facts.add('for ' + DakiyaAgentFormat.rupees(p.Total_Amount__c)); }
                if (s != null && String.isNotBlank(s.AWB__c))  { facts.add('AWB ' + s.AWB__c + (s.Courier__c == null ? '' : ' via ' + s.Courier__c)); }

                String opener, ask;
                if (tone == 'escalate') {
                    opener = 'Hello ' + vendor + ', I have followed up more than once about this order and still have no resolution.';
                    ask = 'Please confirm today what is happening, or process a full refund. Otherwise I will escalate this further.';
                } else if (tone == 'firm') {
                    opener = 'Hello ' + vendor + ', I still have not received an update on this order.';
                    ask = 'Please tell me the current status and a firm date, or refund it.';
                } else {
                    opener = 'Hi ' + vendor + ', I wanted to check on this order.';
                    ask = 'Could you let me know the status when you get a moment? Thank you.';
                }

                List<String> parts = new List<String>{ opener };
                if (!facts.isEmpty()) { parts.add(String.join(facts, ', ') + '.'); }
                if (p.Status__c == DakiyaConstants.ST_NOT_RECEIVED && s != null && s.Delivered_At__c != null) {
                    parts.add('It was marked delivered on ' + DakiyaAgentFormat.when(s.Delivered_At__c)
                              + ', but it never reached me.');
                } else if (p.Last_Event_At__c != null) {
                    parts.add('The last update I have is from ' + DakiyaAgentFormat.when(p.Last_Event_At__c) + '.');
                }
                parts.add(ask);

                r.draft = String.join(parts, ' ');
                r.summary = 'Draft ready (' + tone + ' tone). I have not sent it - copy it and send it yourself.';
            } catch (Exception e) {
                r.summary = DakiyaAgentFormat.problem(e);
            }
            out.add(r);
        }
        return out;
    }
}
