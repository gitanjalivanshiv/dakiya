/**
 * Agent action: what is on its way, and what is waiting to be confirmed.
 *
 * This is the answer to "what's pending?" - the most common question the agent
 * will be asked.
 */
public with sharing class Dakiya_GetPendingDeliveries {

    public class Response {
        @InvocableVariable(label='Summary' description='A short, mobile-friendly summary to read back to the user.')
        public String summary;
        @InvocableVariable(label='Pending Count')
        public Integer pendingCount;
        @InvocableVariable(label='Awaiting Confirmation Count')
        public Integer awaitingConfirmationCount;
    }

    @InvocableMethod(
        label='Dakiya: Get Pending Deliveries'
        description='Lists every order that has not arrived yet, plus any parcel a courier says was delivered but the user has not confirmed receiving. Use for questions like "what is pending", "what is arriving", "where are my parcels", "anything coming today".'
        category='Dakiya'
    )
    public static List<Response> run(List<String> requests) {
        List<Response> out = new List<Response>();
        Integer n = requests == null || requests.isEmpty() ? 1 : requests.size();

        Response r = new Response();
        try {
            List<Purchase__c> pending = Database.query(
                'SELECT ' + DakiyaApi.PURCHASE_FIELDS + ' FROM Purchase__c ' +
                'WHERE Status__c IN (\'Placed\', \'Confirmed\', \'Partially Shipped\', \'Shipped\', \'Out for Delivery\') ' +
                'ORDER BY Expected_Delivery__c NULLS LAST LIMIT 30'
            );
            List<Shipment__c> unconfirmed = [
                SELECT Id, Courier__c, Delivered_At__c, Purchase__r.Title__c, Purchase__r.Vendor__r.Name
                FROM Shipment__c
                WHERE Confirmation__c = 'Pending' AND Status__c = 'Delivered'
                ORDER BY Delivered_At__c LIMIT 30
            ];

            r.pendingCount = pending.size();
            r.awaitingConfirmationCount = unconfirmed.size();

            List<String> lines = new List<String>();
            if (pending.isEmpty() && unconfirmed.isEmpty()) {
                lines.add('Nothing pending - everything is either received or closed.');
            }
            if (!pending.isEmpty()) {
                lines.add('On the way (' + pending.size() + '):');
                for (Purchase__c p : pending) {
                    String line = '- ' + DakiyaAgentFormat.describe(p) + ' - ' + p.Status__c;
                    if (p.Expected_Delivery__c != null) {
                        line += ', expected ' + DakiyaAgentFormat.day(p.Expected_Delivery__c);
                    }
                    lines.add(line);
                }
            }
            if (!unconfirmed.isEmpty()) {
                lines.add('');
                lines.add('Marked delivered but not confirmed by you (' + unconfirmed.size() + '):');
                for (Shipment__c s : unconfirmed) {
                    String vendor = s.Purchase__r.Vendor__r == null ? 'Unknown seller' : s.Purchase__r.Vendor__r.Name;
                    lines.add('- ' + vendor + ' - ' + s.Purchase__r.Title__c
                              + ', courier said delivered ' + DakiyaAgentFormat.when(s.Delivered_At__c));
                }
            }
            r.summary = String.join(lines, '\n');
        } catch (Exception e) {
            r.summary = DakiyaAgentFormat.problem(e);
            r.pendingCount = 0;
            r.awaitingConfirmationCount = 0;
        }

        for (Integer i = 0; i < n; i++) {
            out.add(r);
        }
        return out;
    }
}
