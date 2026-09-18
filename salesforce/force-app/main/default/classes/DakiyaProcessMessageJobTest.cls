/**
 * The confidence gate (BUILD_SPEC 5.4 step 5).
 *
 * A fake parser stands in for the Phase 6 vendor rules, which lets the whole
 * pipeline be exercised now without inventing what a real Myntra email looks
 * like. The point of these tests is the threshold behaviour: apply when certain,
 * ask when not, and never split the difference.
 */
@IsTest
private class DakiyaProcessMessageJobTest {

    /** Returns whatever it is told to, so each test can pick a confidence. */
    private class StubParser implements IDakiyaParser {
        private DakiyaExtraction result;
        StubParser(DakiyaExtraction result) { this.result = result; }
        public String name() { return 'StubParser'; }
        public Boolean handles(Inbound_Message__c msg) { return true; }
        public DakiyaExtraction parse(Inbound_Message__c msg) { return result; }
    }

    private class ExplodingParser implements IDakiyaParser {
        public String name() { return 'ExplodingParser'; }
        public Boolean handles(Inbound_Message__c msg) { throw new CalloutException('boom'); }
        public DakiyaExtraction parse(Inbound_Message__c msg) { return null; }
    }

    @IsTest
    static void confidentOpeningEventCreatesThePurchase() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        String body = 'Your Myntra order MN777 is confirmed. Total Rs. 1299.';
        Inbound_Message__c m = DakiyaTestData.message('Email', 'orders@myntra.in', body);

        DakiyaExtraction ex = DakiyaTestData.extraction('order_placed', 'MN777', null, 1299);
        ex.evidence.order_id = 'order MN777 is confirmed';
        ex.evidence.amount = 'Total Rs. 1299';
        ex.evidence.event_type = 'is confirmed';
        DakiyaParserRegistry.clear();
        DakiyaParserRegistry.register(new StubParser(ex));

        Test.startTest();
        DakiyaProcessMessageJob.process(m.Id);
        Test.stopTest();

        List<Purchase__c> created = [SELECT Id, External_Order_Id__c, Total_Amount__c, Vendor__c FROM Purchase__c];
        Assert.areEqual(1, created.size(), 'A confident order confirmation starts an order');
        Assert.areEqual('MN777', created[0].External_Order_Id__c, 'The real order id is used');
        Assert.areEqual(v.Id, created[0].Vendor__c, 'Vendor resolved from the sender pattern');
        Assert.areEqual('Parsed (Rule)',
            [SELECT Processing_Status__c FROM Inbound_Message__c WHERE Id = :m.Id].Processing_Status__c);
    }

    @IsTest
    static void confidentEventAppliesToTheMatchedPurchase() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_SHIPPED, 1299);
        DakiyaTestData.shipment(p.Id, 'AWB4242', 'Shipped');

        String body = 'Parcel AWB4242 was delivered today.';
        Inbound_Message__c m = DakiyaTestData.message('Email', 'orders@myntra.in', body);

        DakiyaExtraction ex = DakiyaTestData.extraction('delivered', null, 'AWB4242', null);
        ex.evidence.awb = 'Parcel AWB4242 was delivered';
        ex.evidence.event_type = 'was delivered today';
        DakiyaParserRegistry.clear();
        DakiyaParserRegistry.register(new StubParser(ex));

        Test.startTest();
        DakiyaProcessMessageJob.process(m.Id);
        Test.stopTest();

        Assert.areEqual(DakiyaConstants.ST_DELIVERED_UNCONF,
            [SELECT Status__c FROM Purchase__c WHERE Id = :p.Id].Status__c);
        Assert.areEqual(p.Id,
            [SELECT Related_Purchase__c FROM Inbound_Message__c WHERE Id = :m.Id].Related_Purchase__c,
            'The message is linked to the order it updated');
    }

    @IsTest
    static void lowConfidenceAsksInsteadOfApplying() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_SHIPPED, 1299);
        Inbound_Message__c m = DakiyaTestData.message('Email', 'orders@myntra.in', 'Something was delivered.');

        // Only signal is "one open order for this vendor" - worth 0.7, under the gate.
        DakiyaExtraction ex = DakiyaTestData.extraction('delivered', null, null, null);
        ex.evidence.event_type = 'was delivered';
        DakiyaParserRegistry.clear();
        DakiyaParserRegistry.register(new StubParser(ex));

        Test.startTest();
        DakiyaProcessMessageJob.process(m.Id);
        Test.stopTest();

        Inbound_Message__c after = [
            SELECT Processing_Status__c, Candidate_Matches_JSON__c, Related_Purchase__c
            FROM Inbound_Message__c WHERE Id = :m.Id
        ];
        Assert.areEqual('Needs Review', after.Processing_Status__c, 'Uncertainty becomes a question');
        Assert.areEqual(DakiyaConstants.ST_SHIPPED,
            [SELECT Status__c FROM Purchase__c WHERE Id = :p.Id].Status__c,
            'The purchase is untouched - nothing is ever applied tentatively');
        Assert.isNotNull(after.Candidate_Matches_JSON__c, 'Candidates are kept so the review UI can offer them');
        Assert.areEqual(p.Id, after.Related_Purchase__c, 'The best guess is recorded as a suggestion only');
    }

    @IsTest
    static void nonCommerceMessageIsIgnored() {
        Inbound_Message__c m = DakiyaTestData.message('Email', 'news@myntra.in', 'End of season sale!');
        DakiyaExtraction ex = new DakiyaExtraction();
        ex.is_commerce = false;
        ex.confidence = 0.99;
        DakiyaParserRegistry.clear();
        DakiyaParserRegistry.register(new StubParser(ex));

        Test.startTest();
        DakiyaProcessMessageJob.process(m.Id);
        Test.stopTest();

        Assert.areEqual('Ignored',
            [SELECT Processing_Status__c FROM Inbound_Message__c WHERE Id = :m.Id].Processing_Status__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Purchase__c], 'Marketing email creates nothing');
    }

    @IsTest
    static void hallucinatedAwbIsStrippedBeforeMatching() {
        // End to end: the parser claims an AWB the body does not contain. The
        // evidence check removes it, so it can never reach a Shipment record.
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Inbound_Message__c m = DakiyaTestData.message('Email', 'orders@myntra.in', 'Your order is on its way.');

        DakiyaExtraction ex = DakiyaTestData.extraction('shipped', null, '1234567890', null);
        ex.evidence.awb = 'Tracking 1234567890';   // nowhere in the body
        ex.evidence.event_type = 'on its way';
        DakiyaParserRegistry.clear();
        DakiyaParserRegistry.register(new StubParser(ex));

        Test.startTest();
        DakiyaProcessMessageJob.process(m.Id);
        Test.stopTest();

        Assert.areEqual(0, [SELECT COUNT() FROM Shipment__c WHERE AWB__c = '1234567890'],
            'An unevidenced tracking number must never be written anywhere');
        // The evidence quote is deliberately retained for audit - what matters is
        // that the awb FIELD was nulled, so nothing downstream can consume it.
        String stored = [SELECT Extraction_JSON__c FROM Inbound_Message__c WHERE Id = :m.Id].Extraction_JSON__c;
        DakiyaExtraction back = DakiyaExtraction.parse(stored);
        Assert.isNull(back.awb, 'The unevidenced AWB is nulled in the stored extraction');
    }

    @IsTest
    static void unknownEventTypeDegradesToOther() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Inbound_Message__c m = DakiyaTestData.message('Email', 'orders@myntra.in', 'Some update.');
        DakiyaExtraction ex = DakiyaTestData.extraction('teleported', null, null, null);
        ex.evidence.event_type = 'Some update';
        DakiyaParserRegistry.clear();
        DakiyaParserRegistry.register(new StubParser(ex));

        Test.startTest();
        DakiyaProcessMessageJob.process(m.Id);
        Test.stopTest();

        String stored = [SELECT Extraction_JSON__c FROM Inbound_Message__c WHERE Id = :m.Id].Extraction_JSON__c;
        Assert.isTrue(stored.contains(DakiyaConstants.EV_OTHER),
            'An event type outside the contract is normalised, not trusted');
    }

    @IsTest
    static void aBrokenParserDoesNotStopThePipeline() {
        Inbound_Message__c m = DakiyaTestData.message('Email', 'orders@myntra.in', 'body');
        DakiyaParserRegistry.clear();
        DakiyaParserRegistry.register(new ExplodingParser());

        Test.startTest();
        DakiyaProcessMessageJob.process(m.Id);
        Test.stopTest();

        Assert.areEqual('Needs Review',
            [SELECT Processing_Status__c FROM Inbound_Message__c WHERE Id = :m.Id].Processing_Status__c,
            'A throwing parser is skipped, not fatal');
    }

    @IsTest
    static void missingMessageIsNotAnError() {
        Vendor__c v = DakiyaTestData.vendor('X', 'Other');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_PLACED, 1);
        Test.startTest();
        DakiyaProcessMessageJob.process(p.Id);   // not an Inbound_Message id
        Test.stopTest();
        Assert.areEqual(1, [SELECT COUNT() FROM Purchase__c], 'Nothing changed, nothing thrown');
    }
}
