/** POST /services/apexrest/dakiya/v1/ingest - the Worker's intake endpoint. */
@RestResource(urlMapping='/dakiya/v1/ingest')
global with sharing class DakiyaIngestResource {

    @HttpPost
    global static void doPost() {
        RestResponse res = RestContext.response;
        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
                RestContext.request.requestBody.toString()
            );

            DakiyaIngestService.IngestResult r = DakiyaIngestService.ingest(
                (String) body.get('channel'),
                (String) body.get('sender'),
                (String) body.get('subject'),
                (String) body.get('bodyMasked'),
                parseDt((String) body.get('receivedAt')),
                (String) body.get('dedupeKey')
            );

            // Duplicates are a 200, not an error - the Worker retries safely.
            DakiyaApi.ok(res, new Map<String, Object>{
                'id' => r.id, 'duplicate' => r.duplicate
            });
        } catch (DakiyaIngestService.IngestException e) {
            DakiyaApi.fail(res, 400, 'BAD_REQUEST', e.getMessage());
        } catch (Exception e) {
            DakiyaApi.fail(res, 500, 'INGEST_FAILED', e.getMessage());
        }
    }

    private static Datetime parseDt(String s) {
        if (String.isBlank(s)) {
            return null;
        }
        try {
            return (Datetime) JSON.deserialize('"' + s + '"', Datetime.class);
        } catch (Exception e) {
            return null;
        }
    }
}
