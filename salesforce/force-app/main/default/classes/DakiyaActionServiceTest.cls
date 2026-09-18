/** The user's own decisions - the only route to Received and to a refund outcome. */
@IsTest
private class DakiyaActionServiceTest {

    @IsTest
    static void confirmingTheLastParcelMarksItReceived() {
        Vendor__c v = DakiyaTestData.vendor('Nykaa', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_DELIVERED_UNCONF, 800);
        Shipment__c s = DakiyaTestData.shipment(p.Id, 'AWB555', 'Delivered');

        Map<String, Object> out = DakiyaActionService.run('confirm_received', s.Id, null);

        Assert.areEqual(DakiyaConstants.ST_RECEIVED, (String) out.get('status'));
        Assert.areEqual('Received',
            [SELECT Confirmation__c FROM Shipment__c WHERE Id = :s.Id].Confirmation__c);
        Assert.areEqual(DakiyaConstants.BY_USER,
            [SELECT Applied_By__c FROM Tracking_Event__c WHERE Purchase__c = :p.Id LIMIT 1].Applied_By__c,
            'Provenance records that a human said so');
    }

    @IsTest
    static void confirmingOneOfTwoParcelsStaysPartial() {
        Vendor__c v = DakiyaTestData.vendor('Amazon', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_DELIVERED_UNCONF, 2000);
        Shipment__c first = DakiyaTestData.shipment(p.Id, 'AWB-A', 'Delivered');
        DakiyaTestData.shipment(p.Id, 'AWB-B', 'Delivered');

        Map<String, Object> out = DakiyaActionService.run('confirm_received', first.Id, null);

        Assert.areEqual(DakiyaConstants.ST_PARTIALLY_SHIPPED, (String) out.get('status'),
            'A second parcel is still outstanding');
    }

    @IsTest
    static void notReceivedReturnsAComplaintPackFromRealData() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_DELIVERED_UNCONF, 1299);
        Shipment__c s = DakiyaTestData.shipment(p.Id, 'AWB777', 'Delivered');

        Map<String, Object> out = DakiyaActionService.run('not_received', s.Id, null);
        Map<String, Object> pack = (Map<String, Object>) out.get('complaintPack');

        Assert.areEqual(DakiyaConstants.ST_NOT_RECEIVED, (String) out.get('status'));
        Assert.areEqual('AWB777', (String) pack.get('awb'), 'The pack quotes the AWB we actually recorded');
        Assert.areEqual('Myntra', (String) pack.get('vendor'));
        Assert.isNotNull(pack.get('deliveredClaimAt'), 'The disputed claim time is included');
        Assert.isTrue([SELECT Needs_Review__c FROM Purchase__c WHERE Id = :p.Id].Needs_Review__c,
            'A disputed delivery is flagged for attention');
    }

    @IsTest
    static void recordingARefundOutcomeClosesTheReturnAndTeachesTheVendor() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_RETURN_IN_PROGRESS, 1299);
        Return__c r = new Return__c(
            Purchase__c = p.Id, Type__c = 'Return', Status__c = 'Refund Initiated',
            Refund_Initiated_On__c = Date.today().addDays(-5)
        );
        insert r;

        Map<String, Object> out = DakiyaActionService.run(
            'refund_outcome', r.Id,
            new Map<String, Object>{ 'outcome' => 'Full to Original Payment', 'amount' => 1299 }
        );

        Assert.areEqual('Completed', (String) out.get('status'));
        Assert.areEqual(DakiyaConstants.ST_CLOSED, (String) out.get('purchaseStatus'),
            'Nothing else open, so the purchase closes');

        Vendor__c learned = [SELECT Typical_Refund_Days__c, Usual_Refund_Mode__c,
                                    Refund_History_Summary__c FROM Vendor__c WHERE Id = :v.Id];
        Assert.areEqual(5, learned.Typical_Refund_Days__c,
            'The vendor now knows refunds take about 5 days');
        Assert.areEqual('Original Payment', learned.Usual_Refund_Mode__c);
        Assert.isTrue(learned.Refund_History_Summary__c.contains('1 return'),
            'Human-readable history: ' + learned.Refund_History_Summary__c);
    }

    @IsTest
    static void notReceivedYetSchedulesAnotherCheckInsteadOfClosing() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_RETURN_IN_PROGRESS, 1299);
        Return__c r = new Return__c(
            Purchase__c = p.Id, Type__c = 'Return', Status__c = 'Refund Initiated',
            Refund_Initiated_On__c = Date.today().addDays(-8)
        );
        insert r;

        Map<String, Object> out = DakiyaActionService.run(
            'refund_outcome', r.Id, new Map<String, Object>{ 'outcome' => 'Not Received Yet' }
        );

        Return__c after = [SELECT Status__c, Refund_Check_Due__c, Reminder_Count__c
                           FROM Return__c WHERE Id = :r.Id];
        Assert.areEqual('Refund Check Due', after.Status__c, 'Still open');
        Assert.areEqual(Date.today().addDays(DakiyaSettings.refundRecheckDays()), after.Refund_Check_Due__c);
        Assert.areEqual(1, after.Reminder_Count__c);
        Assert.isFalse((Boolean) out.get('escalationSuggested'), 'One nudge is not yet escalation');
    }

    @IsTest
    static void escalationIsSuggestedAfterTooManyNudges() {
        Vendor__c v = DakiyaTestData.vendor('Insta Shop', 'Instagram');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_RETURN_IN_PROGRESS, 600);
        Return__c r = new Return__c(
            Purchase__c = p.Id, Type__c = 'Return', Status__c = 'Refund Check Due',
            Refund_Initiated_On__c = Date.today().addDays(-20),
            Reminder_Count__c = DakiyaSettings.maxRefundReminders() - 1
        );
        insert r;

        Map<String, Object> out = DakiyaActionService.run(
            'refund_outcome', r.Id, new Map<String, Object>{ 'outcome' => 'Not Received Yet' }
        );
        Assert.isTrue((Boolean) out.get('escalationSuggested'),
            'After the cap, offer escalation instead of nagging again');
    }

    @IsTest
    static void resolvingAReviewAsIgnoreChangesNoRecords() {
        Inbound_Message__c m = DakiyaTestData.message('Email', 'spam@nowhere.in', 'Sale! 50% off');
        m.Processing_Status__c = 'Needs Review';
        update m;

        DakiyaActionService.run('resolve_review', m.Id, new Map<String, Object>{ 'resolution' => 'ignore' });

        Assert.areEqual('Ignored',
            [SELECT Processing_Status__c FROM Inbound_Message__c WHERE Id = :m.Id].Processing_Status__c);
        Assert.areEqual(0, [SELECT COUNT() FROM Purchase__c], 'Ignoring creates nothing');
    }

    @IsTest
    static void resolvingAReviewOntoAPurchaseAppliesTheStoredExtraction() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_SHIPPED, 1299);
        Inbound_Message__c m = DakiyaTestData.message('Email', 'x@myntra.in', 'delivered');
        m.Processing_Status__c = 'Needs Review';
        m.Extraction_JSON__c = JSON.serialize(DakiyaTestData.extraction('delivered', null, null, null));
        update m;

        DakiyaActionService.run('resolve_review', m.Id,
            new Map<String, Object>{ 'resolution' => String.valueOf(p.Id) });

        Assert.areEqual(DakiyaConstants.ST_DELIVERED_UNCONF,
            [SELECT Status__c FROM Purchase__c WHERE Id = :p.Id].Status__c,
            'Once Gitanjali picks the order, the event applies');
    }

    @IsTest
    static void snoozePushesANotificationOut() {
        Notification__c n = new Notification__c(
            Type__c = 'Refund Check', Title__c = 'Check refund',
            Due_At__c = Datetime.now(), Status__c = 'Pending',
            Dedupe_Key__c = 'snooze-test-1'
        );
        insert n;

        DakiyaActionService.run('snooze', n.Id, new Map<String, Object>{ 'days' => 2 });

        Notification__c after = [SELECT Due_At__c, Status__c FROM Notification__c WHERE Id = :n.Id];
        Assert.isTrue(after.Due_At__c > Datetime.now().addDays(1), 'Pushed into the future');
        Assert.areEqual('Pending', after.Status__c, 'Still queued, just later');
    }

    @IsTest
    static void unknownActionIsRejected() {
        Vendor__c v = DakiyaTestData.vendor('X', 'Other');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_PLACED, 10);
        try {
            DakiyaActionService.run('delete_everything', p.Id, null);
            Assert.fail('Unknown actions must be refused');
        } catch (DakiyaActionService.ActionException e) {
            Assert.isTrue(e.getMessage().contains('Unknown action'), e.getMessage());
        }
    }

    @IsTest
    static void refundOutcomeRequiresAnOutcome() {
        Vendor__c v = DakiyaTestData.vendor('X', 'Other');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_RETURN_IN_PROGRESS, 10);
        Return__c r = new Return__c(Purchase__c = p.Id, Type__c = 'Return', Status__c = 'Refund Initiated');
        insert r;
        try {
            DakiyaActionService.run('refund_outcome', r.Id, new Map<String, Object>());
            Assert.fail('An outcome cannot be blank');
        } catch (DakiyaActionService.ActionException e) {
            Assert.isTrue(e.getMessage().contains('outcome'), e.getMessage());
        }
    }
}
