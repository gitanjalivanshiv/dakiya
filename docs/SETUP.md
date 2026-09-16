# Dakiya — Setup progress

The build checklist. **[M]** = manual step done by Gitanjali in a browser / on the phone.
Never record secret values here — only that a secret was set, and where.

**Salesforce org alias: `agentTrial2`** — every `sf` command must use `-o agentTrial2`.

Legend: `[ ]` todo · `[~]` in progress · `[x]` done (date + one-line note)

---

## Phase 0 — Workstation and repo

| | Step | Notes |
|---|---|---|
| [x] | node ≥ 20 | 2026-09-16 · v24.18.0 |
| [x] | npm | 2026-09-16 · 11.16.0 |
| [x] | git | 2026-09-16 · 2.50.1 (Apple Git-155) |
| [x] | sf CLI | 2026-09-16 · 2.145.6 (2.150.6 available, not blocking) |
| [x] | `sf org display -o agentTrial2` | 2026-09-16 · Connected · API 67.0 · Org Id `00DgK00000VebolUAB` |
| [x] | wrangler available | 2026-09-16 · 4.132.0 via `npx` |
| [x] | gh CLI installed | 2026-09-16 · 2.101.0 → `~/.local/bin/gh`, PATH added to `~/.zshrc` (see DECISIONS) |
| [x] | **[M]** `gh auth login` | 2026-09-16 · account `gitanjalivanshiv`, HTTPS, scopes repo+workflow+gist+read:org |
| [x] | git identity configured | 2026-09-16 · repo-local; noreply email so no real address enters public history |
| [ ] | **[M]** Cloudflare account + `npx wrangler login` | |
| [ ] | Public repo `dakiya` created and pushed | |
| [x] | Monorepo scaffold, `.gitignore`, README, docs | 2026-09-16 · dirs + .gitignore + README + SETUP + DECISIONS |

**Recorded values (non-secret)**

| Key | Value |
|---|---|
| `SF_MY_DOMAIN_URL` | `https://orgfarm-a6f4756b11-dev-ed.develop.my.salesforce.com` |
| Salesforce org id | `00DgK00000VebolUAB` |
| Salesforce API version | 67.0 |
| Repo name | `dakiya` |
| GitHub account | `gitanjalivanshiv` |
| Future Pages URL (`APP_ORIGIN` path) | `https://gitanjalivanshiv.github.io/dakiya/` |

✅ **Accept:** repo pushed · `sf org display -o agentTrial2` connected · `wrangler whoami` OK.

---

## Phase 1 — Salesforce foundation

| | Step | Notes |
|---|---|---|
| [ ] | **[M]** Company Information → Time Zone IST, Currency INR | |
| [ ] | **[M]** Storage Usage recorded (⚠️ trial org, verify real limits) | |
| [ ] | SFDX project generated | |
| [ ] | Objects + fields + picklists (§4) | |
| [ ] | `Dakiya_Setting__mdt` + default records | |
| [ ] | Permission sets `Dakiya_User`, `Dakiya_Integration` | |
| [ ] | Tabs + Lightning app "Dakiya" | |
| [ ] | Apex: state machine, matching, parser registry, evidence validator, ingest, queueable, REST | |
| [ ] | Deploy to `agentTrial2` | |
| [ ] | `Dakiya_User` assigned | |

✅ **Accept:** deploy succeeds · Apex tests ≥ 85% · Purchase creatable via Apex REST.

---

## Phase 2 — Agentforce agent

| | Step | Notes |
|---|---|---|
| [ ] | **[M]** Confirm Einstein + Agentforce enabled; record usage allowance | |
| [ ] | Invocable actions (§7) + tests, deployed | |
| [ ] | Custom Agentforce Service Agent "Dakiya" created | |
| [ ] | **[M]** `Dakiya_Integration` assigned to agent user; agent activated | |
| [ ] | Agent ID recorded (18-char, `0Xx…`) | |
| [ ] | Agent metadata retrieved into git | |

✅ **Accept:** 10 core utterances behave correctly in Builder preview, including refusing to invent a tracking number.

---

## Phase 3 — External Client App + Worker skeleton

| | Step | Notes |
|---|---|---|
| [ ] | **[M]** External Client App "Dakiya Gateway" + Client Credentials Flow | |
| [ ] | Consumer key recorded (non-secret) | |
| [ ] | `SF_CLIENT_SECRET` set via separate terminal | |
| [ ] | Worker scaffold (Hono, zod, KV) + `/health` | |
| [ ] | Agent API chat proxy + `npm run chat:smoke` | |

✅ **Accept:** `chat:smoke` streams a reply from `agentTrial2` · `wrangler deploy` works.

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
