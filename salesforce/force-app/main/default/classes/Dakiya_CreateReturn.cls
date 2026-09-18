/** Agent action: start a return or exchange against a delivered order. */
public with sharing class Dakiya_CreateReturn {

    public class Request {
        @InvocableVariable(label='Purchase Id' required=true) public String purchaseId;
        @InvocableVariable(label='Item Name' description='Only when a single item is going back.')
        public String itemName;
        @InvocableVariable(label='Reason') public String reason;
        @InvocableVariable(label='Type' description='Return, or Exchange or Replacement.') public String type;
    }

    public class Response {
        @InvocableVariable(label='Summary') public String summary;
        @InvocableVariable(label='Return Id') public String returnId;
    }

    @InvocableMethod(
        label='Dakiya: Create Return'
        description='Starts a return or exchange for an order the user has received. Use for "I want to return the serum", "raising a return for this", "I am exchanging it for a bigger size".'
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

                DakiyaStateMachine.Decision d =
                    DakiyaStateMachine.decide(p.Status__c, DakiyaConstants.EV_RETURN_REQUESTED);
                if (!d.changed && DakiyaConstants.rankOf(p.Status__c) < 60) {
                    r.summary = 'That order has not arrived yet (it is "' + p.Status__c
                        + '"), so there is nothing to return. Do you want to cancel it instead?';
                    out.add(r);
                    continue;
                }

                Id itemId;
                if (String.isNotBlank(req.itemName)) {
                    String needle = '%' + String.escapeSingleQuotes(req.itemName) + '%';
                    List<Purchase_Item__c> items = [
                        SELECT Id FROM Purchase_Item__c
                        WHERE Purchase__c = :pid AND Name LIKE :needle LIMIT 1
                    ];
                    if (!items.isEmpty()) { itemId = items[0].Id; }
                }

                Return__c ret = new Return__c(
                    Purchase__c = pid,
                    Purchase_Item__c = itemId,
                    Type__c = (req.type != null && req.type.toLowerCase().contains('exchange'))
                        ? 'Exchange or Replacement' : 'Return',
                    Reason__c = String.isBlank(req.reason) ? null : req.reason.left(255),
                    Status__c = 'Requested',
                    Requested_On__c = Date.today()
                );
                insert ret;

                if (d.changed) {
                    p.Status__c = d.newStatus;
                    p.Status_Rank__c = DakiyaConstants.rankOf(d.newStatus);
                }
                p.Last_Event_At__c = Datetime.now();
                update p;

                insert new Tracking_Event__c(
                    Purchase__c = pid, Return__c = ret.Id,
                    Event_Type__c = DakiyaConstants.EV_RETURN_REQUESTED, Event_At__c = Datetime.now(),
                    Summary__c = ('Return raised by user' + (String.isBlank(req.reason) ? '' : ': ' + req.reason)).left(255),
                    Applied_By__c = DakiyaConstants.BY_AGENT
                );

                r.returnId = ret.Id;
                r.summary = ret.Type__c + ' started for ' + DakiyaAgentFormat.describe(p)
                    + '. Tell me when it is picked up or the refund is initiated and I will follow it through.';
            } catch (Exception e) {
                r.summary = DakiyaAgentFormat.problem(e);
            }
            out.add(r);
        }
        return out;
    }
}
