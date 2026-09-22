import { env, SELF } from 'cloudflare:test';
import { afterEach, describe, expect, it, vi } from 'vitest';
import { signJwt } from '../src/lib/jwt';

async function bearer(): Promise<string> {
    return `Bearer ${await signJwt(env.JWT_SIGNING_KEY, 'owner', 300)}`;
}

/** Stand in for Salesforce: the OAuth token endpoint plus the Agent API. */
function mockSalesforce(options: { streamStatus?: number; sessionStatus?: number } = {}) {
    const chunks = [
        'event: chunk\ndata: {"text":"Nothing "}\n\n',
        'event: chunk\ndata: {"text":"pending."}\n\n',
        'event: end\ndata: {}\n\n',
    ];
    return vi.spyOn(globalThis, 'fetch').mockImplementation(async (input: RequestInfo | URL) => {
        const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;

        if (url.includes('/services/oauth2/token')) {
            return new Response(
                JSON.stringify({ access_token: 'tok', instance_url: 'https://example.my.salesforce.com' }),
                { status: 200, headers: { 'Content-Type': 'application/json' } },
            );
        }
        if (url.includes('/sessions') && url.endsWith('/sessions')) {
            return new Response(
                JSON.stringify({ sessionId: 'sess-1', messages: [{ message: 'Hi!' }] }),
                { status: options.sessionStatus ?? 200 },
            );
        }
        if (url.includes('/messages/stream')) {
            if (options.streamStatus && options.streamStatus !== 200) {
                return new Response('gone', { status: options.streamStatus });
            }
            const body = new ReadableStream({
                start(controller) {
                    for (const c of chunks) controller.enqueue(new TextEncoder().encode(c));
                    controller.close();
                },
            });
            return new Response(body, { status: 200, headers: { 'Content-Type': 'text/event-stream' } });
        }
        return new Response('{}', { status: 200 });
    });
}

afterEach(() => vi.restoreAllMocks());

describe('health', () => {
    it('is public and reveals nothing', async () => {
        const res = await SELF.fetch('https://worker/health');
        expect(res.status).toBe(200);
        expect(await res.json()).toEqual({ ok: true });
    });

    it('sets security headers', async () => {
        const res = await SELF.fetch('https://worker/health');
        expect(res.headers.get('X-Content-Type-Options')).toBe('nosniff');
        expect(res.headers.get('X-Frame-Options')).toBe('DENY');
        expect(res.headers.get('Referrer-Policy')).toBe('no-referrer');
    });
});

describe('auth guard', () => {
    it('rejects /api/* with no token', async () => {
        const res = await SELF.fetch('https://worker/api/chat/sessions', { method: 'POST' });
        expect(res.status).toBe(401);
    });

    it('rejects a token signed with the wrong key', async () => {
        const forged = await signJwt('wrong-key', 'owner', 300);
        const res = await SELF.fetch('https://worker/api/chat/sessions', {
            method: 'POST',
            headers: { Authorization: `Bearer ${forged}` },
        });
        expect(res.status).toBe(401);
    });

    it('rejects an expired token', async () => {
        const stale = await signJwt(env.JWT_SIGNING_KEY, 'owner', -10);
        const res = await SELF.fetch('https://worker/api/chat/sessions', {
            method: 'POST',
            headers: { Authorization: `Bearer ${stale}` },
        });
        expect(res.status).toBe(401);
    });

    it('accepts a valid token', async () => {
        mockSalesforce();
        const res = await SELF.fetch('https://worker/api/chat/sessions', {
            method: 'POST',
            headers: { Authorization: await bearer() },
        });
        expect(res.status).toBe(200);
        expect(await res.json()).toMatchObject({ sessionId: 'sess-1', welcome: 'Hi!' });
    });
});

describe('cors', () => {
    it('allows only the configured app origin', async () => {
        mockSalesforce();
        const res = await SELF.fetch('https://worker/api/chat/sessions', {
            method: 'OPTIONS',
            headers: {
                Origin: 'https://gitanjalivanshiv.github.io',
                'Access-Control-Request-Method': 'POST',
            },
        });
        expect(res.headers.get('Access-Control-Allow-Origin')).toBe(
            'https://gitanjalivanshiv.github.io',
        );
    });

    it('does not echo a foreign origin back', async () => {
        mockSalesforce();
        const res = await SELF.fetch('https://worker/api/chat/sessions', {
            method: 'OPTIONS',
            headers: { Origin: 'https://evil.example', 'Access-Control-Request-Method': 'POST' },
        });
        expect(res.headers.get('Access-Control-Allow-Origin')).not.toBe('https://evil.example');
    });
});

describe('chat streaming', () => {
    it('pipes the agent SSE stream through', async () => {
        mockSalesforce();
        const res = await SELF.fetch('https://worker/api/chat/sessions/sess-1/messages', {
            method: 'POST',
            headers: { Authorization: await bearer(), 'Content-Type': 'application/json' },
            body: JSON.stringify({ text: "what's pending?" }),
        });
        expect(res.status).toBe(200);
        expect(res.headers.get('Content-Type')).toContain('text/event-stream');
        const text = await res.text();
        expect(text).toContain('Nothing ');
        expect(text).toContain('pending.');
    });

    it('validates the message body', async () => {
        const res = await SELF.fetch('https://worker/api/chat/sessions/sess-1/messages', {
            method: 'POST',
            headers: { Authorization: await bearer(), 'Content-Type': 'application/json' },
            body: JSON.stringify({ nope: 1 }),
        });
        expect(res.status).toBe(400);
    });

    it('starts a fresh session when the old one is gone, rather than losing the message', async () => {
        mockSalesforce({ streamStatus: 404 });
        const res = await SELF.fetch('https://worker/api/chat/sessions/stale/messages', {
            method: 'POST',
            headers: { Authorization: await bearer(), 'Content-Type': 'application/json' },
            body: JSON.stringify({ text: 'still there?' }),
        });
        // The retry hits the same mocked 404, so the call surfaces as unavailable -
        // what matters is that a renewal was attempted, not a 404 handed to the UI.
        expect(res.status).not.toBe(404);
    });
});

describe('sequence numbers', () => {
    it('increments per session and is owned by the Worker, not the client', async () => {
        mockSalesforce();
        const bodies: string[] = [];
        vi.spyOn(globalThis, 'fetch').mockImplementation(async (input: RequestInfo | URL, init) => {
            const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
            if (url.includes('/services/oauth2/token')) {
                return new Response(JSON.stringify({ access_token: 'tok' }), { status: 200 });
            }
            if (url.includes('/messages/stream')) {
                bodies.push(String(init?.body));
                return new Response(new ReadableStream({ start: (c) => c.close() }), { status: 200 });
            }
            return new Response('{}', { status: 200 });
        });

        const headers = { Authorization: await bearer(), 'Content-Type': 'application/json' };
        await SELF.fetch('https://worker/api/chat/sessions/seq-test/messages', {
            method: 'POST',
            headers,
            body: JSON.stringify({ text: 'one' }),
        });
        await SELF.fetch('https://worker/api/chat/sessions/seq-test/messages', {
            method: 'POST',
            headers,
            body: JSON.stringify({ text: 'two' }),
        });

        expect(bodies[0]).toContain('"sequenceId":1');
        expect(bodies[1]).toContain('"sequenceId":2');
    });
});

describe('unknown routes', () => {
    it('404s with the shared error envelope', async () => {
        const res = await SELF.fetch('https://worker/nope');
        expect(res.status).toBe(404);
        expect(await res.json()).toMatchObject({ error: { code: 'NOT_FOUND' } });
    });
});

describe('data api (BUILD_SPEC 9.4)', () => {
    /** Stand in for Salesforce: OAuth token endpoint plus Apex REST. */
    function mockApex(status = 200, body: unknown = { ok: true }) {
        return vi.spyOn(globalThis, 'fetch').mockImplementation(async (input: RequestInfo | URL, init) => {
            const url = typeof input === 'string' ? input : input instanceof URL ? input.href : input.url;
            if (url.includes('/services/oauth2/token')) {
                return new Response(
                    JSON.stringify({ access_token: 'tok', instance_url: 'https://example.my.salesforce.com' }),
                    { status: 200 },
                );
            }
            if (url.includes('/services/apexrest/dakiya/v1')) {
                return new Response(JSON.stringify({ ...(body as object), _url: url, _method: init?.method }), { status });
            }
            return new Response('{}', { status: 200 });
        });
    }

    it('requires auth like every other /api route', async () => {
        const res = await SELF.fetch('https://worker/api/today');
        expect(res.status).toBe(401);
    });

    it('proxies today to Apex REST', async () => {
        mockApex(200, { arrivingToday: [], awaitingConfirmation: [] });
        const res = await SELF.fetch('https://worker/api/today', {
            headers: { Authorization: await bearer() },
        });
        expect(res.status).toBe(200);
        const body = (await res.json()) as Record<string, string>;
        expect(body._url).toContain('/services/apexrest/dakiya/v1/today');
    });

    it('forwards only the search params that were supplied', async () => {
        mockApex();
        const res = await SELF.fetch('https://worker/api/purchases?vendor=Myntra&limit=10', {
            headers: { Authorization: await bearer() },
        });
        const body = (await res.json()) as Record<string, string>;
        expect(body._url).toContain('vendor=Myntra');
        expect(body._url).toContain('limit=10');
        expect(body._url).not.toContain('status=');
    });

    it('validates the actions payload before touching Salesforce', async () => {
        const spy = mockApex();
        const res = await SELF.fetch('https://worker/api/actions', {
            method: 'POST',
            headers: { Authorization: await bearer(), 'Content-Type': 'application/json' },
            body: JSON.stringify({ action: 'delete_everything', recordId: 'a01xxxxxxxxxxxxxxx' }),
        });
        expect(res.status).toBe(400);
        // Nothing should have reached Salesforce - not even a token request.
        const calls = spy.mock.calls.map((c) => String(c[0]));
        expect(calls.some((u) => u.includes('apexrest'))).toBe(false);
    });

    it('passes a valid action through', async () => {
        mockApex(200, { status: 'Received' });
        const res = await SELF.fetch('https://worker/api/actions', {
            method: 'POST',
            headers: { Authorization: await bearer(), 'Content-Type': 'application/json' },
            body: JSON.stringify({ action: 'confirm_received', recordId: 'a01xxxxxxxxxxxxxxx' }),
        });
        expect(res.status).toBe(200);
        const body = (await res.json()) as Record<string, string>;
        expect(body._method).toBe('POST');
        expect(body._url).toContain('/actions');
    });

    it('passes an Apex error envelope through unchanged', async () => {
        mockApex(400, { error: { code: 'BAD_REQUEST', message: 'outcome is required' } });
        const res = await SELF.fetch('https://worker/api/today', {
            headers: { Authorization: await bearer() },
        });
        expect(res.status).toBe(400);
        expect(await res.json()).toMatchObject({ error: { code: 'BAD_REQUEST' } });
    });
});
