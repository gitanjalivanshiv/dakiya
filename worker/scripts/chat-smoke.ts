/**
 * End-to-end smoke test: start a session, send one message, print the stream.
 *
 * Talks to the Worker rather than to Salesforce directly, so it exercises the
 * real path the PWA will use - including the auth guard.
 *
 * Usage:
 *   npx wrangler dev                 # in one terminal
 *   npm run chat:smoke               # in another
 *   npm run chat:smoke -- "where is my Myntra order?"
 *
 * Against the deployed Worker:
 *   WORKER_URL=https://dakiya-gateway.<subdomain>.workers.dev npm run chat:smoke
 */

import { createHmac } from 'node:crypto';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const WORKER_URL = process.env.WORKER_URL ?? 'http://localhost:8787';
const utterance = process.argv.slice(2).join(' ') || "what's pending?";

function devVar(name: string): string {
    if (process.env[name]) return process.env[name] as string;
    try {
        const raw = readFileSync(join(process.cwd(), '.dev.vars'), 'utf8');
        for (const line of raw.split('\n')) {
            const [k, ...rest] = line.split('=');
            if (k?.trim() === name) return rest.join('=').trim();
        }
    } catch {
        /* no .dev.vars: fall through to the error below */
    }
    throw new Error(
        `${name} not found. Set it in worker/.dev.vars or pass it as an environment variable.`,
    );
}

/** Mint the same HS256 token the PWA will get after passkey login. */
function mintToken(secret: string): string {
    const b64 = (o: unknown) => Buffer.from(JSON.stringify(o)).toString('base64url');
    const now = Math.floor(Date.now() / 1000);
    const data = `${b64({ alg: 'HS256', typ: 'JWT' })}.${b64({ sub: 'owner', iat: now, exp: now + 300 })}`;
    const sig = createHmac('sha256', secret).update(data).digest('base64url');
    return `${data}.${sig}`;
}

async function main(): Promise<void> {
    const token = mintToken(devVar('JWT_SIGNING_KEY'));
    const auth = { Authorization: `Bearer ${token}`, 'Content-Type': 'application/json' };

    process.stdout.write(`\nWorker: ${WORKER_URL}\n`);

    const health = await fetch(`${WORKER_URL}/health`);
    process.stdout.write(`health: ${health.status} ${await health.text()}\n`);

    const guard = await fetch(`${WORKER_URL}/api/chat/sessions`, { method: 'POST' });
    process.stdout.write(
        `auth guard (no token): ${guard.status}${guard.status === 401 ? ' OK' : ' EXPECTED 401'}\n`,
    );

    process.stdout.write('\nstarting session...\n');
    const sessionRes = await fetch(`${WORKER_URL}/api/chat/sessions`, {
        method: 'POST',
        headers: auth,
    });
    const sessionBody = await sessionRes.text();
    if (!sessionRes.ok) {
        process.stdout.write(`FAILED (${sessionRes.status}): ${sessionBody}\n`);
        process.exit(1);
    }
    const { sessionId, welcome } = JSON.parse(sessionBody) as {
        sessionId: string;
        welcome?: string;
    };
    process.stdout.write(`session: ${sessionId}\n`);
    if (welcome) process.stdout.write(`agent: ${welcome}\n`);

    process.stdout.write(`\nyou: ${utterance}\nagent: `);
    const streamRes = await fetch(`${WORKER_URL}/api/chat/sessions/${sessionId}/messages`, {
        method: 'POST',
        headers: auth,
        body: JSON.stringify({ text: utterance }),
    });

    if (!streamRes.ok || !streamRes.body) {
        process.stdout.write(`\nFAILED (${streamRes.status}): ${await streamRes.text()}\n`);
        process.exit(1);
    }
    if (streamRes.headers.get('sessionRenewed') === 'true') {
        process.stdout.write('[session was renewed] ');
    }

    const reader = streamRes.body.getReader();
    const decoder = new TextDecoder();
    let sawAnything = false;
    for (;;) {
        const { done, value } = await reader.read();
        if (done) break;
        sawAnything = true;
        process.stdout.write(decoder.decode(value, { stream: true }));
    }

    process.stdout.write('\n\n');
    await fetch(`${WORKER_URL}/api/chat/sessions/${sessionId}`, {
        method: 'DELETE',
        headers: auth,
    });
    process.stdout.write(sawAnything ? 'PASS: streamed a reply\n' : 'FAIL: stream was empty\n');
    process.exit(sawAnything ? 0 : 1);
}

main().catch((e: unknown) => {
    process.stdout.write(`\nERROR: ${e instanceof Error ? e.message : String(e)}\n`);
    process.exit(1);
});
