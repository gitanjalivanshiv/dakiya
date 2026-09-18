/** Test fixtures. Kept in one place so tests read as behaviour, not setup. */
@IsTest
public class DakiyaTestData {

    public static Vendor__c vendor(String name, String channel) {
        Vendor__c v = new Vendor__c(
            Name = name,
            Channel__c = channel,
            Email_Sender_Patterns__c = name.toLowerCase() + '.in',
            SMS_Sender_Patterns__c = name.toUpperCase(),
            Return_Window_Days__c = 7
        );
        insert v;
        return v;
    }

    public static Purchase__c purchase(Id vendorId, String status, Decimal amount) {
        Purchase__c p = new Purchase__c(
            Vendor__c = vendorId,
            Title__c = 'Test order',
            External_Order_Id__c = 'OD' + String.valueOf(Crypto.getRandomLong()).replace('-', ''),
            Vendor_Order_Key__c = String.valueOf(vendorId) + ':' + Crypto.getRandomLong(),
            Status__c = status,
            Status_Rank__c = DakiyaConstants.rankOf(status),
            Total_Amount__c = amount,
            Order_Date__c = Date.today().addDays(-3),
            Source__c = 'Email',
            Last_Event_At__c = Datetime.now().addDays(-1)
        );
        insert p;
        return p;
    }

    public static Shipment__c shipment(Id purchaseId, String awb, String status) {
        Shipment__c s = new Shipment__c(
            Purchase__c = purchaseId,
            AWB__c = awb,
            Courier__c = 'Delhivery',
            Status__c = status,
            Confirmation__c = status == 'Delivered' ? 'Pending' : null,
            Delivered_At__c = status == 'Delivered' ? Datetime.now().addHours(-6) : null
        );
        insert s;
        return s;
    }

    public static Inbound_Message__c message(String channel, String sender, String body) {
        Inbound_Message__c m = new Inbound_Message__c(
            Channel__c = channel,
            Sender__c = sender,
            Subject__c = 'Test subject',
            Body_Masked__c = body,
            Received_At__c = Datetime.now(),
            Dedupe_Key__c = 'test-' + Crypto.getRandomLong(),
            Processing_Status__c = 'New'
        );
        insert m;
        return m;
    }

    /** An extraction that would pass evidence validation against `body`. */
    public static DakiyaExtraction extraction(String eventType, String orderId, String awb, Decimal amount) {
        DakiyaExtraction ex = new DakiyaExtraction();
        ex.is_commerce = true;
        ex.event_type = eventType;
        ex.order_id = orderId;
        ex.awb = awb;
        ex.amount = amount;
        ex.confidence = 0.95;
        ex.evidence = new DakiyaExtraction.Evidence();
        ex.evidence.order_id = orderId == null ? null : 'Order ' + orderId;
        ex.evidence.awb = awb == null ? null : 'AWB ' + awb;
        ex.evidence.amount = amount == null ? null : 'Rs. ' + amount;
        ex.evidence.event_type = eventType;
        return ex;
    }
}
