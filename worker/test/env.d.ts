import type { Env } from '../src/env';

// Tell cloudflare:test that the bindings it hands back are our Env, so tests can
// read env.JWT_SIGNING_KEY without casting.
declare module 'cloudflare:test' {
    interface ProvidedEnv extends Env {}
}
