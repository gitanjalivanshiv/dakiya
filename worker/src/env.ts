/**
 * Worker bindings (BUILD_SPEC section 9).
 *
 * Nothing here is ever sent to the browser. The PWA knows exactly one thing:
 * the Worker's URL.
 */
export interface Env {
    // ── KV ────────────────────────────────────────────────────────────
    /** Salesforce token cache, chat session sequence numbers, push subs, passkey. */
    DAKIYA_KV: KVNamespace;

    // ── vars (not secret; live in wrangler.jsonc) ─────────────────────
    SF_MY_DOMAIN_URL: string;
    /** 18-char agent id, starts 0Xx. Empty until the agent is published. */
    SF_AGENT_ID: string;
    /** The only origin allowed to call /api/*. */
    APP_ORIGIN: string;
    SMS_SENDER_ALLOWLIST: string;
    RP_ID: string;

    // ── secrets (wrangler secret put) ─────────────────────────────────
    SF_CLIENT_ID: string;
    SF_CLIENT_SECRET: string;
    JWT_SIGNING_KEY: string;
    SETUP_CODE: string;
    EMAIL_HMAC_SECRET: string;
    SMS_INGEST_TOKEN: string;
    VAPID_PUBLIC_KEY: string;
    VAPID_PRIVATE_KEY: string;
    ANTHROPIC_API_KEY: string;
    TWILIO_ACCOUNT_SID: string;
    TWILIO_AUTH_TOKEN: string;
    WHATSAPP_ALLOWED_FROM: string;
}
