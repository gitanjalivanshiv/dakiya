/**
 * GET  /dakiya/v1/notifications/due          what the Worker cron should send
 * POST /dakiya/v1/notifications/{id}/result  what happened when it tried
 */
@RestResource(urlMapping='/dakiya/v1/notifications/*')
global with sharing class DakiyaNotificationsResource {

    @HttpGet
    global static void doGet() {
        RestResponse res = RestContext.response;
        try {
            String tail = DakiyaApi.pathTail(RestContext.request.requestURI, '/dakiya/v1/notifications');
            if (tail != 'due') {
                DakiyaApi.fail(res, 404, 'NOT_FOUND', 'Unknown notifications path: ' + tail);
                return;
            }
            Datetime now = Datetime.now();
            List<Map<String, Object>> rows = new List<Map<String, Object>>();
            for (Notification__c n : [
                SELECT Id, Type__c, Title__c, Body__c, Actions_JSON__c, Deep_Link__c,
                       Related_Record_Id__c, Due_At__c
                FROM Notification__c
                WHERE Status__c = 'Pending' AND Due_At__c <= :now
                ORDER BY Due_At__c
                LIMIT 20
            ]) {
                rows.add(new Map<String, Object>{
                    'id' => n.Id, 'type' => n.Type__c, 'title' => n.Title__c,
                    'body' => n.Body__c, 'actions' => n.Actions_JSON__c,
                    'deepLink' => n.Deep_Link__c, 'relatedRecordId' => n.Related_Record_Id__c,
                    'dueAt' => n.Due_At__c
                });
            }
            DakiyaApi.ok(res, new Map<String, Object>{ 'notifications' => rows });
        } catch (Exception e) {
            DakiyaApi.fail(res, 500, 'NOTIFICATIONS_FAILED', e.getMessage());
        }
    }

    @HttpPost
    global static void doPost() {
        RestResponse res = RestContext.response;
        try {
            String tail = DakiyaApi.pathTail(RestContext.request.requestURI, '/dakiya/v1/notifications');
            if (String.isBlank(tail) || !tail.endsWith('/result')) {
                DakiyaApi.fail(res, 404, 'NOT_FOUND', 'Expected /notifications/{id}/result');
                return;
            }
            Id notificationId = (Id) tail.removeEnd('/result');

            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
                RestContext.request.requestBody.toString()
            );
            String status = (String) body.get('status');
            if (status != 'Sent' && status != 'Failed') {
                DakiyaApi.fail(res, 400, 'BAD_REQUEST', 'status must be Sent or Failed');
                return;
            }

            Notification__c n = new Notification__c(Id = notificationId, Status__c = status);
            if (status == 'Sent') {
                n.Sent_At__c = Datetime.now();
            } else {
                String err = (String) body.get('error');
                n.Error__c = err == null ? 'Unknown error' : err.left(4000);
            }
            update n;
            DakiyaApi.ok(res, new Map<String, Object>{ 'id' => notificationId, 'status' => status });
        } catch (Exception e) {
            DakiyaApi.fail(res, 500, 'NOTIFICATION_RESULT_FAILED', e.getMessage());
        }
    }
}
