# CLAUDE.md — Dakiya (personal parcel, returns & refund tracker)

> "Dakiya" is a working name (Hindi for postman). Rename freely.

## What this project is
A **personal-use** system for one person (Gitanjali, Android user, India, IST, INR) that tracks every online order
(Amazon, Flipkart, Myntra, Nykaa, Instagram sellers, D2C sites), its deliveries, returns and refund *check-ins*.
Salesforce + Agentforce is the brain (Headless 360 style), a Cloudflare Worker is the secure gateway, and a React PWA
on GitHub Pages is the only UI, installed on her phone.

Full design and phase plan: **`docs/BUILD_SPEC.md`**. Read it before any work. Progress/checklist: **`docs/SETUP.md`**
(you create and maintain it).

## Non-negotiables
1. **Salesforce org alias is `agentTrial2`.** Every `sf` command MUST include `-o agentTrial2` (or `--target-org agentTrial2`).
   Never deploy, query or delete against any other org. Run `sf org display -o agentTrial2` at the start of each session
   and stop if it fails.
2. **Public repo, zero secrets in git.** GitHub Pages (free) needs a public repo. No client secrets, tokens, HMAC keys,
   phone numbers, email addresses, real order data or sample messages may ever be committed.
   Keep `.gitignore` covering: `.dev.vars`, `.env*`, `samples/raw/`, `.sfdx/`, `.sf/`, `node_modules/`, `dist/`.
   Before every commit run `git diff --cached` and scan for secrets / personal data; stop and tell the user if found.
3. **The frontend holds no secrets.** The PWA only knows the Worker URL. All Salesforce/Twilio/Anthropic credentials live
   in Worker secrets (`wrangler secret put`) or Apps Script Script Properties.
4. **Accuracy over automation.** Never invent order IDs, tracking numbers, amounts or dates. Every LLM-extracted field needs
   an evidence quote that exists verbatim in the (masked) source text, or it is discarded. When unsure, create a review item and
   ask the user instead of guessing.
5. **Refunds are not tracked against bank data.** The system tracks returns up to "refund initiated" and then *reminds the user
   to check* and record the outcome (full / partial / store credit / not received / replacement).
6. **Verify current docs before implementing platform-specific pieces** (Agent API request shapes, External Client App settings,
   Agentforce DX commands, Prompt Template Apex API, Web Push/WebAuthn libraries on Workers, Twilio). Platforms change; the spec
   marks these with ⚠️VERIFY. If the docs differ from the spec, follow the docs and note the change in `docs/DECISIONS.md`.

## How to guide the user through manual steps (IMPORTANT)
Many steps happen in browser UIs (Salesforce Setup, Cloudflare dashboard, GitHub settings, Google Apps Script, the phone).
The user wants to be walked through them properly. For every manual step:

1. **Say it's manual** and why it can't be automated.
2. Give **numbered, click-by-click instructions** with exact menu names, field names and the exact values to enter.
   Tell the user what they should see if it worked.
3. **One manual step (or one small group) at a time.** Then stop and wait for the user to confirm "done".
4. **Secrets never go into the chat.** If a value is secret (consumer secret, HMAC key, Twilio auth token), tell the user to run
   the command in a **separate terminal**, e.g. `cd worker && npx wrangler secret put SF_CLIENT_SECRET`, and paste it there.
   Non-secret IDs (Agent ID, My Domain URL, consumer key) may be shared in chat.
5. After confirmation, **verify it programmatically** where possible (`sf data query`, `sf org display`, `curl` a health
   endpoint, `wrangler secret list`, `gh api`). If verification fails, troubleshoot before moving on.
6. Tick the step in `docs/SETUP.md` (checklist with date and a one-line note). Never record secret values there.
7. If the user seems stuck, offer the likely causes first (permissions, wrong org, missing scope, caching), not a wall of text.

## Ways of working
- Work **phase by phase** as defined in `docs/BUILD_SPEC.md`. At the start of a phase: short plan + list of manual steps coming up.
  At the end: run the phase's acceptance checks, summarise, commit, and ask before starting the next phase.
- Small, reviewable commits with clear messages. Push to GitHub at the end of each phase (ask first the very first time).
- Prefer boring, well-supported tech. Don't add dependencies without a reason.
- Keep the user's token budget in mind: don't re-read large files needlessly; don't paste huge logs back.
- When a decision deviates from the spec, record it in `docs/DECISIONS.md` (date, decision, reason).

## Repo layout
```
/salesforce     SFDX project (objects, Apex, permission sets, agent metadata, prompt templates)
/worker         Cloudflare Worker (TypeScript, Hono) – gateway, auth, ingest, chat proxy, push, Twilio
/app            React + Vite + TypeScript PWA (GitHub Pages)
/apps-script    Gmail intake script (Code.gs, appsscript.json)
/android        MacroDroid macro setup guide (docs only)
/samples        masked/ fixtures only (raw/ is gitignored)
/docs           BUILD_SPEC.md, SETUP.md, DECISIONS.md, RUNBOOK.md
```

## Commands (fill in as they become real)
- Salesforce deploy: `cd salesforce && sf project deploy start -o agentTrial2`
- Apex tests: `sf apex run test -o agentTrial2 --test-level RunLocalTests --result-format human --code-coverage --wait 20`
- Worker dev/test/deploy: `cd worker && npm run dev | npm test | npx wrangler deploy`
- App dev/test/build: `cd app && npm run dev | npm test | npm run build`
- Extraction accuracy harness: `npm run eval` (see spec §10)

## Conventions
- Time zone **Asia/Kolkata** everywhere user-facing; store UTC datetimes in Salesforce; currency INR (₹, en-IN formatting).
- Salesforce: custom object is `Purchase__c` (NOT `Order__c`, to avoid confusion with the standard Order object).
  Apex: service classes + thin `@RestResource` controllers + `@InvocableMethod` actions; bulk-safe; `with sharing` unless justified;
  test coverage ≥ 85% with meaningful asserts.
- TypeScript strict mode. Validate every external payload with `zod`.
