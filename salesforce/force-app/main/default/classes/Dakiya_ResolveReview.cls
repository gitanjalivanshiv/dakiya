/** Agent action: answer a question Dakiya parked in the review queue. */
public with sharing class Dakiya_ResolveReview {

    public class Request {
        @InvocableVariable(label='Inbound Message Id' required=true) public String inboundMessageId;
        @InvocableVariable(label='Resolution' description='A Purchase Id to attach it to, the word "new" to start a new order, or "ignore".' required=true)
        public String resolution;
        @InvocableVariable(label='Vendor Id' description='Required only when the resolution is "new".')
        public String vendorId;
    }

    public class Response {
        @InvocableVariable(label='Summary') public String summary;
        @InvocableVariable(label='Purchase Id') public String purchaseId;
    }

    @InvocableMethod(
        label='Dakiya: Resolve Review Item'
        description='Resolves a message Dakiya could not place, by attaching it to an order the user picks, starting a new order from it, or ignoring it. Use after listing review items, for "that one is my Myntra order", "ignore that one", "that is a new order".'
        category='Dakiya'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            Response r = new Response();
            try {
                Map<String, Object> payload = new Map<String, Object>{ 'resolution' => req.resolution };
                if (String.isNotBlank(req.vendorId)) { payload.put('vendorId', (Id) req.vendorId); }

                Map<String, Object> result =
                    DakiyaActionService.resolveReview((Id) req.inboundMessageId, payload);

                r.purchaseId = (String) result.get('purchaseId');
                r.summary = req.resolution == 'ignore'
                    ? 'Ignored - I will not ask about that one again.'
                    : 'Applied. The order is now "' + result.get('status') + '".';
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
