/**
 * Turns a validated extraction into record changes.
 *
 * Every applied event writes a Tracking_Event__c, including events that changed
 * nothing because they arrived out of order - the timeline is the audit trail,
 * and "we saw this and deliberately ignored it" is worth keeping.
 */
public with sharing class DakiyaEventApplier {

    public class ApplyResult {
        public Id purchaseId;
        public Boolean statusChanged = false;
        public String newStatus;
        public String note;
    }

    /** Create a purchase from an opening event. */
    public static Purchase__c createPurchase(DakiyaExtraction ex, Id vendorId, String source) {
        Date orderDate = ex.eventDateValue();
        Purchase__c p = new Purchase__c(
            Vendor__c = vendorId,
            External_Order_Id__c = ex.order_id,
            Vendor_Order_Key__c = buildKey(vendorId, ex.order_id),
            Title__c = titleFor(ex),
            Order_Date__c = orderDate == null ? Date.today() : orderDate,
            Total_Amount__c = ex.amount,
            Status__c = DakiyaConstants.ST_PLACED,
            Status_Rank__c = DakiyaConstants.rankOf(DakiyaConstants.ST_PLACED),
            Source__c = source,
            Expected_Delivery__c = ex.expectedDateValue(),
            Last_Event_At__c = Datetime.now()
        );
        insert p;

        if (ex.items != null && !ex.items.isEmpty()) {
            List<Purchase_Item__c> items = new List<Purchase_Item__c>();
            for (DakiyaExtraction.Item i : ex.items) {
                if (i == null || String.isBlank(i.name)) {
                    continue;
                }
                items.add(new Purchase_Item__c(
                    Name = i.name.length() > 80 ? i.name.substring(0, 80) : i.name,
                    Purchase__c = p.Id,
                    Quantity__c = i.qty == null ? 1 : i.qty,
                    Price__c = i.price,
                    Status__c = 'Active'
                ));
            }
            if (!items.isEmpty()) {
                insert items;
            }
        }
        return p;
    }

    /**
     * Apply an event to an existing purchase.
     *
     * @param appliedBy Rule, LLM, User, Agent or System - provenance, so an
     *                  accuracy problem can be traced back to its source.
     */
    public static ApplyResult apply(
        Purchase__c p,
        DakiyaExtraction ex,
        Id sourceMessageId,
        String appliedBy
    ) {
        ApplyResult out = new ApplyResult();
        out.purchaseId = p.Id;

        DakiyaStateMachine.Decision d = DakiyaStateMachine.decide(p.Status__c, ex.event_type);
        out.statusChanged = d.changed;
        out.newStatus = d.newStatus;
        out.note = d.note;

        Datetime eventAt = eventTimeOf(ex);
        Shipment__c shipment = upsertShipment(p, ex, eventAt);
        Return__c ret = applyReturnEvent(p, ex, eventAt);

        // The purchase's own fields
        p.Last_Event_At__c = eventAt;
        if (d.changed) {
            p.Status__c = d.newStatus;
            p.Status_Rank__c = DakiyaConstants.rankOf(d.newStatus);
        }
        if (ex.event_type == DakiyaConstants.EV_DELIVERED) {
            p.Delivered_At__c = eventAt;
            p.Return_Window_Ends__c = returnWindowEnd(p, eventAt);
        }
        if (ex.expectedDateValue() != null) {
            p.Expected_Delivery__c = ex.expectedDateValue();
        }
        update p;

        insert new Tracking_Event__c(
            Purchase__c = p.Id,
            Shipment__c = shipment == null ? null : shipment.Id,
            Return__c = ret == null ? null : ret.Id,
            Event_Type__c = ex.event_type,
            Event_At__c = eventAt,
            Summary__c = summaryOf(ex, d),
            Source_Message__c = sourceMessageId,
            Applied_By__c = appliedBy
        );
        return out;
    }

    /** Create or advance the shipment this event is about, keyed on AWB. */
    private static Shipment__c upsertShipment(Purchase__c p, DakiyaExtraction ex, Datetime eventAt) {
        Boolean isShipmentEvent =
            ex.event_type == DakiyaConstants.EV_SHIPPED
            || ex.event_type == DakiyaConstants.EV_OUT_FOR_DELIVERY
            || ex.event_type == DakiyaConstants.EV_DELIVERED
            || ex.event_type == DakiyaConstants.EV_DELIVERY_FAILED;
        if (!isShipmentEvent && String.isBlank(ex.awb)) {
            return null;
        }

        Shipment__c s;
        if (String.isNotBlank(ex.awb)) {
            List<Shipment__c> found = [
                SELECT Id, Status__c, Confirmation__c
                FROM Shipment__c WHERE AWB__c = :ex.awb LIMIT 1
            ];
            s = found.isEmpty() ? null : found[0];
        }
        if (s == null) {
            // No AWB, or an AWB never seen before: reuse the purchase's only open
            // parcel if there is exactly one, otherwise start a new one.
            List<Shipment__c> onPurchase = [
                SELECT Id, Status__c, Confirmation__c, AWB__c
                FROM Shipment__c WHERE Purchase__c = :p.Id LIMIT 5
            ];
            if (String.isBlank(ex.awb) && onPurchase.size() == 1) {
                s = onPurchase[0];
            } else {
                s = new Shipment__c(Purchase__c = p.Id, Status__c = 'Created');
            }
        }

        if (String.isNotBlank(ex.awb)) {
            s.AWB__c = ex.awb;
        }
        if (String.isNotBlank(ex.courier)) {
            s.Courier__c = ex.courier;
        }
        if (String.isNotBlank(ex.tracking_url)) {
            s.Tracking_URL__c = ex.tracking_url;
        }

        if (ex.event_type == DakiyaConstants.EV_SHIPPED) {
            s.Status__c = 'Shipped';
        } else if (ex.event_type == DakiyaConstants.EV_OUT_FOR_DELIVERY) {
            s.Status__c = 'Out for Delivery';
        } else if (ex.event_type == DakiyaConstants.EV_DELIVERY_FAILED) {
            s.Status__c = 'Failed Attempt';
        } else if (ex.event_type == DakiyaConstants.EV_DELIVERED) {
            s.Status__c = 'Delivered';
            s.Delivered_At__c = eventAt;
            // A courier saying "delivered" only ever produces Pending. Received
            // requires Gitanjali to say so.
            if (s.Confirmation__c == null || s.Confirmation__c == 'Pending') {
                s.Confirmation__c = 'Pending';
            }
        }
        upsert s;
        return s;
    }

    /** Create or advance the return this event is about. */
    private static Return__c applyReturnEvent(Purchase__c p, DakiyaExtraction ex, Datetime eventAt) {
        if (!DakiyaConstants.RETURN_EVENTS.contains(ex.event_type)) {
            return null;
        }

        List<Return__c> open = [
            SELECT Id, Status__c, Refund_Initiated_On__c, Refund_Check_Due__c, Purchase__c
            FROM Return__c
            WHERE Purchase__c = :p.Id AND Status__c NOT IN ('Completed', 'Rejected', 'Cancelled')
            ORDER BY CreatedDate DESC LIMIT 1
        ];
        Return__c r = open.isEmpty() ? null : open[0];

        if (r == null) {
            if (ex.event_type != DakiyaConstants.EV_RETURN_REQUESTED) {
                // A refund event with no return on file means we missed the start.
                // Create the return so the refund is still tracked, and flag it.
                p.Needs_Review__c = true;
            }
            r = new Return__c(
                Purchase__c = p.Id,
                Type__c = ex.event_type == DakiyaConstants.EV_EXCHANGE_SHIPPED
                    ? 'Exchange or Replacement' : 'Return',
                Status__c = 'Requested',
                Requested_On__c = eventAt.date()
            );
        }

        if (ex.event_type == DakiyaConstants.EV_RETURN_REQUESTED) {
            r.Status__c = 'Requested';
            r.Requested_On__c = eventAt.date();
        } else if (ex.event_type == DakiyaConstants.EV_RETURN_PICKUP_SCHEDULED) {
            r.Status__c = 'Pickup Scheduled';
            r.Pickup_Date__c = eventAt.date();
        } else if (ex.event_type == DakiyaConstants.EV_RETURN_PICKED_UP) {
            r.Status__c = 'Picked Up';
        } else if (ex.event_type == DakiyaConstants.EV_RETURN_RECEIVED) {
            r.Status__c = 'Received by Seller';
        } else if (ex.event_type == DakiyaConstants.EV_RETURN_REJECTED) {
            r.Status__c = 'Rejected';
        } else if (ex.event_type == DakiyaConstants.EV_REFUND_INITIATED) {
            r.Status__c = 'Refund Initiated';
            r.Refund_Initiated_On__c = eventAt.date();
            r.Refund_Check_Due__c = refundCheckDue(p, eventAt.date());
            if (ex.amount != null) {
                r.Expected_Refund_Amount__c = ex.amount;
            }
        } else if (ex.event_type == DakiyaConstants.EV_REFUND_COMPLETED) {
            // The vendor claiming the refund is done is NOT the outcome. Only
            // Gitanjali checking her account records that (BUILD_SPEC goal 4).
            r.Status__c = 'Refund Check Due';
            r.Refund_Check_Due__c = Date.today();
        }
        upsert r;
        return r;
    }

    /** Refund check date from the vendor's learned habit, else the default. */
    private static Date refundCheckDue(Purchase__c p, Date initiatedOn) {
        Integer days = DakiyaSettings.defaultRefundCheckDays();
        if (p.Vendor__c != null) {
            List<Vendor__c> v = [
                SELECT Typical_Refund_Days__c FROM Vendor__c WHERE Id = :p.Vendor__c LIMIT 1
            ];
            if (!v.isEmpty() && v[0].Typical_Refund_Days__c != null && v[0].Typical_Refund_Days__c > 0) {
                days = Integer.valueOf(v[0].Typical_Refund_Days__c);
            }
        }
        return initiatedOn.addDays(days);
    }

    /** Null when the vendor's return window is unknown - we never invent one. */
    private static Date returnWindowEnd(Purchase__c p, Datetime deliveredAt) {
        if (p.Vendor__c == null) {
            return null;
        }
        List<Vendor__c> v = [
            SELECT Return_Window_Days__c FROM Vendor__c WHERE Id = :p.Vendor__c LIMIT 1
        ];
        if (v.isEmpty() || v[0].Return_Window_Days__c == null || v[0].Return_Window_Days__c <= 0) {
            return null;
        }
        return deliveredAt.date().addDays(Integer.valueOf(v[0].Return_Window_Days__c));
    }

    private static Datetime eventTimeOf(DakiyaExtraction ex) {
        Date d = ex.eventDateValue();
        return d == null ? Datetime.now() : Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0));
    }

    private static String buildKey(Id vendorId, String orderId) {
        String key = String.isBlank(orderId)
            ? String.valueOf(Crypto.getRandomLong())
            : String.valueOf(vendorId) + ':' + orderId;
        key = key.toLowerCase();
        return key.length() > 120 ? key.substring(0, 120) : key;
    }

    private static String titleFor(DakiyaExtraction ex) {
        if (ex.items != null && !ex.items.isEmpty() && String.isNotBlank(ex.items[0].name)) {
            String t = ex.items[0].name;
            if (ex.items.size() > 1) {
                t += ' + ' + (ex.items.size() - 1) + ' more';
            }
            return t.length() > 255 ? t.substring(0, 255) : t;
        }
        return String.isNotBlank(ex.order_id) ? 'Order ' + ex.order_id : 'Untitled order';
    }

    private static String summaryOf(DakiyaExtraction ex, DakiyaStateMachine.Decision d) {
        String s = ex.event_type + ' - ' + d.note;
        return s.length() > 255 ? s.substring(0, 255) : s;
    }
}
