/**
 * The forward-only rule and its exceptions (BUILD_SPEC 6).
 *
 * These are pure-function tests on purpose: no records, no DML, so every row of
 * the rule table is cheap to assert and a regression points at one line.
 */
@IsTest
private class DakiyaStateMachineTest {

    @IsTest
    static void advancesThroughTheHappyPath() {
        assertMoves(DakiyaConstants.ST_PLACED, DakiyaConstants.EV_SHIPPED, DakiyaConstants.ST_SHIPPED);
        assertMoves(DakiyaConstants.ST_SHIPPED, DakiyaConstants.EV_OUT_FOR_DELIVERY, DakiyaConstants.ST_OUT_FOR_DELIVERY);
        assertMoves(DakiyaConstants.ST_OUT_FOR_DELIVERY, DakiyaConstants.EV_DELIVERED, DakiyaConstants.ST_DELIVERED_UNCONF);
    }

    @IsTest
    static void refusesToGoBackwards() {
        // The classic case: a "shipped" email arrives after the parcel landed.
        DakiyaStateMachine.Decision d =
            DakiyaStateMachine.decide(DakiyaConstants.ST_DELIVERED_UNCONF, DakiyaConstants.EV_SHIPPED);
        Assert.isFalse(d.changed, 'An older event must not pull the status backwards');
        Assert.isTrue(d.note.contains('Older or duplicate'), 'Reason should say why: ' + d.note);
    }

    @IsTest
    static void ignoresDuplicateOfCurrentStatus() {
        DakiyaStateMachine.Decision d =
            DakiyaStateMachine.decide(DakiyaConstants.ST_SHIPPED, DakiyaConstants.EV_SHIPPED);
        Assert.isFalse(d.changed, 'The same event twice must be a no-op');
    }

    @IsTest
    static void cancelsOnlyBeforeDelivery() {
        assertMoves(DakiyaConstants.ST_SHIPPED, DakiyaConstants.EV_CANCELLED, DakiyaConstants.ST_CANCELLED);

        DakiyaStateMachine.Decision after =
            DakiyaStateMachine.decide(DakiyaConstants.ST_DELIVERED_UNCONF, DakiyaConstants.EV_CANCELLED);
        Assert.isFalse(after.changed, 'A delivered parcel cannot be cancelled by an event');
    }

    @IsTest
    static void cancelledIsTerminal() {
        // A vendor mailing list re-sending "shipped" must not revive a dead order.
        DakiyaStateMachine.Decision d =
            DakiyaStateMachine.decide(DakiyaConstants.ST_CANCELLED, DakiyaConstants.EV_SHIPPED);
        Assert.isFalse(d.changed, 'Cancelled absorbs later events');
    }

    @IsTest
    static void failedDeliveryHoldsStatus() {
        DakiyaStateMachine.Decision d =
            DakiyaStateMachine.decide(DakiyaConstants.ST_OUT_FOR_DELIVERY, DakiyaConstants.EV_DELIVERY_FAILED);
        Assert.isFalse(d.changed, 'A failed attempt is information, not progress');
    }

    @IsTest
    static void returnEventsNeedADeliveryFirst() {
        DakiyaStateMachine.Decision early =
            DakiyaStateMachine.decide(DakiyaConstants.ST_SHIPPED, DakiyaConstants.EV_RETURN_REQUESTED);
        Assert.isFalse(early.changed, 'Cannot return something not yet delivered');

        assertMoves(DakiyaConstants.ST_RECEIVED, DakiyaConstants.EV_RETURN_REQUESTED,
                    DakiyaConstants.ST_RETURN_IN_PROGRESS);
    }

    @IsTest
    static void refundEventsDoNotRestartAReturn() {
        DakiyaStateMachine.Decision d = DakiyaStateMachine.decide(
            DakiyaConstants.ST_RETURN_IN_PROGRESS, DakiyaConstants.EV_REFUND_INITIATED);
        Assert.isFalse(d.changed, 'Already in progress; no status churn');
    }

    @IsTest
    static void confirmReceivedNeedsAllParcels() {
        DakiyaStateMachine.Decision partial =
            DakiyaStateMachine.confirmReceived(DakiyaConstants.ST_DELIVERED_UNCONF, true);
        Assert.areEqual(DakiyaConstants.ST_PARTIALLY_SHIPPED, partial.newStatus,
            'One of several parcels leaves the order partially shipped');

        DakiyaStateMachine.Decision full =
            DakiyaStateMachine.confirmReceived(DakiyaConstants.ST_DELIVERED_UNCONF, false);
        Assert.areEqual(DakiyaConstants.ST_RECEIVED, full.newStatus,
            'Last parcel confirmed means the order is received');
    }

    @IsTest
    static void onlyTheUserProducesReceived() {
        // No event type anywhere maps to Received - that is the whole point.
        for (String ev : DakiyaConstants.EVENT_TYPES) {
            DakiyaStateMachine.Decision d = DakiyaStateMachine.decide(DakiyaConstants.ST_DELIVERED_UNCONF, ev);
            Assert.areNotEqual(DakiyaConstants.ST_RECEIVED, d.newStatus,
                'Event ' + ev + ' must never mark a parcel received; only Gitanjali can');
        }
    }

    @IsTest
    static void notReceivedNeedsADeliveryClaim() {
        DakiyaStateMachine.Decision tooEarly =
            DakiyaStateMachine.reportNotReceived(DakiyaConstants.ST_SHIPPED);
        Assert.isFalse(tooEarly.changed, 'Nothing claims delivery yet, so there is nothing to dispute');

        DakiyaStateMachine.Decision ok =
            DakiyaStateMachine.reportNotReceived(DakiyaConstants.ST_DELIVERED_UNCONF);
        Assert.areEqual(DakiyaConstants.ST_NOT_RECEIVED, ok.newStatus, 'User dispute is honoured');
    }

    @IsTest
    static void closesOnlyWhenNothingIsOpen() {
        Assert.isFalse(DakiyaStateMachine.closeIfSettled(DakiyaConstants.ST_RETURN_IN_PROGRESS, true).changed,
            'Another open return keeps the purchase open');
        Assert.areEqual(DakiyaConstants.ST_CLOSED,
            DakiyaStateMachine.closeIfSettled(DakiyaConstants.ST_RETURN_IN_PROGRESS, false).newStatus,
            'Last return settled closes the purchase');
    }

    @IsTest
    static void everyStatusHasARank() {
        for (String s : DakiyaConstants.STATUS_RANK.keySet()) {
            Assert.isTrue(DakiyaConstants.rankOf(s) > 0, s + ' must have a non-zero rank');
        }
        Assert.areEqual(0, DakiyaConstants.rankOf('Nonsense'), 'Unknown status ranks zero');
    }

    private static void assertMoves(String fromStatus, String ev, String expected) {
        // 'from' cannot be a parameter name in Apex - it is a SOQL keyword.
        DakiyaStateMachine.Decision d = DakiyaStateMachine.decide(fromStatus, ev);
        Assert.isTrue(d.changed, fromStatus + ' + ' + ev + ' should change status');
        Assert.areEqual(expected, d.newStatus, fromStatus + ' + ' + ev);
    }
}
