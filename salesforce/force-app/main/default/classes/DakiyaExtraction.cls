/**
 * The extraction contract (BUILD_SPEC 5.3), shared by rule parsers and the LLM.
 *
 * Field names are snake_case to match the JSON exactly, so JSON.deserialize maps
 * straight onto this class with no translation layer to get out of step.
 */
public with sharing class DakiyaExtraction {
    public Boolean is_commerce;
    public String vendor_name;
    public String channel_hint;
    public String event_type;
    public String order_id;
    public String awb;
    public String courier;
    public String tracking_url;
    public List<Item> items;
    public Decimal amount;
    public String event_date;      // YYYY-MM-DD
    public String expected_date;   // YYYY-MM-DD
    public String refund_mode;
    public Decimal confidence;
    public Evidence evidence;

    public class Item {
        public String name;
        public Integer qty;
        public Decimal price;
    }

    /** Verbatim quotes from the source. Without one, the paired field is discarded. */
    public class Evidence {
        public String order_id;
        public String awb;
        public String amount;
        public String event_type;
    }

    public static DakiyaExtraction parse(String payload) {
        // Note: the parameter cannot be called 'json' - Apex identifiers are
        // case-insensitive, so it would shadow the system JSON class.
        return (DakiyaExtraction) JSON.deserialize(payload, DakiyaExtraction.class);
    }

    /** Parse date strings defensively - a bad date is dropped, never guessed. */
    public Date eventDateValue()    { return toDate(event_date); }
    public Date expectedDateValue() { return toDate(expected_date); }

    private static Date toDate(String s) {
        if (String.isBlank(s)) {
            return null;
        }
        try {
            return Date.valueOf(s.trim());
        } catch (Exception e) {
            return null;
        }
    }
}
