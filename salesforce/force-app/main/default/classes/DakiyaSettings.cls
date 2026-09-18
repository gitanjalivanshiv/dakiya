/**
 * Typed access to Dakiya_Setting__mdt with hard-coded fallbacks.
 *
 * Every threshold in the system comes from here, so behaviour can be retuned by
 * editing custom metadata instead of redeploying Apex. The fallbacks mean a
 * missing or mistyped setting degrades to the BUILD_SPEC default rather than
 * throwing in the middle of a Queueable.
 */
public with sharing class DakiyaSettings {
    @TestVisible
    private static Map<String, String> cache;

    /** Test seam: lets tests set values without inserting custom metadata. */
    @TestVisible
    private static void setOverride(String key, String value) {
        if (cache == null) {
            cache = new Map<String, String>();
        }
        cache.put(key, value);
    }

    private static Map<String, String> values() {
        if (cache == null) {
            cache = new Map<String, String>();
            for (Dakiya_Setting__mdt s : Dakiya_Setting__mdt.getAll().values()) {
                cache.put(s.DeveloperName, s.Value__c);
            }
        }
        return cache;
    }

    public static Integer getInt(String key, Integer fallback) {
        String raw = values().get(key);
        if (String.isBlank(raw)) {
            return fallback;
        }
        try {
            return Integer.valueOf(raw.trim());
        } catch (Exception e) {
            return fallback;
        }
    }

    public static Decimal getDecimal(String key, Decimal fallback) {
        String raw = values().get(key);
        if (String.isBlank(raw)) {
            return fallback;
        }
        try {
            return Decimal.valueOf(raw.trim());
        } catch (Exception e) {
            return fallback;
        }
    }

    public static String getString(String key, String fallback) {
        String raw = values().get(key);
        return String.isBlank(raw) ? fallback : raw.trim();
    }

    // ── Named accessors (BUILD_SPEC 4.9) ──────────────────────────────
    public static Integer confirmReminderHours()  { return getInt('ConfirmReminderHours', 4); }
    public static Integer confirmFlagHours()      { return getInt('ConfirmFlagHours', 24); }
    public static Integer stallShippedDays()      { return getInt('StallShippedDays', 5); }
    public static Integer stallPlacedDays()       { return getInt('StallPlacedDays', 7); }
    public static Integer instagramFollowUpDays() { return getInt('InstagramFollowUpDays', 5); }
    public static Integer defaultRefundCheckDays(){ return getInt('DefaultRefundCheckDays', 7); }
    public static Integer refundRecheckDays()     { return getInt('RefundRecheckDays', 3); }
    public static Integer maxRefundReminders()    { return getInt('MaxRefundReminders', 3); }
    public static Integer morningDigestHourIST()  { return getInt('MorningDigestHourIST', 8); }
    public static Integer returnWindowWarnDays()  { return getInt('ReturnWindowWarnDays', 2); }
    public static Integer rawBodyRetentionDays()  { return getInt('RawBodyRetentionDays', 30); }
    public static Decimal autoApplyConfidence()   { return getDecimal('AutoApplyConfidence', 0.90); }
    public static Decimal reviewConfidence()      { return getDecimal('ReviewConfidence', 0.60); }
    public static String  extractor()             { return getString('Extractor', 'PromptTemplate'); }
}
