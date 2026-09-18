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
