/**
 * Enforces the project's first rule: nothing is recorded that cannot be pointed
 * to in the source text.
 *
 * For each of order_id, awb, amount and event_type that the extractor returned,
 * there must be an evidence quote that appears verbatim in the masked body.
 * A field whose quote does not check out is nulled and confidence drops by 0.2
 * (BUILD_SPEC 5.4 step 3). The extraction is never discarded wholesale, because
 * a message with one bad field and three good ones is still worth matching.
 */
public with sharing class DakiyaEvidenceValidator {
    /** Confidence lost per field that failed its evidence check. */
    @TestVisible
    private static final Decimal PENALTY = 0.2;

    public class Result {
        public DakiyaExtraction extraction;
        /** Names of fields dropped for want of valid evidence. */
        public List<String> dropped = new List<String>();
        public Boolean isClean() {
            return dropped.isEmpty();
        }
    }

    public static Result validate(DakiyaExtraction ex, String maskedBody) {
        Result r = new Result();
        r.extraction = ex;
        if (ex == null) {
            return r;
        }

        String body = normalize(maskedBody);
        DakiyaExtraction.Evidence ev = ex.evidence;

        if (String.isNotBlank(ex.order_id) && !quoteHolds(ev == null ? null : ev.order_id, ex.order_id, body, false)) {
            ex.order_id = null;
            r.dropped.add('order_id');
        }
        if (String.isNotBlank(ex.awb) && !quoteHolds(ev == null ? null : ev.awb, ex.awb, body, false)) {
            ex.awb = null;
            r.dropped.add('awb');
        }
        if (ex.amount != null && !quoteHolds(ev == null ? null : ev.amount, String.valueOf(ex.amount), body, true)) {
            ex.amount = null;
            r.dropped.add('amount');
        }
        // event_type drives the whole state machine, so an unevidenced one
        // degrades to 'other' rather than null - the message is still logged.
        if (String.isNotBlank(ex.event_type)
            && ex.event_type != DakiyaConstants.EV_OTHER
            && !quoteHolds(ev == null ? null : ev.event_type, null, body, false)) {
            ex.event_type = DakiyaConstants.EV_OTHER;
            r.dropped.add('event_type');
        }

        if (!r.dropped.isEmpty()) {
            Decimal c = ex.confidence == null ? 0 : ex.confidence;
            ex.confidence = Math.max(0, c - (PENALTY * r.dropped.size()));
        }
        return r;
    }

    /**
     * A quote holds when it is non-blank, appears in the body, and - when the
     * field has a value of its own - that value appears inside the quote. The
     * second check is what stops a model quoting a real sentence and attaching
     * an invented order id to it.
     */
    @TestVisible
    private static Boolean quoteHolds(String quote, String fieldValue, String body, Boolean isAmount) {
        if (String.isBlank(quote)) {
            return false;
        }
        String q = normalize(quote);
        String b = body;
        if (isAmount) {
            q = stripCurrency(q);
            b = stripCurrency(b);
        }
        if (String.isBlank(q) || !b.contains(q)) {
            return false;
        }
        if (String.isNotBlank(fieldValue)) {
            String v = normalize(fieldValue);
            if (isAmount) {
                v = stripCurrency(v);
                // 1299.00 and 1299 are the same amount in a quote.
                if (v.endsWith('.00')) {
                    v = v.removeEnd('.00');
                }
            }
            if (!q.contains(v)) {
                return false;
            }
        }
        return true;
    }

    /** Lowercase and collapse whitespace so formatting differences never matter. */
    @TestVisible
    private static String normalize(String s) {
        if (s == null) {
            return '';
        }
        return s.toLowerCase().replaceAll('\\s+', ' ').trim();
    }

    /** Amounts are quoted as Rs.1,299 / INR 1299 / 1299.00 - all the same number. */
    @TestVisible
    private static String stripCurrency(String s) {
        return s.replaceAll('(?i)(inr|rs\\.?|₹)', '').replaceAll('[,\\s]', '');
    }
}
