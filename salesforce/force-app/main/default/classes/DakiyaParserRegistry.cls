/**
 * Chooses a rule parser for an inbound message, and resolves its vendor.
 *
 * Phase 1 registers no parsers - they are built in Phase 6 from Gitanjali's real
 * masked samples rather than from guesses about what Amazon's emails look like.
 * Until then every message falls through to the LLM path.
 */
public with sharing class DakiyaParserRegistry {
    @TestVisible
    private static List<IDakiyaParser> parsers = new List<IDakiyaParser>();

    /** Test seam, and the hook Phase 6 uses to register vendor parsers. */
    @TestVisible
    public static void register(IDakiyaParser p) {
        parsers.add(p);
    }

    @TestVisible
    public static void clear() {
        parsers = new List<IDakiyaParser>();
    }

    /** First parser that claims the message, or null to fall through to the LLM. */
    public static IDakiyaParser selectFor(Inbound_Message__c msg) {
        if (msg == null) {
            return null;
        }
        for (IDakiyaParser p : parsers) {
            try {
                if (p.handles(msg)) {
                    return p;
                }
            } catch (Exception e) {
                // A broken parser must not stop the pipeline; the LLM path still runs.
                continue;
            }
        }
        return null;
    }

    /**
     * Resolve the vendor from the message sender using the pattern lists on
     * Vendor__c. Email senders match Email_Sender_Patterns__c, SMS senders match
     * SMS_Sender_Patterns__c; both are one pattern per line, matched as a
     * case-insensitive substring of the sender.
     */
    public static Vendor__c resolveVendor(Inbound_Message__c msg) {
        if (msg == null || String.isBlank(msg.Sender__c)) {
            return null;
        }
        String sender = msg.Sender__c.toLowerCase();
        Boolean isSms = msg.Channel__c == 'SMS';

        for (Vendor__c v : [
            SELECT Id, Name, Channel__c, Return_Window_Days__c, Typical_Refund_Days__c,
                   Follow_Up_After_Days__c, Email_Sender_Patterns__c, SMS_Sender_Patterns__c
            FROM Vendor__c
            LIMIT 500
        ]) {
            String patterns = isSms ? v.SMS_Sender_Patterns__c : v.Email_Sender_Patterns__c;
            if (String.isBlank(patterns)) {
                continue;
            }
            for (String line : patterns.split('\n')) {
                String pattern = line.trim().toLowerCase();
                if (String.isNotBlank(pattern) && sender.contains(pattern)) {
                    return v;
                }
            }
        }
        return null;
    }

    /** Vendor by exact name, case-insensitive. Used by the agent's create actions. */
    public static Vendor__c findByName(String vendorName) {
        if (String.isBlank(vendorName)) {
            return null;
        }
        String needle = vendorName.trim();
        List<Vendor__c> found = [
            SELECT Id, Name, Channel__c, Return_Window_Days__c, Typical_Refund_Days__c,
                   Follow_Up_After_Days__c
            FROM Vendor__c
            WHERE Name = :needle
            LIMIT 1
        ];
        return found.isEmpty() ? null : found[0];
    }
}
