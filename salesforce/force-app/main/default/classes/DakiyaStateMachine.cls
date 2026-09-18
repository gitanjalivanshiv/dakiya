/**
 * Decides what an event does to a purchase's status (BUILD_SPEC 6).
 *
 * Deliberately pure: it takes a current status and an event and returns a
 * decision, touching no records and issuing no DML. That is what makes the whole
 * rule table unit-testable without building object graphs, and it keeps the
 * "only move forward" invariant in one readable place.
 *
 * DakiyaEventApplier does the record mutations that follow from a Decision.
 */
public with sharing class DakiyaStateMachine {

    public class Decision {
        public Boolean changed = false;
        public String newStatus;
        /** Why, in plain words - written onto the Tracking Event summary. */
        public String note;

        private Decision(Boolean changed, String newStatus, String note) {
            this.changed = changed;
            this.newStatus = newStatus;
            this.note = note;
        }
    }

    private static Decision noChange(String note) {
        return new Decision(false, null, note);
    }

    private static Decision moveTo(String status, String note) {
        return new Decision(true, status, note);
    }

    /** The happy path: event type to the status it implies. */
    private static final Map<String, String> EVENT_TARGET = new Map<String, String>{
        DakiyaConstants.EV_ORDER_PLACED     => DakiyaConstants.ST_PLACED,
        DakiyaConstants.EV_ORDER_CONFIRMED  => DakiyaConstants.ST_CONFIRMED,
        DakiyaConstants.EV_SHIPPED          => DakiyaConstants.ST_SHIPPED,
        DakiyaConstants.EV_OUT_FOR_DELIVERY => DakiyaConstants.ST_OUT_FOR_DELIVERY,
        DakiyaConstants.EV_DELIVERED        => DakiyaConstants.ST_DELIVERED_UNCONF
    };

    /**
     * Below this rank a purchase has not been delivered yet, so it can still be
     * cancelled and cannot yet have a return raised against it.
     */
    private static final Integer DELIVERED_RANK = 60;

    /**
     * The single entry point for automatic events. User and agent decisions go
     * through confirmReceived / reportNotReceived instead, because those are
     * assertions of fact rather than observations.
     */
    public static Decision decide(String currentStatus, String eventType) {
        Integer current = DakiyaConstants.rankOf(currentStatus);

        // Terminal states absorb everything. A cancelled order that later emits a
        // stray "shipped" from the vendor's mailing list must not spring back to life.
        if (currentStatus == DakiyaConstants.ST_CANCELLED) {
            return noChange('Purchase is cancelled; event logged only');
        }

        // ── Sideways exceptions (BUILD_SPEC 6) ────────────────────────
        if (eventType == DakiyaConstants.EV_CANCELLED) {
            return current < DELIVERED_RANK
                ? moveTo(DakiyaConstants.ST_CANCELLED, 'Cancelled before delivery')
                : noChange('Cancellation after delivery ignored; needs review');
        }

        if (eventType == DakiyaConstants.EV_DELIVERY_FAILED) {
            // A failed attempt is real information but not progress - the parcel
            // is still with the courier, so the purchase holds its status.
            return noChange('Delivery attempt failed; status held');
        }

        if (DakiyaConstants.RETURN_EVENTS.contains(eventType)) {
            if (current < DELIVERED_RANK) {
                return noChange('Return event before delivery; out of order, logged only');
            }
            return currentStatus == DakiyaConstants.ST_RETURN_IN_PROGRESS
                ? noChange('Return already in progress')
                : moveTo(DakiyaConstants.ST_RETURN_IN_PROGRESS, 'Return started');
        }

        // ── Normal forward-only progression ───────────────────────────
        String target = EVENT_TARGET.get(eventType);
        if (target == null) {
            return noChange('Event carries no status meaning');
        }
        Integer targetRank = DakiyaConstants.rankOf(target);
        if (targetRank > current) {
            return moveTo(target, 'Advanced to ' + target);
        }
        return noChange('Older or duplicate event; status held at ' + currentStatus);
    }

    /**
     * Gitanjali says she has the parcel. This is the only thing that produces
     * Received - a courier claiming delivery never does.
     *
     * anyOtherPending covers the multi-parcel case: confirming one box of three
     * leaves the purchase partially shipped, not received.
     */
    public static Decision confirmReceived(String currentStatus, Boolean anyOtherPending) {
        if (currentStatus == DakiyaConstants.ST_CANCELLED) {
            return noChange('Purchase is cancelled');
        }
        if (anyOtherPending) {
            return currentStatus == DakiyaConstants.ST_PARTIALLY_SHIPPED
                ? noChange('Other parcels still pending')
                : moveTo(DakiyaConstants.ST_PARTIALLY_SHIPPED, 'One parcel received, others pending');
        }
        return moveTo(DakiyaConstants.ST_RECEIVED, 'Confirmed received');
    }

    /** Gitanjali says the parcel never arrived despite a delivered claim. */
    public static Decision reportNotReceived(String currentStatus) {
        Integer current = DakiyaConstants.rankOf(currentStatus);
        if (current < DELIVERED_RANK) {
            return noChange('Nothing claims to have been delivered yet');
        }
        return currentStatus == DakiyaConstants.ST_NOT_RECEIVED
            ? noChange('Already flagged as not received')
            : moveTo(DakiyaConstants.ST_NOT_RECEIVED, 'Reported not received');
    }

    /**
     * A return finished. The purchase closes only when nothing else is open,
     * otherwise it stays where it is.
     */
    public static Decision closeIfSettled(String currentStatus, Boolean anyOpenReturns) {
        if (anyOpenReturns) {
            return noChange('Other returns still open');
        }
        if (currentStatus == DakiyaConstants.ST_CLOSED) {
            return noChange('Already closed');
        }
        return moveTo(DakiyaConstants.ST_CLOSED, 'All returns settled');
    }
}
