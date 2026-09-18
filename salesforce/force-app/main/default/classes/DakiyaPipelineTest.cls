/**
 * Ingest, matching, application and the queueable, end to end.
 *
 * The recurring assertion here is restraint: when the pipeline is not confident,
 * it must produce a review item rather than a record change.
 */
@IsTest
private class DakiyaPipelineTest {

    @IsTest
    static void ingestStoresAndDedupes() {
        Test.startTest();
        DakiyaIngestService.IngestResult first = DakiyaIngestService.ingest(
            'Email', 'ship@myntra.in', 'Shipped', 'Your order MN1 shipped',
            Datetime.now(), 'gmail-msg-1'
        );
        DakiyaIngestService.IngestResult again = DakiyaIngestService.ingest(
            'Email', 'ship@myntra.in', 'Shipped', 'Your order MN1 shipped',
            Datetime.now(), 'gmail-msg-1'
        );
        Test.stopTest();

        Assert.isFalse(first.duplicate, 'First delivery is new');
        Assert.isTrue(again.duplicate, 'Gmail re-delivering the same id must be a no-op');
        Assert.areEqual(first.id, again.id, 'Both point at the same stored message');
        Assert.areEqual(1, [SELECT COUNT() FROM Inbound_Message__c], 'Exactly one row stored');
    }

    @IsTest
    static void ingestRejectsMissingDedupeKey() {
        try {
            DakiyaIngestService.ingest('Email', 'a@b.in', 's', 'body', Datetime.now(), null);
            Assert.fail('Should have refused a message with no dedupe key');
        } catch (DakiyaIngestService.IngestException e) {
            Assert.isTrue(e.getMessage().contains('dedupeKey'), e.getMessage());
        }
    }

    @IsTest
    static void matchesOnAwbAboveEverythingElse() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_SHIPPED, 1299);
        DakiyaTestData.shipment(p.Id, 'AWB999111', 'Shipped');

        DakiyaExtraction ex = DakiyaTestData.extraction('delivered', null, 'AWB999111', null);
        DakiyaMatchingService.MatchResult r = DakiyaMatchingService.match(ex, v.Id);

        Assert.areEqual(p.Id, r.best.purchaseId, 'AWB identifies the parcel');
        Assert.areEqual(1.0, r.best.score, 'AWB is a certain match');
    }

    @IsTest
    static void matchesOnVendorAndOrderId() {
        Vendor__c v = DakiyaTestData.vendor('Nykaa', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_PLACED, 500);

        DakiyaExtraction ex = DakiyaTestData.extraction('shipped', p.External_Order_Id__c, null, null);
        DakiyaMatchingService.MatchResult r = DakiyaMatchingService.match(ex, v.Id);

        Assert.areEqual(p.Id, r.best.purchaseId);
        Assert.areEqual(1.0, r.best.score);
    }

    @IsTest
    static void singleOpenPurchaseScoresBelowAutoApply() {
        // 0.7 is deliberately under AutoApplyConfidence: "the only open order"
        // is a hint, not proof, so it must ask rather than act.
        Vendor__c v = DakiyaTestData.vendor('Nykaa', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_PLACED, 500);

        DakiyaExtraction ex = DakiyaTestData.extraction('shipped', null, null, null);
        DakiyaMatchingService.MatchResult r = DakiyaMatchingService.match(ex, v.Id);

        Assert.areEqual(0.7, r.best.score, 'Weak signal scores weakly');
        Assert.isTrue(r.best.score < DakiyaSettings.autoApplyConfidence(),
            'A lone open order must not be enough to auto-apply');
    }

    @IsTest
    static void suggestsCreationOnlyForOpeningEvents() {
        Vendor__c v = DakiyaTestData.vendor('Amazon', 'Marketplace');

        DakiyaMatchingService.MatchResult opening =
            DakiyaMatchingService.match(DakiyaTestData.extraction('order_placed', 'A1', null, 99), v.Id);
        Assert.isTrue(opening.shouldCreateNew, 'An order confirmation with no match starts a new order');

        DakiyaMatchingService.MatchResult later =
            DakiyaMatchingService.match(DakiyaTestData.extraction('delivered', 'A2', null, 99), v.Id);
        Assert.isFalse(later.shouldCreateNew,
            'A delivery with no matching order means we lost the thread and must ask');
    }

    @IsTest
    static void applyingADeliveryLeavesConfirmationPending() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_SHIPPED, 1299);
        DakiyaTestData.shipment(p.Id, 'AWB123', 'Shipped');
        Inbound_Message__c m = DakiyaTestData.message('Email', 'ship@myntra.in', 'Delivered AWB123');

        DakiyaExtraction ex = DakiyaTestData.extraction('delivered', null, 'AWB123', null);

        Test.startTest();
        DakiyaEventApplier.apply(p, ex, m.Id, DakiyaConstants.BY_RULE);
        Test.stopTest();

        Purchase__c after = [SELECT Status__c, Delivered_At__c, Return_Window_Ends__c FROM Purchase__c WHERE Id = :p.Id];
        Shipment__c s = [SELECT Status__c, Confirmation__c FROM Shipment__c WHERE AWB__c = 'AWB123'];

        Assert.areEqual(DakiyaConstants.ST_DELIVERED_UNCONF, after.Status__c,
            'A courier claim only ever produces Delivered (Unconfirmed)');
        Assert.areEqual('Pending', s.Confirmation__c, 'Confirmation waits for Gitanjali');
        Assert.isNotNull(after.Return_Window_Ends__c, 'Vendor window is known, so it is set');
        Assert.areEqual(1, [SELECT COUNT() FROM Tracking_Event__c WHERE Purchase__c = :p.Id],
            'Every applied event is recorded on the timeline');
    }

    @IsTest
    static void outOfOrderEventStillWritesATimelineEntry() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_DELIVERED_UNCONF, 1299);
        Inbound_Message__c m = DakiyaTestData.message('Email', 'ship@myntra.in', 'shipped');

        DakiyaEventApplier.ApplyResult r =
            DakiyaEventApplier.apply(p, DakiyaTestData.extraction('shipped', null, null, null),
                                     m.Id, DakiyaConstants.BY_RULE);

        Assert.isFalse(r.statusChanged, 'Status held');
        Assert.areEqual(1, [SELECT COUNT() FROM Tracking_Event__c WHERE Purchase__c = :p.Id],
            'The event is still logged - "we saw this and ignored it" is worth keeping');
    }

    @IsTest
    static void refundInitiatedSetsACheckDate() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        v.Typical_Refund_Days__c = 4;
        update v;
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_RECEIVED, 1299);
        Inbound_Message__c m = DakiyaTestData.message('Email', 'ship@myntra.in', 'refund initiated');

        DakiyaEventApplier.apply(p, DakiyaTestData.extraction('refund_initiated', null, null, 1299),
                                 m.Id, DakiyaConstants.BY_RULE);

        Return__c r = [SELECT Status__c, Refund_Check_Due__c, Expected_Refund_Amount__c
                       FROM Return__c WHERE Purchase__c = :p.Id];
        Assert.areEqual('Refund Initiated', r.Status__c);
        Assert.areEqual(Date.today().addDays(4), r.Refund_Check_Due__c,
            'Check date comes from the vendor learned habit, not the default');
    }

    @IsTest
    static void vendorRefundCompletedDoesNotRecordAnOutcome() {
        // The vendor saying "refunded" is a claim. Only Gitanjali checking counts.
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_RETURN_IN_PROGRESS, 1299);
        Inbound_Message__c m = DakiyaTestData.message('Email', 'ship@myntra.in', 'refund processed');

        DakiyaEventApplier.apply(p, DakiyaTestData.extraction('refund_completed', null, null, null),
                                 m.Id, DakiyaConstants.BY_RULE);

        Return__c r = [SELECT Status__c, Refund_Outcome__c FROM Return__c WHERE Purchase__c = :p.Id];
        Assert.areEqual('Refund Check Due', r.Status__c, 'It becomes a question, not a conclusion');
        Assert.isNull(r.Refund_Outcome__c, 'No outcome is recorded from a vendor claim');
    }

    @IsTest
    static void unparseableMessageGoesToReviewNotToAGuess() {
        Inbound_Message__c m = DakiyaTestData.message('Email', 'unknown@nowhere.in', 'Some text');

        Test.startTest();
        DakiyaProcessMessageJob.process(m.Id);
        Test.stopTest();

        Inbound_Message__c after = [SELECT Processing_Status__c FROM Inbound_Message__c WHERE Id = :m.Id];
        Assert.areEqual('Needs Review', after.Processing_Status__c,
            'With no rule parser and the LLM stubbed, the honest outcome is a question');
        Assert.areEqual(0, [SELECT COUNT() FROM Purchase__c], 'Nothing was invented');
    }

    @IsTest
    static void queueableRunsWithoutError() {
        Inbound_Message__c m = DakiyaTestData.message('SMS', 'AMAZON', 'Order shipped');
        Test.startTest();
        System.enqueueJob(new DakiyaProcessMessageJob(m.Id));
        Test.stopTest();
        Assert.areEqual('Needs Review',
            [SELECT Processing_Status__c FROM Inbound_Message__c WHERE Id = :m.Id].Processing_Status__c);
    }

    @IsTest
    static void resolvesVendorFromSenderPatterns() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Inbound_Message__c email = DakiyaTestData.message('Email', 'orders@myntra.in', 'body');
        Inbound_Message__c sms = DakiyaTestData.message('SMS', 'VM-MYNTRA', 'body');

        Assert.areEqual(v.Id, DakiyaParserRegistry.resolveVendor(email).Id, 'Email domain pattern matches');
        Assert.areEqual(v.Id, DakiyaParserRegistry.resolveVendor(sms).Id, 'SMS header pattern matches');
        Assert.isNull(DakiyaParserRegistry.resolveVendor(
            DakiyaTestData.message('Email', 'someone@elsewhere.com', 'body')), 'No false positives');
    }

    @IsTest
    static void registryHasNoParsersUntilPhaseSix() {
        Inbound_Message__c m = DakiyaTestData.message('Email', 'orders@myntra.in', 'body');
        Assert.isNull(DakiyaParserRegistry.selectFor(m),
            'Rule parsers are built in Phase 6 from real samples, not guessed now');
    }

    @IsTest
    static void settingsFallBackWhenValueIsUnusable() {
        Assert.areEqual(7, DakiyaSettings.getInt('NotARealSetting', 7), 'Missing key uses the fallback');
        Assert.areEqual(0.90, DakiyaSettings.autoApplyConfidence(), 'Deployed default is read');
        Assert.areEqual(30, DakiyaSettings.rawBodyRetentionDays());
        Assert.areEqual('PromptTemplate', DakiyaSettings.extractor());
    }
}
