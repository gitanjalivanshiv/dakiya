/**
 * Agent action: the user says she has the parcel.
 *
 * This is the only route to Received. No courier event and no model inference
 * can produce it - the whole point of Dakiya is that "delivered" and "I have it"
 * are different facts.
 */
public with sharing class Dakiya_ConfirmReceived {

    public class Request {
        @InvocableVariable(label='Record Id' description='Purchase Id or Shipment Id.' required=true)
        public String recordId;
    }

    public class Response {
        @InvocableVariable(label='Summary') public String summary;
        @InvocableVariable(label='Status') public String status;
    }

    @InvocableMethod(
        label='Dakiya: Confirm Received'
        description='Records that the user has physically received a parcel. Use for "I got the Nykaa parcel", "it arrived", "yes I have it". This is the only way an order becomes Received - a courier marking something delivered never counts.'
        category='Dakiya'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            Response r = new Response();
            try {
                Map<String, Object> result = DakiyaActionService.confirmReceived((Id) req.recordId);
                r.status = (String) result.get('status');
                Integer pending = (Integer) result.get('otherParcelsPending');
                r.summary = pending != null && pending > 0
                    ? 'Marked that one received. ' + pending + ' more parcel(s) on this order are still outstanding.'
                    : 'Marked received. Nothing else outstanding on that order.';
            } catch (DakiyaActionService.ActionException e) {
                r.summary = e.getMessage() + ' Tell me which order you mean and I will mark it.';
            } catch (Exception e) {
                r.summary = DakiyaAgentFormat.problem(e);
            }
            out.add(r);
        }
        return out;
    }
}
