# Dakiya — Setup progress

The build checklist. **[M]** = manual step done by Gitanjali in a browser / on the phone.
Never record secret values here — only that a secret was set, and where.

**Salesforce org alias: `trial3`** — every `sf` command must use `-o trial3`.

Legend: `[ ]` todo · `[~]` in progress · `[x]` done (date + one-line note)

---

## Phase 0 — Workstation and repo

| | Step | Notes |
|---|---|---|
| [x] | node ≥ 20 | 2026-09-16 · v24.18.0 |
| [x] | npm | 2026-09-16 · 11.16.0 |
| [x] | git | 2026-09-16 · 2.50.1 (Apple Git-155) |
| [x] | sf CLI | 2026-09-16 · 2.145.6 (2.150.6 available, not blocking) |
| [x] | `sf org display -o trial3` | 2026-09-21 · Connected · API 67.0 · Org Id `00DgK00000aAUcnUAG` |
| [x] | wrangler available | 2026-09-16 · 4.132.0 via `npx` |
| [x] | gh CLI installed | 2026-09-16 · 2.101.0 → `~/.local/bin/gh`, PATH added to `~/.zshrc` (see DECISIONS) |
| [x] | **[M]** `gh auth login` | 2026-09-16 · account `gitanjalivanshiv`, HTTPS, scopes repo+workflow+gist+read:org |
| [x] | git identity configured | 2026-09-16 · repo-local; noreply email so no real address enters public history |
| [x] | **[M]** Cloudflare account + `npx wrangler login` | 2026-09-16 · OAuth token in `~/Library/Preferences/.wrangler`; single account (id not committed) |
| [x] | Public repo `dakiya` created and pushed | 2026-09-16 · https://github.com/gitanjalivanshiv/dakiya · public, main, 14 files, leak-scanned |
| [x] | Monorepo scaffold, `.gitignore`, README, docs | 2026-09-16 · dirs + .gitignore + README + SETUP + DECISIONS |

**Recorded values (non-secret)**

| Key | Value |
|---|---|
| `SF_MY_DOMAIN_URL` | `https://orgfarm-562b8294cc-dev-ed.develop.my.salesforce.com` |
| Salesforce org id | `00DgK00000aAUcnUAG` |
| Salesforce API version | 67.0 |
| Einstein Agent User (agent runs as) | `dakiya.agent@trial3.dakiya` |
| Worker URL (`VITE_WORKER_URL`) | `https://dakiya-gateway.gitanjali-mishra.workers.dev` |
| Cloudflare KV namespace | `46048fe901c4437f9527448d587f0496` |
| Repo name | `dakiya` |
| GitHub account | `gitanjalivanshiv` |
| Future Pages URL (`APP_ORIGIN` path) | `https://gitanjalivanshiv.github.io/dakiya/` |

✅ **Accept:** repo pushed · `sf org display -o trial3` connected · `wrangler whoami` OK.

**Phase 0 complete — 2026-09-16.** All 10 acceptance checks pass.

---

## Phase 1 — Salesforce foundation

| | Step | Notes |
|---|---|---|
| [x] | **[M]** Company Information → Time Zone IST, Currency INR | 2026-09-16 · org + user both `Asia/Kolkata` / `en_IN`, verified by query |
| [x] | Storage limits recorded (no manual step needed) | 2026-09-21 · trial3: **DataStorageMB 5 max, 5 remaining** (empty org). Developer Edition confirmed |
| [x] | SFDX project generated | 2026-09-16 · API 67.0, LWC/jest tooling removed |
| [x] | Objects + fields + picklists (§4) | 2026-09-16 · 8 objects, 84 fields |
| [x] | `Dakiya_Setting__mdt` + default records | 2026-09-16 · 14 records (13 from spec + `Extractor`) |
| [x] | Permission sets `Dakiya_User`, `Dakiya_Integration` | 2026-09-16 · 76 field perms each; Integration has no delete on Purchase/Vendor/Return |
| [x] | Tabs + Lightning app "Dakiya" | 2026-09-16 · 7 tabs |
| [x] | Apex: state machine, matching, parser registry, evidence validator, ingest, queueable, REST | 2026-09-18 · 19 classes; LLM path stubbed until Phase 6 |
| [x] | Deploy to `trial3` | 2026-09-18 · 153 components |
| [x] | `Dakiya_User` assigned | 2026-09-16 · **required** — metadata-deployed fields grant FLS to nobody, not even admin (see DECISIONS) |

✅ **Accept:** deploy succeeds · Apex tests ≥ 85% · Purchase creatable via Apex REST.

**Phase 1 complete — 2026-09-18.**
- Deploy: 153/153 components to `trial3`
- Tests: **131 passing, 0 failing**, **89.7%** coverage on Dakiya classes (bar is 85%)
- REST verified live: `POST /purchases` created an order + items and auto-created the vendor;
  `POST /ingest` returned `duplicate:false` then `duplicate:true` for the same key; `/today` and
  `/health` return their full shapes. Smoke-test records deleted afterwards.

**Not yet built (deliberately, per the spec):** vendor rule parsers and the LLM extraction call.
Parsers are written in Phase 6 from real masked samples rather than guessed now; until then every
message falls through to the review queue instead of being guessed at.

---

## Phase 2 — Agentforce agent

| | Step | Notes |
|---|---|---|
| [x] | Agentforce prerequisites confirmed | 2026-09-18 · Einstein Agent User `agent.user.…@agentforce.com` found via API; no manual step needed |
| [x] | Invocable actions (§7) + tests, deployed | 2026-09-18 · 16 actions, 159 tests passing, 88.6% coverage |
| [x] | Custom Agentforce Service Agent "Dakiya" created | 2026-09-18 · Agent Script bundle in git; local compile clean; `sf agent validate` success; deployed as **draft** |
| [x] | **[M]** Einstein Agent User created; `Dakiya_Integration` assigned | 2026-09-21 · `dakiya.agent@trial3.dakiya`, profile Einstein Agent User, + AgentforceServiceAgentUserPsg & SecureBase |
| [ ] | **[M]** **Agent published + activated by Gitanjali** | Claude never publishes or activates (see DECISIONS) |
| [ ] | Agent ID recorded (18-char, `0Xx…`) | |
| [x] | Agent metadata in git | 2026-09-18 · authored in git as source, so nothing to retrieve |

✅ **Accept:** 10 core utterances behave correctly in Builder preview, including refusing to invent a tracking number.

**Phase 2 status — 2026-09-18.** Built and validated; behavioural preview outstanding.
- 16 invocable actions deployed; 159 tests passing, 88.6% coverage
- Agent Script bundle compiles clean locally (0 severity-1) and validates against the org
- Deployed as a **draft**. Publish + activate are Gitanjali's step, by her instruction
- `sf agent preview` needs an interactive TTY, so the 15 use cases in `docs/AGENT_SPEC.md`
  are exercised by her, not by Claude

---

## Phase 3 — External Client App + Worker skeleton

| | Step | Notes |
|---|---|---|
| [x] | **[M]** External Client App "Dakiya Gateway" + Client Credentials Flow | 2026-09-21 · created in trial3; functional verification pending `npm run sf:token-check` |
| [ ] | Consumer key recorded (non-secret) | |
| [ ] | `SF_CLIENT_SECRET` set via separate terminal | |
| [x] | Worker scaffold (Hono, zod, KV) + `/health` | 2026-09-22 · deployed; /health 200, /api/* 401, CORS refuses foreign origins, security headers verified live |
| [ ] | Agent API chat proxy + `npm run chat:smoke` | |

✅ **Accept:** `chat:smoke` streams a reply from `trial3` · `wrangler deploy` works.

---

## Phase 4 — PWA shell + passkey + chat

| | Step | Notes |
|---|---|---|
| [ ] | App scaffold, HashRouter, tab bar, Chat, Settings | |
| [ ] | **[M]** `SETUP_CODE` + `JWT_SIGNING_KEY` generated & set (separate terminal) | |
| [ ] | Worker passkey auth + JWT + CORS | |
| [ ] | GitHub Actions → Pages | |
| [ ] | **[M]** Repo Settings → Pages source = GitHub Actions; var `VITE_WORKER_URL` | |
| [ ] | **[M] Phone:** install PWA, register passkey | |

✅ **Accept:** multi-turn chat from the installed app after fingerprint login · `/api/*` 401 without JWT.

---

## Phase 5 — Today / Orders / Returns + push

| | Step | Notes |
|---|---|---|
| [ ] | Apex REST fully implemented | |
| [ ] | Screens built | |
| [ ] | **[M]** VAPID keys generated, private key set as secret | |
| [ ] | **[M] Phone:** enable notifications | |
| [ ] | Worker cron + `DakiyaScheduler` scheduled | |

✅ **Accept:** test notification arrives within 15 min · "Got it ✅" updates Salesforce.

---

## Phase 6 — Samples, masking and parsers (accuracy)

| | Step | Notes |
|---|---|---|
| [ ] | **[M]** 30–50 real samples collected to `samples/raw/` (gitignored) | |
| [ ] | Masking module + fixtures | |
| [ ] | **[M]** User reviewed masked output before commit | |
| [ ] | Expected JSON labelled | |
| [ ] | Vendor + courier rule parsers | |
| [ ] | `Dakiya_Extract` prompt template + Apex invocation | |
| [ ] | **[M]** Anthropic API key + monthly spend limit | |
| [ ] | `npm run eval` harness | |

✅ **Accept:** §10.5 go-live gate passes — 0 hallucinated IDs, 0 masking leaks.

---

## Phase 7 — Gmail + SMS intake

| | Step | Notes |
|---|---|---|
| [ ] | `/ingest/email` + `/ingest/sms` with tests | |
| [ ] | **[M]** Gmail labels + filters | |
| [ ] | **[M]** Apps Script project + Script Properties + trigger | |
| [ ] | **[M] Phone:** MacroDroid macro + battery exemption | |

✅ **Accept:** a real email and a courier SMS each land correctly within 15 min · OTPs never reach the Worker.

---

## Phase 8 — Shadow week + polish

| | Step | Notes |
|---|---|---|
| [ ] | 7-day shadow run | |
| [ ] | Retention jobs verified | |
| [ ] | `docs/RUNBOOK.md` written | |
| [ ] | Security checklist §13 passed | |

---

## Phase 9 — Twilio WhatsApp showcase (optional)

| | Step | Notes |
|---|---|---|
| [ ] | **[M]** Twilio sandbox join + webhook | |
| [ ] | `/twilio/whatsapp` implemented | |

---

## Secrets register (names only — never values)

| Secret | Lives in | Set? |
|---|---|---|
| `SF_CLIENT_ID` | Worker (non-secret, but stored as secret) | [ ] |
| `SF_CLIENT_SECRET` | Worker secret | [ ] |
| `EMAIL_HMAC_SECRET` | Worker secret + Apps Script property | [ ] |
| `SMS_INGEST_TOKEN` | Worker secret + MacroDroid | [ ] |
| `JWT_SIGNING_KEY` | Worker secret | [ ] |
| `SETUP_CODE` | Worker secret | [ ] |
| `VAPID_PUBLIC_KEY` / `VAPID_PRIVATE_KEY` | Worker | [ ] |
| `ANTHROPIC_API_KEY` | Worker secret | [ ] |
| `TWILIO_ACCOUNT_SID` / `TWILIO_AUTH_TOKEN` | Worker secret | [ ] |
