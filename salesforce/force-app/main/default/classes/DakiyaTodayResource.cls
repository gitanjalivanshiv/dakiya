/** GET /services/apexrest/dakiya/v1/today - everything needing attention. */
@RestResource(urlMapping='/dakiya/v1/today')
global with sharing class DakiyaTodayResource {

    @HttpGet
    global static void doGet() {
        try {
            DakiyaApi.ok(RestContext.response, DakiyaTodayService.build());
        } catch (Exception e) {
            DakiyaApi.fail(RestContext.response, 500, 'TODAY_FAILED', e.getMessage());
        }
    }
}
