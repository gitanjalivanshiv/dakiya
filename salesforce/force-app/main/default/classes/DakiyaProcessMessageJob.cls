/**
 * Parses one inbound message and applies what it finds.
 *
 * Runs as a Queueable because Apex forbids callouts after DML in the same
 * transaction, and the LLM fallback is a callout (BUILD_SPEC 3).
 *
 * Order of business (BUILD_SPEC 5.4):
 *   1. rules first - free, deterministic, cannot hallucinate
 *   2. LLM only if no rule matched          [STUBBED until Phase 6]
 *   3. validate every field against its evidence quote
 *   4. score candidate purchases
 *   5. apply only at or above AutoApplyConfidence; otherwise ask
 */
public with sharing class DakiyaProcessMessageJob implements Queueable, Database.AllowsCallouts {

    private final Id messageId;

    public DakiyaProcessMessageJob(Id messageId) {
        this.messageId = messageId;
    }

    public void execute(QueueableContext ctx) {
        process(messageId);
    }

    /** Separated from execute() so tests can drive it without the queue. */
    public static void process(Id messageId) {
        List<Inbound_Message__c> found = [
            SELECT Id, Channel__c, Sender__c, Subject__c, Body_Masked__c, Received_At__c,
                   Processing_Status__c, Parser__c, Extraction_JSON__c, Confidence__c,
                   Related_Purchase__c
            FROM Inbound_Message__c WHERE Id = :messageId LIMIT 1
        ];
        if (found.isEmpty()) {
            return;
        }
        Inbound_Message__c msg = found[0];

        try {
            // ── 1. Rules ──────────────────────────────────────────────
            DakiyaExtraction ex;
            String appliedBy = DakiyaConstants.BY_RULE;
            IDakiyaParser parser = DakiyaParserRegistry.selectFor(msg);
            if (parser != null) {
                ex = parser.parse(msg);
                msg.Parser__c = parser.name();
            }

            // ── 2. LLM fallback ───────────────────────────────────────
            if (ex == null) {
                ex = extractWithLlm(msg);
                appliedBy = DakiyaConstants.BY_LLM;
                msg.Parser__c = 'PromptTemplate:Dakiya_Extract';
            }

            if (ex == null) {
                // Nothing could read it. Park it for a human rather than guess.
                finish(msg, 'Needs Review', null, null, 'No parser matched and no extraction available');
                return;
            }

            if (ex.is_commerce == false) {
                finish(msg, 'Ignored', JSON.serialize(ex), ex.confidence, null);
                return;
            }

            // ── 3. Evidence validation ────────────────────────────────
            DakiyaEvidenceValidator.Result ev = DakiyaEvidenceValidator.validate(ex, msg.Body_Masked__c);
            if (String.isBlank(ex.event_type) || !DakiyaConstants.EVENT_TYPES.contains(ex.event_type)) {
                ex.event_type = DakiyaConstants.EV_OTHER;
            }

            // ── 4. Match ──────────────────────────────────────────────
            Vendor__c vendor = DakiyaParserRegistry.resolveVendor(msg);
            if (vendor == null && String.isNotBlank(ex.vendor_name)) {
                vendor = DakiyaParserRegistry.findByName(ex.vendor_name);
            }
            Id vendorId = vendor == null ? null : vendor.Id;

            DakiyaMatchingService.MatchResult mr = DakiyaMatchingService.match(ex, vendorId);
            msg.Candidate_Matches_JSON__c = JSON.serialize(mr.candidates);

            Decimal extractionConfidence = ex.confidence == null ? 0 : ex.confidence;
            Decimal effective = Math.min(extractionConfidence, mr.bestScore());

            // ── 5. Apply, or ask ──────────────────────────────────────
            if (mr.shouldCreateNew && vendorId != null && extractionConfidence >= DakiyaSettings.autoApplyConfidence()) {
                Purchase__c created = DakiyaEventApplier.createPurchase(ex, vendorId, sourceFor(msg.Channel__c));
                msg.Related_Purchase__c = created.Id;
                finish(msg, parsedStatus(appliedBy), JSON.serialize(ex), extractionConfidence, null);
                return;
            }

            if (mr.best != null && effective >= DakiyaSettings.autoApplyConfidence()) {
                Purchase__c p = [
                    SELECT Id, Status__c, Status_Rank__c, Vendor__c, Delivered_At__c,
                           Needs_Review__c, Expected_Delivery__c, Return_Window_Ends__c,
                           Last_Event_At__c
                    FROM Purchase__c WHERE Id = :mr.best.purchaseId LIMIT 1
                ];
                DakiyaEventApplier.apply(p, ex, msg.Id, appliedBy);
                msg.Related_Purchase__c = p.Id;
                finish(msg, parsedStatus(appliedBy), JSON.serialize(ex), effective, null);
                return;
            }

            // Not confident enough. Nothing is ever applied tentatively.
            if (mr.best != null) {
                msg.Related_Purchase__c = mr.best.purchaseId;
            }
            finish(msg, 'Needs Review', JSON.serialize(ex), effective, null);

        } catch (Exception e) {
            finish(msg, 'Error', msg.Extraction_JSON__c, msg.Confidence__c,
                   e.getTypeName() + ': ' + e.getMessage() + '\n' + e.getStackTraceString());
        }
    }

    /**
     * The LLM extraction path.
     *
     * STUB (Phase 1). Phase 6 wires this to the Dakiya_Extract prompt template,
     * with the Worker's Claude Haiku endpoint as the fallback when Prompt Builder
     * is unavailable - selected by Dakiya_Setting__mdt.Extractor.
     *
     * Returning null is the honest answer for now: it sends the message to the
     * review queue rather than inventing an extraction.
     */
    @TestVisible
    private static DakiyaExtraction extractWithLlm(Inbound_Message__c msg) {
        return null;
    }

    private static String parsedStatus(String appliedBy) {
        return appliedBy == DakiyaConstants.BY_RULE ? 'Parsed (Rule)' : 'Parsed (LLM)';
    }

    private static String sourceFor(String channel) {
        if (channel == 'Email') { return 'Email'; }
        if (channel == 'SMS')   { return 'SMS'; }
        if (channel == 'Share') { return 'Share'; }
        if (channel == 'Chat')  { return 'Chat'; }
        return 'Manual';
    }

    private static void finish(Inbound_Message__c msg, String status, String extractionJson,
                               Decimal confidence, String error) {
        msg.Processing_Status__c = status;
        if (extractionJson != null) {
            msg.Extraction_JSON__c = extractionJson.length() > 32000
                ? extractionJson.substring(0, 32000) : extractionJson;
        }
        if (confidence != null) {
            // Confidence__c is a percent field; the contract carries 0-1.
            msg.Confidence__c = confidence <= 1 ? confidence * 100 : confidence;
        }
        if (String.isNotBlank(error)) {
            msg.Error__c = error.length() > 4000 ? error.substring(0, 4000) : error;
        }
        update msg;
    }
}
