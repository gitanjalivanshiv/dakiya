/** Agent action: mark an order cancelled. */
public with sharing class Dakiya_CancelPurchase {

    public class Request {
        @InvocableVariable(label='Purchase Id' required=true) public String purchaseId;
        @InvocableVariable(label='Reason') public String reason;
    }

    public class Response {
        @InvocableVariable(label='Summary') public String summary;
        @InvocableVariable(label='Cancelled') public Boolean cancelled;
    }

    @InvocableMethod(
        label='Dakiya: Cancel Purchase'
        description='Marks an order as cancelled. Use for "I cancelled my Myntra order", "that order was cancelled". Confirm which order is meant before calling this. An order that has already been delivered cannot be cancelled - raise a return instead.'
        category='Dakiya'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            Response r = new Response();
            r.cancelled = false;
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
                    DakiyaStateMachine.decide(p.Status__c, DakiyaConstants.EV_CANCELLED);

                if (!d.changed) {
                    r.summary = 'I have not cancelled that - ' + d.note.toLowerCase()
                        + '. It is currently "' + p.Status__c + '".'
                        + (DakiyaConstants.rankOf(p.Status__c) >= 60
                            ? ' Since it already arrived, a return is the right route.' : '');
                    out.add(r);
                    continue;
                }

                p.Status__c = d.newStatus;
                p.Status_Rank__c = DakiyaConstants.rankOf(d.newStatus);
                p.Last_Event_At__c = Datetime.now();
                if (String.isNotBlank(req.reason)) {
                    p.Notes__c = (String.isBlank(p.Notes__c) ? '' : p.Notes__c + '\n')
                        + 'Cancelled: ' + req.reason;
                }
                update p;

                insert new Tracking_Event__c(
                    Purchase__c = p.Id, Event_Type__c = DakiyaConstants.EV_CANCELLED,
                    Event_At__c = Datetime.now(),
                    Summary__c = ('Cancelled by user' + (String.isBlank(req.reason) ? '' : ': ' + req.reason)).left(255),
                    Applied_By__c = DakiyaConstants.BY_AGENT
                );

                r.cancelled = true;
                r.summary = 'Cancelled: ' + DakiyaAgentFormat.describe(p) + '.';
            } catch (Exception e) {
                r.summary = DakiyaAgentFormat.problem(e);
            }
            out.add(r);
        }
        return out;
    }
}
