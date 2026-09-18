/**
 * Agent action: courier says delivered, the user never got it.
 *
 * Returns a complaint pack assembled purely from recorded facts, so the user can
 * argue with the courier using details that are demonstrably on file.
 */
public with sharing class Dakiya_ReportNotReceived {

    public class Request {
        @InvocableVariable(label='Record Id' description='Purchase Id or Shipment Id.' required=true)
        public String recordId;
    }

    public class Response {
        @InvocableVariable(label='Summary') public String summary;
        @InvocableVariable(label='Complaint Pack' description='The facts on file, ready to quote to the seller or courier.')
        public String complaintPack;
    }

    @InvocableMethod(
        label='Dakiya: Report Not Received'
        description='Records that a parcel marked delivered never actually arrived, and returns the order number, courier, tracking number and claimed delivery time to quote in a complaint. Use for "it says delivered but I never got it", "the parcel is missing", "I did not receive it".'
        category='Dakiya'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            Response r = new Response();
            try {
                Map<String, Object> result = DakiyaActionService.reportNotReceived((Id) req.recordId);
                Map<String, Object> pack = (Map<String, Object>) result.get('complaintPack');

                List<String> lines = new List<String>();
                if (pack.get('vendor') != null)  { lines.add('Seller: ' + pack.get('vendor')); }
                if (pack.get('orderId') != null) { lines.add('Order id: ' + pack.get('orderId')); }
                if (pack.get('courier') != null) { lines.add('Courier: ' + pack.get('courier')); }
                if (pack.get('awb') != null)     { lines.add('Tracking number: ' + pack.get('awb')); }
                if (pack.get('deliveredClaimAt') != null) {
                    lines.add('Courier claimed delivery: '
                        + DakiyaAgentFormat.when((Datetime) pack.get('deliveredClaimAt')));
                }
                if (pack.get('amount') != null) {
                    lines.add('Amount: ' + DakiyaAgentFormat.rupees((Decimal) pack.get('amount')));
                }
                // Anything not recorded is simply absent - a complaint built on an
                // invented AWB is worse than one with a gap in it.
                r.complaintPack = lines.isEmpty()
                    ? 'I have very little recorded about this one - only what you see on the order.'
                    : String.join(lines, '\n');
                r.summary = 'Flagged as not received. Here is what I have on file to quote:\n' + r.complaintPack;
            } catch (DakiyaActionService.ActionException e) {
                r.summary = e.getMessage() + ' Which order do you mean?';
            } catch (Exception e) {
                r.summary = DakiyaAgentFormat.problem(e);
            }
            out.add(r);
        }
        return out;
    }
}
