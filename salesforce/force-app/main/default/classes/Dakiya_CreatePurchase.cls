/**
 * Agent action: record an order the automatic intake cannot see - typically an
 * Instagram seller, where there is no order email and no courier SMS.
 */
public with sharing class Dakiya_CreatePurchase {

    public class Request {
        @InvocableVariable(label='Vendor Name' description='Seller name or Instagram handle. Created if not already on file.' required=true)
        public String vendorName;
        @InvocableVariable(label='Channel' description='Marketplace, Instagram, D2C Website or Other.')
        public String channel;
        @InvocableVariable(label='Title' description='Short description of what was bought, e.g. "two soaps".')
        public String title;
        @InvocableVariable(label='Items' description='Item names, comma separated. Only what the user actually said.')
        public String items;
        @InvocableVariable(label='Amount' description='Total paid in rupees. Leave empty if the user did not say.')
        public Decimal amount;
        @InvocableVariable(label='Order Date') public Date orderDate;
        @InvocableVariable(label='Payment Method' description='UPI, Card, COD, Wallet, Other or Unknown.')
        public String paymentMethod;
        @InvocableVariable(label='Order Id' description='The seller\'s order number, only if the user gave one.')
        public String orderId;
        @InvocableVariable(label='Instagram Handle') public String instagramHandle;
    }

    public class Response {
        @InvocableVariable(label='Summary') public String summary;
        @InvocableVariable(label='Purchase Id') public String purchaseId;
        @InvocableVariable(label='Created') public Boolean created;
    }

    @InvocableMethod(
        label='Dakiya: Create Purchase'
        description='Records a new order that arrived outside email and SMS, such as an Instagram or WhatsApp purchase. Use for "I ordered two soaps from @shop for 450 rupees", "add an order", "log this purchase". Only record details the user actually stated - never invent an order number, amount or date.'
        category='Dakiya'
    )
    public static List<Response> run(List<Request> requests) {
        List<Response> out = new List<Response>();
        for (Request req : requests) {
            Response r = new Response();
            r.created = false;
            try {
                if (String.isBlank(req.vendorName)) {
                    r.summary = 'I need to know who you bought it from before I can record it.';
                    out.add(r);
                    continue;
                }

                Vendor__c v = DakiyaParserRegistry.findByName(req.vendorName);
                if (v == null) {
                    String channel = String.isBlank(req.channel)
                        ? (req.vendorName.startsWith('@') ? 'Instagram' : 'Other')
                        : req.channel;
                    v = new Vendor__c(
                        Name = req.vendorName.left(80),
                        Channel__c = channel,
                        Instagram_Handle__c = String.isBlank(req.instagramHandle)
                            ? (req.vendorName.startsWith('@') ? req.vendorName.left(80) : null)
                            : req.instagramHandle.left(80),
                        // Instagram sellers go quiet more often, so chase them sooner.
                        Follow_Up_After_Days__c = channel == 'Instagram'
                            ? DakiyaSettings.instagramFollowUpDays() : null
                    );
                    insert v;
                }

                DakiyaExtraction ex = new DakiyaExtraction();
                ex.is_commerce = true;
                ex.vendor_name = req.vendorName;
                ex.event_type = DakiyaConstants.EV_ORDER_PLACED;
                ex.order_id = req.orderId;
                ex.amount = req.amount;
                ex.event_date = req.orderDate == null ? null : String.valueOf(req.orderDate);
                ex.items = itemsFrom(req.items);

                Purchase__c p = DakiyaEventApplier.createPurchase(ex, v.Id, 'Chat');
                if (String.isNotBlank(req.title)) { p.Title__c = req.title.left(255); }
                if (String.isNotBlank(req.paymentMethod)) { p.Payment_Method__c = req.paymentMethod; }
                update p;

                insert new Tracking_Event__c(
                    Purchase__c = p.Id, Event_Type__c = DakiyaConstants.EV_ORDER_PLACED,
                    Event_At__c = Datetime.now(), Summary__c = 'Recorded by the user in chat',
                    Applied_By__c = DakiyaConstants.BY_AGENT
                );

                r.created = true;
                r.purchaseId = p.Id;
                r.summary = 'Recorded: ' + req.vendorName
                    + (String.isBlank(req.title) ? '' : ' - ' + req.title)
                    + (req.amount == null ? '' : ' (' + DakiyaAgentFormat.rupees(req.amount) + ')')
                    + '. I will track it from here.';
            } catch (Exception e) {
                r.summary = DakiyaAgentFormat.problem(e);
            }
            out.add(r);
        }
        return out;
    }

    private static List<DakiyaExtraction.Item> itemsFrom(String csv) {
        List<DakiyaExtraction.Item> out = new List<DakiyaExtraction.Item>();
        if (String.isBlank(csv)) { return out; }
        for (String name : csv.split(',')) {
            if (String.isBlank(name)) { continue; }
            DakiyaExtraction.Item i = new DakiyaExtraction.Item();
            i.name = name.trim();
            i.qty = 1;
            out.add(i);
        }
        return out;
    }
}
