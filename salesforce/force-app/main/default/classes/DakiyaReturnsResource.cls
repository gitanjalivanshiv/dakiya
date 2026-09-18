/** GET /dakiya/v1/returns?open=true */
@RestResource(urlMapping='/dakiya/v1/returns')
global with sharing class DakiyaReturnsResource {

    @HttpGet
    global static void doGet() {
        RestResponse res = RestContext.response;
        try {
            Boolean openOnly = RestContext.request.params.get('open') != 'false';
            Set<String> closed = new Set<String>{ 'Completed', 'Rejected', 'Cancelled' };

            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            for (Return__c r : [
                SELECT Id, Type__c, Status__c, Reason__c, Requested_On__c, Pickup_Date__c,
                       Refund_Initiated_On__c, Refund_Check_Due__c, Refund_Outcome__c,
                       Expected_Refund_Amount__c, Refund_Received_Amount__c, Reminder_Count__c,
                       Purchase__c, Purchase__r.Title__c, Purchase__r.Vendor__r.Name,
                       Purchase__r.Vendor__r.Usual_Refund_Mode__c
                FROM Return__c
                ORDER BY CreatedDate DESC
                LIMIT 200
            ]) {
                if (openOnly && closed.contains(r.Status__c)) {
                    continue;
                }
                rows.add(new Map<String, Object>{
                    'id' => r.Id,
                    'purchaseId' => r.Purchase__c,
                    'title' => r.Purchase__r.Title__c,
                    'vendor' => r.Purchase__r.Vendor__r == null ? null : r.Purchase__r.Vendor__r.Name,
                    'type' => r.Type__c,
                    'status' => r.Status__c,
                    'reason' => r.Reason__c,
                    'requestedOn' => r.Requested_On__c,
                    'pickupDate' => r.Pickup_Date__c,
                    'refundInitiatedOn' => r.Refund_Initiated_On__c,
                    'refundCheckDue' => r.Refund_Check_Due__c,
                    'outcome' => r.Refund_Outcome__c,
                    'expectedRefund' => r.Expected_Refund_Amount__c,
                    'refundReceived' => r.Refund_Received_Amount__c,
                    'remindersSent' => r.Reminder_Count__c,
                    'vendorUsualMode' => r.Purchase__r.Vendor__r == null
                        ? null : r.Purchase__r.Vendor__r.Usual_Refund_Mode__c
                });
            }
            DakiyaApi.ok(res, new Map<String, Object>{ 'returns' => rows });
        } catch (Exception e) {
            DakiyaApi.fail(res, 500, 'RETURNS_FAILED', e.getMessage());
        }
    }
}
