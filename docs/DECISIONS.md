# Decisions

Anything that deviates from `BUILD_SPEC.md`, with the date and the reason.
Newest last.

---

## 2026-09-16 — Salesforce org alias is `agentTrial2`, not `agentTrail2`

**Decision.** The org alias used for every `sf` command is **`agentTrial2`**.

**Reason.** `sf org display -o agentTrail2` failed with `NamedOrgNotFoundError`. The authenticated
org list contains `agentTrial2` (Org Id
`00DgK00000VebolUAB`, Connected) — "Trial", not "Trail". Confirmed with the user that the spec
contained a typo. `CLAUDE.md`, `docs/BUILD_SPEC.md` and `KICKOFF_PROMPT.md` were corrected.

---

## 2026-09-16 — Storage assumption checked, and my trial-org caveat was wrong

**Decision.** The spec's §3 storage constraint stands as written. Retention (§8.6) is load-bearing.

**Reason.** I initially assumed the `@agentforce.com` username meant this was not a classic
Developer Edition, and logged a caveat saying so. That was wrong. `SELECT OrganizationType FROM
Organization` returns **`Developer Edition`**, and the limits API confirms
**`DataStorageMB` max 5, with 2 remaining** — about 3 MB already consumed. At the ~2 KB per record
Salesforce charges, that is roughly **1,000 records of total headroom**, which is tighter than the
spec anticipated. Both ⚠️VERIFY items in §3 were answered from the API, so no manual
Setup → Storage Usage step was needed.

**Consequence.** `RawBodyRetentionDays` and the §8.6 purges are not optional tidiness; the weekly
storage check in the spec should alert well before the limit. Phase 5 should verify the retention
job actually reclaims space.

## 2026-09-16 — `gh` CLI installed from the official release tarball, not Homebrew

**Decision.** `gh` 2.101.0 installed to `~/.local/bin/gh` from
`github.com/cli/cli/releases/download/v2.101.0/gh_2.101.0_macOS_arm64.zip`.
`export PATH="$HOME/.local/bin:$PATH"` appended to `~/.zshrc`.

**Reason.** The workstation has no Homebrew. A full Homebrew install needs the user's password and
several minutes, and is not otherwise required by this project. The official release tarball needs
no sudo. `gh` is preferred over a bare SSH key because `gh auth login` also configures the git
credential helper, and later phases use `gh api` / `gh repo view` to verify manual GitHub steps
(Pages source, repo variables) programmatically.

---

## 2026-09-18 — Master-detail fields must never ride along into an update

**Decision.** Code that updates `Shipment__c` or `Purchase_Item__c` constructs a narrow SObject
(`new Shipment__c(Id = ..., <only the fields being changed>)`) instead of updating a record that was
loaded with its master-detail field.

**Reason.** `Shipment__c.Purchase__c` is a non-reparentable master-detail field, so
`isUpdateable()` is **false**. Updating a queried record that carries it fails with
`Operation failed due to fields being inaccessible on Sobject Shipment__c`, naming `Purchase__c`.
This is not a permissions gap — the permission set is correct, and master-detail fields cannot carry
`fieldPermissions` at all. Applies to `DakiyaActionService` and `DakiyaEventApplier`.

---

## 2026-09-18 — Field-level security is not granted by a metadata deploy

**Decision.** `Dakiya_User` must be assigned before anyone, including the System Administrator, can
read or write the custom fields. Recorded in `SETUP.md` as a required step, not an optional one.

**Reason.** Fields created through the Metadata API grant FLS to no profile, unlike fields created
in Setup where the creating admin gets access automatically. Every REST test failed with
"fields being inaccessible" until `sf org assign permset -n Dakiya_User` was run. Anyone rebuilding
this org from git will hit the same wall, so it belongs in the runbook.

---

## 2026-09-18 — Three small data-model deviations from the spec

**Decisions and reasons:**

1. `Return__c.Type__c` uses **"Exchange or Replacement"**, not the spec's "Exchange/Replacement" —
   keeps a slash out of a picklist API name.
2. `Dakiya_Setting__mdt` has a **14th record, `Extractor`** (default `PromptTemplate`). §5.4
   references `Dakiya_Setting__mdt.Extractor` to select the LLM path, but §4.9 omitted it from the
   key list.
3. **`Not Received` (65) and `Cancelled` (95) were given status ranks.** §6 ranks only the nine
   happy-path statuses, but the forward-only rule needs a rank for every value or these two would
   rank 0 and any later event could regress out of them. Not Received sits just above
   Delivered (Unconfirmed) because it is a decision about that delivery; Cancelled is terminal.

---

## 2026-09-18 — The agent is built with Agent Script, not clicked together in Builder

**Decision.** "Dakiya" is authored as an `AiAuthoringBundle` (`Dakiya.agent` + `Dakiya.bundle-meta.xml`)
and deployed from source, rather than built by hand in Agentforce Builder.

**Reason.** §7 of the spec allowed either ("Build with Agentforce DX if available in the user's CLI,
otherwise guide the user through Agentforce Builder"). `sf agent` is available and complete in this
CLI, so the agent lives in git, is diffable, compiles locally, and can be rebuilt if the org is lost -
none of which is true of a UI-built agent. It also removes roughly an hour of click-by-click steps.

---

## 2026-09-18 — `default_agent_user` lives in `access:`, not `config:`

**Decision.** The bundle uses a top-level `access:` block. `agent_type: "AgentforceServiceAgent"` is
also set explicitly.

**Reason.** The CLI scaffold still emits `config.default_agent_user`, but the Agent Script compiler
flags it: *"deprecated: Property default_agent_user has moved from config to access."* The `access:`
form was then confirmed against the org itself - `sf agent validate authoring-bundle -o agentTrial2`
returns success - so this is not just a local-compiler preference.

---

## 2026-09-18 — No escalation subagent

**Decision.** The scaffolded `escalation` subagent and its `@utils.escalate` action were removed.

**Reason.** Escalation hands a conversation to a human support agent. Dakiya is one person's private
tracker; there is nobody to escalate to. An agent offering to "transfer you to an agent" would be
misleading. Off-topic and ambiguous-question handling were kept, since both are real.

---

## 2026-09-18 — Parameterless invocable actions keep a `List<String>` signature

**Decision.** `Dakiya_GetPendingDeliveries`, `Dakiya_ListOpenReturns` and `Dakiya_ListReviewItems`
take `List<String>`, and their Agent Script definitions declare no inputs.

**Reason.** A request wrapper would give the planner properly named inputs, but Salesforce rejects a
request class with no `@InvocableVariable` fields: *"InvocableMethod methods do not support parameter
type of List<...Request>"*. `List<String>` is the supported shape for an action that genuinely takes
no arguments.

---

## 2026-09-18 — Claude does not publish or activate the agent

**Decision.** Claude builds, validates and deploys the agent as a **draft** only. `sf agent publish`
and `sf agent activate` are never run by Claude, now or on any later change.

**Reason.** The owner asked to keep activation - the point at which the agent becomes reachable
through the Agent API - as her own decision. This also matches the Agent Script skill's own
draft-first rule, which treats publish and activate as explicit release actions requiring the
owner's confirmation.

---

## 2026-09-18 — The Einstein Agent User username is committed

**Decision.** `access.default_agent_user` in `Dakiya.agent` contains the real Einstein Agent User
login, and that file is in the public repo.

**Reason.** `CLAUDE.md` forbids committing email addresses, and this value is email-shaped, so it was
raised with the owner rather than committed silently. She confirmed it should go in as-is. It is a
system-generated agent-user login inside a disposable developer org, not a personal address, and a
username without a password grants no access. The alternative - a placeholder plus a manual edit
before every deploy - would leave a clean clone unable to deploy.

**How to apply:** this exception covers the agent-user login only. Every other rule in
`CLAUDE.md` non-negotiable 2 stands: no secrets, no personal email addresses, no phone numbers,
no real order data.

---

## 2026-09-18 — Agent API shapes verified; the spec was already correct

**Decision.** `worker/src/lib/agent-api.ts` implements §9.2 exactly as the spec describes it. No
deviation.

**Reason.** §9.2 is marked ⚠️VERIFY, so every shape was checked against current documentation before
implementing. All confirmed:

| Thing | Confirmed |
|---|---|
| Token endpoint | `POST {myDomain}/services/oauth2/token`, `grant_type=client_credentials` |
| Start session | `POST https://api.salesforce.com/einstein/ai-agent/v1/agents/{agentId}/sessions` |
| Session body | `externalSessionKey`, `instanceConfig.endpoint`, `streamingCapabilities.chunkTypes`, `bypassUser` |
| Send message | `POST /einstein/ai-agent/v1/sessions/{sessionId}/messages` (and `/messages/stream`) |
| Message body | `{ message: { sequenceId, type: "Text", text } }` |
| End session | `DELETE /einstein/ai-agent/v1/sessions/{sessionId}` with `x-session-end-reason` |
| ECA scopes | `api`, `refresh_token offline_access`, `chatbot_api`, `sfap_api` |

Note: `developer.salesforce.com` returns 403 to automated fetching, so these were confirmed from
search results and secondary documentation rather than by reading the page directly. The client is
deliberately confined to one small file so a future shape change is a one-file fix.

---

## 2026-09-18 — The Salesforce token is cached on a fixed TTL, not on `expires_in`

**Decision.** Cache the client-credentials token in KV for 30 minutes, and refresh once on any 401.

**Reason.** The client-credentials grant does not return `expires_in`, so there is no expiry to
honour. A fixed conservative TTL plus a single silent retry on 401 covers both early revocation and
an org session timeout, without a token being re-fetched on every request.

---

## 2026-09-18 — Client Credentials "Run As" is the owner's own user

**Decision.** The External Client App runs as Gitanjali's user, not a dedicated integration user.

**Reason.** §14 Phase 3 asks for an integration user holding only `Dakiya_Integration`, which is the
right shape for least privilege. Developer Edition does not provide spare user licences to create
one. Her user already holds `Dakiya_User`, which covers everything the Worker calls.

**Consequence.** The Worker's Salesforce access is broader than the design intends. This is a
single-user personal system where that user is the only human in the org, so the blast radius is
unchanged in practice - but if this ever moved to an org with more users, a dedicated integration
user would be required before anything else.

---

## 2026-09-18 — JWT auth is hand-rolled over WebCrypto

**Decision.** `worker/src/lib/jwt.ts` implements HS256 sign/verify directly rather than adding a JWT
library.

**Reason.** It needs two functions; many JWT libraries assume Node APIs that the Workers runtime does
not provide; and a dependency with access to the signing key is a dependency worth not having.
Verification uses `crypto.subtle.verify`, which is constant-time, so there is no hand-written
comparison to get wrong.

---

## 2026-09-21 — The project org moves from `agentTrial2` to `trial3`

**Decision.** `trial3` (Org Id `00DgK00000aAUcnUAG`, My Domain
`https://orgfarm-562b8294cc-dev-ed.develop.my.salesforce.com`) is now the project org. Every `sf`
command uses `-o trial3`. `CLAUDE.md` non-negotiable 1 was rewritten accordingly, and the Worker's
`SF_MY_DOMAIN_URL` was repointed.

**Reason.** The owner asked for everything built so far to be rebuilt in a fresh org, and confirmed
trial3 replaces agentTrial2 rather than running alongside it. Dated entries above still name
agentTrial2 because that is where that work actually happened; they are a record, not configuration.

**What the move proved.** The repo rebuilds a clean org from source with no manual data entry:
168 components deployed, 121 tests passing at 88.6% coverage, and a live REST round-trip, all
without touching agentTrial2. That was the real test of "metadata in git so the org can be rebuilt"
in BUILD_SPEC section 3.

**Two differences worth knowing:**

1. **Storage is 5 MB free, not 2.** agentTrial2 had roughly 3 MB already consumed by unrelated
   work; trial3 is empty. Roughly 2,500 records of headroom rather than 1,000. The section 8.6
   retention jobs still matter, but there is more room to be wrong in.
2. **No Einstein Agent User exists yet.** The Einstein Agent licence is present and entirely unused
   (0 of 201), but no user holds it, so `access.default_agent_user` in `Dakiya.agent` still names
   agentTrial2's user and the agent cannot be deployed to trial3 until Agentforce is switched on and
   that user is provisioned.

**Also carried over:** the agent is still never published or activated by Claude. See the
2026-09-18 entry - that rule follows the project, not the org.

---

## 2026-09-21 — The agent user is created by hand, not by Agentforce Builder

**Decision.** `trial3`'s Einstein Agent User (`dakiya.agent@trial3.dakiya`) was created manually in
Setup and given `AgentforceServiceAgentUserPsg`, `AgentforceServiceAgentSecureBase` and our own
`Dakiya_Integration`.

**Reason.** Salesforce normally provisions this user as a side effect of creating a Service Agent in
Agentforce Builder - it prompts for an Agent User and assigns the permission set group automatically.
Dakiya is deployed from source instead, so that flow never runs, and `access.default_agent_user` has
to name a user that already exists. Turning Agentforce on alone does not create one: after enabling
it, `trial3` still had 0 of 201 Einstein Agent licences in use.

**Consequence.** Any future org rebuild needs this user created before the agent bundle will deploy.
It belongs in the runbook as a prerequisite, not a footnote.

---

## 2026-09-22 — Org-wide default changes from Private to Public Read/Write

**Decision.** `Vendor__c`, `Purchase__c`, `Return__c`, `Tracking_Event__c`, `Inbound_Message__c` and
`Notification__c` move from `Private` to `ReadWrite`. `View All Records` is dropped from both
permission sets, since record access now comes from the org-wide default.

**Reason.** §4 specifies "All objects: sharing Private; the user and the agent/integration user get
access via permission sets." That combination does not work. `Dakiya_Integration` granted
`viewAllRecords` but not `modifyAllRecords`, so the agent user could **read** every record and
**write** none of them - it does not own the records the Worker creates, and the sharing model
blocked the update.

Behaviour testing caught it, and only because the tests ran with live actions: the agent answered
"the Nykaa parcel says delivered but I never got it" with *"it could not be updated due to access
issues"*. Every read scenario passed and every write scenario failed, which is the signature of
exactly this gap. Simulated actions would have reported success.

The obvious alternative, granting `modifyAllRecords`, is worse: Modify All implies delete, which
would undo the deliberate choice that `Dakiya_Integration` cannot delete a Purchase, Vendor or
Return.

**Why this is safe here.** The org has one human. Private sharing exists to keep users' records
apart; with a single user and one agent acting on her behalf there is nobody to partition from, so
Private bought nothing and silently broke the core write path. If Dakiya ever became multi-user this
must be revisited first - it is the assumption the whole sharing design now rests on.
