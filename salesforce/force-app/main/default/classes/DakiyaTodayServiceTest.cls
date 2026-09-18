/** Every Today bucket, and the thresholds that decide what lands in each. */
@IsTest
private class DakiyaTodayServiceTest {

    @IsTest
    static void arrivingTodayPicksUpExpectedDeliveries() {
        Vendor__c v = DakiyaTestData.vendor('Amazon', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_OUT_FOR_DELIVERY, 999);
        p.Expected_Delivery__c = DakiyaApi.todayIst();
        update p;

        List<Object> rows = (List<Object>) DakiyaTodayService.build().get('arrivingToday');
        Assert.areEqual(1, rows.size(), 'An order due today shows up');
    }

    @IsTest
    static void awaitingConfirmationWaitsForTheReminderDelay() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_DELIVERED_UNCONF, 1299);

        // Delivered a minute ago: too soon to nag.
        Shipment__c fresh = DakiyaTestData.shipment(p.Id, 'AWB-FRESH', 'Delivered');
        update new Shipment__c(Id = fresh.Id, Delivered_At__c = Datetime.now().addMinutes(-1));

        List<Object> none = (List<Object>) DakiyaTodayService.build().get('awaitingConfirmation');
        Assert.areEqual(0, none.size(), 'A just-delivered parcel is not chased immediately');

        update new Shipment__c(
            Id = fresh.Id,
            Delivered_At__c = Datetime.now().addHours(-DakiyaSettings.confirmReminderHours() - 1)
        );

        List<Object> now = (List<Object>) DakiyaTodayService.build().get('awaitingConfirmation');
        Assert.areEqual(1, now.size(), 'Past the delay, it needs confirming');
    }

    @IsTest
    static void stalledUsesTheInstagramThresholdForInstagramSellers() {
        Vendor__c insta = DakiyaTestData.vendor('@soap_shop', 'Instagram');
        Purchase__c p = DakiyaTestData.purchase(insta.Id, DakiyaConstants.ST_PLACED, 450);
        p.Last_Event_At__c = Datetime.now().addDays(-DakiyaSettings.instagramFollowUpDays() - 1);
        update p;

        List<Object> rows = (List<Object>) DakiyaTodayService.build().get('stalled');
        Assert.areEqual(1, rows.size(), 'A quiet Instagram seller is chased on the shorter clock');
        Map<String, Object> row = (Map<String, Object>) rows[0];
        Assert.areEqual('Ordered but never shipped', (String) row.get('reason'));
    }

    @IsTest
    static void aVendorOverrideBeatsTheDefaultStallThreshold() {
        Vendor__c v = DakiyaTestData.vendor('SlowShop', 'D2C Website');
        v.Follow_Up_After_Days__c = 30;
        update v;
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_PLACED, 100);
        p.Last_Event_At__c = Datetime.now().addDays(-10);
        update p;

        List<Object> rows = (List<Object>) DakiyaTodayService.build().get('stalled');
        Assert.areEqual(0, rows.size(),
            'A vendor known to be slow is not flagged at the default threshold');
    }

    @IsTest
    static void recentlyActiveOrdersAreNotStalled() {
        Vendor__c v = DakiyaTestData.vendor('Amazon', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_SHIPPED, 100);
        p.Last_Event_At__c = Datetime.now().addHours(-2);
        update p;

        Assert.areEqual(0, ((List<Object>) DakiyaTodayService.build().get('stalled')).size());
    }

    @IsTest
    static void refundChecksDueSurfacesVendorHabits() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        v.Usual_Refund_Mode__c = 'Store Credit';
        v.Refund_History_Summary__c = '2 returns: 2 store credit';
        update v;
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_RETURN_IN_PROGRESS, 1299);
        insert new Return__c(
            Purchase__c = p.Id, Type__c = 'Return', Status__c = 'Refund Initiated',
            Refund_Initiated_On__c = Date.today().addDays(-8),
            Refund_Check_Due__c = Date.today().addDays(-1)
        );

        List<Object> rows = (List<Object>) DakiyaTodayService.build().get('refundChecksDue');
        Assert.areEqual(1, rows.size());
        Map<String, Object> row = (Map<String, Object>) rows[0];
        Assert.areEqual('Store Credit', (String) row.get('vendorUsualMode'),
            'The reminder carries what this vendor usually does, so the question is informed');
        Assert.areEqual('2 returns: 2 store credit', (String) row.get('vendorHistory'));
    }

    @IsTest
    static void refundChecksNotYetDueAreQuiet() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_RETURN_IN_PROGRESS, 1299);
        insert new Return__c(
            Purchase__c = p.Id, Type__c = 'Return', Status__c = 'Refund Initiated',
            Refund_Initiated_On__c = Date.today(),
            Refund_Check_Due__c = Date.today().addDays(7)
        );
        Assert.areEqual(0, ((List<Object>) DakiyaTodayService.build().get('refundChecksDue')).size());
    }

    @IsTest
    static void returnWindowsClosingWarnsInsideTheWindow() {
        Vendor__c v = DakiyaTestData.vendor('Nykaa', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_RECEIVED, 700);
        p.Return_Window_Ends__c = Date.today().addDays(1);
        update p;

        List<Object> rows = (List<Object>) DakiyaTodayService.build().get('returnWindowsClosing');
        Assert.areEqual(1, rows.size(), 'A window closing tomorrow is worth a warning');
        Assert.areEqual(1, (Integer) ((Map<String, Object>) rows[0]).get('daysLeft'));
    }

    @IsTest
    static void returnWindowsFarOffAreQuiet() {
        Vendor__c v = DakiyaTestData.vendor('Nykaa', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_RECEIVED, 700);
        p.Return_Window_Ends__c = Date.today().addDays(20);
        update p;
        Assert.areEqual(0, ((List<Object>) DakiyaTodayService.build().get('returnWindowsClosing')).size());
    }

    @IsTest
    static void reviewItemsListsWhatNeedsAnswering() {
        Inbound_Message__c m = DakiyaTestData.message('SMS', 'VM-UNKNOWN', 'Parcel out for delivery');
        m.Processing_Status__c = 'Needs Review';
        m.Confidence__c = 55;
        update m;

        List<Object> rows = (List<Object>) DakiyaTodayService.build().get('reviewItems');
        Assert.areEqual(1, rows.size());
        Assert.areEqual('SMS', (String) ((Map<String, Object>) rows[0]).get('channel'));
    }

    @IsTest
    static void emptyOrgReturnsEmptyBucketsNotNulls() {
        Map<String, Object> today = DakiyaTodayService.build();
        for (String key : today.keySet()) {
            Assert.isNotNull(today.get(key), key + ' must be an empty list, never null');
            Assert.areEqual(0, ((List<Object>) today.get(key)).size());
        }
    }

    @IsTest
    static void settingsOverridesAreHonoured() {
        DakiyaSettings.setOverride('StallShippedDays', '99');
        Assert.areEqual(99, DakiyaSettings.stallShippedDays(), 'Overrides drive behaviour');
        DakiyaSettings.setOverride('AutoApplyConfidence', 'not-a-number');
        Assert.areEqual(0.90, DakiyaSettings.getDecimal('AutoApplyConfidence', 0.90),
            'An unparseable value falls back rather than throwing mid-Queueable');
        DakiyaSettings.setOverride('Extractor', '  WorkerHaiku  ');
        Assert.areEqual('WorkerHaiku', DakiyaSettings.extractor(), 'Values are trimmed');
        Assert.areEqual(4, DakiyaSettings.confirmReminderHours());
        Assert.areEqual(24, DakiyaSettings.confirmFlagHours());
        Assert.areEqual(7, DakiyaSettings.stallPlacedDays());
        Assert.areEqual(3, DakiyaSettings.maxRefundReminders());
        Assert.areEqual(8, DakiyaSettings.morningDigestHourIST());
        Assert.areEqual(2, DakiyaSettings.returnWindowWarnDays());
        Assert.areEqual(0.60, DakiyaSettings.reviewConfidence());
        Assert.areEqual(7, DakiyaSettings.defaultRefundCheckDays());
    }
}
