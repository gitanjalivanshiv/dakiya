/** GET /dakiya/v1/vendors - with the learned refund stats the agent quotes. */
@RestResource(urlMapping='/dakiya/v1/vendors')
global with sharing class DakiyaVendorsResource {

    @HttpGet
    global static void doGet() {
        RestResponse res = RestContext.response;
        try {
            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            for (Vendor__c v : [
                SELECT Id, Name, Channel__c, Instagram_Handle__c, Return_Window_Days__c,
                       Typical_Refund_Days__c, Usual_Refund_Mode__c, Refund_History_Summary__c,
                       Follow_Up_After_Days__c
                FROM Vendor__c ORDER BY Name LIMIT 500
            ]) {
                rows.add(new Map<String, Object>{
                    'id' => v.Id, 'name' => v.Name, 'channel' => v.Channel__c,
                    'instagramHandle' => v.Instagram_Handle__c,
                    'returnWindowDays' => v.Return_Window_Days__c,
                    'typicalRefundDays' => v.Typical_Refund_Days__c,
                    'usualRefundMode' => v.Usual_Refund_Mode__c,
                    'refundHistory' => v.Refund_History_Summary__c,
                    'followUpAfterDays' => v.Follow_Up_After_Days__c
                });
            }
            DakiyaApi.ok(res, new Map<String, Object>{ 'vendors' => rows });
        } catch (Exception e) {
            DakiyaApi.fail(res, 500, 'VENDORS_FAILED', e.getMessage());
        }
    }
}
