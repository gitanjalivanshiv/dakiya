/**
 * GET /dakiya/v1/health
 *
 * Storage is reported because this org has 5 MB total and roughly 1000 records
 * of headroom - the retention jobs are load-bearing, so the number is worth
 * watching from the Settings screen rather than discovering when writes fail.
 */
@RestResource(urlMapping='/dakiya/v1/health')
global with sharing class DakiyaHealthResource {

    @HttpGet
    global static void doGet() {
        RestResponse res = RestContext.response;
        try {
            Datetime lastJobRun;
            List<Inbound_Message__c> recent = [
                SELECT LastModifiedDate FROM Inbound_Message__c
                WHERE Processing_Status__c != 'New'
                ORDER BY LastModifiedDate DESC LIMIT 1
            ];
            if (!recent.isEmpty()) {
                lastJobRun = recent[0].LastModifiedDate;
            }

            DakiyaApi.ok(res, new Map<String, Object>{
                'ok' => true,
                'lastJobRun' => lastJobRun,
                'counts' => new Map<String, Object>{
                    'purchases' => [SELECT COUNT() FROM Purchase__c],
                    'openReturns' => [
                        SELECT COUNT() FROM Return__c
                        WHERE Status__c NOT IN ('Completed', 'Rejected', 'Cancelled')
                    ],
                    'reviewQueue' => [
                        SELECT COUNT() FROM Inbound_Message__c
                        WHERE Processing_Status__c = 'Needs Review'
                    ],
                    'pendingNotifications' => [
                        SELECT COUNT() FROM Notification__c WHERE Status__c = 'Pending'
                    ]
                }
            });
        } catch (Exception e) {
            DakiyaApi.fail(res, 500, 'HEALTH_FAILED', e.getMessage());
        }
    }
}
