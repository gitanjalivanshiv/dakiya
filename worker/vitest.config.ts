import { defineWorkersConfig } from '@cloudflare/vitest-pool-workers/config';

export default defineWorkersConfig({
    test: {
        poolOptions: {
            workers: {
                wrangler: { configPath: './wrangler.jsonc' },
                miniflare: {
                    // Test-only values. Real secrets live in `wrangler secret put`.
                    bindings: {
                        JWT_SIGNING_KEY: 'test-signing-key-not-a-real-secret',
                        SF_CLIENT_ID: 'test-client-id',
                        SF_CLIENT_SECRET: 'test-client-secret',
                        SF_AGENT_ID: '0XxTEST000000000AAA',
                        APP_ORIGIN: 'https://gitanjalivanshiv.github.io',
                    },
                },
            },
        },
    },
});
