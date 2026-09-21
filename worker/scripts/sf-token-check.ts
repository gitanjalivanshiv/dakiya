/**
 * Proves the External Client App is configured correctly, without printing
 * anything sensitive.
 *
 * Reads SF_CLIENT_ID / SF_CLIENT_SECRET from .dev.vars, asks Salesforce for a
 * client-credentials token, and reports only whether it worked. The token
 * itself is never printed, logged or stored.
 *
 * Usage:  npm run sf:token-check
 */

import { readFileSync } from 'node:fs';
import { join } from 'node:path';

const MY_DOMAIN = process.env.SF_MY_DOMAIN_URL ?? readVar('SF_MY_DOMAIN_URL', false)
    ?? 'https://orgfarm-562b8294cc-dev-ed.develop.my.salesforce.com';

function readVar(name: string, required = true): string | undefined {
    if (process.env[name]) return process.env[name];
    try {
        const raw = readFileSync(join(process.cwd(), '.dev.vars'), 'utf8');
        for (const line of raw.split('\n')) {
            if (line.trim().startsWith('#')) continue;
            const [k, ...rest] = line.split('=');
            if (k?.trim() === name) {
                const v = rest.join('=').trim();
                if (v) return v;
            }
        }
    } catch {
        /* fall through */
    }
    if (required) {
        process.stdout.write(`\nMissing ${name}. Add it to worker/.dev.vars and try again.\n`);
        process.exit(1);
    }
    return undefined;
}

async function main(): Promise<void> {
    const clientId = readVar('SF_CLIENT_ID') as string;
    const clientSecret = readVar('SF_CLIENT_SECRET') as string;

    process.stdout.write(`\nOrg: ${MY_DOMAIN}\n`);
    process.stdout.write(`Consumer key: ...${clientId.slice(-6)} (last 6 shown)\n\n`);

    const res = await fetch(`${MY_DOMAIN}/services/oauth2/token`, {
        method: 'POST',
        headers: { 'Content-Type': 'application/x-www-form-urlencoded' },
        body: new URLSearchParams({
            grant_type: 'client_credentials',
            client_id: clientId,
            client_secret: clientSecret,
        }),
    });

    const body = (await res.json()) as Record<string, string>;

    if (!res.ok) {
        process.stdout.write(`FAILED (HTTP ${res.status})\n`);
        process.stdout.write(`  error: ${body.error ?? '(none)'}\n`);
        process.stdout.write(`  detail: ${body.error_description ?? '(none)'}\n\n`);
        const hints: Record<string, string> = {
            invalid_client: 'Consumer key or secret is wrong, or the app is still propagating (can take a few minutes).',
            invalid_grant: 'Client Credentials Flow is not enabled, or no Run As user is set on the Policies tab.',
            inactive_user: 'The Run As user is inactive.',
            invalid_client_id: 'Consumer key not recognised by this org - check you created the app in trial3.',
        };
        if (body.error && hints[body.error]) process.stdout.write(`  likely cause: ${hints[body.error]}\n\n`);
        process.exit(1);
    }

    // Deliberately never printed: body.access_token
    process.stdout.write('PASS - Salesforce issued a token.\n');
    process.stdout.write(`  instance_url     : ${body.instance_url ?? '(none)'}\n`);
    process.stdout.write(`  api_instance_url : ${body.api_instance_url ?? '(none)'}\n`);
    process.stdout.write(`  token_type       : ${body.token_type ?? '(none)'}\n\n`);
    process.stdout.write('The External Client App, its scopes and its Run As user are all working.\n');
}

main().catch((e: unknown) => {
    process.stdout.write(`\nERROR: ${e instanceof Error ? e.message : String(e)}\n`);
    process.exit(1);
});
