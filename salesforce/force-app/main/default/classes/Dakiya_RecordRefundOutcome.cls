/**
 * Agent action: the user reports what the refund actually turned out to be.
 *
 * Dakiya never reads bank or UPI data, so this is the only way a refund outcome
 * is ever known. A seller's "refund processed" email is a claim, not an outcome.
 */
public with sharing class Dakiya_RecordRefundOutcome {

    public class Request {
        @InvocableVariable(label='Return Id' required=true) public String returnId;
        @InvocableVariable(label='Outcome' description='Full to Original Payment, Partial, Store Credit, Replacement, Not Received Yet, or Not Received (Escalated).' required=true)
        public String outcome;
        @InvocableVariable(label='Amount' description='What actually arrived, in rupees, if the user said.')
        public Decimal amount;
    }

    public class Response {
        @InvocableVariable(label='Summary') public String summary;
        @InvocableVariable(label='Escalation Suggested') public Boolean escalationSuggested;
    }

    @InvocableMethod(
        label='Dakiya: Record Refund Outcome'
        description='Records what actually happened to a refund once the user has checked: full refund, partial, store credit, a replacement, or still nothing. Use for "the refund came through", "they only gave me store credit", "I got 800 back", "still nothing". Only record what the user states.'
        category='Dakiya'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        Set<String> allowed = new Set<String>{
            'Full to Original Payment', 'Partial', 'Store Credit', 'Replacement',
            'Not Received Yet', 'Not Received (Escalated)'
        };
        for (Request req : requests) {
            Response r = new Response();
            r.escalationSuggested = false;
            try {
                if (!allowed.contains(req.outcome)) {
                    r.summary = 'I can record one of: ' + String.join(new List<String>(allowed), ', ') + '.';
                    out.add(r);
                    continue;
                }
                Map<String, Object> payload = new Map<String, Object>{ 'outcome' => req.outcome };
                if (req.amount != null) { payload.put('amount', req.amount); }

                Map<String, Object> result =
                    DakiyaActionService.recordRefundOutcome((Id) req.returnId, payload);

                if (req.outcome == 'Not Received Yet') {
                    Date next = (Date) result.get('nextCheck');
                    r.escalationSuggested = (Boolean) result.get('escalationSuggested');
                    r.summary = 'Noted - nothing yet. I will ask again around ' + DakiyaAgentFormat.day(next) + '.';
                    if (r.escalationSuggested) {
                        r.summary += ' This has now been chased several times; would you like me to draft an escalation message?';
                    }
                } else {
                    r.summary = 'Recorded: ' + req.outcome
                        + (req.amount == null ? '' : ' (' + DakiyaAgentFormat.rupees(req.amount) + ')')
                        + '. The return is closed'
                        + (result.get('purchaseStatus') == DakiyaConstants.ST_CLOSED
                            ? ' and so is the order.' : '.')
                        + ' I have updated what I know about how this seller refunds.';
                }
            } catch (DakiyaActionService.ActionException e) {
                r.summary = e.getMessage();
            } catch (Exception e) {
                r.summary = DakiyaAgentFormat.problem(e);
            }
            out.add(r);
        }
        return out;
    }
}
