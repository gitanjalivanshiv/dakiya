# Dakiya 📮

A personal parcel, returns and refund-reminder system for one person.

Dakiya (Hindi: *postman*) captures every online order from email, SMS and the Android share
sheet, keeps one timeline per order (placed → shipped → delivered → **confirmed received**),
tracks returns up to "refund initiated", and then reminds you to check whether the refund
actually landed.

> **Personal project.** Single-user by design. No multi-tenancy, no sign-up, no product.

## Architecture

| Layer | Tech | Role |
|---|---|---|
| Brain | Salesforce + Agentforce (Headless 360) | Data model, extraction, state machine, scheduled reminders, conversational agent |
| Gateway | Cloudflare Worker (TypeScript + Hono) | Auth, intake verification, PII masking, Agent API proxy, Web Push |
| UI | React + Vite PWA on GitHub Pages | Chat, Today, Orders, Returns — installed on an Android phone |
| Intake | Google Apps Script (Gmail) · MacroDroid (SMS) · PWA share target | Automatic capture |

The Worker exists because GitHub Pages is static and public and therefore cannot hold the
Salesforce client secret. **No credential of any kind lives in this repo or in the frontend.**

## Repo layout

```
salesforce/    SFDX project — objects, Apex, permission sets, agent metadata, prompt templates
worker/        Cloudflare Worker — gateway, auth, ingest, chat proxy, push, Twilio
app/           React + Vite + TypeScript PWA (GitHub Pages)
apps-script/   Gmail intake script (Code.gs, appsscript.json)
android/       MacroDroid macro setup guide (docs only)
samples/       masked/ + expected/ fixtures only — raw/ is gitignored
docs/          BUILD_SPEC.md · SETUP.md · DECISIONS.md · RUNBOOK.md
```

## Docs

- **[docs/BUILD_SPEC.md](docs/BUILD_SPEC.md)** — full design and phase plan (the source of truth)
- **[docs/SETUP.md](docs/SETUP.md)** — build progress and the manual-step checklist
- **[docs/DECISIONS.md](docs/DECISIONS.md)** — decisions that deviate from the spec, and why

## Security

This repo is public so that GitHub Pages can host the PWA for free. Therefore:

- No secrets, tokens, API keys or HMAC secrets are ever committed. They live in Cloudflare
  Worker secrets and Apps Script Script Properties.
- No personal data: no real order data, phone numbers, email addresses or raw messages.
  `samples/raw/` is gitignored; only **masked** fixtures are committed, after human review.
- The PWA knows exactly one thing: the Worker URL.

## Design principles

1. **Accuracy over automation.** Every LLM-extracted field needs an evidence quote that exists
   verbatim in the source text, or it is discarded. When unsure, the system asks instead of guessing.
2. **Refunds are reminders, not reconciliation.** Dakiya never touches bank data. It tracks a
   return to "refund initiated" and then reminds you to check and record the outcome yourself.
3. **Boring, well-supported tech.** Few dependencies, each with a reason.

## Licence

Personal project, no licence granted. Read it, learn from it, but it is built for one person.
