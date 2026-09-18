/** The endpoints the Worker will call (BUILD_SPEC 8). */
@IsTest
private class DakiyaRestTest {

    private static RestRequest req;
    private static RestResponse res;

    private static void setup(String method, String uri, String body) {
        req = new RestRequest();
        res = new RestResponse();
        req.httpMethod = method;
        req.requestURI = uri;
        if (body != null) {
            req.requestBody = Blob.valueOf(body);
        }
        RestContext.request = req;
        RestContext.response = res;
    }

    private static Map<String, Object> parsed() {
        return (Map<String, Object>) JSON.deserializeUntyped(res.responseBody.toString());
    }

    @IsTest
    static void ingestReturnsIdAndDuplicateFlag() {
        setup('POST', '/services/apexrest/dakiya/v1/ingest', JSON.serialize(new Map<String, Object>{
            'channel' => 'Email', 'sender' => 'a@myntra.in', 'subject' => 'Shipped',
            'bodyMasked' => 'Your order shipped', 'dedupeKey' => 'rest-1'
        }));
        Test.startTest();
        DakiyaIngestResource.doPost();
        Test.stopTest();

        Assert.areEqual(200, res.statusCode);
        Assert.isFalse((Boolean) parsed().get('duplicate'));
        Assert.isNotNull(parsed().get('id'));
    }

    @IsTest
    static void ingestRejectsBadPayloadWithTheErrorEnvelope() {
        setup('POST', '/services/apexrest/dakiya/v1/ingest',
              JSON.serialize(new Map<String, Object>{ 'channel' => 'Email' }));
        DakiyaIngestResource.doPost();

        Assert.areEqual(400, res.statusCode);
        Map<String, Object> err = (Map<String, Object>) parsed().get('error');
        Assert.areEqual('BAD_REQUEST', (String) err.get('code'), 'Errors use the shared envelope');
    }

    @IsTest
    static void todayReturnsEveryBucket() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_DELIVERED_UNCONF, 1299);
        DakiyaTestData.shipment(p.Id, 'AWB-T1', 'Delivered');

        setup('GET', '/services/apexrest/dakiya/v1/today', null);
        Test.startTest();
        DakiyaTodayResource.doGet();
        Test.stopTest();

        Map<String, Object> body = parsed();
        for (String key : new List<String>{
            'arrivingToday', 'awaitingConfirmation', 'stalled',
            'refundChecksDue', 'returnWindowsClosing', 'reviewItems'
        }) {
            Assert.isTrue(body.containsKey(key), 'Today must always include ' + key);
        }
        Assert.areEqual(1, ((List<Object>) body.get('awaitingConfirmation')).size(),
            'The delivered-but-unconfirmed parcel shows up');
    }

    @IsTest
    static void purchasesListAndDetail() {
        Vendor__c v = DakiyaTestData.vendor('Nykaa', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_SHIPPED, 799);
        DakiyaTestData.shipment(p.Id, 'AWB-D1', 'Shipped');

        setup('GET', '/services/apexrest/dakiya/v1/purchases', null);
        DakiyaPurchasesResource.doGet();
        Assert.areEqual(1, ((List<Object>) parsed().get('purchases')).size());

        setup('GET', '/services/apexrest/dakiya/v1/purchases/' + p.Id, null);
        DakiyaPurchasesResource.doGet();
        Map<String, Object> detail = parsed();
        Assert.areEqual('Nykaa', (String) detail.get('vendor'));
        Assert.areEqual(1, ((List<Object>) detail.get('shipments')).size(), 'Detail includes shipments');
        Assert.isTrue(detail.containsKey('events'), 'Detail includes the timeline');
        Assert.isTrue(detail.containsKey('returns'), 'Detail includes returns');
    }

    @IsTest
    static void purchasesListFiltersByStatus() {
        Vendor__c v = DakiyaTestData.vendor('Nykaa', 'Marketplace');
        DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_SHIPPED, 100);
        DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_PLACED, 200);

        setup('GET', '/services/apexrest/dakiya/v1/purchases', null);
        req.params.put('status', DakiyaConstants.ST_SHIPPED);
        DakiyaPurchasesResource.doGet();

        Assert.areEqual(1, ((List<Object>) parsed().get('purchases')).size(),
            'Only the shipped one comes back');
    }

    @IsTest
    static void manualCreateMakesTheVendorIfItIsNew() {
        setup('POST', '/services/apexrest/dakiya/v1/purchases', JSON.serialize(new Map<String, Object>{
            'vendorName' => '@handmade_soaps', 'channel' => 'Instagram',
            'title' => 'Two soaps', 'amount' => 450, 'orderDate' => String.valueOf(Date.today()),
            'items' => new List<Object>{ new Map<String, Object>{ 'name' => 'Lavender soap', 'qty' => 2 } }
        }));
        Test.startTest();
        DakiyaPurchasesResource.doPost();
        Test.stopTest();

        Assert.areEqual(200, res.statusCode, res.responseBody.toString());
        Assert.areEqual(1, [SELECT COUNT() FROM Vendor__c WHERE Name = '@handmade_soaps'],
            'An Instagram seller is created on first order');
        Assert.areEqual(1, [SELECT COUNT() FROM Purchase_Item__c], 'Items are stored');
    }

    @IsTest
    static void actionsEndpointConfirmsDelivery() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_DELIVERED_UNCONF, 1299);
        Shipment__c s = DakiyaTestData.shipment(p.Id, 'AWB-A1', 'Delivered');

        setup('POST', '/services/apexrest/dakiya/v1/actions', JSON.serialize(new Map<String, Object>{
            'action' => 'confirm_received', 'recordId' => s.Id
        }));
        Test.startTest();
        DakiyaActionsResource.doPost();
        Test.stopTest();

        Assert.areEqual(200, res.statusCode, res.responseBody.toString());
        Assert.areEqual(DakiyaConstants.ST_RECEIVED, (String) parsed().get('status'));
    }

    @IsTest
    static void actionsEndpointNeedsARecordId() {
        setup('POST', '/services/apexrest/dakiya/v1/actions',
              JSON.serialize(new Map<String, Object>{ 'action' => 'confirm_received' }));
        DakiyaActionsResource.doPost();
        Assert.areEqual(400, res.statusCode);
    }

    @IsTest
    static void returnsEndpointListsOpenOnesByDefault() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_RETURN_IN_PROGRESS, 1299);
        insert new Return__c(Purchase__c = p.Id, Type__c = 'Return', Status__c = 'Refund Initiated');
        insert new Return__c(Purchase__c = p.Id, Type__c = 'Return', Status__c = 'Completed');

        setup('GET', '/services/apexrest/dakiya/v1/returns', null);
        DakiyaReturnsResource.doGet();

        Assert.areEqual(1, ((List<Object>) parsed().get('returns')).size(),
            'Completed returns are excluded unless asked for');
    }

    @IsTest
    static void vendorsEndpointExposesLearnedStats() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        v.Typical_Refund_Days__c = 6;
        v.Usual_Refund_Mode__c = 'Store Credit';
        update v;

        setup('GET', '/services/apexrest/dakiya/v1/vendors', null);
        DakiyaVendorsResource.doGet();

        List<Object> rows = (List<Object>) parsed().get('vendors');
        Map<String, Object> row = (Map<String, Object>) rows[0];
        Assert.areEqual(6, (Integer) row.get('typicalRefundDays'));
        Assert.areEqual('Store Credit', (String) row.get('usualRefundMode'));
    }

    @IsTest
    static void notificationsDueAndResultRoundTrip() {
        Notification__c n = new Notification__c(
            Type__c = 'Confirm Delivery', Title__c = 'Got the parcel?',
            Due_At__c = Datetime.now().addMinutes(-5), Status__c = 'Pending',
            Dedupe_Key__c = 'rest-notif-1'
        );
        insert n;

        setup('GET', '/services/apexrest/dakiya/v1/notifications/due', null);
        DakiyaNotificationsResource.doGet();
        Assert.areEqual(1, ((List<Object>) parsed().get('notifications')).size(),
            'A due notification is offered to the Worker');

        setup('POST', '/services/apexrest/dakiya/v1/notifications/' + n.Id + '/result',
              JSON.serialize(new Map<String, Object>{ 'status' => 'Sent' }));
        DakiyaNotificationsResource.doPost();

        Notification__c after = [SELECT Status__c, Sent_At__c FROM Notification__c WHERE Id = :n.Id];
        Assert.areEqual('Sent', after.Status__c);
        Assert.isNotNull(after.Sent_At__c);
    }

    @IsTest
    static void notificationFailureIsRecordedWithItsError() {
        Notification__c n = new Notification__c(
            Type__c = 'System', Title__c = 'x', Due_At__c = Datetime.now(),
            Status__c = 'Pending', Dedupe_Key__c = 'rest-notif-2'
        );
        insert n;

        setup('POST', '/services/apexrest/dakiya/v1/notifications/' + n.Id + '/result',
              JSON.serialize(new Map<String, Object>{ 'status' => 'Failed', 'error' => 'push subscription gone' }));
        DakiyaNotificationsResource.doPost();

        Notification__c after = [SELECT Status__c, Error__c FROM Notification__c WHERE Id = :n.Id];
        Assert.areEqual('Failed', after.Status__c);
        Assert.areEqual('push subscription gone', after.Error__c);
    }

    @IsTest
    static void notificationsRejectsAnUnknownStatus() {
        Notification__c n = new Notification__c(
            Type__c = 'System', Title__c = 'x', Due_At__c = Datetime.now(),
            Status__c = 'Pending', Dedupe_Key__c = 'rest-notif-3'
        );
        insert n;
        setup('POST', '/services/apexrest/dakiya/v1/notifications/' + n.Id + '/result',
              JSON.serialize(new Map<String, Object>{ 'status' => 'Maybe' }));
        DakiyaNotificationsResource.doPost();
        Assert.areEqual(400, res.statusCode);
    }

    @IsTest
    static void notificationsRejectsAnUnknownPath() {
        setup('GET', '/services/apexrest/dakiya/v1/notifications/everything', null);
        DakiyaNotificationsResource.doGet();
        Assert.areEqual(404, res.statusCode);
    }

    @IsTest
    static void healthReportsCounts() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_PLACED, 100);

        setup('GET', '/services/apexrest/dakiya/v1/health', null);
        DakiyaHealthResource.doGet();

        Map<String, Object> body = parsed();
        Assert.isTrue((Boolean) body.get('ok'));
        Map<String, Object> counts = (Map<String, Object>) body.get('counts');
        Assert.areEqual(1, (Integer) counts.get('purchases'));
        Assert.areEqual(0, (Integer) counts.get('reviewQueue'));
    }

    @IsTest
    static void pathTailHandlesTrailingSlashesAndMisses() {
        Assert.areEqual('abc', DakiyaApi.pathTail('/dakiya/v1/purchases/abc/', '/dakiya/v1/purchases'));
        Assert.isNull(DakiyaApi.pathTail('/dakiya/v1/purchases', '/dakiya/v1/purchases'));
        Assert.isNull(DakiyaApi.pathTail(null, '/dakiya/v1/purchases'));
        Assert.areEqual(5, DakiyaApi.intParam('abc', 5), 'Unparseable numbers fall back');
        Assert.areEqual(9, DakiyaApi.intParam('9', 5));
    }
}
