/** Agent action: attach a courier and tracking number the user read out. */
public with sharing class Dakiya_AddTracking {

    public class Request {
        @InvocableVariable(label='Purchase Id' required=true) public String purchaseId;
        @InvocableVariable(label='Courier' description='Ekart, Delhivery, Blue Dart, India Post, Shadowfax, XpressBees, Amazon Shipping or Other.')
        public String courier;
        @InvocableVariable(label='AWB' description='Tracking number exactly as the user gave it. Never invent or complete one.')
        public String awb;
        @InvocableVariable(label='Tracking URL') public String trackingUrl;
    }

    public class Response {
        @InvocableVariable(label='Summary') public String summary;
        @InvocableVariable(label='Shipment Id') public String shipmentId;
    }

    @InvocableMethod(
        label='Dakiya: Add Tracking'
        description='Attaches a courier name and tracking number (AWB) to an existing order, for when a seller sends tracking details by DM or WhatsApp. Use for "the tracking number is 12345", "it is shipping via Delhivery". Record the number exactly as given and never guess one.'
        category='Dakiya'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            Response r = new Response();
            try {
                if (String.isBlank(req.awb) && String.isBlank(req.courier)) {
                    r.summary = 'I need at least a courier name or a tracking number.';
                    out.add(r);
                    continue;
                }
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

                Shipment__c s;
                if (String.isNotBlank(req.awb)) {
                    List<Shipment__c> existing = [
                        SELECT Id, Status__c FROM Shipment__c WHERE AWB__c = :req.awb LIMIT 1
                    ];
                    s = existing.isEmpty() ? null : existing[0];
                }
                if (s == null) {
                    s = new Shipment__c(Purchase__c = p.Id, Status__c = 'Shipped');
                }
                if (String.isNotBlank(req.awb))         { s.AWB__c = req.awb.trim().left(60); }
                if (String.isNotBlank(req.courier))     { s.Courier__c = req.courier.left(80); }
                if (String.isNotBlank(req.trackingUrl)) { s.Tracking_URL__c = req.trackingUrl; }
                upsert s;

                DakiyaStateMachine.Decision d =
                    DakiyaStateMachine.decide(p.Status__c, DakiyaConstants.EV_SHIPPED);
                if (d.changed) {
                    p.Status__c = d.newStatus;
                    p.Status_Rank__c = DakiyaConstants.rankOf(d.newStatus);
                }
                p.Last_Event_At__c = Datetime.now();
                update p;

                insert new Tracking_Event__c(
                    Purchase__c = p.Id, Shipment__c = s.Id,
                    Event_Type__c = DakiyaConstants.EV_SHIPPED, Event_At__c = Datetime.now(),
                    Summary__c = 'Tracking added by the user', Applied_By__c = DakiyaConstants.BY_AGENT
                );

                r.shipmentId = s.Id;
                r.summary = 'Tracking saved'
                    + (String.isBlank(req.courier) ? '' : ' (' + req.courier + ')')
                    + (String.isBlank(req.awb) ? '' : ', AWB ' + req.awb)
                    + ' for ' + DakiyaAgentFormat.describe(p) + '.';
            } catch (Exception e) {
                r.summary = DakiyaAgentFormat.problem(e);
            }
            out.add(r);
        }
        return out;
    }
}
