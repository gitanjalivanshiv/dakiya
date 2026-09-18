/** Agent action: returns still in flight, and which refunds need checking. */
public with sharing class Dakiya_ListOpenReturns {

    public class Response {
        @InvocableVariable(label='Summary') public String summary;
        @InvocableVariable(label='Open Count') public Integer openCount;
        @InvocableVariable(label='Refund Checks Due') public Integer refundChecksDue;
    }

    @InvocableMethod(
        label='Dakiya: List Open Returns'
        description='Lists returns and exchanges that are not finished, flagging any whose refund the user should now check on. Use for "what returns are open", "any refunds pending", "did my refund come through".'
        category='Dakiya'
    )
    public static List<Response> run(List<String> requests) {
        Integer n = requests == null || requests.isEmpty() ? 1 : requests.size();
        Response r = new Response();
        try {
            List<Return__c> open = [
                SELECT Type__c, Status__c, Requested_On__c, Refund_Initiated_On__c, Refund_Check_Due__c,
                       Expected_Refund_Amount__c, Purchase__r.Title__c, Purchase__r.Vendor__r.Name,
                       Purchase__r.Vendor__r.Usual_Refund_Mode__c
                FROM Return__c
                WHERE Status__c NOT IN ('Completed', 'Rejected', 'Cancelled')
                ORDER BY Refund_Check_Due__c NULLS LAST LIMIT 30
            ];
            r.openCount = open.size();
            r.refundChecksDue = 0;

            if (open.isEmpty()) {
                r.summary = 'No open returns.';
            } else {
                List<String> lines = new List<String>{ open.size() + ' open return(s):' };
                for (Return__c ret : open) {
                    String vendor = ret.Purchase__r.Vendor__r == null ? 'Unknown seller' : ret.Purchase__r.Vendor__r.Name;
                    String line = '- ' + vendor + ' - ' + ret.Purchase__r.Title__c + ' - ' + ret.Status__c;
                    if (ret.Expected_Refund_Amount__c != null) {
                        line += ', expecting ' + DakiyaAgentFormat.rupees(ret.Expected_Refund_Amount__c);
                    }
                    if (ret.Refund_Check_Due__c != null && ret.Refund_Check_Due__c <= Date.today()) {
                        r.refundChecksDue++;
                        line += ' - WORTH CHECKING NOW';
                        if (ret.Purchase__r.Vendor__r != null && ret.Purchase__r.Vendor__r.Usual_Refund_Mode__c != null) {
                            line += ' (this seller usually refunds to: '
                                 + ret.Purchase__r.Vendor__r.Usual_Refund_Mode__c + ')';
                        }
                    } else if (ret.Refund_Check_Due__c != null) {
                        line += ', check by ' + DakiyaAgentFormat.day(ret.Refund_Check_Due__c);
                    }
                    lines.add(line);
                }
                if (r.refundChecksDue > 0) {
                    lines.add('');
                    lines.add('Dakiya cannot see bank accounts - please check and tell me what actually arrived.');
                }
                r.summary = String.join(lines, '\n');
            }
        } catch (Exception e) {
            r.summary = DakiyaAgentFormat.problem(e);
            r.openCount = 0;
            r.refundChecksDue = 0;
        }
        List<Response> out = new List<Response>();
        for (Integer i = 0; i < n; i++) { out.add(r); }
        return out;
    }
}
