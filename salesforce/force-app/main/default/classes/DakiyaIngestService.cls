/**
 * Accepts a masked message from the Worker and parks it for processing.
 *
 * This does the minimum and returns: insert the row, enqueue the job. Parsing
 * and the LLM callout happen in DakiyaProcessMessageJob because Apex forbids
 * callouts after DML in the same transaction (BUILD_SPEC 3).
 *
 * Dedupe is by Dedupe_Key__c, so Gmail re-delivering the same message or
 * MacroDroid firing twice is a no-op rather than a duplicate order.
 */
public with sharing class DakiyaIngestService {

    public class IngestResult {
        public Id id;
        public Boolean duplicate = false;

        public IngestResult(Id id, Boolean duplicate) {
            this.id = id;
            this.duplicate = duplicate;
        }
    }

    public class IngestException extends Exception {}

    /**
     * @param channel   Email, SMS, Share, Chat or WhatsApp
     * @param bodyMasked ALREADY masked by the Worker. Never pass raw text here.
     */
    public static IngestResult ingest(
        String channel,
        String sender,
        String subject,
        String bodyMasked,
        Datetime receivedAt,
        String dedupeKey
    ) {
        if (String.isBlank(channel)) {
            throw new IngestException('channel is required');
        }
        if (String.isBlank(dedupeKey)) {
            throw new IngestException('dedupeKey is required');
        }

        List<Inbound_Message__c> existing = [
            SELECT Id FROM Inbound_Message__c WHERE Dedupe_Key__c = :dedupeKey LIMIT 1
        ];
        if (!existing.isEmpty()) {
            return new IngestResult(existing[0].Id, true);
        }

        Inbound_Message__c msg = new Inbound_Message__c(
            Channel__c = channel,
            Sender__c = truncate(sender, 255),
            Subject__c = truncate(subject, 255),
            Body_Masked__c = truncate(bodyMasked, 32000),
            Received_At__c = receivedAt == null ? Datetime.now() : receivedAt,
            Dedupe_Key__c = truncate(dedupeKey, 128),
            Processing_Status__c = 'New'
        );

        try {
            insert msg;
        } catch (DmlException e) {
            // Two requests raced on the same key. The other one won, which is fine.
            if (e.getMessage().contains('DUPLICATE_VALUE')) {
                List<Inbound_Message__c> raced = [
                    SELECT Id FROM Inbound_Message__c WHERE Dedupe_Key__c = :dedupeKey LIMIT 1
                ];
                if (!raced.isEmpty()) {
                    return new IngestResult(raced[0].Id, true);
                }
            }
            throw e;
        }

        enqueue(msg.Id);
        return new IngestResult(msg.Id, false);
    }

    /**
     * Queueable chaining is not allowed from a Queueable in a test context, and
     * a full queue is a poor reason to lose a message - the row is already saved
     * and the scheduler can pick up stragglers.
     */
    private static void enqueue(Id messageId) {
        if (Test.isRunningTest()) {
            return;
        }
        try {
            System.enqueueJob(new DakiyaProcessMessageJob(messageId));
        } catch (Exception e) {
            // Leave it as New; it stays visible in the review queue.
        }
    }

    private static String truncate(String s, Integer max) {
        if (String.isBlank(s)) {
            return s;
        }
        return s.length() > max ? s.substring(0, max) : s;
    }
}
