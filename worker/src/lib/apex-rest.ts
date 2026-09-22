import type { Env } from '../env';
import { withToken, type SalesforceToken } from './sf-auth';

/**
 * Thin proxy to the Apex REST API (BUILD_SPEC section 8).
 *
 * The PWA never talks to Salesforce directly - it has no credentials and never
 * will. Everything it reads or changes goes through here, which is also where
 * the single retry-on-401 lives.
 */

const BASE = '/services/apexrest/dakiya/v1';

export class ApexRestError extends Error {
    constructor(
        message: string,
        readonly status: number,
        readonly body?: string,
    ) {
        super(message);
        this.name = 'ApexRestError';
    }
}

async function call(
    env: Env,
    method: 'GET' | 'POST',
    path: string,
    body?: unknown,
): Promise<Response> {
    return withToken(env, (token: SalesforceToken) => {
        const url = `${token.instanceUrl}${BASE}${path}`;
        return fetch(url, {
            method,
            headers: {
                Authorization: `Bearer ${token.accessToken}`,
                'Content-Type': 'application/json',
            },
            ...(body === undefined ? {} : { body: JSON.stringify(body) }),
        });
    });
}

/**
 * Forward an Apex REST response to the browser as-is.
 *
 * Apex already returns the shared `{error:{code,message}}` envelope, so its
 * errors are passed through unchanged rather than being re-wrapped into
 * something the app would have to special-case.
 */
export async function proxy(
    env: Env,
    method: 'GET' | 'POST',
    path: string,
    body?: unknown,
): Promise<Response> {
    const res = await call(env, method, path, body);
    const text = await res.text();
    return new Response(text || '{}', {
        status: res.status,
        headers: { 'Content-Type': 'application/json' },
    });
}

/** Build a query string from only the params that were actually supplied. */
export function queryString(params: Record<string, string | undefined | null>): string {
    const q = new URLSearchParams();
    for (const [k, v] of Object.entries(params)) {
        if (v !== undefined && v !== null && v !== '') {
            q.set(k, v);
        }
    }
    const s = q.toString();
    return s ? `?${s}` : '';
}
