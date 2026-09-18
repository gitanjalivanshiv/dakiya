/**
 * Works out which existing purchase an extraction belongs to (BUILD_SPEC 5.4 step 4).
 *
 * Scores are deliberately conservative. Anything below AutoApplyConfidence goes
 * to the review queue rather than being applied tentatively, because a tracking
 * event written onto the wrong order is harder to notice and undo than a review
 * item that sits there asking a question.
 */
public with sharing class DakiyaMatchingService {

    /** How far back to look. Older orders are settled and would only add noise. */
    private static final Integer LOOKBACK_DAYS = 90;

    public class Candidate implements Comparable {
        public Id purchaseId;
        public Decimal score;
        public String reason;

        public Candidate(Id purchaseId, Decimal score, String reason) {
            this.purchaseId = purchaseId;
            this.score = score;
            this.reason = reason;
        }

        /** Highest score first. */
        public Integer compareTo(Object other) {
            Candidate o = (Candidate) other;
            if (score == o.score) {
                return 0;
            }
            return score > o.score ? -1 : 1;
        }
    }

    public class MatchResult {
        public List<Candidate> candidates = new List<Candidate>();
        public Candidate best;
        /** True when nothing matched and the event is an opening one. */
        public Boolean shouldCreateNew = false;

        public Decimal bestScore() {
            return best == null ? 0 : best.score;
        }
    }

    public static MatchResult match(DakiyaExtraction ex, Id vendorId) {
        MatchResult result = new MatchResult();
        if (ex == null) {
            return result;
        }

        Datetime since = Datetime.now().addDays(-LOOKBACK_DAYS);
        Set<String> openStatuses = new Set<String>{
            DakiyaConstants.ST_PLACED, DakiyaConstants.ST_CONFIRMED,
            DakiyaConstants.ST_PARTIALLY_SHIPPED, DakiyaConstants.ST_SHIPPED,
            DakiyaConstants.ST_OUT_FOR_DELIVERY, DakiyaConstants.ST_DELIVERED_UNCONF,
            DakiyaConstants.ST_RECEIVED, DakiyaConstants.ST_NOT_RECEIVED,
            DakiyaConstants.ST_RETURN_IN_PROGRESS
        };

        List<Purchase__c> open = [
            SELECT Id, Vendor__c, External_Order_Id__c, Total_Amount__c, Order_Date__c,
                   Status__c, Title__c,
                   (SELECT Id, Name FROM Purchase_Items__r LIMIT 50),
                   (SELECT Id, AWB__c FROM Shipments__r LIMIT 20)
            FROM Purchase__c
            WHERE Status__c IN :openStatuses
              AND CreatedDate >= :since
            ORDER BY CreatedDate DESC
            LIMIT 200
        ];

        Map<Id, Candidate> byPurchase = new Map<Id, Candidate>();

        // ── 1.0: the AWB is the parcel's identity. Nothing beats it. ──
        if (String.isNotBlank(ex.awb)) {
            String awb = ex.awb.trim().toLowerCase();
            for (Purchase__c p : open) {
                for (Shipment__c s : p.Shipments__r) {
                    if (String.isNotBlank(s.AWB__c) && s.AWB__c.trim().toLowerCase() == awb) {
                        byPurchase.put(p.Id, new Candidate(p.Id, 1.0, 'Same AWB ' + s.AWB__c));
                    }
                }
            }
        }

        // ── 1.0: vendor + the vendor's own order number ───────────────
        if (String.isNotBlank(ex.order_id) && vendorId != null) {
            String oid = ex.order_id.trim().toLowerCase();
            for (Purchase__c p : open) {
                if (byPurchase.containsKey(p.Id) || p.Vendor__c != vendorId) {
                    continue;
                }
                if (String.isNotBlank(p.External_Order_Id__c)
                    && p.External_Order_Id__c.trim().toLowerCase() == oid) {
                    byPurchase.put(p.Id, new Candidate(p.Id, 1.0, 'Same vendor and order id'));
                }
            }
        }

        // ── 0.8: vendor + exact amount + order date within 3 days ─────
        if (vendorId != null && ex.amount != null) {
            Date evDate = ex.eventDateValue();
            for (Purchase__c p : open) {
                if (byPurchase.containsKey(p.Id) || p.Vendor__c != vendorId) {
                    continue;
                }
                if (p.Total_Amount__c == null || p.Total_Amount__c != ex.amount) {
                    continue;
                }
                if (evDate != null && p.Order_Date__c != null
                    && Math.abs(p.Order_Date__c.daysBetween(evDate)) > 3) {
                    continue;
                }
                byPurchase.put(p.Id, new Candidate(p.Id, 0.8, 'Same vendor and amount, dates close'));
            }
        }

        // ── 0.7: vendor has exactly one open purchase ─────────────────
        if (vendorId != null) {
            List<Purchase__c> vendorOpen = new List<Purchase__c>();
            for (Purchase__c p : open) {
                if (p.Vendor__c == vendorId) {
                    vendorOpen.add(p);
                }
            }
            if (vendorOpen.size() == 1 && !byPurchase.containsKey(vendorOpen[0].Id)) {
                byPurchase.put(vendorOpen[0].Id,
                    new Candidate(vendorOpen[0].Id, 0.7, 'Only open purchase for this vendor'));
            }
        }

        // ── +0.15 (cap 0.95): item names overlap ──────────────────────
        if (vendorId != null && ex.items != null && !ex.items.isEmpty()) {
            Set<String> wanted = tokens(ex.items);
            if (!wanted.isEmpty()) {
                for (Purchase__c p : open) {
                    Candidate c = byPurchase.get(p.Id);
                    if (c == null || p.Vendor__c != vendorId || c.score >= 1.0) {
                        continue;
                    }
                    if (overlap(wanted, itemTokens(p)) >= 0.6) {
                        c.score = Math.min(0.95, c.score + 0.15);
                        c.reason += ' + item names overlap';
                    }
                }
            }
        }

        result.candidates = byPurchase.values();
        result.candidates.sort();
        if (!result.candidates.isEmpty()) {
            result.best = result.candidates[0];
        } else {
            // Nothing matched. An opening event legitimately starts a new order;
            // anything later means we have lost the thread and must ask.
            result.shouldCreateNew =
                ex.event_type == DakiyaConstants.EV_ORDER_PLACED
                || ex.event_type == DakiyaConstants.EV_ORDER_CONFIRMED;
        }
        return result;
    }

    private static Set<String> tokens(List<DakiyaExtraction.Item> items) {
        Set<String> out = new Set<String>();
        for (DakiyaExtraction.Item i : items) {
            if (i != null && String.isNotBlank(i.name)) {
                out.addAll(wordsOf(i.name));
            }
        }
        return out;
    }

    private static Set<String> itemTokens(Purchase__c p) {
        Set<String> out = new Set<String>();
        for (Purchase_Item__c i : p.Purchase_Items__r) {
            if (String.isNotBlank(i.Name)) {
                out.addAll(wordsOf(i.Name));
            }
        }
        if (String.isNotBlank(p.Title__c)) {
            out.addAll(wordsOf(p.Title__c));
        }
        return out;
    }

    /** Words of 3+ characters, lowercased. Short words carry no signal. */
    private static Set<String> wordsOf(String s) {
        Set<String> out = new Set<String>();
        for (String w : s.toLowerCase().split('[^a-z0-9]+')) {
            if (w.length() >= 3) {
                out.add(w);
            }
        }
        return out;
    }

    /** Fraction of the wanted tokens that appear in the candidate. */
    @TestVisible
    private static Decimal overlap(Set<String> wanted, Set<String> have) {
        if (wanted.isEmpty()) {
            return 0;
        }
        Integer hits = 0;
        for (String w : wanted) {
            if (have.contains(w)) {
                hits++;
            }
        }
        return Decimal.valueOf(hits) / Decimal.valueOf(wanted.size());
    }
}
