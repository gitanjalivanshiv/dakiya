import { describe, expect, it } from 'vitest';
import { signJwt, verifyJwt } from '../src/lib/jwt';

const SECRET = 'a-test-signing-key';

describe('jwt', () => {
    it('round-trips a token', async () => {
        const token = await signJwt(SECRET, 'owner', 60);
        expect(await verifyJwt(SECRET, token)).toBe('owner');
    });

    it('rejects a token signed with a different key', async () => {
        const token = await signJwt('someone-elses-key', 'owner', 60);
        expect(await verifyJwt(SECRET, token)).toBeNull();
    });

    it('rejects a tampered payload', async () => {
        const token = await signJwt(SECRET, 'owner', 60);
        const [head, , sig] = token.split('.');
        const forged = btoa(JSON.stringify({ sub: 'attacker', iat: 1, exp: 9999999999 }))
            .replace(/\+/g, '-')
            .replace(/\//g, '_')
            .replace(/=+$/, '');
        expect(await verifyJwt(SECRET, `${head}.${forged}.${sig}`)).toBeNull();
    });

    it('rejects an expired token', async () => {
        const token = await signJwt(SECRET, 'owner', -1);
        expect(await verifyJwt(SECRET, token)).toBeNull();
    });

    it('rejects malformed input without throwing', async () => {
        for (const bad of ['', 'not-a-jwt', 'a.b', 'a.b.c.d', '...']) {
            expect(await verifyJwt(SECRET, bad)).toBeNull();
        }
    });
});
