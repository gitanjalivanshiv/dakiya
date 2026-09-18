/**
 * Builds the Today screen (BUILD_SPEC 8, GET /today).
 *
 * Shared by the REST endpoint and the agent's "what's pending?" action, so the
 * app and the conversation can never disagree about what needs attention.
 */
public with sharing class DakiyaTodayService {

    public static Map<String, Object> build() {
        Date today = DakiyaApi.todayIst();

        return new Map<String, Object>{
            'arrivingToday' => arrivingToday(today),
            'awaitingConfirmation' => awaitingConfirmation(),
            'stalled' => stalled(),
            'refundChecksDue' => refundChecksDue(today),
            'returnWindowsClosing' => returnWindowsClosing(today),
            'reviewItems' => reviewItems()
        };
    }

    private static List<Map<String, Object>> arrivingToday(Date today) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Purchase__c p : Database.query(
            'SELECT ' + DakiyaApi.PURCHASE_FIELDS + ' FROM Purchase__c ' +
            'WHERE Expected_Delivery__c = :today ' +
            'AND Status__c IN (\'Shipped\', \'Out for Delivery\', \'Confirmed\', \'Partially Shipped\') ' +
            'ORDER BY Expected_Delivery__c LIMIT 50'
        )) {
            out.add(DakiyaApi.purchaseSummary(p));
        }
        return out;
    }

    /** Courier says delivered, Gitanjali has not said so. The core of the product. */
    private static List<Map<String, Object>> awaitingConfirmation() {
        Datetime cutoff = Datetime.now().addHours(-DakiyaSettings.confirmReminderHours());
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Shipment__c s : [
            SELECT Id, Courier__c, AWB__c, Delivered_At__c, Confirmation_Reminders__c,
                   Purchase__c, Purchase__r.Title__c, Purchase__r.Vendor__r.Name,
                   Purchase__r.Status__c
            FROM Shipment__c
            WHERE Confirmation__c = 'Pending'
              AND Status__c = 'Delivered'
              AND Delivered_At__c <= :cutoff
            ORDER BY Delivered_At__c
            LIMIT 50
        ]) {
            out.add(new Map<String, Object>{
                'shipmentId' => s.Id,
                'purchaseId' => s.Purchase__c,
                'title' => s.Purchase__r.Title__c,
                'vendor' => s.Purchase__r.Vendor__r == null ? null : s.Purchase__r.Vendor__r.Name,
                'courier' => s.Courier__c,
                'awb' => s.AWB__c,
                'deliveredAt' => s.Delivered_At__c,
                'remindersSent' => s.Confirmation_Reminders__c
            });
        }
        return out;
    }

    /**
     * Shipped but silent, or placed and never shipped. Instagram sellers get a
     * shorter leash because they go quiet more often.
     */
    private static List<Map<String, Object>> stalled() {
        Datetime shippedCutoff = Datetime.now().addDays(-DakiyaSettings.stallShippedDays());
        Datetime placedCutoff = Datetime.now().addDays(-DakiyaSettings.stallPlacedDays());
        Datetime instaCutoff = Datetime.now().addDays(-DakiyaSettings.instagramFollowUpDays());

        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Purchase__c p : Database.query(
            'SELECT ' + DakiyaApi.PURCHASE_FIELDS + ', Vendor__r.Channel__c, Vendor__r.Follow_Up_After_Days__c ' +
            'FROM Purchase__c ' +
            'WHERE Status__c IN (\'Placed\', \'Confirmed\', \'Shipped\', \'Out for Delivery\', \'Partially Shipped\') ' +
            'ORDER BY Last_Event_At__c NULLS FIRST LIMIT 200'
        )) {
            Datetime last = p.Last_Event_At__c == null ? p.CreatedDate : p.Last_Event_At__c;
            Boolean shipped = p.Status__c == DakiyaConstants.ST_SHIPPED
                || p.Status__c == DakiyaConstants.ST_OUT_FOR_DELIVERY
                || p.Status__c == DakiyaConstants.ST_PARTIALLY_SHIPPED;

            Datetime cutoff;
            if (p.Vendor__r != null && p.Vendor__r.Follow_Up_After_Days__c != null) {
                cutoff = Datetime.now().addDays(-Integer.valueOf(p.Vendor__r.Follow_Up_After_Days__c));
            } else if (p.Vendor__r != null && p.Vendor__r.Channel__c == 'Instagram') {
                cutoff = instaCutoff;
            } else {
                cutoff = shipped ? shippedCutoff : placedCutoff;
            }

            if (last != null && last <= cutoff) {
                Map<String, Object> row = DakiyaApi.purchaseSummary(p);
                row.put('silentSince', last);
                row.put('reason', shipped ? 'Shipped but no update' : 'Ordered but never shipped');
                out.add(row);
            }
            if (out.size() >= 50) {
                break;
            }
        }
        return out;
    }

    private static List<Map<String, Object>> refundChecksDue(Date today) {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Return__c r : [
            SELECT Id, Status__c, Refund_Initiated_On__c, Refund_Check_Due__c,
                   Expected_Refund_Amount__c, Reminder_Count__c,
                   Purchase__c, Purchase__r.Title__c, Purchase__r.Vendor__r.Name,
                   Purchase__r.Vendor__r.Usual_Refund_Mode__c,
                   Purchase__r.Vendor__r.Refund_History_Summary__c
            FROM Return__c
            WHERE Refund_Check_Due__c <= :today
              AND Status__c IN ('Refund Initiated', 'Refund Check Due')
            ORDER BY Refund_Check_Due__c
            LIMIT 50
        ]) {
            out.add(new Map<String, Object>{
                'returnId' => r.Id,
                'purchaseId' => r.Purchase__c,
                'title' => r.Purchase__r.Title__c,
                'vendor' => r.Purchase__r.Vendor__r == null ? null : r.Purchase__r.Vendor__r.Name,
                'refundInitiatedOn' => r.Refund_Initiated_On__c,
                'checkDue' => r.Refund_Check_Due__c,
                'expectedAmount' => r.Expected_Refund_Amount__c,
                'remindersSent' => r.Reminder_Count__c,
                'vendorUsualMode' => r.Purchase__r.Vendor__r == null ? null : r.Purchase__r.Vendor__r.Usual_Refund_Mode__c,
                'vendorHistory' => r.Purchase__r.Vendor__r == null ? null : r.Purchase__r.Vendor__r.Refund_History_Summary__c
            });
        }
        return out;
    }

    private static List<Map<String, Object>> returnWindowsClosing(Date today) {
        Date warnBy = today.addDays(DakiyaSettings.returnWindowWarnDays());
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Purchase__c p : Database.query(
            'SELECT ' + DakiyaApi.PURCHASE_FIELDS + ' FROM Purchase__c ' +
            'WHERE Return_Window_Ends__c != null AND Return_Window_Ends__c <= :warnBy ' +
            'AND Return_Window_Ends__c >= :today ' +
            'AND Status__c IN (\'Delivered (Unconfirmed)\', \'Received\') ' +
            'ORDER BY Return_Window_Ends__c LIMIT 50'
        )) {
            Map<String, Object> row = DakiyaApi.purchaseSummary(p);
            row.put('daysLeft', today.daysBetween(p.Return_Window_Ends__c));
            out.add(row);
        }
        return out;
    }

    private static List<Map<String, Object>> reviewItems() {
        List<Map<String, Object>> out = new List<Map<String, Object>>();
        for (Inbound_Message__c m : [
            SELECT Id, Channel__c, Sender__c, Subject__c, Received_At__c, Confidence__c,
                   Candidate_Matches_JSON__c, Extraction_JSON__c, Related_Purchase__c
            FROM Inbound_Message__c
            WHERE Processing_Status__c = 'Needs Review'
            ORDER BY Received_At__c DESC
            LIMIT 50
        ]) {
            out.add(new Map<String, Object>{
                'messageId' => m.Id,
                'channel' => m.Channel__c,
                'sender' => m.Sender__c,
                'subject' => m.Subject__c,
                'receivedAt' => m.Received_At__c,
                'confidence' => m.Confidence__c,
                'candidates' => m.Candidate_Matches_JSON__c,
                'extraction' => m.Extraction_JSON__c,
                'suggestedPurchaseId' => m.Related_Purchase__c
            });
        }
        return out;
    }
}
