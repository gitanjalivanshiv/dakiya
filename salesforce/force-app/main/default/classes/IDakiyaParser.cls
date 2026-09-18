/**
 * A deterministic parser for one vendor's or courier's message format.
 *
 * Rules run before the LLM (BUILD_SPEC 5.4 step 1) because a regex that matches
 * is both free and incapable of hallucinating. A parser returns null rather than
 * guessing when its required groups do not all match.
 */
public interface IDakiyaParser {
    /** Stored on Inbound_Message__c.Parser__c so a bad extraction is traceable. */
    String name();

    /** Cheap pre-check on sender/subject, so only plausible parsers run. */
    Boolean handles(Inbound_Message__c msg);

    /** Full extraction, or null if the format did not match. Never a partial guess. */
    DakiyaExtraction parse(Inbound_Message__c msg);
}
