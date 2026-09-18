/** Agent action: find orders by seller, text, status or date range. */
public with sharing class Dakiya_SearchPurchases {

    public class Request {
        @InvocableVariable(label='Vendor' description='Seller name, e.g. Myntra, Nykaa, or an Instagram handle like @soap_shop.')
        public String vendor;
        @InvocableVariable(label='Search Text' description='Words from the item or order title, e.g. "serum".')
        public String text;
        @InvocableVariable(label='Status' description='One of: Placed, Confirmed, Partially Shipped, Shipped, Out for Delivery, Delivered (Unconfirmed), Received, Not Received, Cancelled, Return in Progress, Closed.')
        public String status;
        @InvocableVariable(label='From Date') public Date fromDate;
        @InvocableVariable(label='To Date') public Date toDate;
    }

    public class Response {
        @InvocableVariable(label='Summary') public String summary;
        @InvocableVariable(label='Match Count') public Integer matchCount;
        @InvocableVariable(label='Purchase Ids' description='Ids of the matches, for use by follow-up actions.')
        public List<String> purchaseIds;
    }

    @InvocableMethod(
        label='Dakiya: Search Purchases'
        description='Searches the user\'s orders by seller, keyword, status or date range. Use for questions like "where is my Myntra order", "show my Nykaa orders", "what did I buy last week", "which orders are still shipping".'
        category='Dakiya'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            Response r = new Response();
            r.purchaseIds = new List<String>();
            try {
                String soql = 'SELECT ' + DakiyaApi.PURCHASE_FIELDS + ' FROM Purchase__c';
                List<String> wheres = new List<String>();
                String vendor = req.vendor, status = req.status;
                Date fromDate = req.fromDate, toDate = req.toDate;
                String text = String.isBlank(req.text) ? null : '%' + String.escapeSingleQuotes(req.text) + '%';

                if (String.isNotBlank(vendor)) { wheres.add('Vendor__r.Name LIKE :vendor'); vendor = '%' + vendor + '%'; }
                if (String.isNotBlank(status)) { wheres.add('Status__c = :status'); }
                if (text != null)              { wheres.add('(Title__c LIKE :text OR External_Order_Id__c LIKE :text)'); }
                if (fromDate != null)          { wheres.add('Order_Date__c >= :fromDate'); }
                if (toDate != null)            { wheres.add('Order_Date__c <= :toDate'); }
                if (!wheres.isEmpty()) { soql += ' WHERE ' + String.join(wheres, ' AND '); }
                soql += ' ORDER BY Order_Date__c DESC NULLS LAST LIMIT 25';

                List<Purchase__c> found = Database.query(soql);
                r.matchCount = found.size();

                if (found.isEmpty()) {
                    r.summary = 'No orders match that. Nothing was found - I have not guessed at anything close.';
                } else {
                    List<String> lines = new List<String>{ found.size() + ' matching order(s):' };
                    for (Purchase__c p : found) {
                        r.purchaseIds.add(p.Id);
                        String line = '- ' + DakiyaAgentFormat.describe(p) + ' - ' + p.Status__c;
                        if (p.Order_Date__c != null) { line += ', ordered ' + DakiyaAgentFormat.day(p.Order_Date__c); }
                        lines.add(line);
                    }
                    r.summary = String.join(lines, '\n');
                }
            } catch (Exception e) {
                r.summary = DakiyaAgentFormat.problem(e);
                r.matchCount = 0;
            }
            out.add(r);
        }
        return out;
    }
}
