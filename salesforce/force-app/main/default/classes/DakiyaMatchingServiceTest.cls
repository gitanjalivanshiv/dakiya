/** The scoring ladder (BUILD_SPEC 5.4 step 4) and the things it refuses to match. */
@IsTest
private class DakiyaMatchingServiceTest {

    @IsTest
    static void amountAndCloseDateScoreZeroPointEight() {
        Vendor__c v = DakiyaTestData.vendor('Nykaa', 'Marketplace');
        Purchase__c a = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_PLACED, 1499);
        DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_PLACED, 250);   // decoy, wrong amount

        DakiyaExtraction ex = DakiyaTestData.extraction('shipped', null, null, 1499);
        ex.event_date = String.valueOf(a.Order_Date__c.addDays(1));

        DakiyaMatchingService.MatchResult r = DakiyaMatchingService.match(ex, v.Id);

        Assert.areEqual(a.Id, r.best.purchaseId, 'Matched on amount and a nearby date');
        Assert.areEqual(0.8, r.best.score);
    }

    @IsTest
    static void amountMatchIsRejectedWhenDatesAreFarApart() {
        Vendor__c v = DakiyaTestData.vendor('Nykaa', 'Marketplace');
        Purchase__c a = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_PLACED, 1499);
        DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_PLACED, 300);   // keeps it from being the lone order

        DakiyaExtraction ex = DakiyaTestData.extraction('shipped', null, null, 1499);
        ex.event_date = String.valueOf(a.Order_Date__c.addDays(40));

        DakiyaMatchingService.MatchResult r = DakiyaMatchingService.match(ex, v.Id);

        Assert.isNull(r.best, 'Same amount 40 days apart is a coincidence, not a match');
    }

    @IsTest
    static void itemNameOverlapBoostsButNeverReachesCertainty() {
        Vendor__c v = DakiyaTestData.vendor('Nykaa', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_PLACED, 1499);
        insert new Purchase_Item__c(Name = 'Vitamin C Serum', Purchase__c = p.Id, Quantity__c = 1, Status__c = 'Active');
        DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_PLACED, 999);

        DakiyaExtraction ex = DakiyaTestData.extraction('shipped', null, null, 1499);
        ex.event_date = String.valueOf(p.Order_Date__c);
        DakiyaExtraction.Item i = new DakiyaExtraction.Item();
        i.name = 'Vitamin C Serum';
        ex.items = new List<DakiyaExtraction.Item>{ i };

        DakiyaMatchingService.MatchResult r = DakiyaMatchingService.match(ex, v.Id);

        Assert.areEqual(p.Id, r.best.purchaseId);
        Assert.areEqual(0.95, r.best.score, 'Boosted, but capped below a certain match');
        Assert.isTrue(r.best.reason.contains('item names overlap'), r.best.reason);
    }

    @IsTest
    static void closedPurchasesAreNotCandidates() {
        Vendor__c v = DakiyaTestData.vendor('Amazon', 'Marketplace');
        Purchase__c closed = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_CLOSED, 500);

        DakiyaExtraction ex = DakiyaTestData.extraction('delivered', closed.External_Order_Id__c, null, null);
        DakiyaMatchingService.MatchResult r = DakiyaMatchingService.match(ex, v.Id);

        Assert.isNull(r.best, 'A settled order is not reopened by a stray event');
    }

    @IsTest
    static void cancelledPurchasesAreNotCandidates() {
        Vendor__c v = DakiyaTestData.vendor('Amazon', 'Marketplace');
        Purchase__c c = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_CANCELLED, 500);
        DakiyaExtraction ex = DakiyaTestData.extraction('shipped', c.External_Order_Id__c, null, null);
        Assert.isNull(DakiyaMatchingService.match(ex, v.Id).best);
    }

    @IsTest
    static void awbFromAnotherVendorStillMatchesThatParcel() {
        // Courier SMS rarely names the seller, so the AWB must work without a vendor.
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Purchase__c p = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_SHIPPED, 1299);
        DakiyaTestData.shipment(p.Id, 'EK00918273', 'Shipped');

        DakiyaExtraction ex = DakiyaTestData.extraction('out_for_delivery', null, 'EK00918273', null);
        DakiyaMatchingService.MatchResult r = DakiyaMatchingService.match(ex, null);

        Assert.areEqual(p.Id, r.best.purchaseId, 'A courier SMS with only an AWB still lands correctly');
        Assert.areEqual(1.0, r.best.score);
    }

    @IsTest
    static void twoOpenOrdersForOneVendorGiveNoLoneMatch() {
        Vendor__c v = DakiyaTestData.vendor('Nykaa', 'Marketplace');
        DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_PLACED, 100);
        DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_PLACED, 200);

        DakiyaExtraction ex = DakiyaTestData.extraction('shipped', null, null, null);
        DakiyaMatchingService.MatchResult r = DakiyaMatchingService.match(ex, v.Id);

        Assert.isNull(r.best, 'With two candidates and no distinguishing detail, it must ask');
    }

    @IsTest
    static void nullExtractionIsHandled() {
        DakiyaMatchingService.MatchResult r = DakiyaMatchingService.match(null, null);
        Assert.isNull(r.best);
        Assert.isFalse(r.shouldCreateNew);
        Assert.areEqual(0, r.bestScore());
    }

    @IsTest
    static void candidatesAreSortedBestFirst() {
        Vendor__c v = DakiyaTestData.vendor('Myntra', 'Marketplace');
        Purchase__c exact = DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_SHIPPED, 1299);
        DakiyaTestData.shipment(exact.Id, 'AWB-SORT', 'Shipped');
        DakiyaTestData.purchase(v.Id, DakiyaConstants.ST_PLACED, 1299);

        DakiyaExtraction ex = DakiyaTestData.extraction('delivered', null, 'AWB-SORT', 1299);
        ex.event_date = String.valueOf(Date.today());
        DakiyaMatchingService.MatchResult r = DakiyaMatchingService.match(ex, v.Id);

        Assert.isTrue(r.candidates.size() >= 2, 'Both are candidates');
        Assert.areEqual(exact.Id, r.candidates[0].purchaseId, 'The AWB match sorts first');
        Assert.isTrue(r.candidates[0].score >= r.candidates[1].score, 'Sorted descending');
    }
}
