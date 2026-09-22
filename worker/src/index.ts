import { Hono } from 'hono';
import { cors } from 'hono/cors';
import { z } from 'zod';
import type { Env } from './env';
import { verifyJwt } from './lib/jwt';
import {
    AgentApiError,
    createSession,
    endSession,
    isSessionGone,
    nextSequence,
    sendMessageStream,
} from './lib/agent-api';
import { proxy, queryString } from './lib/apex-rest';

const app = new Hono<{ Bindings: Env; Variables: { sub: string } }>();

// ── CORS: exactly one origin, and only for the browser API ────────────
app.use('/api/*', async (c, next) =>
    cors({
        origin: c.env.APP_ORIGIN,
        allowHeaders: ['Content-Type', 'Authorization'],
        allowMethods: ['GET', 'POST', 'DELETE', 'OPTIONS'],
        maxAge: 86400,
    })(c, next),
);

// ── Security headers on everything ────────────────────────────────────
app.use('*', async (c, next) => {
    await next();
    c.header('X-Content-Type-Options', 'nosniff');
    c.header('Referrer-Policy', 'no-referrer');
    c.header('X-Frame-Options', 'DENY');
    c.header('Permissions-Policy', 'geolocation=(), microphone=(), camera=()');
});

// ── Auth: every /api/* needs a valid bearer JWT ───────────────────────
app.use('/api/*', async (c, next) => {
    const header = c.req.header('Authorization') ?? '';
    const token = header.startsWith('Bearer ') ? header.slice(7) : '';
    if (!token) {
        return c.json({ error: { code: 'UNAUTHORIZED', message: 'Missing bearer token' } }, 401);
    }
    const sub = await verifyJwt(c.env.JWT_SIGNING_KEY, token);
    if (!sub) {
        return c.json({ error: { code: 'UNAUTHORIZED', message: 'Invalid or expired token' } }, 401);
    }
    c.set('sub', sub);
    await next();
});

/**
 * Health is public and deliberately says nothing useful to a stranger
 * (BUILD_SPEC section 9.4).
 */
app.get('/health', (c) => c.json({ ok: true }));

// ── Data API (BUILD_SPEC 9.4) - everything the app reads or changes ───
// Thin pass-through to Apex REST. Shapes live in Apex so the app and the agent
// can never disagree about what "pending" means.

app.get('/api/today', (c) => proxy(c.env, 'GET', '/today'));

app.get('/api/purchases', (c) => {
    const q = c.req.query();
    return proxy(c.env, 'GET', '/purchases' + queryString({
        status: q.status, vendor: q.vendor, q: q.q, limit: q.limit, offset: q.offset,
    }));
});

app.get('/api/purchases/:id', (c) => proxy(c.env, 'GET', `/purchases/${c.req.param('id')}`));

app.post('/api/purchases', async (c) =>
    proxy(c.env, 'POST', '/purchases', await c.req.json().catch(() => ({}))));

app.get('/api/returns', (c) =>
    proxy(c.env, 'GET', '/returns' + queryString({ open: c.req.query('open') })));

app.get('/api/vendors', (c) => proxy(c.env, 'GET', '/vendors'));

const actionSchema = z.object({
    action: z.enum(['confirm_received', 'not_received', 'refund_outcome', 'resolve_review', 'snooze']),
    recordId: z.string().min(15).max(18),
    payload: z.record(z.unknown()).optional(),
});

app.post('/api/actions', async (c) => {
    const parsed = actionSchema.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) {
        return c.json({
            error: { code: 'BAD_REQUEST', message: 'action and recordId are required' },
        }, 400);
    }
    return proxy(c.env, 'POST', '/actions', parsed.data);
});

app.get('/api/health/salesforce', (c) => proxy(c.env, 'GET', '/health'));

// ── Chat proxy (BUILD_SPEC 9.2) ───────────────────────────────────────

app.post('/api/chat/sessions', async (c) => {
    try {
        const session = await createSession(c.env, crypto.randomUUID());
        return c.json(session);
    } catch (e) {
        return agentError(c, e);
    }
});

const messageSchema = z.object({
    text: z.string().min(1).max(4000),
});

app.post('/api/chat/sessions/:id/messages', async (c) => {
    const sessionId = c.req.param('id');

    const parsed = messageSchema.safeParse(await c.req.json().catch(() => null));
    if (!parsed.success) {
        return c.json({ error: { code: 'BAD_REQUEST', message: 'text is required (1-4000 chars)' } }, 400);
    }

    try {
        const seq = await nextSequence(c.env, sessionId);
        let upstream = await sendMessageStream(c.env, sessionId, parsed.data.text, seq);

        // An expired session is the normal case after a while, not an error.
        // Start a fresh one and tell the UI, so it can show a quiet divider
        // rather than losing the user's message.
        if (isSessionGone(upstream.status)) {
            const fresh = await createSession(c.env, crypto.randomUUID());
            const freshSeq = await nextSequence(c.env, fresh.sessionId);
            upstream = await sendMessageStream(c.env, fresh.sessionId, parsed.data.text, freshSeq);
            if (!upstream.ok || !upstream.body) {
                return agentError(c, new AgentApiError('Agent did not respond', upstream.status));
            }
            return new Response(upstream.body, {
                status: 200,
                headers: sseHeaders({ sessionRenewed: 'true', sessionId: fresh.sessionId }),
            });
        }

        if (!upstream.ok || !upstream.body) {
            const body = await upstream.text().catch(() => undefined);
            return agentError(c, new AgentApiError('Agent did not respond', upstream.status, body));
        }

        return new Response(upstream.body, { status: 200, headers: sseHeaders() });
    } catch (e) {
        return agentError(c, e);
    }
});

app.delete('/api/chat/sessions/:id', async (c) => {
    try {
        await endSession(c.env, c.req.param('id'));
        return c.json({ ended: true });
    } catch (e) {
        return agentError(c, e);
    }
});

function sseHeaders(extra: Record<string, string> = {}): Record<string, string> {
    return {
        'Content-Type': 'text/event-stream',
        'Cache-Control': 'no-cache, no-store',
        Connection: 'keep-alive',
        // Cloudflare and some proxies buffer by default; streaming needs this off.
        'X-Accel-Buffering': 'no',
        ...extra,
    };
}

// eslint-disable-next-line @typescript-eslint/no-explicit-any
function agentError(c: any, e: unknown) {
    if (e instanceof AgentApiError) {
        // 503 means "not wired up yet" (no agent id); everything else is upstream.
        const status = e.status === 503 ? 503 : 502;
        return c.json({ error: { code: 'AGENT_UNAVAILABLE', message: e.message } }, status);
    }
    const message = e instanceof Error ? e.message : 'Unknown error';
    return c.json({ error: { code: 'INTERNAL', message } }, 500);
}

app.notFound((c) => c.json({ error: { code: 'NOT_FOUND', message: 'No such route' } }, 404));

export default app;
