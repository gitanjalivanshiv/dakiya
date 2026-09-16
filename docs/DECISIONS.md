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

## 2026-09-16 — The org is an Agentforce trial org, not a classic Developer Edition

**Decision.** Treat §3's storage figures as unverified until measured in Phase 1.

**Reason.** The org's username is on the `agentforce.com` domain and its instance is
`orgfarm-a6f4756b11-dev-ed.develop.my.salesforce.com`. The spec's §3 constraint table assumes a
classic Developer Edition with ≈5 MB data storage. Agentforce trial orgs may have different data
storage and different Einstein/Agentforce usage allowances. Phase 1 records the real numbers from
Setup → Storage Usage, and Phase 2 records the real Agentforce allowance, before the retention job
thresholds in §8.6 are finalised.

**Upside.** Agentforce and Einstein are likely already enabled, which may shorten Phase 2.

---

## 2026-09-16 — `gh` CLI installed from the official release tarball, not Homebrew

**Decision.** `gh` 2.101.0 installed to `~/.local/bin/gh` from
`github.com/cli/cli/releases/download/v2.101.0/gh_2.101.0_macOS_arm64.zip`.
`export PATH="$HOME/.local/bin:$PATH"` appended to `~/.zshrc`.

**Reason.** The workstation has no Homebrew. A full Homebrew install needs the user's password and
several minutes, and is not otherwise required by this project. The official release tarball needs
no sudo. `gh` is preferred over a bare SSH key because `gh auth login` also configures the git
credential helper, and later phases use `gh api` / `gh repo view` to verify manual GitHub steps
(Pages source, repo variables) programmatically.
