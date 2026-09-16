# How to start

1. Create an empty folder on your computer, e.g. `dakiya`.
2. Put `CLAUDE.md` in its root and `BUILD_SPEC.md` inside a `docs/` subfolder (keep this file too, or delete it).
3. Open a terminal in that folder and run `claude`.
4. Paste the prompt below as your first message.
5. Keep a **second terminal** open in the same folder. Claude will ask you to type secrets there, never in the chat.

---

## Prompt to paste into Claude Code

```
We're starting the Dakiya build from scratch. This is a personal-use parcel, returns and refund-reminder system for me
(Android user, India). Salesforce + Agentforce is the brain (Headless 360 style), a Cloudflare Worker is the secure gateway,
and a React PWA on GitHub Pages is the UI installed on my phone. Twilio WhatsApp comes later, as a demo only.

Before doing anything:
1. Read CLAUDE.md and docs/BUILD_SPEC.md fully. They are the source of truth.
2. My Salesforce org alias is agentTrial2. Run `sf org display -o agentTrial2` and confirm it's connected. Use
   `-o agentTrial2` on every sf command and never touch any other org.
3. Check my workstation for Phase 0 (node ≥ 20, git, gh auth, sf CLI, wrangler) and tell me what's missing.
4. For each ⚠️VERIFY item in the phase you're about to do, check the current official docs first. If the docs differ
   from the spec, follow the docs and log it in docs/DECISIONS.md.

How I want to work:
- Go phase by phase (Phase 0 → 9 in the spec). At the start of each phase, give me a short plan and list the manual steps
  coming up. At the end, run the acceptance checks, update docs/SETUP.md, commit, and ask me before pushing or starting
  the next phase.
- I need proper guidance on every manual step (Salesforce Setup, Agentforce Builder, Cloudflare, GitHub settings, Gmail,
  Apps Script, MacroDroid and installing the app on my phone):
  • tell me it's manual and why
  • give numbered, click-by-click instructions with exact menu names, field names and values
  • tell me what I should see if it worked
  • give me one step at a time, then wait for me to say "done"
  • verify it yourself afterwards with a command wherever possible
- Never ask me to paste secrets (client secret, HMAC keys, tokens, API keys) into this chat. Give me the exact command to
  run in my second terminal instead. IDs like the Agent ID or consumer key are fine to share.
- The repo will be public (free GitHub Pages). Never commit secrets, personal data or raw sample messages. Check the staged
  diff before every commit.
- Accuracy is the top priority: no invented order IDs, tracking numbers, amounts or dates. Evidence-checked extraction and a
  review queue whenever you're unsure.
- Be mindful of my token budget. Keep your explanations tight and don't dump long logs.

Start with Phase 0 now: check the workstation, then help me create the public GitHub repo (suggest a name and confirm it
with me) and scaffold the monorepo structure from CLAUDE.md.
```

---

## Handy follow-up prompts

- **Resume a later session:** `Read CLAUDE.md, docs/BUILD_SPEC.md, docs/SETUP.md and docs/DECISIONS.md. Tell me where we are and continue with the next unchecked step.`
- **Stuck on a manual step:** `I'm stuck on <step>. Here's what I see: <describe/screenshot>. Walk me through it again, starting from where I am.`
- **Report a wrong extraction:** `This message was handled wrong: <paste masked text>. Expected: <what should have happened>. Add it as a fixture, fix it, and rerun the eval.`
- **Phase check:** `Run the acceptance checks and the §13 security checklist for the current phase and give me a pass/fail table.`
