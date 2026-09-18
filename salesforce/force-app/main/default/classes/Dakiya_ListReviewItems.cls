/** Agent action: messages Dakiya could not confidently place. */
public with sharing class Dakiya_ListReviewItems {

    public class Response {
        @InvocableVariable(label='Summary') public String summary;
        @InvocableVariable(label='Review Count') public Integer reviewCount;
        @InvocableVariable(label='Message Ids') public List<String> messageIds;
    }

    @InvocableMethod(
        label='Dakiya: List Review Items'
        description='Lists captured emails or texts that Dakiya could not confidently match to an order, and is therefore asking about rather than guessing. Use for "anything to review", "what needs my attention", "is there anything you are unsure about".'
        category='Dakiya'
    )
    public static List<Response> run(List<String> requests) {
        Integer n = requests == null || requests.isEmpty() ? 1 : requests.size();
        Response r = new Response();
        r.messageIds = new List<String>();
        try {
            List<Inbound_Message__c> items = [
                SELECT Id, Channel__c, Sender__c, Subject__c, Received_At__c, Confidence__c,
                       Related_Purchase__c, Related_Purchase__r.Title__c,
                       Related_Purchase__r.Vendor__r.Name
                FROM Inbound_Message__c
                WHERE Processing_Status__c = 'Needs Review'
                ORDER BY Received_At__c DESC LIMIT 20
            ];
            r.reviewCount = items.size();
            if (items.isEmpty()) {
                r.summary = 'Nothing waiting for review.';
            } else {
                List<String> lines = new List<String>{ items.size() + ' message(s) I could not place confidently:' };
                for (Inbound_Message__c m : items) {
                    r.messageIds.add(m.Id);
                    String line = '- ' + m.Channel__c + ' from ' + m.Sender__c
                                + ' (' + DakiyaAgentFormat.when(m.Received_At__c) + ')';
                    if (String.isNotBlank(m.Subject__c)) { line += ': ' + m.Subject__c; }
                    if (m.Related_Purchase__c != null) {
                        String vendor = m.Related_Purchase__r.Vendor__r == null
                            ? '' : m.Related_Purchase__r.Vendor__r.Name + ' - ';
                        line += ' - best guess: ' + vendor + m.Related_Purchase__r.Title__c;
                    }
                    lines.add(line);
                }
                r.summary = String.join(lines, '\n');
            }
        } catch (Exception e) {
            r.summary = DakiyaAgentFormat.problem(e);
            r.reviewCount = 0;
        }
        List<Response> out = new List<Response>();
        for (Integer i = 0; i < n; i++) { out.add(r); }
        return out;
    }
}
