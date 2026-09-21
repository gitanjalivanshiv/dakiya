# Dakiya — Build Spec (v1, personal use)

Owner: Gitanjali · Phone: Android · Locale: India (IST, INR) · Salesforce org alias: `trial3`
Items marked **⚠️VERIFY** must be checked against current official docs before implementation.

---

## 1. Goals and non-goals

**Goals**
1. Every online order is captured automatically from Gmail and SMS, or manually through chat / Android share, including Instagram-seller orders.
2. One timeline per order: placed → shipped → out for delivery → delivered → *confirmed received by me*.
3. Catch problems: courier says delivered but I didn't get it, stalled shipments, sellers who never shipped, return windows about to close.
4. Returns tracked to "refund initiated", then reminders to check and record the refund outcome, with per-vendor refund habits learned from history.
5. A full conversational agent (Agentforce) inside my own React PWA, plus Today / Orders / Returns screens and push notifications.
6. Secure, accurate, effectively free to run for years.
7. Showcase path: the same agent reachable over WhatsApp via the Twilio sandbox (demo only).

**Non-goals (v1)**
- Bank/UPI/card reconciliation or Account Aggregator.
- Multi-user / public product, app stores, Google OAuth verification.
- Reading Instagram DMs automatically (not possible via API; use share/screenshot).
- Sending messages to sellers automatically (the agent only *drafts*; I send).

## 2. Architecture

```
 Gmail ──(Apps Script, label "Dakiya/Inbox", every 10 min, HMAC)──┐
 Android SMS ──(MacroDroid, allowlisted senders, bearer token)────┤
 Android share sheet (screenshots/text) ──(PWA share target)──────┤
                                                                   ▼
                                       ┌──────────────────────────────────────┐
 React PWA (GitHub Pages) ◀──HTTPS──▶  │ Cloudflare Worker "dakiya-gateway"   │
   Chat · Today · Orders · Returns     │  • passkey auth + CORS               │
   Add · Settings · Web Push           │  • ingest: verify, dedupe, mask      │
                                       │  • image extraction (Claude Haiku)   │
 Twilio WhatsApp sandbox ◀────────────▶│  • Agent API chat proxy (SSE)        │
                                       │  • push sender (cron outbox poll)    │
                                       │  • KV: sessions, push subs, passkey  │
                                       └──────────────┬───────────────────────┘
                                                      │ OAuth client credentials (ECA)
                                                      ▼
                                   ┌──────────────────────────────────────────┐
                                   │ Salesforce Dev org (trial3)          │
                                   │  • Custom objects (Purchase, Shipment…)   │
                                   │  • Apex REST /dakiya/v1/*                 │
                                   │  • Rule parsers + Prompt Template (LLM)   │
                                   │  • Matching + state machine               │
                                   │  • Scheduled Apex → Notification outbox   │
                                   │  • Agentforce Service Agent "Dakiya"      │
                                   │    (Agent API, Einstein Trust Layer)      │
                                   └──────────────────────────────────────────┘
```

**Why the Worker exists:** GitHub Pages is static and public, so it can't hold the Salesforce client secret. The Agent API
uses the client-credentials flow and is meant to be called server-side. The Worker also does intake verification, push
notifications and the Twilio webhook.

**Why Salesforce is the brain:** data model + automation + Agentforce + Trust Layer (masking, zero retention) in one place,
exposed headlessly (Headless 360) to a custom UI. It's also a strong showcase.

## 3. Known constraints and gotchas (design for these)
| Constraint | Handling |
|---|---|
| Developer Edition data storage is small (≈5 MB, and most records count as ≈2 KB each) ⚠️VERIFY in Setup → Storage Usage | Retention jobs (§8.6); don't store images/files; keep raw bodies ≤ 30 days; storage check in weekly job |
| Dev Edition is not for production and Agentforce/LLM usage allowances aren't clearly published ⚠️VERIFY in Setup (Digital Wallet / usage) | Cache nothing in LLM; rules-first extraction; alert if usage errors appear; Haiku fallback path in Worker (`EXTRACTOR_FALLBACK=claude`) |
| Dev orgs can be locked or deleted after long inactivity | Weekly job keeps the integration active; RUNBOOK lists monthly login; metadata in git so the org can be rebuilt |
| Agent API doesn't support the "Agentforce (Default)" agent type | Create a **custom Agentforce Service Agent** named Dakiya |
| Agent API sessions expire | Worker recreates the session transparently on 404/expired and replays nothing (chat history is kept client-side) |
| Apex callouts not allowed in triggers / after DML in the same transaction | Ingest inserts `Inbound_Message__c`, then a **Queueable** does parsing + LLM |
| GitHub Pages can't receive POST (share target) | The **service worker** intercepts the share-target POST and stores payload in IndexedDB, then opens `#/add` |
| GitHub Pages SPA deep links 404 | Use **HashRouter**; set Vite `base` to `/<repo-name>/` |
| Cross-site cookies between `github.io` and `workers.dev` are unreliable | Bearer tokens (short-lived JWT in IndexedDB), not cookies |
| MacroDroid can't compute HMAC | Long random bearer token over HTTPS + sender allowlist + rate limit + dedupe |
| Twilio webhook timeout (~15 s) < agent latency | Reply empty TwiML immediately; send the agent reply via Twilio REST in `ctx.waitUntil` |
| Indian phone-number regex can collide with AWB/order numbers | Mask phones only when prefixed by +91/0 or preceded by keywords (call, mobile, ph, contact, whatsapp); fixture tests prove order IDs/AWBs survive |
| Android battery optimisation kills SMS automation | Guide user to exempt MacroDroid |

## 4. Salesforce data model (`/salesforce`)

All objects: sharing Private; the user and the agent/integration user get access via permission sets.

### 4.1 `Vendor__c`
| Field | Type | Notes |
|---|---|---|
| Name | Text | "Amazon", "Myntra", "@some_insta_shop" |
| Channel__c | Picklist | Marketplace, Instagram, D2C Website, Other |
| Instagram_Handle__c | Text(80) | |
| Email_Sender_Patterns__c | Long Text | one pattern per line (domain or address) |
| SMS_Sender_Patterns__c | Long Text | DLT header fragments e.g. `AMAZON`, `MYNTRA` |
| Return_Window_Days__c | Number | default null = unknown |
| Typical_Refund_Days__c | Number | learned: median days from Refund Initiated → outcome recorded |
| Usual_Refund_Mode__c | Picklist | Original Payment, Store Credit, Mixed, Unknown (learned) |
| Refund_History_Summary__c | Text(255) | e.g. "3 returns: 2 full to UPI, 1 store credit" (recomputed) |
| Follow_Up_After_Days__c | Number | stall threshold override (Instagram default 5) |

### 4.2 `Purchase__c` (an order)
| Field | Type | Notes |
|---|---|---|
| Vendor__c | Lookup(Vendor__c) | required |
| External_Order_Id__c | Text(80) | vendor order number |
| Vendor_Order_Key__c | Text(120), Unique, External ID | `lower(vendorId + ':' + orderId)`; manual orders use a UUID |
| Title__c | Text(255) | short human label, e.g. "Serum + lipstick" |
| Order_Date__c | Date | |
| Total_Amount__c | Currency | INR |
| Payment_Method__c | Picklist | UPI, Card, COD, Wallet, Other, Unknown |
| Status__c | Picklist | Placed, Confirmed, Partially Shipped, Shipped, Out for Delivery, Delivered (Unconfirmed), Received, Not Received, Cancelled, Return in Progress, Closed |
| Status_Rank__c | Number | used by state machine (§6) |
| Source__c | Picklist | Email, SMS, Share, Chat, Manual |
| Expected_Delivery__c | Date | |
| Last_Event_At__c | DateTime | |
| Delivered_At__c | DateTime | |
| Return_Window_Ends__c | Date | Delivered date + vendor window |
| Needs_Review__c | Checkbox | |
| Notes__c | Long Text | |

### 4.3 `Purchase_Item__c` (master-detail → Purchase__c)
Name, Quantity__c, Price__c, Status__c (Active, Cancelled, Returned, Replaced).

### 4.4 `Shipment__c` (master-detail → Purchase__c)
| Field | Type | Notes |
|---|---|---|
| Courier__c | Text(80) | Ekart, Delhivery, Blue Dart, Amazon Shipping, India Post, Shadowfax, XpressBees, Other |
| AWB__c | Text(60), Unique, External ID (nullable) | |
| Tracking_URL__c | URL | |
| Status__c | Picklist | Created, Shipped, In Transit, Out for Delivery, Delivered, Failed Attempt, RTO, Lost |
| Delivered_At__c | DateTime | |
| Confirmation__c | Picklist | Pending, Received, Not Received |
| Confirmed_At__c | DateTime | |
| Confirmation_Reminders__c | Number | |

### 4.5 `Tracking_Event__c`
Purchase__c (Lookup), Shipment__c (Lookup), Return__c (Lookup), Event_Type__c (picklist = extraction event types §5.3),
Event_At__c, Summary__c (Text 255), Source_Message__c (Lookup Inbound_Message__c), Applied_By__c (Rule, LLM, User, Agent, System).

### 4.6 `Return__c`
| Field | Type | Notes |
|---|---|---|
| Purchase__c | Lookup | required |
| Purchase_Item__c | Lookup | optional |
| Type__c | Picklist | Return, Exchange/Replacement |
| Reason__c | Text(255) | |
| Status__c | Picklist | Requested, Pickup Scheduled, Picked Up, Received by Seller, Refund Initiated, Refund Check Due, Completed, Rejected, Cancelled |
| Requested_On__c | Date | |
| Pickup_Date__c | Date | |
| Refund_Initiated_On__c | Date | |
| Expected_Refund_Amount__c | Currency | |
| Refund_Check_Due__c | Date | initiated + vendor typical days (default 7) |
| Refund_Outcome__c | Picklist | Full to Original Payment, Partial, Store Credit, Replacement, Not Received Yet, Not Received (Escalated) |
| Refund_Received_Amount__c | Currency | |
| Outcome_Recorded_On__c | Date | |
| Reminder_Count__c | Number | |

### 4.7 `Inbound_Message__c`
| Field | Type | Notes |
|---|---|---|
| Channel__c | Picklist | Email, SMS, Share, Chat, WhatsApp |
| Sender__c | Text(255) | email address or SMS header |
| Subject__c | Text(255) | |
| Body_Masked__c | Long Text(32000) | already masked by Worker; purged after 30 days |
| Received_At__c | DateTime | |
| Dedupe_Key__c | Text(128), Unique, External ID | Gmail messageId, or sha256(sender+body+minute) |
| Processing_Status__c | Picklist | New, Parsed (Rule), Parsed (LLM), Needs Review, Ignored, Error |
| Parser__c | Text(80) | rule class name or `PromptTemplate:Dakiya_Extract` |
| Extraction_JSON__c | Long Text | validated extraction |
| Confidence__c | Percent | |
| Candidate_Matches_JSON__c | Long Text | for review UI |
| Related_Purchase__c | Lookup(Purchase__c) | |
| Error__c | Long Text | |

### 4.8 `Notification__c` (outbox)
Type__c (Morning Digest, Confirm Delivery, Stalled, Seller Follow-up, Refund Check, Return Window, Review Needed, Weekly Check, System),
Title__c, Body__c, Actions_JSON__c (≤2 actions for Android: `[{"id":"received","label":"Got it ✅"}]`),
Deep_Link__c (e.g. `#/orders/a01...`), Related_Record_Id__c, Due_At__c, Status__c (Pending, Sent, Failed, Cancelled),
Dedupe_Key__c (Unique, e.g. `confirm:{shipmentId}:{n}`), Sent_At__c, Error__c.

### 4.9 Config: Custom Metadata `Dakiya_Setting__mdt`
Keys (with defaults): `ConfirmReminderHours=4`, `ConfirmFlagHours=24`, `StallShippedDays=5`, `StallPlacedDays=7`,
`InstagramFollowUpDays=5`, `DefaultRefundCheckDays=7`, `RefundRecheckDays=3`, `MaxRefundReminders=3`,
`MorningDigestHourIST=8`, `ReturnWindowWarnDays=2`, `RawBodyRetentionDays=30`, `AutoApplyConfidence=0.90`,
`ReviewConfidence=0.60`.

### 4.10 Permission sets
- `Dakiya_User`: full CRUD on all Dakiya objects, Apex classes, tabs (for the user in Salesforce UI).
- `Dakiya_Integration`: CRUD needed by Apex REST + Agent actions; assigned to the ECA run-as user **and** the agent user. ⚠️VERIFY which user Agentforce Service Agent actions run as in the current release.

## 5. Intake and extraction pipeline

### 5.1 Worker ingest endpoints
- `POST /ingest/email` — from Apps Script. Headers: `X-Dakiya-Timestamp`, `X-Dakiya-Signature` = hex(HMAC-SHA256(secret, timestamp + "." + rawBody)). Reject if |now − ts| > 5 min or bad signature (constant-time compare). Body: `{ messageId, from, subject, date, textBody }` (textBody ≤ 20 000 chars).
- `POST /ingest/sms` — from MacroDroid. Header `Authorization: Bearer <SMS_INGEST_TOKEN>` (≥ 32 random bytes). Body: `{ sender, body, receivedAt }`. Worker checks sender against `SMS_SENDER_ALLOWLIST` (comma-separated header fragments); drops any body matching `/\b(otp|one[\s-]?time password|verification code)\b/i`. Rate-limit to 60/hour.
- `POST /api/share` — from the authenticated PWA: `{ text?, imageBase64?, mimeType? }`.
- All ingest: zod validation → masking (§5.2) → forward to Salesforce `POST /services/apexrest/dakiya/v1/ingest`. Return 200 on duplicates (idempotent).

### 5.2 Masking (Worker, `worker/src/mask.ts`, fully unit-tested)
Mask before anything leaves the Worker:
- OTP-like codes near OTP keywords → drop whole message (SMS) or replace `[OTP]` (email).
- Card numbers / masked cards (`XX1234`, `**** 1234`, 13–19 digit Luhn-valid) → `[CARD]`.
- Bank account numbers near "a/c", "account" → `[ACCT]`.
- Phone numbers only with `+91`/`0` prefix or preceded by call/mobile/ph/contact/whatsapp → `[PHONE]`.
- Email addresses other than the vendor sender → `[EMAIL]`.
- Street address blocks after "Ship to"/"Delivery address"/"Deliver to" lines → `[ADDRESS]` (keep city + PIN only if needed; default mask).
- UPI IDs (`name@bank`) → `[UPI]`.
**Must NOT mask:** order IDs (e.g. `403-1234567-1234567`, `OD1234...`), AWBs, amounts, dates, item names. Fixture tests assert this.

### 5.3 Extraction contract (shared by rules and LLM)
```json
{
  "is_commerce": true,
  "vendor_name": "Myntra",
  "channel_hint": "Marketplace",
  "event_type": "order_placed | order_confirmed | shipped | out_for_delivery | delivered | delivery_failed | cancelled | return_requested | return_pickup_scheduled | return_picked_up | return_received | return_rejected | refund_initiated | refund_completed | exchange_shipped | other",
  "order_id": "string|null",
  "awb": "string|null",
  "courier": "string|null",
  "tracking_url": "string|null",
  "items": [{"name": "string", "qty": 1, "price": 499.0}],
  "amount": 1299.0,
  "event_date": "YYYY-MM-DD|null",
  "expected_date": "YYYY-MM-DD|null",
  "refund_mode": "original_payment | store_credit | unknown | null",
  "confidence": 0.0,
  "evidence": {"order_id": "exact quote", "awb": "exact quote", "amount": "exact quote", "event_type": "exact quote"}
}
```

### 5.4 Salesforce processing (Queueable `DakiyaProcessMessageJob`)
1. **Rules first.** `DakiyaParserRegistry` selects an `IDakiyaParser` by sender (Vendor patterns). Build parsers for Amazon, Flipkart,
   Myntra, Nykaa and common courier SMS (Ekart, Delhivery, Blue Dart, Amazon Shipping, Shadowfax, XpressBees). **Build parsers from the
   user's real masked samples (§10), not from guesses.** A parser returns the contract with confidence 0.95 when all its required
   regex groups match, or null.
2. **LLM fallback** when no parser matched or the parser returned null: Prompt Builder **Flex template `Dakiya_Extract`** invoked from Apex
   (`ConnectApi.EinsteinLLM.generateMessagesForPromptTemplate` ⚠️VERIFY API + Dev Edition availability). Prompt demands JSON only, the
   schema above, `null` when unknown, and evidence quotes copied verbatim. Temperature lowest available.
   If Prompt Builder is unavailable, fall back to the Worker's `/internal/extract` (Claude Haiku) — configurable via `Dakiya_Setting__mdt.Extractor`.
3. **Validate.** Parse JSON; enforce enums/types; **for every non-null of order_id, awb, amount, event_type there must be an evidence quote
   that is a substring of the normalized masked body** (normalize whitespace + case; for amount also accept `₹`, `Rs.`, `INR`, commas).
   Fail → null that field and lower confidence by 0.2. `is_commerce=false` → status Ignored.
4. **Match** (`DakiyaMatchingService`), scoring candidates among open purchases (last 90 days):
   - same AWB → 1.0; same vendor + order_id → 1.0
   - same vendor + amount equal + order date within ±3 days → 0.8
   - same vendor + item name token overlap ≥ 0.6 → +0.15 (capped at 0.95)
   - same vendor and only one open purchase → 0.7
   No candidate and event is `order_placed/confirmed` → create a new Purchase. No candidate and a later-stage event → Needs Review.
5. **Apply** only if `min(extraction confidence, match score) ≥ AutoApplyConfidence`. Nothing is ever applied tentatively.
   Between ReviewConfidence and AutoApplyConfidence → mark Needs Review **and** push "Is this your <vendor> order from <date>?" with actions
   (top candidate / not mine). Below ReviewConfidence → Needs Review without a push (it appears in Today → Review).
6. **State machine** (§6) updates Purchase/Shipment/Return; write a `Tracking_Event__c` for every applied event.

### 5.5 Image shares (Instagram screenshots)
Worker `/api/share` with image → Claude Haiku (vision) with the same schema + evidence (evidence must quote text visible in the image; also return
`ocr_text`) → Worker masks `ocr_text`, sends `{ocr_text, extraction}` to Salesforce ingest as Channel=Share. Salesforce re-validates evidence
against `ocr_text`. The image is never stored anywhere. ⚠️VERIFY current Haiku model id and pricing; hard spend cap set in Anthropic console.

### 5.6 Apps Script (`/apps-script/Code.gs`)
- Time-driven trigger every 10 minutes. Query: `label:Dakiya/Inbox -label:Dakiya/Done newer_than:3d`.
- For each message: build payload (messageId, from, subject, date ISO, `getPlainBody()` truncated), sign with
  `Utilities.computeHmacSha256Signature`, `UrlFetchApp.fetch` to Worker with `muteHttpExceptions`.
  On 200 → add `Dakiya/Done`, remove `Dakiya/Inbox`. On failure → leave for retry; after 5 failures (count in PropertiesService) add `Dakiya/Error`.
- Script Properties: `WORKER_URL`, `HMAC_SECRET`. No secrets in code.
- Gmail filters are created by the user (manual step) from the sender addresses seen in *her* samples, applying label `Dakiya/Inbox`.

### 5.7 MacroDroid (`/android/MACRODROID_SETUP.md`)
Macro "Dakiya SMS": Trigger = SMS Received (from any, content any) · Constraint = sender matches allowlist (MacroDroid's contact/number
filter or a text-match on `{sms_number}`) and body does NOT contain OTP keywords · Action = HTTP Request POST to `/ingest/sms`, header
`Authorization: Bearer …`, JSON body using magic text `{sms_number}`, `{sms_message}`, `{system_time}` ⚠️VERIFY exact magic-text names in current MacroDroid.
Also: exempt MacroDroid from battery optimisation; test with a self-sent SMS containing a sample courier text.

## 6. State machine rules (`DakiyaStateMachine`, unit-tested table-driven)
Rank: Placed 10 · Confirmed 20 · Partially Shipped 30 · Shipped 40 · Out for Delivery 50 · Delivered (Unconfirmed) 60 · Received 70 · Return in Progress 80 · Closed 90.
- A normal event may only move status **forward** (higher rank). Out-of-order older events are recorded as Tracking Events but don't change status.
- Exceptions that can move "sideways": `cancelled` (any rank < 60 → Cancelled), `delivery_failed` (stays at Shipped/OFD, logs), `RTO` (Shipment RTO, Purchase → Needs Review), user "Not Received" (60 → Not Received), return events (≥ 60 → Return in Progress).
- `delivered` sets Shipment Delivered + Confirmation Pending and Purchase → Delivered (Unconfirmed); sets Return_Window_Ends__c if vendor window known.
- User "Got it" → Shipment Confirmation Received, Purchase → Received (or stays Partially Shipped if other shipments/items pending).
- `refund_initiated` → Return Refund Initiated; Refund_Check_Due__c = today + (vendor Typical_Refund_Days__c ?? DefaultRefundCheckDays).
- Outcome recorded → Return Completed; Purchase → Closed if no other open returns/items; recompute vendor refund stats.

## 7. Agentforce agent "Dakiya"
Type: **custom Agentforce Service Agent** (Agent API compatible). Build with Agentforce DX if available in the user's CLI
(`sf agent --help`; e.g. agent spec / authoring bundle commands ⚠️VERIFY), otherwise guide the user through Agentforce Builder with exact
values from this section. Store all resulting metadata in git (retrieve after UI creation).

**Agent-level instructions (summary):** You are Dakiya, Gitanjali's personal parcel and returns assistant. Always use actions to read or change data;
never invent order IDs, tracking numbers, amounts or dates. Use IST dates and ₹. Be brief and mobile-friendly. Before creating, cancelling or
recording a refund outcome, confirm the details in one short line unless the user already stated them explicitly. You can draft messages to sellers,
but you never send them. If something is ambiguous, ask one clarifying question.

| Topic | Scope | Actions (Apex `@InvocableMethod`, clear descriptions + input/output docs) |
|---|---|---|
| Order Status | "what's pending", "where's my Myntra order", "arriving today" | `Dakiya_GetPendingDeliveries`, `Dakiya_SearchPurchases(vendor?, text?, status?, fromDate?, toDate?)`, `Dakiya_GetPurchaseTimeline(purchaseId)` |
| Add or Update Order | manual/Instagram orders, add tracking, cancel | `Dakiya_CreatePurchase(vendorName, channel, title, items, amount, orderDate, paymentMethod, instagramHandle?)`, `Dakiya_AddTracking(purchaseId, courier, awb, trackingUrl?)`, `Dakiya_CancelPurchase(purchaseId, reason)` |
| Delivery Confirmation | "got the Nykaa parcel", "didn't receive" | `Dakiya_ConfirmReceived(purchaseId|shipmentId)`, `Dakiya_ReportNotReceived(purchaseId)` → returns complaint pack text (order id, courier, AWB, delivered-claim time, suggested message) |
| Returns & Refunds | start return, update status, record refund | `Dakiya_CreateReturn(purchaseId, itemName?, reason, type)`, `Dakiya_UpdateReturnStatus(returnId, status, date?)`, `Dakiya_RecordRefundOutcome(returnId, outcome, amount?)`, `Dakiya_ListOpenReturns()`, `Dakiya_GetVendorRefundPattern(vendorName)` |
| Seller Follow-up | chase Instagram sellers / support | `Dakiya_DraftFollowUp(purchaseId, tone?)` → text only |
| Review Queue | "anything to review?" | `Dakiya_ListReviewItems()`, `Dakiya_ResolveReview(inboundMessageId, purchaseId|'new'|'ignore')` |

Agent test cases (Agentforce testing center or `sf agent test` ⚠️VERIFY): ≥ 20 utterances covering each topic, incl. Hinglish ("mera Nykaa ka parcel aaya kya?")
and adversarial ("just make up the tracking number").

## 8. Apex REST API (for the Worker) — `/services/apexrest/dakiya/v1/*`
All responses JSON, camelCase, errors as `{error:{code,message}}`.
| Method & path | Purpose |
|---|---|
| `POST /ingest` | insert Inbound_Message (dedupe) and enqueue job → `{id, duplicate}` |
| `GET /today` | `{arrivingToday[], awaitingConfirmation[], stalled[], refundChecksDue[], returnWindowsClosing[], reviewItems[]}` |
| `GET /purchases?status=&vendor=&q=&limit=&offset=` | list |
| `GET /purchases/{id}` | detail + items + shipments + events + returns |
| `POST /purchases` | manual create (used by Add screen after share-confirm) |
| `POST /actions` | `{action: "confirm_received"|"not_received"|"refund_outcome"|"resolve_review"|"snooze", recordId, payload}` |
| `GET /returns?open=true` | list |
| `GET /vendors` | list with refund stats |
| `GET /notifications/due` | Pending notifications with Due_At ≤ now (max 20) |
| `POST /notifications/{id}/result` | `{status: "Sent"|"Failed", error?}` |
| `GET /health` | `{ok, storageUsedPct?, lastJobRun}` |

### 8.6 Scheduled Apex (hourly `DakiyaScheduler`, idempotent via Notification dedupe keys)
- 08:00 IST digest (only if something is arriving or pending).
- Delivered unconfirmed ≥ ConfirmReminderHours → "Got the <vendor> parcel?" [Got it ✅][Not received ❌]; ≥ ConfirmFlagHours → flag + push.
- Shipped with no event for StallShippedDays; Placed with no shipment for StallPlacedDays (Instagram: InstagramFollowUpDays) → push with "Draft follow-up" deep link.
- Return window ends within ReturnWindowWarnDays → push.
- Refund_Check_Due__c ≤ today → push "Did your <vendor> refund arrive?" [Yes, record it][Not yet]; Not yet → due + RefundRecheckDays; after MaxRefundReminders → suggest escalation draft.
- Sunday 11:00 IST weekly check: purchases with no update ≥ 7 days + review queue count.
- Daily 03:00 IST retention: blank `Body_Masked__c` older than RawBodyRetentionDays; delete Ignored inbound messages older than 7 days; delete Sent notifications older than 30 days; delete Tracking Events of Closed purchases older than 180 days (keep a summary).

## 9. Cloudflare Worker (`/worker`, TypeScript + Hono)
**Bindings:** KV `DAKIYA_KV` · vars `SF_MY_DOMAIN_URL`, `SF_AGENT_ID`, `APP_ORIGIN` (e.g. `https://<user>.github.io`), `SMS_SENDER_ALLOWLIST`, `RP_ID`
· secrets `SF_CLIENT_ID`, `SF_CLIENT_SECRET`, `EMAIL_HMAC_SECRET`, `SMS_INGEST_TOKEN`, `JWT_SIGNING_KEY`, `SETUP_CODE`, `VAPID_PUBLIC_KEY`, `VAPID_PRIVATE_KEY`, `ANTHROPIC_API_KEY`, `TWILIO_ACCOUNT_SID`, `TWILIO_AUTH_TOKEN`, `WHATSAPP_ALLOWED_FROM`.
**Cron:** `*/15 * * * *` → poll `/notifications/due`, send Web Push, report results.

### 9.1 Salesforce auth
Client credentials token from `${SF_MY_DOMAIN_URL}/services/oauth2/token` (grant_type=client_credentials). Cache token in KV until ~5 min before expiry; on 401 refresh once. ⚠️VERIFY response fields (e.g. `api_instance_url`).

### 9.2 Agent API proxy ⚠️VERIFY all shapes against the Agent API developer guide
- `POST /api/chat/sessions` → Worker calls `POST https://api.salesforce.com/einstein/ai-agent/v1/agents/{SF_AGENT_ID}/sessions` with
  `externalSessionKey` (uuid), `instanceConfig.endpoint = SF_MY_DOMAIN_URL`, `streamingCapabilities.chunkTypes=["Text"]`, `bypassUser: true`. Returns `{sessionId, welcome}`.
- `POST /api/chat/sessions/{id}/messages` → Worker calls `…/sessions/{id}/messages/stream` (`Accept: text/event-stream`) with
  `{message:{sequenceId, type:"Text", text}}`; **pipes SSE through** to the client (normalize to `event: chunk|message|end|error`). Worker tracks sequenceId in KV.
- `DELETE /api/chat/sessions/{id}` → end session (`x-session-end-reason: UserRequest`).
- On expired session: create new session, return `{sessionRenewed:true}` so the UI shows a subtle "new session" divider.

### 9.3 PWA auth — passkey, one device
- `POST /auth/register/options` + `/auth/register/verify` — only allowed when no credential exists **and** body contains `SETUP_CODE`. Stores one credential in KV.
- `POST /auth/login/options` + `/auth/login/verify` → issues JWT (HS256, 12 h, `sub=owner`). Use `@simplewebauthn/server` ⚠️VERIFY Workers compatibility.
- `POST /auth/reset` disabled by default; recovery = `wrangler kv key delete` documented in RUNBOOK.
- Every `/api/*` requires `Authorization: Bearer <jwt>`. CORS: allow only `APP_ORIGIN`. Security headers on all responses.

### 9.4 Other routes
`/api/today`, `/api/purchases…`, `/api/returns`, `/api/actions`, `/api/share` → proxy to Apex REST (§8).
`/api/push/subscribe` (store subscription in KV), `/api/push/test`.
`/internal/extract` (called by Salesforce fallback; authenticated with a shared header secret stored in a Salesforce Named Credential — only if fallback is enabled).
`/twilio/whatsapp` (Phase 9).
`/health` (no auth; returns only `{ok:true}`).
Web Push: VAPID + aes128gcm encryption using a Workers-compatible library ⚠️VERIFY (e.g. one built on WebCrypto); notification payload `{title, body, actions, deepLink, notificationId}`.

### 9.5 Tests
Vitest (+ Miniflare/`@cloudflare/vitest-pool-workers`): signature verification, replay window, allowlist, OTP drop, masking fixtures, auth guard, CORS, SSE piping (mocked Salesforce), push encryption smoke.

## 10. Accuracy harness (`/samples`, `npm run eval`)
1. **Manual step (guided):** user exports 30–50 real messages: forward to self / copy SMS text → `samples/raw/` (gitignored) as `.eml`/`.txt`,
   covering order placed, shipped, OFD, delivered, cancelled, return pickup, refund initiated for Amazon, Flipkart, Myntra, Nykaa, 2+ couriers, 2+ Instagram/D2C sellers.
2. Script masks them (Worker masking module) → `samples/masked/`; **user reviews** masked output before anything is committed or sent to an LLM.
3. User + Claude label expected JSON → `samples/expected/*.json`.
4. `npm run eval` runs rules (via a TS port of the regexes or an Apex test harness) and LLM extraction; reports per-field precision/recall and **hallucination count**.
5. **Go-live gate:** templated senders ≥ 95% exact match on order_id, awb, event_type; overall event_type ≥ 90%; **0 hallucinated IDs**; masking leaks 0.
6. Every production mistake the user reports becomes a new fixture.

## 11. React PWA (`/app`)
Stack: React 18 + Vite + TypeScript, React Router **HashRouter**, TanStack Query, `vite-plugin-pwa` (injectManifest for custom SW), IndexedDB (`idb`) for chat history + share inbox, zod.
Design: mobile-first, bottom tab bar, light/dark via system, large tap targets, ₹ en-IN formatting, relative IST dates ("today 2 pm").

Screens:
- **Today** — cards: Arriving today · Confirm delivery (Got it / Not received) · Refund checks due (Full / Partial / Store credit / Not yet) · Return windows closing · Stalled (Draft follow-up → opens chat with prefilled prompt) · Review (pick matching order / new / ignore).
- **Chat** — streaming bubbles, typing indicator, quick chips ("What's pending?", "Open returns", "Anything to review?"), local history, new-session button, copy button on drafted messages.
- **Orders** — search + filter chips (status, vendor); detail with timeline, items, shipments, returns, actions.
- **Returns** — open returns with status stepper; record outcome sheet.
- **Add** — share-target landing: shows shared text/image, "Extract" → preview extraction with highlighted evidence → Confirm / Edit / Cancel; also manual form.
- **Settings** — enable notifications, test push, passkey status, Worker health, app version, sign out.
Manifest: name "Dakiya", `start_url` and `scope` = base path, `display: standalone`, icons (generate simple original icon), `share_target` `{action: "<base>share-target", method: "POST", enctype: "multipart/form-data", params: {title, text, url, files:[{name:"media", accept:["image/*"]}]}}`.
Service worker: precache, share-target POST handler → IndexedDB → redirect to `#/add`; `push` → showNotification with actions; `notificationclick` → call `/api/actions` for action buttons (needs JWT: store a short-lived action token in IndexedDB, or open the app to complete the action if token expired) or open deep link.
Deploy: GitHub Actions → build with `VITE_WORKER_URL` → GitHub Pages. Tests: Vitest + Testing Library for components, Playwright smoke against a mocked Worker.

## 12. Twilio WhatsApp showcase (Phase 9, demo only)
Sandbox number → webhook `POST /twilio/whatsapp`: validate `X-Twilio-Signature`; allow only `WHATSAPP_ALLOWED_FROM`; map From → agent session in KV; respond empty TwiML; in `waitUntil` call Agent API (non-streaming or collect stream) and send reply via Twilio Messages API. Note: sandbox participants must re-join periodically; this is not the daily channel.

## 13. Security checklist (verify at the end of each phase)
- [ ] No secrets or personal data in git history (`git log -p | grep` for known patterns; gitleaks if available)
- [ ] CORS only `APP_ORIGIN`; all `/api/*` require JWT; `/ingest/*` verified; `/twilio/*` signature-validated
- [ ] Masking fixtures pass; OTPs dropped at MacroDroid and at Worker
- [ ] ECA scoped to minimal scopes; run-as user has only `Dakiya_Integration`
- [ ] Anthropic key has a hard monthly spend limit; Twilio has no auto-recharge
- [ ] Raw bodies purged ≤ 30 days; images never persisted
- [ ] RUNBOOK covers: rotate each secret, reset passkey, re-deploy org from git, what to do if Dev org is locked

## 14. Phases, manual steps and acceptance criteria
Each phase ends with: acceptance checks → update `docs/SETUP.md` → commit → push → ask to continue.
**[M]** = manual step Claude must guide click-by-click (see CLAUDE.md protocol).

### Phase 0 — Workstation and repo
- Check: `node -v` (≥ 20), `git`, `gh auth status`, `sf --version`, `sf org display -o trial3`, `npx wrangler --version`.
- **[M]** `gh auth login` if needed · **[M]** create free Cloudflare account + `npx wrangler login` (browser).
- Create public GitHub repo (confirm name with user) via `gh repo create`, scaffold monorepo, `.gitignore`, README, `docs/SETUP.md`, `docs/DECISIONS.md`.
- ✅ Accept: repo pushed; `sf org display -o trial3` shows connected; wrangler whoami OK.

### Phase 1 — Salesforce foundation
- **[M]** Setup → Company Information: Default Time Zone = (GMT+05:30) India Standard Time, Currency = INR (if editable); user's own time zone IST.
- **[M]** Setup → Storage Usage: record current data/file storage limits in SETUP.md.
- Generate SFDX project; objects/fields/picklists (§4); CMDT + default records; permission sets; tab + simple Lightning app "Dakiya" for admin browsing.
- Apex: `DakiyaStateMachine`, `DakiyaMatchingService`, `DakiyaParserRegistry` (+ interface, no vendor parsers yet), `DakiyaEvidenceValidator`, `DakiyaIngestService`, `DakiyaProcessMessageJob` (LLM call stubbed), REST controllers (§8), tests.
- Deploy to `trial3`; assign `Dakiya_User` to the user (`sf org assign permset -n Dakiya_User -o trial3`).
- ✅ Accept: deploy succeeds; Apex tests pass ≥ 85%; creating a Purchase via Apex REST in anonymous Apex / Workbench works.

### Phase 2 — Agentforce agent
- **[M]** Confirm Einstein + Agentforce enabled (Setup → Einstein Setup; Setup → Agentforce Agents) and check usage/allowance page.
- Invocable actions (§7) with tests; deploy.
- Create **custom Agentforce Service Agent "Dakiya"** (Agentforce DX or **[M]** Agentforce Builder with exact topic names, descriptions, instructions, actions).
- **[M]** Assign `Dakiya_Integration` to the agent's user; activate the agent; copy **Agent ID** (18-char, starts `0Xx`) from Setup URL.
- Retrieve agent metadata into git.
- ✅ Accept: in Agentforce Builder preview, 10 core utterances behave correctly (create manual order, list pending, confirm received, create return, record refund outcome, draft follow-up, refuses to invent tracking numbers).

### Phase 3 — External Client App + Worker skeleton
- **[M]** Setup → External Client App Manager → New External Client App "Dakiya Gateway": enable OAuth; callback `https://localhost/callback` (unused); scopes `api`, `refresh_token, offline_access`, `chatbot_api`, `sfap_api`; enable **Client Credentials Flow**; enable JWT-based access tokens for named users if required ⚠️VERIFY; Policies → Client Credentials Flow **Run As** = integration user with `Dakiya_Integration`. Copy consumer key (chat OK) and secret (**separate terminal** → `wrangler secret put`).
- **[M]** Connect the ECA to the agent if the current Agent API setup requires it (e.g. agent Connections → API) ⚠️VERIFY.
- Worker scaffold (Hono, zod, KV, vars/secrets per §9), SF token client, `/health`, `/api/chat/*` proxy, CLI test script `npm run chat:smoke` that creates a session and streams one reply.
- ✅ Accept: `npm run chat:smoke` gets a streamed agent reply from `trial3`; `wrangler deploy` works; secrets listed (names only).

### Phase 4 — PWA shell + passkey + chat
- App scaffold, HashRouter, tab bar, Chat screen wired to Worker, Settings.
- Worker passkey auth + JWT + CORS. **[M]** generate `SETUP_CODE` & `JWT_SIGNING_KEY` in separate terminal (`openssl rand -base64 32`) → `wrangler secret put`.
- GitHub Actions deploy to Pages. **[M]** Repo Settings → Pages → Source: GitHub Actions; set repo variable `VITE_WORKER_URL`.
- **[M] Phone:** open the Pages URL in Chrome on Android → menu → Install app → open app → Register passkey with setup code (fingerprint).
- ✅ Accept: from the installed app, after fingerprint login, a full multi-turn conversation with Dakiya works; unauthenticated `/api/*` returns 401; request from another origin blocked.

### Phase 5 — Today/Orders/Returns + push
- Apex REST endpoints fully implemented; screens (§11); actions.
- Web Push: **[M]** generate VAPID keys (script prints; private key → separate terminal secret); Settings → Enable notifications on phone; Worker cron; `DakiyaScheduler` scheduled (`System.schedule` via anonymous Apex, documented).
- ✅ Accept: create test data via chat → appears in Today; a due test Notification arrives on the phone within 15 min; "Got it ✅" from the notification updates Salesforce.

### Phase 6 — Samples, masking and parsers (accuracy)
- **[M]** Collect samples (§10.1); review masked output.
- Masking module + fixtures; label expected JSON with user; vendor + courier rule parsers; `Dakiya_Extract` Prompt Template (**[M]** if it must be created in Prompt Builder UI — exact steps) + Apex invocation; evidence validator; Haiku image path; eval harness.
- **[M]** Anthropic console: create API key, set monthly spend limit (e.g. $5), store key via separate terminal.
- ✅ Accept: go-live gate in §10.5 passes; report committed (masked only).

### Phase 7 — Gmail + SMS intake
- `/ingest/email`, `/ingest/sms` with tests.
- **[M]** Gmail: create labels `Dakiya/Inbox`, `Dakiya/Done`, `Dakiya/Error`; create filters from senders found in samples (Claude lists exact `from:` queries); optionally apply to existing recent mails.
- **[M]** Apps Script: script.google.com → New project "Dakiya Intake" → paste `Code.gs` & manifest (or `clasp` if user prefers) → Project Settings → Script Properties (`WORKER_URL`, `HMAC_SECRET` typed by user) → run `setup()` once → authorize (Advanced → Go to project (unsafe) is expected for own unverified script) → confirm 10-min trigger created.
- **[M] Phone:** install MacroDroid → build macro per `/android/MACRODROID_SETUP.md` → exempt from battery optimisation → test.
- ✅ Accept: a real order email and a courier SMS each create/update the right Purchase within 15 min; duplicates ignored; an OTP SMS never reaches the Worker logs.

### Phase 8 — Shadow week + polish
- Run alongside the WhatsApp self-chat for 7 days. Daily 2-minute check: anything missing or wrong → fixture + fix.
- Retention jobs verified; RUNBOOK.md; security checklist §13.
- ✅ Accept: 7 days with no missed orders the user cares about; user decides to retire the WhatsApp list.

### Phase 9 — Twilio WhatsApp showcase (optional)
- **[M]** Twilio console: sandbox join; set "When a message comes in" webhook to Worker URL; secrets via separate terminal.
- Implement §12. ✅ Accept: WhatsApp conversation with the same agent works for a demo.
