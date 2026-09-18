/** POST /dakiya/v1/actions - the decisions only Gitanjali can make. */
@RestResource(urlMapping='/dakiya/v1/actions')
global with sharing class DakiyaActionsResource {

    @HttpPost
    global static void doPost() {
        RestResponse res = RestContext.response;
        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
                RestContext.request.requestBody.toString()
            );
            String action = (String) body.get('action');
            String recordId = (String) body.get('recordId');
            Map<String, Object> payload = body.get('payload') == null
                ? new Map<String, Object>()
                : (Map<String, Object>) body.get('payload');

            if (String.isBlank(recordId)) {
                DakiyaApi.fail(res, 400, 'BAD_REQUEST', 'recordId is required');
                return;
            }
            DakiyaApi.ok(res, DakiyaActionService.run(action, (Id) recordId, payload));
        } catch (DakiyaActionService.ActionException e) {
            DakiyaApi.fail(res, 400, 'BAD_REQUEST', e.getMessage());
        } catch (Exception e) {
            DakiyaApi.fail(res, 500, 'ACTION_FAILED', e.getMessage());
        }
    }
}
