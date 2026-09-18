/**
 * The decisions only Gitanjali can make (BUILD_SPEC 8, POST /actions).
 *
 * Everything here is an assertion of fact from the person, not an observation
 * from a courier or a model: "I have it", "I never got it", "the refund came
 * back as store credit". These are the only things that produce Received,
 * Not Received, or a recorded refund outcome.
 */
public with sharing class DakiyaActionService {

    public class ActionException extends Exception {}

    public static Map<String, Object> run(String action, Id recordId, Map<String, Object> payload) {
        if (String.isBlank(action)) {
            throw new ActionException('action is required');
        }
        if (payload == null) {
            payload = new Map<String, Object>();
        }

        if (action == 'confirm_received')  { return confirmReceived(recordId); }
        if (action == 'not_received')      { return reportNotReceived(recordId); }
        if (action == 'refund_outcome')    { return recordRefundOutcome(recordId, payload); }
        if (action == 'resolve_review')    { return resolveReview(recordId, payload); }
        if (action == 'snooze')            { return snooze(recordId, payload); }
        throw new ActionException('Unknown action: ' + action);
    }

    /** "Got it." Accepts a shipment id or a purchase id. */
    public static Map<String, Object> confirmReceived(Id recordId) {
        Shipment__c shipment = resolveShipment(recordId);
        if (shipment == null) {
            throw new ActionException('No shipment found for ' + recordId);
        }

        // Update a narrow record, not the queried one: Shipment__c.Purchase__c is a
        // non-reparentable master-detail field and therefore not updateable, so
        // carrying it into the DML fails the field-accessibility check.
        update new Shipment__c(
            Id = shipment.Id,
            Confirmation__c = 'Received',
            Confirmed_At__c = Datetime.now()
        );

        Integer stillPending = [
            SELECT COUNT() FROM Shipment__c
            WHERE Purchase__c = :shipment.Purchase__c AND Confirmation__c = 'Pending'
        ];

        Purchase__c p = purchaseById(shipment.Purchase__c);
        DakiyaStateMachine.Decision d =
            DakiyaStateMachine.confirmReceived(p.Status__c, stillPending > 0);
        applyDecision(p, d);

        logEvent(p.Id, shipment.Id, null, DakiyaConstants.EV_DELIVERED,
                 'Confirmed received by user', DakiyaConstants.BY_USER);

        return new Map<String, Object>{
            'purchaseId' => p.Id,
            'shipmentId' => shipment.Id,
            'status' => p.Status__c,
            'otherParcelsPending' => stillPending
        };
    }

    /**
     * "It never arrived." Returns the complaint pack - everything needed to
     * argue with the courier, assembled from what we actually recorded.
     */
    public static Map<String, Object> reportNotReceived(Id recordId) {
        Shipment__c shipment = resolveShipment(recordId);
        Purchase__c p = shipment != null
            ? purchaseById(shipment.Purchase__c)
            : purchaseById(recordId);

        if (shipment != null) {
            update new Shipment__c(
                Id = shipment.Id,
                Confirmation__c = 'Not Received',
                Confirmed_At__c = Datetime.now()
            );
        }

        DakiyaStateMachine.Decision d = DakiyaStateMachine.reportNotReceived(p.Status__c);
        p.Needs_Review__c = true;
        applyDecision(p, d);

        logEvent(p.Id, shipment == null ? null : shipment.Id, null,
                 DakiyaConstants.EV_DELIVERY_FAILED, 'Reported not received by user',
                 DakiyaConstants.BY_USER);

        return new Map<String, Object>{
            'purchaseId' => p.Id,
            'status' => p.Status__c,
            'complaintPack' => new Map<String, Object>{
                'vendor' => p.Vendor__r == null ? null : p.Vendor__r.Name,
                'orderId' => p.External_Order_Id__c,
                'courier' => shipment == null ? null : shipment.Courier__c,
                'awb' => shipment == null ? null : shipment.AWB__c,
                'deliveredClaimAt' => shipment == null ? null : shipment.Delivered_At__c,
                'amount' => p.Total_Amount__c
            }
        };
    }

    /** The refund check-in. Recorded by the person, never inferred. */
    public static Map<String, Object> recordRefundOutcome(Id returnId, Map<String, Object> payload) {
        String outcome = (String) payload.get('outcome');
        if (String.isBlank(outcome)) {
            throw new ActionException('outcome is required');
        }

        Return__c r = [
            SELECT Id, Status__c, Purchase__c, Refund_Initiated_On__c, Reminder_Count__c,
                   Purchase__r.Vendor__c
            FROM Return__c WHERE Id = :returnId LIMIT 1
        ];

        if (outcome == 'Not Received Yet') {
            // Not an outcome, a "ask me again later".
            r.Status__c = 'Refund Check Due';
            r.Refund_Check_Due__c = Date.today().addDays(DakiyaSettings.refundRecheckDays());
            r.Reminder_Count__c = (r.Reminder_Count__c == null ? 0 : r.Reminder_Count__c) + 1;
            r.Refund_Outcome__c = outcome;
            update r;
            return new Map<String, Object>{
                'returnId' => r.Id,
                'status' => r.Status__c,
                'nextCheck' => r.Refund_Check_Due__c,
                'escalationSuggested' => r.Reminder_Count__c >= DakiyaSettings.maxRefundReminders()
            };
        }

        r.Refund_Outcome__c = outcome;
        r.Outcome_Recorded_On__c = Date.today();
        r.Status__c = 'Completed';
        Object amt = payload.get('amount');
        if (amt != null) {
            r.Refund_Received_Amount__c = Decimal.valueOf(String.valueOf(amt));
        }
        update r;

        Integer openReturns = [
            SELECT COUNT() FROM Return__c
            WHERE Purchase__c = :r.Purchase__c
              AND Status__c NOT IN ('Completed', 'Rejected', 'Cancelled')
        ];
        Purchase__c p = purchaseById(r.Purchase__c);
        applyDecision(p, DakiyaStateMachine.closeIfSettled(p.Status__c, openReturns > 0));

        recomputeVendorRefundStats(r.Purchase__r.Vendor__c);

        logEvent(p.Id, null, r.Id, DakiyaConstants.EV_REFUND_COMPLETED,
                 'Refund outcome recorded: ' + outcome, DakiyaConstants.BY_USER);

        return new Map<String, Object>{
            'returnId' => r.Id,
            'status' => r.Status__c,
            'purchaseStatus' => p.Status__c,
            'outcome' => outcome
        };
    }

    /** Resolve a review item: attach to a purchase, start a new one, or ignore. */
    public static Map<String, Object> resolveReview(Id messageId, Map<String, Object> payload) {
        String resolution = (String) payload.get('resolution');
        if (String.isBlank(resolution)) {
            throw new ActionException('resolution is required (a purchase id, "new" or "ignore")');
        }

        Inbound_Message__c m = [
            SELECT Id, Extraction_JSON__c, Channel__c, Body_Masked__c, Processing_Status__c,
                   Related_Purchase__c
            FROM Inbound_Message__c WHERE Id = :messageId LIMIT 1
        ];

        if (resolution == 'ignore') {
            m.Processing_Status__c = 'Ignored';
            update m;
            return new Map<String, Object>{ 'messageId' => m.Id, 'status' => m.Processing_Status__c };
        }

        if (String.isBlank(m.Extraction_JSON__c)) {
            throw new ActionException('Message has no extraction to apply');
        }
        DakiyaExtraction ex = DakiyaExtraction.parse(m.Extraction_JSON__c);

        Purchase__c p;
        if (resolution == 'new') {
            Id vendorId = (Id) payload.get('vendorId');
            if (vendorId == null) {
                throw new ActionException('vendorId is required when creating a new purchase');
            }
            p = DakiyaEventApplier.createPurchase(ex, vendorId, 'Manual');
        } else {
            p = purchaseById((Id) resolution);
            DakiyaEventApplier.apply(p, ex, m.Id, DakiyaConstants.BY_USER);
        }

        m.Related_Purchase__c = p.Id;
        m.Processing_Status__c = 'Parsed (Rule)';
        update m;

        return new Map<String, Object>{
            'messageId' => m.Id,
            'purchaseId' => p.Id,
            'status' => p.Status__c
        };
    }

    /** Push a pending notification out by N days. */
    public static Map<String, Object> snooze(Id recordId, Map<String, Object> payload) {
        Integer days = payload.get('days') == null
            ? 3 : Integer.valueOf(String.valueOf(payload.get('days')));
        Notification__c n = [
            SELECT Id, Due_At__c, Status__c FROM Notification__c WHERE Id = :recordId LIMIT 1
        ];
        n.Due_At__c = Datetime.now().addDays(days);
        n.Status__c = 'Pending';
        update n;
        return new Map<String, Object>{ 'notificationId' => n.Id, 'dueAt' => n.Due_At__c };
    }

    /**
     * Recompute a vendor's learned refund habits from its settled returns.
     *
     * This is what lets the next refund reminder be timed from experience rather
     * than from a flat default.
     */
    public static void recomputeVendorRefundStats(Id vendorId) {
        if (vendorId == null) {
            return;
        }
        List<Return__c> settled = [
            SELECT Refund_Initiated_On__c, Outcome_Recorded_On__c, Refund_Outcome__c
            FROM Return__c
            WHERE Purchase__r.Vendor__c = :vendorId
              AND Status__c = 'Completed'
              AND Outcome_Recorded_On__c != null
            LIMIT 200
        ];
        if (settled.isEmpty()) {
            return;
        }

        List<Integer> gaps = new List<Integer>();
        Integer toOriginal = 0, storeCredit = 0, partial = 0, other = 0;
        for (Return__c r : settled) {
            if (r.Refund_Initiated_On__c != null) {
                gaps.add(r.Refund_Initiated_On__c.daysBetween(r.Outcome_Recorded_On__c));
            }
            if (r.Refund_Outcome__c == 'Full to Original Payment')  { toOriginal++; }
            else if (r.Refund_Outcome__c == 'Store Credit')         { storeCredit++; }
            else if (r.Refund_Outcome__c == 'Partial')              { partial++; }
            else                                                     { other++; }
        }

        Vendor__c v = new Vendor__c(Id = vendorId);
        if (!gaps.isEmpty()) {
            gaps.sort();
            v.Typical_Refund_Days__c = gaps[gaps.size() / 2]; // median
        }
        if (storeCredit > 0 && toOriginal > 0)      { v.Usual_Refund_Mode__c = 'Mixed'; }
        else if (storeCredit > 0)                    { v.Usual_Refund_Mode__c = 'Store Credit'; }
        else if (toOriginal > 0)                     { v.Usual_Refund_Mode__c = 'Original Payment'; }
        else                                         { v.Usual_Refund_Mode__c = 'Unknown'; }

        String summary = settled.size() + (settled.size() == 1 ? ' return: ' : ' returns: ');
        List<String> parts = new List<String>();
        if (toOriginal > 0)  { parts.add(toOriginal + ' full to original payment'); }
        if (partial > 0)     { parts.add(partial + ' partial'); }
        if (storeCredit > 0) { parts.add(storeCredit + ' store credit'); }
        if (other > 0)       { parts.add(other + ' other'); }
        summary += String.join(parts, ', ');
        v.Refund_History_Summary__c = summary.length() > 255 ? summary.substring(0, 255) : summary;

        update v;
    }

    // ── helpers ───────────────────────────────────────────────────────

    private static Shipment__c resolveShipment(Id recordId) {
        if (recordId == null) {
            return null;
        }
        String prefix = String.valueOf(recordId).substring(0, 3);
        if (prefix == Shipment__c.SObjectType.getDescribe().getKeyPrefix()) {
            List<Shipment__c> s = [
                SELECT Id, Purchase__c, Confirmation__c, Courier__c, AWB__c, Delivered_At__c
                FROM Shipment__c WHERE Id = :recordId LIMIT 1
            ];
            return s.isEmpty() ? null : s[0];
        }
        // A purchase id: use its pending parcel if there is exactly one.
        List<Shipment__c> pending = [
            SELECT Id, Purchase__c, Confirmation__c, Courier__c, AWB__c, Delivered_At__c
            FROM Shipment__c WHERE Purchase__c = :recordId AND Confirmation__c = 'Pending'
            ORDER BY Delivered_At__c DESC LIMIT 2
        ];
        return pending.size() == 1 ? pending[0] : null;
    }

    private static Purchase__c purchaseById(Id purchaseId) {
        return Database.query(
            'SELECT ' + DakiyaApi.PURCHASE_FIELDS + ' FROM Purchase__c WHERE Id = :purchaseId LIMIT 1'
        );
    }

    private static void applyDecision(Purchase__c p, DakiyaStateMachine.Decision d) {
        if (d.changed) {
            p.Status__c = d.newStatus;
            p.Status_Rank__c = DakiyaConstants.rankOf(d.newStatus);
        }
        p.Last_Event_At__c = Datetime.now();
        update p;
    }

    private static void logEvent(Id purchaseId, Id shipmentId, Id returnId,
                                 String eventType, String summary, String appliedBy) {
        insert new Tracking_Event__c(
            Purchase__c = purchaseId,
            Shipment__c = shipmentId,
            Return__c = returnId,
            Event_Type__c = eventType,
            Event_At__c = Datetime.now(),
            Summary__c = summary,
            Applied_By__c = appliedBy
        );
    }
}
