import type { Env } from '../env';

/**
 * Salesforce OAuth client-credentials token, cached in KV.
 *
 * Salesforce does not return `expires_in` on this grant, so the cache uses a
 * conservative fixed TTL well inside the org's session timeout, and callers
 * refresh once on a 401 rather than trusting the clock.
 */

const CACHE_KEY = 'sf:token';
/** 30 minutes. Org session timeouts are hours; this is deliberately cautious. */
const CACHE_TTL_SECONDS = 1800;

export interface SalesforceToken {
    accessToken: string;
    /** Where Salesforce REST calls go. */
    instanceUrl: string;
    /** Where Einstein/Agent API calls go, when Salesforce supplies one. */
    apiInstanceUrl?: string;
}

export class SalesforceAuthError extends Error {
    constructor(
        message: string,
        readonly status: number,
        readonly body?: string,
    ) {
        super(message);
        this.name = 'SalesforceAuthError';
    }
}

export async function getToken(env: Env, forceRefresh = false): Promise<SalesforceToken> {
    if (!forceRefresh) {
        const cached = await env.DAKIYA_KV.get(CACHE_KEY, 'json');
        if (cached) return cached as SalesforceToken;
    }

    if (!env.SF_CLIENT_ID || !env.SF_CLIENT_SECRET) {
        throw new SalesforceAuthError('SF_CLIENT_ID / SF_CLIENT_SECRET are not set', 500);
    }

    const res = await fetch(`${env.SF_MY_DOMAIN_URL}/services/oauth2/token`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
            grant_type: 'client_credentials',
            client_id: env.SF_CLIENT_ID,
            client_secret: env.SF_CLIENT_SECRET,
        }),
    });

    const text = await res.text();
    if (!res.ok) {
        // The body carries error/error_description but never the secret itself.
        throw new SalesforceAuthError('Salesforce token request failed', res.status, text);
    }

    const json = JSON.parse(text) as {
        access_token?: string;
        instance_url?: string;
        api_instance_url?: string;
    };
    if (!json.access_token) {
        throw new SalesforceAuthError('Token response had no access_token', 502, text);
    }

    const token: SalesforceToken = {
        accessToken: json.access_token,
        instanceUrl: json.instance_url ?? env.SF_MY_DOMAIN_URL,
        ...(json.api_instance_url ? { apiInstanceUrl: json.api_instance_url } : {}),
    };

    await env.DAKIYA_KV.put(CACHE_KEY, JSON.stringify(token), {
        expirationTtl: CACHE_TTL_SECONDS,
    });
    return token;
}

/** Drop the cached token, so the next call fetches a fresh one. */
export async function invalidateToken(env: Env): Promise<void> {
    await env.DAKIYA_KV.delete(CACHE_KEY);
}

/**
 * Run a Salesforce call with one automatic retry on 401.
 *
 * A cached token can be revoked or expire early; one silent refresh is the
 * difference between a working app and a mysterious intermittent failure.
 */
export async function withToken(
    env: Env,
    call: (token: SalesforceToken) => Promise<Response>,
): Promise<Response> {
    let token = await getToken(env);
    let res = await call(token);
    if (res.status === 401) {
        await invalidateToken(env);
        token = await getToken(env, true);
        res = await call(token);
    }
    return res;
}
