/**
 * The 16 agent actions (BUILD_SPEC 7).
 *
 * Beyond "does it work", these assert the guardrails the agent leans on: it
 * cannot mark something received without the user saying so, cannot cancel a
 * delivered order, cannot return an undelivered one, and never fills a gap in a
 * complaint or a draft with an invented value.
 */
@IsTest
private class DakiyaAgentActionsTest {

    private static Vendor__c vendor;
    private static Purchase__c purchase;

    private static void seed(String status) {
        vendor = DakiyaTestData.vendor('Myntra', 'Marketplace');
        purchase = DakiyaTestData.purchase(vendor.Id, status, 1299);
    }

    // ── read actions ──────────────────────────────────────────────────

    @IsTest
    static void pendingDeliveriesSeparatesOnTheWayFromUnconfirmed() {
        seed(DakiyaConstants.ST_SHIPPED);
        Purchase__c delivered = DakiyaTestData.purchase(vendor.Id, DakiyaConstants.ST_DELIVERED_UNCONF, 500);
        DakiyaTestData.shipment(delivered.Id, 'AWB-PD1', 'Delivered');

        Dakiya_GetPendingDeliveries.Response r =
            Dakiya_GetPendingDeliveries.run(new List<String>{ 'x' })[0];

        Assert.areEqual(1, r.pendingCount, 'One order still on the way');
        Assert.areEqual(1, r.awaitingConfirmationCount, 'One delivered but unconfirmed');
        Assert.isTrue(r.summary.contains('not confirmed by you'), r.summary);
    }

    @IsTest
    static void pendingDeliveriesSaysSoWhenThereIsNothing() {
        Dakiya_GetPendingDeliveries.Response r =
            Dakiya_GetPendingDeliveries.run(new List<String>{ 'x' })[0];
        Assert.areEqual(0, r.pendingCount);
        Assert.isTrue(r.summary.contains('Nothing pending'), r.summary);
    }

    @IsTest
    static void searchFindsByVendorAndReportsHonestEmptiness() {
        seed(DakiyaConstants.ST_SHIPPED);

        Dakiya_SearchPurchases.Request hit = new Dakiya_SearchPurchases.Request();
        hit.vendor = 'Myntra';
        Dakiya_SearchPurchases.Response found =
            Dakiya_SearchPurchases.run(new List<Dakiya_SearchPurchases.Request>{ hit })[0];
        Assert.areEqual(1, found.matchCount);
        Assert.areEqual(purchase.Id, found.purchaseIds[0]);

        Dakiya_SearchPurchases.Request miss = new Dakiya_SearchPurchases.Request();
        miss.vendor = 'Flipkart';
        Dakiya_SearchPurchases.Response none =
            Dakiya_SearchPurchases.run(new List<Dakiya_SearchPurchases.Request>{ miss })[0];
        Assert.areEqual(0, none.matchCount);
        Assert.isTrue(none.summary.contains('not guessed'),
            'An empty result must say nothing matched, not offer a near-miss: ' + none.summary);
    }

    @IsTest
    static void timelineIncludesParcelsEventsAndReturns() {
        seed(DakiyaConstants.ST_DELIVERED_UNCONF);
        DakiyaTestData.shipment(purchase.Id, 'AWB-TL1', 'Delivered');
        insert new Tracking_Event__c(Purchase__c = purchase.Id, Event_Type__c = 'delivered',
            Event_At__c = Datetime.now(), Applied_By__c = 'Rule', Summary__c = 'Delivered');
        insert new Return__c(Purchase__c = purchase.Id, Type__c = 'Return', Status__c = 'Requested');

        Dakiya_GetPurchaseTimeline.Request req = new Dakiya_GetPurchaseTimeline.Request();
        req.purchaseId = purchase.Id;
        Dakiya_GetPurchaseTimeline.Response r =
            Dakiya_GetPurchaseTimeline.run(new List<Dakiya_GetPurchaseTimeline.Request>{ req })[0];

        Assert.isTrue(r.found);
        Assert.isTrue(r.summary.contains('AWB-TL1'), 'Parcel shown: ' + r.summary);
        Assert.isTrue(r.summary.contains('Timeline:'), 'Events shown');
        Assert.isTrue(r.summary.contains('Return:'), 'Returns shown');
    }

    @IsTest
    static void openReturnsFlagsRefundsWorthChecking() {
        seed(DakiyaConstants.ST_RETURN_IN_PROGRESS);
        insert new Return__c(Purchase__c = purchase.Id, Type__c = 'Return',
            Status__c = 'Refund Initiated', Refund_Initiated_On__c = Date.today().addDays(-9),
            Refund_Check_Due__c = Date.today().addDays(-2), Expected_Refund_Amount__c = 1299);

        Dakiya_ListOpenReturns.Response r = Dakiya_ListOpenReturns.run(new List<String>{ 'x' })[0];

        Assert.areEqual(1, r.openCount);
        Assert.areEqual(1, r.refundChecksDue);
        Assert.isTrue(r.summary.contains('WORTH CHECKING NOW'), r.summary);
        Assert.isTrue(r.summary.contains('cannot see bank accounts'),
            'The reply must be explicit that the user has to check: ' + r.summary);
    }

    @IsTest
    static void vendorPatternAdmitsWhenItKnowsNothing() {
        DakiyaTestData.vendor('Nykaa', 'Marketplace');
        Dakiya_GetVendorRefundPattern.Request req = new Dakiya_GetVendorRefundPattern.Request();
        req.vendorName = 'Nykaa';
        Dakiya_GetVendorRefundPattern.Response r =
            Dakiya_GetVendorRefundPattern.run(new List<Dakiya_GetVendorRefundPattern.Request>{ req })[0];

        Assert.isFalse(r.known, 'No completed refunds yet');
        Assert.isTrue(r.summary.contains('no timing to go on'), r.summary);
    }

    @IsTest
    static void vendorPatternReportsLearnedHabits() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        v.Typical_Refund_Days__c = 5;
        v.Usual_Refund_Mode__c = 'Store Credit';
        v.Refund_History_Summary__c = '3 returns: 3 store credit';
        update v;

        Dakiya_GetVendorRefundPattern.Request req = new Dakiya_GetVendorRefundPattern.Request();
        req.vendorName = 'Myntra';
        Dakiya_GetVendorRefundPattern.Response r =
            Dakiya_GetVendorRefundPattern.run(new List<Dakiya_GetVendorRefundPattern.Request>{ req })[0];

        Assert.isTrue(r.known);
        Assert.isTrue(r.summary.contains('about 5 days'), r.summary);
        Assert.isTrue(r.summary.contains('Store Credit'), r.summary);
    }

    @IsTest
    static void reviewItemsListsWhatDakiyaIsUnsureAbout() {
        Inbound_Message__c m = DakiyaTestData.message('SMS', 'VM-COURIER', 'Out for delivery');
        m.Processing_Status__c = 'Needs Review';
        update m;

        Dakiya_ListReviewItems.Response r = Dakiya_ListReviewItems.run(new List<String>{ 'x' })[0];
        Assert.areEqual(1, r.reviewCount);
        Assert.areEqual(m.Id, r.messageIds[0]);
    }

    // ── write actions ─────────────────────────────────────────────────

    @IsTest
    static void createPurchaseMakesAnInstagramSellerWithAShorterLeash() {
        Dakiya_CreatePurchase.Request req = new Dakiya_CreatePurchase.Request();
        req.vendorName = '@soap_shop';
        req.title = 'Two soaps';
        req.items = 'Lavender soap, Neem soap';
        req.amount = 450;

        Dakiya_CreatePurchase.Response r =
            Dakiya_CreatePurchase.run(new List<Dakiya_CreatePurchase.Request>{ req })[0];

        Assert.isTrue(r.created, r.summary);
        Vendor__c v = [SELECT Channel__c, Instagram_Handle__c, Follow_Up_After_Days__c
                       FROM Vendor__c WHERE Name = '@soap_shop'];
        Assert.areEqual('Instagram', v.Channel__c, 'An @handle is inferred as an Instagram seller');
        Assert.areEqual(DakiyaSettings.instagramFollowUpDays(), v.Follow_Up_After_Days__c,
            'Instagram sellers get the shorter stall threshold');
        Assert.areEqual(2, [SELECT COUNT() FROM Purchase_Item__c], 'Both items recorded');
        Assert.areEqual('Chat', [SELECT Source__c FROM Purchase__c WHERE Id = :r.purchaseId].Source__c);
    }

    @IsTest
    static void createPurchaseLeavesUnstatedFieldsEmpty() {
        Dakiya_CreatePurchase.Request req = new Dakiya_CreatePurchase.Request();
        req.vendorName = '@soap_shop';
        req.title = 'Two soaps';
        // No amount, no order id, no date given.

        Dakiya_CreatePurchase.Response r =
            Dakiya_CreatePurchase.run(new List<Dakiya_CreatePurchase.Request>{ req })[0];

        Purchase__c p = [SELECT Total_Amount__c, External_Order_Id__c FROM Purchase__c WHERE Id = :r.purchaseId];
        Assert.isNull(p.Total_Amount__c, 'An amount the user never gave stays empty');
        Assert.isNull(p.External_Order_Id__c, 'An order id the user never gave stays empty');
    }

    @IsTest
    static void createPurchaseNeedsASeller() {
        Dakiya_CreatePurchase.Request req = new Dakiya_CreatePurchase.Request();
        req.title = 'Something';
        Dakiya_CreatePurchase.Response r =
            Dakiya_CreatePurchase.run(new List<Dakiya_CreatePurchase.Request>{ req })[0];
        Assert.isFalse(r.created);
        Assert.isTrue(r.summary.contains('who you bought it from'), r.summary);
    }

    @IsTest
    static void addTrackingStoresTheNumberVerbatimAndAdvancesStatus() {
        seed(DakiyaConstants.ST_CONFIRMED);
        Dakiya_AddTracking.Request req = new Dakiya_AddTracking.Request();
        req.purchaseId = purchase.Id;
        req.courier = 'Delhivery';
        req.awb = '  7412589630  ';

        Dakiya_AddTracking.Response r =
            Dakiya_AddTracking.run(new List<Dakiya_AddTracking.Request>{ req })[0];

        Assert.areEqual('7412589630', [SELECT AWB__c FROM Shipment__c WHERE Id = :r.shipmentId].AWB__c,
            'Trimmed but otherwise exactly as given');
        Assert.areEqual(DakiyaConstants.ST_SHIPPED,
            [SELECT Status__c FROM Purchase__c WHERE Id = :purchase.Id].Status__c);
    }

    @IsTest
    static void addTrackingNeedsSomethingToGoOn() {
        seed(DakiyaConstants.ST_CONFIRMED);
        Dakiya_AddTracking.Request req = new Dakiya_AddTracking.Request();
        req.purchaseId = purchase.Id;
        Dakiya_AddTracking.Response r =
            Dakiya_AddTracking.run(new List<Dakiya_AddTracking.Request>{ req })[0];
        Assert.isTrue(r.summary.contains('at least a courier'), r.summary);
    }

    @IsTest
    static void cancelRefusesOnceDelivered() {
        seed(DakiyaConstants.ST_DELIVERED_UNCONF);
        Dakiya_CancelPurchase.Request req = new Dakiya_CancelPurchase.Request();
        req.purchaseId = purchase.Id;

        Dakiya_CancelPurchase.Response r =
            Dakiya_CancelPurchase.run(new List<Dakiya_CancelPurchase.Request>{ req })[0];

        Assert.isFalse(r.cancelled);
        Assert.isTrue(r.summary.contains('return is the right route'),
            'It should redirect rather than silently doing nothing: ' + r.summary);
    }

    @IsTest
    static void cancelWorksBeforeDelivery() {
        seed(DakiyaConstants.ST_PLACED);
        Dakiya_CancelPurchase.Request req = new Dakiya_CancelPurchase.Request();
        req.purchaseId = purchase.Id;
        req.reason = 'Changed my mind';

        Dakiya_CancelPurchase.Response r =
            Dakiya_CancelPurchase.run(new List<Dakiya_CancelPurchase.Request>{ req })[0];

        Assert.isTrue(r.cancelled, r.summary);
        Purchase__c p = [SELECT Status__c, Notes__c FROM Purchase__c WHERE Id = :purchase.Id];
        Assert.areEqual(DakiyaConstants.ST_CANCELLED, p.Status__c);
        Assert.isTrue(p.Notes__c.contains('Changed my mind'), 'The reason is kept');
    }

    @IsTest
    static void confirmReceivedIsTheOnlyRouteToReceived() {
        seed(DakiyaConstants.ST_DELIVERED_UNCONF);
        Shipment__c s = DakiyaTestData.shipment(purchase.Id, 'AWB-CR1', 'Delivered');

        Dakiya_ConfirmReceived.Request req = new Dakiya_ConfirmReceived.Request();
        req.recordId = s.Id;
        Dakiya_ConfirmReceived.Response r =
            Dakiya_ConfirmReceived.run(new List<Dakiya_ConfirmReceived.Request>{ req })[0];

        Assert.areEqual(DakiyaConstants.ST_RECEIVED, r.status);
        Assert.isTrue(r.summary.contains('Nothing else outstanding'), r.summary);
    }

    @IsTest
    static void confirmReceivedAsksWhenTheParcelIsAmbiguous() {
        seed(DakiyaConstants.ST_DELIVERED_UNCONF);
        DakiyaTestData.shipment(purchase.Id, 'AWB-X1', 'Delivered');
        DakiyaTestData.shipment(purchase.Id, 'AWB-X2', 'Delivered');

        Dakiya_ConfirmReceived.Request req = new Dakiya_ConfirmReceived.Request();
        req.recordId = purchase.Id;    // two pending parcels, so which one?
        Dakiya_ConfirmReceived.Response r =
            Dakiya_ConfirmReceived.run(new List<Dakiya_ConfirmReceived.Request>{ req })[0];

        Assert.isTrue(r.summary.contains('which order'),
            'With two candidates it must ask rather than pick one: ' + r.summary);
    }

    @IsTest
    static void notReceivedBuildsAComplaintPackFromRecordedFactsOnly() {
        seed(DakiyaConstants.ST_DELIVERED_UNCONF);
        Shipment__c s = DakiyaTestData.shipment(purchase.Id, 'AWB-NR1', 'Delivered');

        Dakiya_ReportNotReceived.Request req = new Dakiya_ReportNotReceived.Request();
        req.recordId = s.Id;
        Dakiya_ReportNotReceived.Response r =
            Dakiya_ReportNotReceived.run(new List<Dakiya_ReportNotReceived.Request>{ req })[0];

        Assert.isTrue(r.complaintPack.contains('AWB-NR1'), r.complaintPack);
        Assert.isTrue(r.complaintPack.contains('Myntra'), r.complaintPack);
        Assert.isTrue(r.complaintPack.contains('Courier claimed delivery'), r.complaintPack);
    }

    @IsTest
    static void createReturnRefusesBeforeDelivery() {
        seed(DakiyaConstants.ST_SHIPPED);
        Dakiya_CreateReturn.Request req = new Dakiya_CreateReturn.Request();
        req.purchaseId = purchase.Id;
        req.reason = 'Wrong size';

        Dakiya_CreateReturn.Response r =
            Dakiya_CreateReturn.run(new List<Dakiya_CreateReturn.Request>{ req })[0];

        Assert.isNull(r.returnId, 'Nothing created');
        Assert.isTrue(r.summary.contains('cancel it instead'),
            'It should offer the action that does make sense: ' + r.summary);
    }

    @IsTest
    static void createReturnLinksTheNamedItem() {
        seed(DakiyaConstants.ST_RECEIVED);
        insert new Purchase_Item__c(Name = 'Vitamin C Serum', Purchase__c = purchase.Id,
            Quantity__c = 1, Status__c = 'Active');

        Dakiya_CreateReturn.Request req = new Dakiya_CreateReturn.Request();
        req.purchaseId = purchase.Id;
        req.itemName = 'serum';
        req.reason = 'Reaction';
        req.type = 'exchange';

        Dakiya_CreateReturn.Response r =
            Dakiya_CreateReturn.run(new List<Dakiya_CreateReturn.Request>{ req })[0];

        Return__c ret = [SELECT Type__c, Purchase_Item__c FROM Return__c WHERE Id = :r.returnId];
        Assert.areEqual('Exchange or Replacement', ret.Type__c);
        Assert.isNotNull(ret.Purchase_Item__c, 'Matched the item by name');
        Assert.areEqual(DakiyaConstants.ST_RETURN_IN_PROGRESS,
            [SELECT Status__c FROM Purchase__c WHERE Id = :purchase.Id].Status__c);
    }

    @IsTest
    static void refundInitiatedSchedulesTheCheckAndSaysWhy() {
        seed(DakiyaConstants.ST_RETURN_IN_PROGRESS);
        Return__c ret = new Return__c(Purchase__c = purchase.Id, Type__c = 'Return', Status__c = 'Picked Up');
        insert ret;

        Dakiya_UpdateReturnStatus.Request req = new Dakiya_UpdateReturnStatus.Request();
        req.returnId = ret.Id;
        req.status = 'Refund Initiated';

        Dakiya_UpdateReturnStatus.Response r =
            Dakiya_UpdateReturnStatus.run(new List<Dakiya_UpdateReturnStatus.Request>{ req })[0];

        Assert.areEqual(Date.today().addDays(DakiyaSettings.defaultRefundCheckDays()), r.refundCheckDue);
        Assert.isTrue(r.summary.contains('cannot see your bank'),
            'It must be explicit about who checks: ' + r.summary);
    }

    @IsTest
    static void updateReturnStatusRejectsAnOutcomeMasqueradingAsAStage() {
        seed(DakiyaConstants.ST_RETURN_IN_PROGRESS);
        Return__c ret = new Return__c(Purchase__c = purchase.Id, Type__c = 'Return', Status__c = 'Picked Up');
        insert ret;

        Dakiya_UpdateReturnStatus.Request req = new Dakiya_UpdateReturnStatus.Request();
        req.returnId = ret.Id;
        req.status = 'Completed';

        Dakiya_UpdateReturnStatus.Response r =
            Dakiya_UpdateReturnStatus.run(new List<Dakiya_UpdateReturnStatus.Request>{ req })[0];

        Assert.isTrue(r.summary.contains('refund outcome action'),
            'Closing a return is an outcome the user reports, not a stage: ' + r.summary);
        Assert.areEqual('Picked Up', [SELECT Status__c FROM Return__c WHERE Id = :ret.Id].Status__c);
    }

    @IsTest
    static void recordRefundOutcomeClosesAndLearns() {
        seed(DakiyaConstants.ST_RETURN_IN_PROGRESS);
        Return__c ret = new Return__c(Purchase__c = purchase.Id, Type__c = 'Return',
            Status__c = 'Refund Initiated', Refund_Initiated_On__c = Date.today().addDays(-6));
        insert ret;

        Dakiya_RecordRefundOutcome.Request req = new Dakiya_RecordRefundOutcome.Request();
        req.returnId = ret.Id;
        req.outcome = 'Store Credit';
        req.amount = 1299;

        Dakiya_RecordRefundOutcome.Response r =
            Dakiya_RecordRefundOutcome.run(new List<Dakiya_RecordRefundOutcome.Request>{ req })[0];

        Assert.isTrue(r.summary.contains('Store Credit'), r.summary);
        Assert.areEqual('Store Credit',
            [SELECT Usual_Refund_Mode__c FROM Vendor__c WHERE Id = :vendor.Id].Usual_Refund_Mode__c);
    }

    @IsTest
    static void recordRefundOutcomeRejectsAnInventedOutcome() {
        seed(DakiyaConstants.ST_RETURN_IN_PROGRESS);
        Return__c ret = new Return__c(Purchase__c = purchase.Id, Type__c = 'Return', Status__c = 'Refund Initiated');
        insert ret;

        Dakiya_RecordRefundOutcome.Request req = new Dakiya_RecordRefundOutcome.Request();
        req.returnId = ret.Id;
        req.outcome = 'They sent me a voucher maybe';

        Dakiya_RecordRefundOutcome.Response r =
            Dakiya_RecordRefundOutcome.run(new List<Dakiya_RecordRefundOutcome.Request>{ req })[0];

        Assert.isTrue(r.summary.contains('I can record one of'), r.summary);
        Assert.isNull([SELECT Refund_Outcome__c FROM Return__c WHERE Id = :ret.Id].Refund_Outcome__c);
    }

    @IsTest
    static void draftFollowUpUsesOnlyRecordedFacts() {
        seed(DakiyaConstants.ST_SHIPPED);
        DakiyaTestData.shipment(purchase.Id, 'AWB-DF1', 'Shipped');

        Dakiya_DraftFollowUp.Request req = new Dakiya_DraftFollowUp.Request();
        req.purchaseId = purchase.Id;
        req.tone = 'firm';

        Dakiya_DraftFollowUp.Response r =
            Dakiya_DraftFollowUp.run(new List<Dakiya_DraftFollowUp.Request>{ req })[0];

        Assert.isTrue(r.draft.contains('AWB-DF1'), 'Quotes the real AWB: ' + r.draft);
        Assert.isTrue(r.draft.contains(purchase.External_Order_Id__c), 'Quotes the real order id');
        Assert.isTrue(r.summary.contains('not sent it'),
            'It must be explicit that sending is the user\'s job: ' + r.summary);
    }

    @IsTest
    static void draftFollowUpOmitsWhatIsNotKnown() {
        Vendor__c v = DakiyaTestData.vendor('@quiet_shop', 'Instagram');
        Purchase__c bare = new Purchase__c(
            Vendor__c = v.Id, Title__c = 'Two soaps', Vendor_Order_Key__c = 'bare:1',
            Status__c = DakiyaConstants.ST_PLACED, Status_Rank__c = 10, Source__c = 'Chat'
        );
        insert bare;

        Dakiya_DraftFollowUp.Request req = new Dakiya_DraftFollowUp.Request();
        req.purchaseId = bare.Id;
        Dakiya_DraftFollowUp.Response r =
            Dakiya_DraftFollowUp.run(new List<Dakiya_DraftFollowUp.Request>{ req })[0];

        Assert.isFalse(r.draft.contains('Order null'), 'No placeholder order id: ' + r.draft);
        Assert.isFalse(r.draft.contains('AWB'), 'No invented tracking number');
        Assert.isTrue(r.draft.contains('@quiet_shop'), 'Still addresses the right seller');
    }

    @IsTest
    static void resolveReviewCanIgnore() {
        Inbound_Message__c m = DakiyaTestData.message('Email', 'sale@shop.in', 'Sale!');
        m.Processing_Status__c = 'Needs Review';
        update m;

        Dakiya_ResolveReview.Request req = new Dakiya_ResolveReview.Request();
        req.inboundMessageId = m.Id;
        req.resolution = 'ignore';

        Dakiya_ResolveReview.Response r =
            Dakiya_ResolveReview.run(new List<Dakiya_ResolveReview.Request>{ req })[0];

        Assert.isTrue(r.summary.contains('not ask about that one again'), r.summary);
        Assert.areEqual('Ignored',
            [SELECT Processing_Status__c FROM Inbound_Message__c WHERE Id = :m.Id].Processing_Status__c);
    }

    @IsTest
    static void rupeeFormattingUsesIndianGrouping() {
        Assert.areEqual('Rs 1,299', DakiyaAgentFormat.rupees(1299));
        Assert.areEqual('Rs 1,29,900', DakiyaAgentFormat.rupees(129900),
            'Indian grouping: lakhs, not thousands');
        Assert.areEqual('Rs 450', DakiyaAgentFormat.rupees(450));
        Assert.areEqual('amount unknown', DakiyaAgentFormat.rupees(null),
            'A missing amount is said plainly, never shown as zero');
    }
}
