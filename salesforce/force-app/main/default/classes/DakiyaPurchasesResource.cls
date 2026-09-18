/**
 * GET  /dakiya/v1/purchases?status=&vendor=&q=&limit=&offset=   list
 * GET  /dakiya/v1/purchases/{id}                                detail with timeline
 * POST /dakiya/v1/purchases                                     manual create
 */
@RestResource(urlMapping='/dakiya/v1/purchases/*')
global with sharing class DakiyaPurchasesResource {

    @HttpGet
    global static void doGet() {
        RestRequest req = RestContext.request;
        RestResponse res = RestContext.response;
        try {
            String id = DakiyaApi.pathTail(req.requestURI, '/dakiya/v1/purchases');
            if (String.isNotBlank(id)) {
                DakiyaApi.ok(res, detail((Id) id));
                return;
            }
            DakiyaApi.ok(res, listPurchases(req));
        } catch (Exception e) {
            DakiyaApi.fail(res, 500, 'PURCHASES_FAILED', e.getMessage());
        }
    }

    @HttpPost
    global static void doPost() {
        RestResponse res = RestContext.response;
        try {
            Map<String, Object> body = (Map<String, Object>) JSON.deserializeUntyped(
                RestContext.request.requestBody.toString()
            );
            String vendorName = (String) body.get('vendorName');
            if (String.isBlank(vendorName)) {
                DakiyaApi.fail(res, 400, 'BAD_REQUEST', 'vendorName is required');
                return;
            }

            Vendor__c v = DakiyaParserRegistry.findByName(vendorName);
            if (v == null) {
                v = new Vendor__c(
                    Name = vendorName,
                    Channel__c = (String) (body.get('channel') == null ? 'Other' : body.get('channel')),
                    Instagram_Handle__c = (String) body.get('instagramHandle')
                );
                insert v;
            }

            DakiyaExtraction ex = new DakiyaExtraction();
            ex.is_commerce = true;
            ex.vendor_name = vendorName;
            ex.event_type = DakiyaConstants.EV_ORDER_PLACED;
            ex.order_id = (String) body.get('orderId');
            ex.event_date = (String) body.get('orderDate');
            if (body.get('amount') != null) {
                ex.amount = Decimal.valueOf(String.valueOf(body.get('amount')));
            }
            ex.items = itemsFrom(body.get('items'));

            Purchase__c p = DakiyaEventApplier.createPurchase(ex, v.Id, 'Manual');
            if (body.get('title') != null) {
                p.Title__c = (String) body.get('title');
            }
            if (body.get('paymentMethod') != null) {
                p.Payment_Method__c = (String) body.get('paymentMethod');
            }
            update p;

            Id newId = p.Id;
            DakiyaApi.ok(res, DakiyaApi.purchaseSummary(Database.query(
                'SELECT ' + DakiyaApi.PURCHASE_FIELDS + ' FROM Purchase__c WHERE Id = :newId LIMIT 1'
            )));
        } catch (Exception e) {
            DakiyaApi.fail(res, 500, 'CREATE_FAILED', e.getMessage());
        }
    }

    private static List<DakiyaExtraction.Item> itemsFrom(Object raw) {
        List<DakiyaExtraction.Item> out = new List<DakiyaExtraction.Item>();
        if (!(raw instanceof List<Object>)) {
            return out;
        }
        for (Object o : (List<Object>) raw) {
            Map<String, Object> m = (Map<String, Object>) o;
            DakiyaExtraction.Item i = new DakiyaExtraction.Item();
            i.name = (String) m.get('name');
            i.qty = m.get('qty') == null ? 1 : Integer.valueOf(String.valueOf(m.get('qty')));
            if (m.get('price') != null) {
                i.price = Decimal.valueOf(String.valueOf(m.get('price')));
            }
            out.add(i);
        }
        return out;
    }

    private static Map<String, Object> listPurchases(RestRequest req) {
        Map<String, String> q = req.params;
        Integer lim = Math.min(DakiyaApi.intParam(q.get('limit'), 50), 200);
        Integer off = DakiyaApi.intParam(q.get('offset'), 0);

        String soql = 'SELECT ' + DakiyaApi.PURCHASE_FIELDS + ' FROM Purchase__c';
        List<String> wheres = new List<String>();
        String status = q.get('status');
        String vendor = q.get('vendor');
        String text = q.get('q');

        if (String.isNotBlank(status)) { wheres.add('Status__c = :status'); }
        if (String.isNotBlank(vendor)) { wheres.add('Vendor__r.Name = :vendor'); }
        if (String.isNotBlank(text)) {
            text = '%' + String.escapeSingleQuotes(text) + '%';
            wheres.add('(Title__c LIKE :text OR External_Order_Id__c LIKE :text)');
        }
        if (!wheres.isEmpty()) {
            soql += ' WHERE ' + String.join(wheres, ' AND ');
        }
        soql += ' ORDER BY CreatedDate DESC LIMIT :lim OFFSET :off';

        List<Map<String, Object>> rows = new List<Map<String, Object>>();
        for (Purchase__c p : Database.query(soql)) {
            rows.add(DakiyaApi.purchaseSummary(p));
        }
        return new Map<String, Object>{ 'purchases' => rows, 'limit' => lim, 'offset' => off };
    }

    private static Map<String, Object> detail(Id purchaseId) {
        Purchase__c p = Database.query(
            'SELECT ' + DakiyaApi.PURCHASE_FIELDS +
            ' FROM Purchase__c WHERE Id = :purchaseId LIMIT 1'
        );
        Map<String, Object> out = DakiyaApi.purchaseSummary(p);
        out.put('notes', p.Notes__c);
        out.put('paymentMethod', p.Payment_Method__c);
        out.put('source', p.Source__c);

        List<Map<String, Object>> items = new List<Map<String, Object>>();
        for (Purchase_Item__c i : [
            SELECT Id, Name, Quantity__c, Price__c, Status__c
            FROM Purchase_Item__c WHERE Purchase__c = :purchaseId LIMIT 100
        ]) {
            items.add(new Map<String, Object>{
                'id' => i.Id, 'name' => i.Name, 'qty' => i.Quantity__c,
                'price' => i.Price__c, 'status' => i.Status__c
            });
        }
        out.put('items', items);

        List<Map<String, Object>> shipments = new List<Map<String, Object>>();
        for (Shipment__c s : [
            SELECT Id, Courier__c, AWB__c, Tracking_URL__c, Status__c, Delivered_At__c,
                   Confirmation__c, Confirmed_At__c
            FROM Shipment__c WHERE Purchase__c = :purchaseId LIMIT 50
        ]) {
            shipments.add(new Map<String, Object>{
                'id' => s.Id, 'courier' => s.Courier__c, 'awb' => s.AWB__c,
                'trackingUrl' => s.Tracking_URL__c, 'status' => s.Status__c,
                'deliveredAt' => s.Delivered_At__c, 'confirmation' => s.Confirmation__c,
                'confirmedAt' => s.Confirmed_At__c
            });
        }
        out.put('shipments', shipments);

        List<Map<String, Object>> events = new List<Map<String, Object>>();
        for (Tracking_Event__c e : [
            SELECT Id, Event_Type__c, Event_At__c, Summary__c, Applied_By__c
            FROM Tracking_Event__c WHERE Purchase__c = :purchaseId
            ORDER BY Event_At__c DESC LIMIT 100
        ]) {
            events.add(new Map<String, Object>{
                'id' => e.Id, 'type' => e.Event_Type__c, 'at' => e.Event_At__c,
                'summary' => e.Summary__c, 'appliedBy' => e.Applied_By__c
            });
        }
        out.put('events', events);

        List<Map<String, Object>> returns = new List<Map<String, Object>>();
        for (Return__c r : [
            SELECT Id, Type__c, Status__c, Reason__c, Requested_On__c, Refund_Initiated_On__c,
                   Refund_Check_Due__c, Refund_Outcome__c, Refund_Received_Amount__c,
                   Expected_Refund_Amount__c
            FROM Return__c WHERE Purchase__c = :purchaseId LIMIT 50
        ]) {
            returns.add(new Map<String, Object>{
                'id' => r.Id, 'type' => r.Type__c, 'status' => r.Status__c,
                'reason' => r.Reason__c, 'requestedOn' => r.Requested_On__c,
                'refundInitiatedOn' => r.Refund_Initiated_On__c,
                'refundCheckDue' => r.Refund_Check_Due__c,
                'outcome' => r.Refund_Outcome__c,
                'refundReceived' => r.Refund_Received_Amount__c,
                'expectedRefund' => r.Expected_Refund_Amount__c
            });
        }
        out.put('returns', returns);
        return out;
    }
}
