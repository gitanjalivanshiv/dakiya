/**
 * Minimal HS256 JWT over WebCrypto (BUILD_SPEC section 9.3).
 *
 * Hand-rolled rather than pulled from npm: this needs two functions, runs on the
 * Workers runtime where many JWT libraries do not, and a dependency that can
 * reach a signing key is a dependency worth not having.
 */

interface Payload {
    sub: string;
    iat: number;
    exp: number;
}

const encoder = new TextEncoder();

function b64url(bytes: Uint8Array): string {
    let binary = '';
    for (const b of bytes) binary += String.fromCharCode(b);
    return btoa(binary).replace(/\+/g, '-').replace(/\//g, '_').replace(/=+$/, '');
}

function b64urlDecode(s: string): Uint8Array {
    const padded = s.replace(/-/g, '+').replace(/_/g, '/').padEnd(Math.ceil(s.length / 4) * 4, '=');
    const binary = atob(padded);
    return Uint8Array.from(binary, (c) => c.charCodeAt(0));
}

async function key(secret: string): Promise<CryptoKey> {
    return crypto.subtle.importKey(
        'raw',
        encoder.encode(secret),
        { name: 'HMAC', hash: 'SHA-256' },
        false,
        ['sign', 'verify'],
    );
}

export async function signJwt(secret: string, sub: string, ttlSeconds: number): Promise<string> {
    const now = Math.floor(Date.now() / 1000);
    const payload: Payload = { sub, iat: now, exp: now + ttlSeconds };
    const head = b64url(encoder.encode(JSON.stringify({ alg: 'HS256', typ: 'JWT' })));
    const body = b64url(encoder.encode(JSON.stringify(payload)));
    const data = `${head}.${body}`;
    const sig = await crypto.subtle.sign('HMAC', await key(secret), encoder.encode(data));
    return `${data}.${b64url(new Uint8Array(sig))}`;
}

/** Returns the subject, or null for anything that does not verify. */
export async function verifyJwt(secret: string, token: string): Promise<string | null> {
    const parts = token.split('.');
    if (parts.length !== 3) return null;
    const [head, body, sig] = parts as [string, string, string];

    let valid: boolean;
    try {
        // crypto.subtle.verify is constant-time, so no manual comparison here.
        valid = await crypto.subtle.verify(
            'HMAC',
            await key(secret),
            b64urlDecode(sig),
            encoder.encode(`${head}.${body}`),
        );
    } catch {
        return null;
    }
    if (!valid) return null;

    try {
        const payload = JSON.parse(new TextDecoder().decode(b64urlDecode(body))) as Payload;
        if (typeof payload.exp !== 'number' || payload.exp <= Math.floor(Date.now() / 1000)) {
            return null;
        }
        return payload.sub ?? null;
    } catch {
        return null;
    }
}
