/** Agent action: move a return along as the user reports progress. */
public with sharing class Dakiya_UpdateReturnStatus {

    public class Request {
        @InvocableVariable(label='Return Id' required=true) public String returnId;
        @InvocableVariable(label='Status' description='Requested, Pickup Scheduled, Picked Up, Received by Seller, Refund Initiated, Rejected or Cancelled.' required=true)
        public String status;
        @InvocableVariable(label='Date' description='When it happened, if the user said.') public Date statusDate;
    }

    public class Response {
        @InvocableVariable(label='Summary') public String summary;
        @InvocableVariable(label='Refund Check Due') public Date refundCheckDue;
    }

    @InvocableMethod(
        label='Dakiya: Update Return Status'
        description='Moves a return to its next stage: pickup scheduled, picked up, received by the seller, refund initiated, rejected or cancelled. Use for "the courier collected the return", "they have received it", "the refund has been initiated".'
        category='Dakiya'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        Set<String> allowed = new Set<String>{
            'Requested', 'Pickup Scheduled', 'Picked Up', 'Received by Seller',
            'Refund Initiated', 'Rejected', 'Cancelled'
        };
        for (Request req : requests) {
            Response r = new Response();
            try {
                if (!allowed.contains(req.status)) {
                    r.summary = 'I cannot set a return to "' + req.status + '". Valid stages: '
                        + String.join(new List<String>(allowed), ', ') + '.'
                        + ' To record what the refund actually turned out to be, use the refund outcome action.';
                    out.add(r);
                    continue;
                }
                Return__c ret = [
                    SELECT Id, Status__c, Purchase__c, Purchase__r.Vendor__c,
                           Purchase__r.Title__c, Purchase__r.Vendor__r.Name
                    FROM Return__c WHERE Id = :req.returnId LIMIT 1
                ];
                Date effective = req.statusDate == null ? Date.today() : req.statusDate;

                ret.Status__c = req.status;
                if (req.status == 'Pickup Scheduled' || req.status == 'Picked Up') {
                    ret.Pickup_Date__c = effective;
                }
                if (req.status == 'Refund Initiated') {
                    ret.Refund_Initiated_On__c = effective;
                    Integer days = DakiyaSettings.defaultRefundCheckDays();
                    if (ret.Purchase__r.Vendor__c != null) {
                        List<Vendor__c> v = [
                            SELECT Typical_Refund_Days__c FROM Vendor__c
                            WHERE Id = :ret.Purchase__r.Vendor__c LIMIT 1
                        ];
                        if (!v.isEmpty() && v[0].Typical_Refund_Days__c != null && v[0].Typical_Refund_Days__c > 0) {
                            days = Integer.valueOf(v[0].Typical_Refund_Days__c);
                        }
                    }
                    ret.Refund_Check_Due__c = effective.addDays(days);
                    r.refundCheckDue = ret.Refund_Check_Due__c;
                }
                update ret;

                insert new Tracking_Event__c(
                    Purchase__c = ret.Purchase__c, Return__c = ret.Id,
                    Event_Type__c = eventFor(req.status),
                    Event_At__c = Datetime.newInstance(effective, Time.newInstance(12, 0, 0, 0)),
                    Summary__c = ('Return moved to ' + req.status + ' by user').left(255),
                    Applied_By__c = DakiyaConstants.BY_AGENT
                );

                r.summary = 'Return is now "' + req.status + '".';
                if (r.refundCheckDue != null) {
                    r.summary += ' I will remind you around ' + DakiyaAgentFormat.day(r.refundCheckDue)
                        + ' to check whether the money actually arrived - I cannot see your bank, so you will need to tell me.';
                }
            } catch (Exception e) {
                r.summary = DakiyaAgentFormat.problem(e);
            }
            out.add(r);
        }
        return out;
    }

    private static String eventFor(String status) {
        if (status == 'Pickup Scheduled')   { return DakiyaConstants.EV_RETURN_PICKUP_SCHEDULED; }
        if (status == 'Picked Up')          { return DakiyaConstants.EV_RETURN_PICKED_UP; }
        if (status == 'Received by Seller') { return DakiyaConstants.EV_RETURN_RECEIVED; }
        if (status == 'Refund Initiated')   { return DakiyaConstants.EV_REFUND_INITIATED; }
        if (status == 'Rejected')           { return DakiyaConstants.EV_RETURN_REJECTED; }
        return DakiyaConstants.EV_RETURN_REQUESTED;
    }
}
