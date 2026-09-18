/**
 * Formatting shared by every agent action.
 *
 * The agent answers on a phone, so replies are short lines, IST dates and rupee
 * amounts. Formatting lives here rather than in the agent's prompt because a
 * date rendered by Apex cannot drift the way an instruction to the model can.
 */
public with sharing class DakiyaAgentFormat {

    /** "18 Sep", or "18 Sep 2025" when it is not this year. */
    public static String day(Date d) {
        if (d == null) {
            return 'unknown date';
        }
        Datetime dt = Datetime.newInstance(d, Time.newInstance(12, 0, 0, 0));
        return d.year() == Date.today().year()
            ? dt.format('d MMM', DakiyaConstants.TZ_IST)
            : dt.format('d MMM yyyy', DakiyaConstants.TZ_IST);
    }

    /** "today 2:10 pm" / "yesterday" / "18 Sep", always IST. */
    public static String when(Datetime dt) {
        if (dt == null) {
            return 'unknown time';
        }
        Date d = Date.valueOf(dt.format('yyyy-MM-dd', DakiyaConstants.TZ_IST));
        Integer daysAgo = d.daysBetween(Date.today());
        String clock = dt.format('h:mm a', DakiyaConstants.TZ_IST).toLowerCase();
        if (daysAgo == 0) { return 'today ' + clock; }
        if (daysAgo == 1) { return 'yesterday ' + clock; }
        return day(d);
    }

    /** Indian digit grouping: 1,29,900 not 129,900. */
    public static String rupees(Decimal amount) {
        if (amount == null) {
            return 'amount unknown';
        }
        Boolean negative = amount < 0;
        String digits = String.valueOf(amount.setScale(2).abs().round(System.RoundingMode.HALF_UP));
        String grouped;
        if (digits.length() <= 3) {
            grouped = digits;
        } else {
            String last3 = digits.substring(digits.length() - 3);
            String rest = digits.substring(0, digits.length() - 3);

            // Collected right to left, then reversed. Note: Apex List.add(index,
            // element) throws on an empty list, so no indexed insert here.
            List<String> reversed = new List<String>();
            while (rest.length() > 2) {
                reversed.add(rest.substring(rest.length() - 2));
                rest = rest.substring(0, rest.length() - 2);
            }
            if (rest.length() > 0) {
                reversed.add(rest);
            }
            List<String> chunks = new List<String>();
            for (Integer i = reversed.size() - 1; i >= 0; i--) {
                chunks.add(reversed[i]);
            }
            grouped = String.join(chunks, ',') + ',' + last3;
        }
        return (negative ? '-Rs ' : 'Rs ') + grouped;
    }

    /** "Myntra - Serum + lipstick (Rs 1,299)" */
    public static String describe(Purchase__c p) {
        String vendor = p.Vendor__r == null || p.Vendor__r.Name == null ? 'Unknown seller' : p.Vendor__r.Name;
        String title = String.isBlank(p.Title__c) ? 'untitled order' : p.Title__c;
        String line = vendor + ' - ' + title;
        if (p.Total_Amount__c != null) {
            line += ' (' + rupees(p.Total_Amount__c) + ')';
        }
        return line;
    }

    /** Used by every action so a failure reads as a sentence, not a stack trace. */
    public static String problem(Exception e) {
        return 'Could not do that: ' + e.getMessage();
    }
}
