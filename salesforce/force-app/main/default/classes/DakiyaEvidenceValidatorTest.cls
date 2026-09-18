/**
 * The anti-hallucination guard.
 *
 * These tests exist because a wrong tracking number is worse than no tracking
 * number: it sends Gitanjali to argue with the wrong courier about a parcel that
 * was never shipped. Every field must be quotable from the source or it goes.
 */
@IsTest
private class DakiyaEvidenceValidatorTest {

    private static final String BODY =
        'Your Myntra order MN12345678 has been shipped via Delhivery. ' +
        'Tracking number 7412589630. Order total Rs. 1,299 . Expected by 20 Sep.';

    @IsTest
    static void keepsFieldsThatAreQuotable() {
        DakiyaExtraction ex = new DakiyaExtraction();
        ex.order_id = 'MN12345678';
        ex.awb = '7412589630';
        ex.amount = 1299;
        ex.event_type = 'shipped';
        ex.confidence = 0.95;
        ex.evidence = new DakiyaExtraction.Evidence();
        ex.evidence.order_id = 'order MN12345678 has been shipped';
        ex.evidence.awb = 'Tracking number 7412589630';
        ex.evidence.amount = 'Order total Rs. 1,299';
        ex.evidence.event_type = 'has been shipped';

        DakiyaEvidenceValidator.Result r = DakiyaEvidenceValidator.validate(ex, BODY);

        Assert.isTrue(r.isClean(), 'Nothing should be dropped: ' + r.dropped);
        Assert.areEqual('MN12345678', ex.order_id, 'Real order id survives');
        Assert.areEqual('7412589630', ex.awb, 'Real AWB survives');
        Assert.areEqual(1299, ex.amount, 'Real amount survives');
        Assert.areEqual(0.95, ex.confidence, 'Confidence untouched when all evidence holds');
    }

    @IsTest
    static void dropsAnInventedTrackingNumber() {
        DakiyaExtraction ex = new DakiyaExtraction();
        ex.awb = '9999999999';                    // never appears in BODY
        ex.confidence = 0.95;
        ex.evidence = new DakiyaExtraction.Evidence();
        ex.evidence.awb = 'Tracking number 9999999999';

        DakiyaEvidenceValidator.Result r = DakiyaEvidenceValidator.validate(ex, BODY);

        Assert.isNull(ex.awb, 'An AWB that is not in the source must be discarded');
        Assert.isTrue(r.dropped.contains('awb'), 'The drop must be reported');
        Assert.areEqual(0.75, ex.confidence, 'Confidence drops by the 0.2 penalty');
    }

    @IsTest
    static void dropsARealQuoteCarryingAFabricatedId() {
        // The subtle failure: the model quotes a true sentence but attaches an
        // order id that does not appear in it.
        DakiyaExtraction ex = new DakiyaExtraction();
        ex.order_id = 'MN00000000';
        ex.confidence = 0.9;
        ex.evidence = new DakiyaExtraction.Evidence();
        ex.evidence.order_id = 'has been shipped via Delhivery';  // true quote, wrong field

        DakiyaEvidenceValidator.Result r = DakiyaEvidenceValidator.validate(ex, BODY);

        Assert.isNull(ex.order_id, 'The quote must actually contain the value it evidences');
        Assert.isTrue(r.dropped.contains('order_id'), 'Drop reported');
    }

    @IsTest
    static void dropsFieldsWithNoEvidenceAtAll() {
        DakiyaExtraction ex = new DakiyaExtraction();
        ex.order_id = 'MN12345678';
        ex.confidence = 0.9;
        ex.evidence = null;

        DakiyaEvidenceValidator.Result r = DakiyaEvidenceValidator.validate(ex, BODY);

        Assert.isNull(ex.order_id, 'No evidence means no field, even if it happens to be right');
        Assert.isTrue(r.dropped.contains('order_id'));
    }

    @IsTest
    static void matchesAmountsAcrossCurrencyFormatting() {
        // Rs. 1,299 in the body, 1299.00 in the extraction - the same money.
        DakiyaExtraction ex = new DakiyaExtraction();
        ex.amount = 1299.00;
        ex.confidence = 0.95;
        ex.evidence = new DakiyaExtraction.Evidence();
        ex.evidence.amount = 'Rs. 1,299';

        DakiyaEvidenceValidator.Result r = DakiyaEvidenceValidator.validate(ex, BODY);

        Assert.areEqual(1299.00, ex.amount, 'Comma and Rs. formatting must not fail a true amount');
        Assert.isTrue(r.isClean(), 'Nothing dropped: ' + r.dropped);
    }

    @IsTest
    static void degradesUnevidencedEventTypeToOther() {
        DakiyaExtraction ex = new DakiyaExtraction();
        ex.event_type = 'delivered';               // body says shipped, not delivered
        ex.confidence = 0.9;
        ex.evidence = new DakiyaExtraction.Evidence();
        ex.evidence.event_type = 'was delivered to your address';

        DakiyaEvidenceValidator.Result r = DakiyaEvidenceValidator.validate(ex, BODY);

        Assert.areEqual(DakiyaConstants.EV_OTHER, ex.event_type,
            'An unevidenced event type degrades to other rather than moving the state machine');
        Assert.isTrue(r.dropped.contains('event_type'));
    }

    @IsTest
    static void ignoresWhitespaceAndCaseDifferences() {
        DakiyaExtraction ex = new DakiyaExtraction();
        ex.order_id = 'MN12345678';
        ex.confidence = 0.95;
        ex.evidence = new DakiyaExtraction.Evidence();
        ex.evidence.order_id = '  ORDER   mn12345678  HAS BEEN  ';

        DakiyaEvidenceValidator.Result r = DakiyaEvidenceValidator.validate(ex, BODY);

        Assert.areEqual('MN12345678', ex.order_id, 'Formatting differences must not reject true evidence');
    }

    @IsTest
    static void penaltyCompoundsAndNeverGoesNegative() {
        DakiyaExtraction ex = new DakiyaExtraction();
        ex.order_id = 'X1';
        ex.awb = 'X2';
        ex.amount = 999;
        ex.confidence = 0.3;
        ex.evidence = new DakiyaExtraction.Evidence();

        DakiyaEvidenceValidator.Result r = DakiyaEvidenceValidator.validate(ex, BODY);

        Assert.areEqual(3, r.dropped.size(), 'All three unevidenced fields dropped');
        Assert.areEqual(0, ex.confidence, 'Confidence floors at zero rather than going negative');
    }

    @IsTest
    static void handlesNullExtractionSafely() {
        DakiyaEvidenceValidator.Result r = DakiyaEvidenceValidator.validate(null, BODY);
        Assert.isTrue(r.isClean(), 'A null extraction is not an error');
    }
}
