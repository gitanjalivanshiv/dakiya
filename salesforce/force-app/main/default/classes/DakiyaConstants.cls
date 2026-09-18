/**
 * The shared vocabulary: purchase statuses, their ranks, and the event types
 * from the extraction contract (BUILD_SPEC 5.3).
 *
 * Rules, the LLM, the state machine and the agent all speak these exact strings.
 * If a string changes here it must change in the picklists too.
 */
public with sharing class DakiyaConstants {
    // ── Purchase statuses ─────────────────────────────────────────────
    public static final String ST_PLACED            = 'Placed';
    public static final String ST_CONFIRMED         = 'Confirmed';
    public static final String ST_PARTIALLY_SHIPPED = 'Partially Shipped';
    public static final String ST_SHIPPED           = 'Shipped';
    public static final String ST_OUT_FOR_DELIVERY  = 'Out for Delivery';
    public static final String ST_DELIVERED_UNCONF  = 'Delivered (Unconfirmed)';
    public static final String ST_RECEIVED          = 'Received';
    public static final String ST_NOT_RECEIVED      = 'Not Received';
    public static final String ST_CANCELLED         = 'Cancelled';
    public static final String ST_RETURN_IN_PROGRESS= 'Return in Progress';
    public static final String ST_CLOSED            = 'Closed';

    /**
     * Rank drives the "events may only move a purchase forward" rule (BUILD_SPEC 6).
     *
     * The spec lists ranks for the nine happy-path statuses only. Not Received and
     * Cancelled are exception states reached deliberately, never by a normal
     * forward event, so they are ranked here to make regression impossible:
     * Not Received sits just above Delivered (Unconfirmed) because it is a
     * decision about that delivery, and Cancelled sits at the terminal end.
     */
    public static final Map<String, Integer> STATUS_RANK = new Map<String, Integer>{
        ST_PLACED             => 10,
        ST_CONFIRMED          => 20,
        ST_PARTIALLY_SHIPPED  => 30,
        ST_SHIPPED            => 40,
        ST_OUT_FOR_DELIVERY   => 50,
        ST_DELIVERED_UNCONF   => 60,
        ST_NOT_RECEIVED       => 65,
        ST_RECEIVED           => 70,
        ST_RETURN_IN_PROGRESS => 80,
        ST_CLOSED             => 90,
        ST_CANCELLED          => 95
    };

    public static Integer rankOf(String status) {
        Integer r = STATUS_RANK.get(status);
        return r == null ? 0 : r;
    }

    // ── Event types (BUILD_SPEC 5.3) ──────────────────────────────────
    public static final String EV_ORDER_PLACED      = 'order_placed';
    public static final String EV_ORDER_CONFIRMED   = 'order_confirmed';
    public static final String EV_SHIPPED           = 'shipped';
    public static final String EV_OUT_FOR_DELIVERY  = 'out_for_delivery';
    public static final String EV_DELIVERED         = 'delivered';
    public static final String EV_DELIVERY_FAILED   = 'delivery_failed';
    public static final String EV_CANCELLED         = 'cancelled';
    public static final String EV_RETURN_REQUESTED  = 'return_requested';
    public static final String EV_RETURN_PICKUP_SCHEDULED = 'return_pickup_scheduled';
    public static final String EV_RETURN_PICKED_UP  = 'return_picked_up';
    public static final String EV_RETURN_RECEIVED   = 'return_received';
    public static final String EV_RETURN_REJECTED   = 'return_rejected';
    public static final String EV_REFUND_INITIATED  = 'refund_initiated';
    public static final String EV_REFUND_COMPLETED  = 'refund_completed';
    public static final String EV_EXCHANGE_SHIPPED  = 'exchange_shipped';
    public static final String EV_OTHER             = 'other';

    public static final Set<String> EVENT_TYPES = new Set<String>{
        EV_ORDER_PLACED, EV_ORDER_CONFIRMED, EV_SHIPPED, EV_OUT_FOR_DELIVERY,
        EV_DELIVERED, EV_DELIVERY_FAILED, EV_CANCELLED, EV_RETURN_REQUESTED,
        EV_RETURN_PICKUP_SCHEDULED, EV_RETURN_PICKED_UP, EV_RETURN_RECEIVED,
        EV_RETURN_REJECTED, EV_REFUND_INITIATED, EV_REFUND_COMPLETED,
        EV_EXCHANGE_SHIPPED, EV_OTHER
    };

    /** Events that create or advance a return rather than a delivery. */
    public static final Set<String> RETURN_EVENTS = new Set<String>{
        EV_RETURN_REQUESTED, EV_RETURN_PICKUP_SCHEDULED, EV_RETURN_PICKED_UP,
        EV_RETURN_RECEIVED, EV_RETURN_REJECTED, EV_REFUND_INITIATED,
        EV_REFUND_COMPLETED, EV_EXCHANGE_SHIPPED
    };

    /** Provenance values for Tracking_Event__c.Applied_By__c. */
    public static final String BY_RULE   = 'Rule';
    public static final String BY_LLM    = 'LLM';
    public static final String BY_USER   = 'User';
    public static final String BY_AGENT  = 'Agent';
    public static final String BY_SYSTEM = 'System';

    /** IST, used for every user-facing date. Records store UTC. */
    public static final String TZ_IST = 'Asia/Kolkata';
}
