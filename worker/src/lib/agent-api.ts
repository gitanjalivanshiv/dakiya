import type { Env } from '../env';
import { withToken, type SalesforceToken } from './sf-auth';

/**
 * Agentforce Agent API client (BUILD_SPEC section 9.2).
 *
 * Shapes verified against the current Agent API docs on 2026-09-18; see
 * docs/DECISIONS.md. Everything Agent-API-specific is confined to this file, so
 * a platform change is a one-file fix rather than a hunt.
 */

const AGENT_API_BASE = 'https://api.salesforce.com/einstein/ai-agent/v1';

export class AgentApiError extends Error {
    constructor(
        message: string,
        readonly status: number,
        readonly body?: string,
    ) {
        super(message);
        this.name = 'AgentApiError';
    }
}

export interface StartedSession {
    sessionId: string;
    /** The agent's opening line, when it sends one. */
    welcome?: string;
}

/** True when Salesforce is telling us the session no longer exists. */
export function isSessionGone(status: number): boolean {
    return status === 404 || status === 422;
}

export async function createSession(env: Env, externalSessionKey: string): Promise<StartedSession> {
    if (!env.SF_AGENT_ID) {
        throw new AgentApiError(
            'SF_AGENT_ID is not set - publish and activate the agent, then set the var',
            503,
        );
    }

    const res = await withToken(env, (token: SalesforceToken) =>
        fetch(`${AGENT_API_BASE}/agents/${env.SF_AGENT_ID}/sessions`, {
            method: 'POST',
            headers: {
                Authorization: `Bearer ${token.accessToken}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({
                externalSessionKey,
                instanceConfig: { endpoint: env.SF_MY_DOMAIN_URL },
                streamingCapabilities: { chunkTypes: ['Text'] },
                // Run as the agent's own user rather than the token's user, so the
                // agent's permissions are what govern every action.
                bypassUser: true,
            }),
        }),
    );

    const text = await res.text();
    if (!res.ok) {
        throw new AgentApiError('Could not start an agent session', res.status, text);
    }

    const json = JSON.parse(text) as {
        sessionId?: string;
        messages?: Array<{ message?: string; text?: string }>;
    };
    if (!json.sessionId) {
        throw new AgentApiError('Session response had no sessionId', 502, text);
    }

    const first = json.messages?.[0];
    const welcome = first?.message ?? first?.text;
    return { sessionId: json.sessionId, ...(welcome ? { welcome } : {}) };
}

/**
 * Send a message and return the raw SSE response for the caller to pipe.
 *
 * The body is not read here: holding the whole reply before forwarding it would
 * defeat streaming, which is the only thing that makes the agent feel quick.
 */
export async function sendMessageStream(
    env: Env,
    sessionId: string,
    text: string,
    sequenceId: number,
): Promise<Response> {
    return withToken(env, (token: SalesforceToken) =>
        fetch(`${AGENT_API_BASE}/sessions/${sessionId}/messages/stream`, {
            method: 'POST',
            headers: {
                Authorization: `Bearer ${token.accessToken}`,
                'Content-Type': 'application/json',
                Accept: 'text/event-stream',
            },
            body: JSON.stringify({ message: { sequenceId, type: 'Text', text } }),
        }),
    );
}

/** Non-streaming variant, used by the Twilio path in Phase 9. */
export async function sendMessage(
    env: Env,
    sessionId: string,
    text: string,
    sequenceId: number,
): Promise<Response> {
    return withToken(env, (token: SalesforceToken) =>
        fetch(`${AGENT_API_BASE}/sessions/${sessionId}/messages`, {
            method: 'POST',
            headers: {
                Authorization: `Bearer ${token.accessToken}`,
                'Content-Type': 'application/json',
            },
            body: JSON.stringify({ message: { sequenceId, type: 'Text', text } }),
        }),
    );
}

export async function endSession(env: Env, sessionId: string): Promise<void> {
    await withToken(env, (token: SalesforceToken) =>
        fetch(`${AGENT_API_BASE}/sessions/${sessionId}`, {
            method: 'DELETE',
            headers: {
                Authorization: `Bearer ${token.accessToken}`,
                'x-session-end-reason': 'UserRequest',
            },
        }),
    );
    await clearSequence(env, sessionId);
}

// ── sequence numbers ──────────────────────────────────────────────────
// The Agent API wants a sequence id that increases within a session. The PWA is
// not trusted to supply it, so the Worker owns the counter.

const seqKey = (sessionId: string) => `chat:seq:${sessionId}`;
/** Sessions are short-lived; 24h is generous and keeps KV tidy. */
const SEQ_TTL_SECONDS = 86400;

export async function nextSequence(env: Env, sessionId: string): Promise<number> {
    const current = await env.DAKIYA_KV.get(seqKey(sessionId));
    const next = current ? Number.parseInt(current, 10) + 1 : 1;
    await env.DAKIYA_KV.put(seqKey(sessionId), String(next), {
        expirationTtl: SEQ_TTL_SECONDS,
    });
    return Number.isFinite(next) ? next : 1;
}

export async function clearSequence(env: Env, sessionId: string): Promise<void> {
    await env.DAKIYA_KV.delete(seqKey(sessionId));
}
