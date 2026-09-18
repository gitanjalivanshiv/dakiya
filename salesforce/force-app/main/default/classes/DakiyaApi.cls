/**
 * Shared shape for every Dakiya REST response.
 *
 * One error envelope, one date convention. The Worker and the PWA can then treat
 * all endpoints identically instead of special-casing each one.
 */
public with sharing class DakiyaApi {

    /** Errors are always {"error":{"code":...,"message":...}} (BUILD_SPEC 8). */
    public static void fail(RestResponse res, Integer statusCode, String code, String message) {
        res.statusCode = statusCode;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(new Map<String, Object>{
            'error' => new Map<String, Object>{ 'code' => code, 'message' => message }
        }));
    }

    public static void ok(RestResponse res, Object body) {
        res.statusCode = 200;
        res.addHeader('Content-Type', 'application/json');
        res.responseBody = Blob.valueOf(JSON.serialize(body, true));
    }

    /** The path segment after the resource root, or null. */
    public static String pathTail(String requestURI, String root) {
        if (String.isBlank(requestURI)) {
            return null;
        }
        Integer i = requestURI.indexOf(root);
        if (i < 0) {
            return null;
        }
        String tail = requestURI.substring(i + root.length());
        tail = tail.removeStart('/').removeEnd('/');
        return String.isBlank(tail) ? null : tail;
    }

    public static Integer intParam(String raw, Integer fallback) {
        if (String.isBlank(raw)) {
            return fallback;
        }
        try {
            return Integer.valueOf(raw);
        } catch (Exception e) {
            return fallback;
        }
    }

    /** IST date, since every user-facing date in Dakiya is IST. */
    public static Date todayIst() {
        return Datetime.now().dateGmt() == null
            ? Date.today()
            : Date.valueOf(Datetime.now().format('yyyy-MM-dd', DakiyaConstants.TZ_IST));
    }

    public static Map<String, Object> purchaseSummary(Purchase__c p) {
        return new Map<String, Object>{
            'id' => p.Id,
            'title' => p.Title__c,
            'vendor' => p.Vendor__r == null ? null : p.Vendor__r.Name,
            'vendorId' => p.Vendor__c,
            'status' => p.Status__c,
            'orderId' => p.External_Order_Id__c,
            'amount' => p.Total_Amount__c,
            'orderDate' => p.Order_Date__c,
            'expectedDelivery' => p.Expected_Delivery__c,
            'deliveredAt' => p.Delivered_At__c,
            'lastEventAt' => p.Last_Event_At__c,
            'returnWindowEnds' => p.Return_Window_Ends__c,
            'needsReview' => p.Needs_Review__c
        };
    }

    public static final String PURCHASE_FIELDS =
        'Id, Title__c, Vendor__c, Vendor__r.Name, Status__c, Status_Rank__c, ' +
        'External_Order_Id__c, Total_Amount__c, Order_Date__c, Expected_Delivery__c, ' +
        'Delivered_At__c, Last_Event_At__c, Return_Window_Ends__c, Needs_Review__c, ' +
        'Payment_Method__c, Source__c, Notes__c';
}
