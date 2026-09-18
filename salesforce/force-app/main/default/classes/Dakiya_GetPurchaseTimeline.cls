/** Agent action: the full history of one order. */
public with sharing class Dakiya_GetPurchaseTimeline {

    public class Request {
        @InvocableVariable(label='Purchase Id' description='Salesforce Id of the order.' required=true)
        public String purchaseId;
    }

    public class Response {
        @InvocableVariable(label='Summary') public String summary;
        @InvocableVariable(label='Found') public Boolean found;
    }

    @InvocableMethod(
        label='Dakiya: Get Purchase Timeline'
        description='Returns the full history of one order: what was ordered, every tracking event, its parcels and any returns. Use after finding an order, for "what happened with this order", "show me the tracking history".'
        category='Dakiya'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            Response r = new Response();
            r.found = false;
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
                r.found = true;

                List<String> lines = new List<String>{
                    DakiyaAgentFormat.describe(p),
                    'Status: ' + p.Status__c
                };
                if (p.External_Order_Id__c != null) { lines.add('Order id: ' + p.External_Order_Id__c); }
                if (p.Order_Date__c != null)        { lines.add('Ordered: ' + DakiyaAgentFormat.day(p.Order_Date__c)); }
                if (p.Expected_Delivery__c != null) { lines.add('Expected: ' + DakiyaAgentFormat.day(p.Expected_Delivery__c)); }
                if (p.Return_Window_Ends__c != null){ lines.add('Return window ends: ' + DakiyaAgentFormat.day(p.Return_Window_Ends__c)); }

                for (Shipment__c s : [
                    SELECT Courier__c, AWB__c, Status__c, Delivered_At__c, Confirmation__c
                    FROM Shipment__c WHERE Purchase__c = :pid LIMIT 20
                ]) {
                    String line = 'Parcel: ' + (s.Courier__c == null ? 'courier unknown' : s.Courier__c);
                    if (s.AWB__c != null) { line += ', AWB ' + s.AWB__c; }
                    line += ' - ' + s.Status__c;
                    if (s.Confirmation__c != null) { line += ' (you: ' + s.Confirmation__c + ')'; }
                    lines.add(line);
                }

                List<Tracking_Event__c> events = [
                    SELECT Event_Type__c, Event_At__c, Summary__c, Applied_By__c
                    FROM Tracking_Event__c WHERE Purchase__c = :pid
                    ORDER BY Event_At__c DESC LIMIT 25
                ];
                if (!events.isEmpty()) {
                    lines.add('');
                    lines.add('Timeline:');
                    for (Tracking_Event__c e : events) {
                        lines.add('- ' + DakiyaAgentFormat.when(e.Event_At__c) + ': ' + e.Event_Type__c
                                  + ' (' + e.Applied_By__c + ')');
                    }
                }

                for (Return__c ret : [
                    SELECT Type__c, Status__c, Refund_Check_Due__c, Refund_Outcome__c
                    FROM Return__c WHERE Purchase__c = :pid LIMIT 10
                ]) {
                    lines.add('Return: ' + ret.Type__c + ' - ' + ret.Status__c
                        + (ret.Refund_Outcome__c == null ? '' : ' (' + ret.Refund_Outcome__c + ')'));
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
