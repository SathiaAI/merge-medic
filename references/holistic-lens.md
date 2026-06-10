# Holistic review lenses

Four lenses run on every PR. Don't accept reviewer framing as ground truth — every claim is verified against the diff. Adjoining issues outside the reviewer's window are caught here.

## Lens 1 — Project-specific locked decisions

Most teams have a small set of decisions that are *not* up for re-debate every PR — pricing, brand voice, regulatory posture, architectural splits, vendor lock-ins. Skip this lens and the skill will silently let a PR violate them. Run it first.

### How the skill finds your constraints

On every invocation, the skill looks for any of these in the repo (in order):

1. `.merge-medic/constraints.md` — preferred. A single file you author with one line per locked rule. Format below.
2. `STRATEGY/Decisions_Log.md` or `docs/decisions/` — any append-only decision log with D-NN or ADR-NN style entries.
3. `ARCHITECTURE.md`, `CONSTRAINTS.md`, or `CONTRIBUTING.md` — last-resort scrape. The skill warns the user if it falls back here, because these formats are easy to miss.

If none of the above exist, the skill reports `Lens 1: no project constraints configured` and skips the lens. Don't invent constraints from training data.

### `.merge-medic/constraints.md` format

One rule per row, three columns. Severity must be one of Blocker / High / Medium / Low / Nit. `Spotter` is a one-line heuristic the skill applies to the diff.

```
| ID | Rule | Severity | Spotter |
| --- | --- | --- | --- |
| BR-01 | No third-party tracking SDKs in client bundles. | Blocker | grep added JS/HTML for `googletagmanager\|gtag\|fbq\|mixpanel\|amplitude` |
| PRC-02 | Pricing strings must match the current price list in docs/pricing.md. | High | grep added text for `\$\d+/mo` and diff against pricing.md |
| ARC-03 | All new tables require RLS policies on the same migration. | Blocker | new `CREATE TABLE` in supabase/migrations/* without matching `ENABLE ROW LEVEL SECURITY` |
```

The skill reads this table at the start of every review and treats each row as a Lens 1 check. Severity is taken directly from your table.

### What the skill does with violations

Same as every other lens: report the finding with `lens=project-constraint`, source the violation (which rule, file:line), propose a minimal fix, and route through the chosen remediation mode. Critical-tier auto-downgrade still applies if the violation is in a critical-tier path (see `remediation-modes.md`).

### Deriving your own constraints file

The table above is the template. Derive one row per locked decision from your own decisions log — regulatory framing rules, graduated-trust/approval tiers, tracker bans, key-custody rules, required legal embeds, pricing locks, and similar. Keep each Spotter to a single greppable heuristic.

## Lens 2 — Security and vulnerabilities

| Category | What to flag | Severity guide |
| --- | --- | --- |
| **Auth boundary** | Endpoint added without auth check, or with auth check that uses the wrong identity (anon vs service-role vs user-JWT). For Supabase, confirm RLS covers the table. | Missing auth = Blocker. Wrong identity = High. |
| **RLS coverage** | New table without RLS policies enabled, or `service_role` used in user-path code instead of `anon` + JWT. | Blocker for any user-data table. |
| **Secret handling** | Hardcoded keys, secrets logged on error paths, secrets passed in URL query, secrets in client-side bundles, `.env` committed. | Hardcoded = Blocker. Logged = High. |
| **Injection** | SQL string concatenation, shell command with unsanitized input, prompt injection (user input flowed into a system prompt without delimiter / quoting), unescaped HTML rendering. | Blocker. |
| **Dependency CVEs** | New deps added — check for known CVEs. New version pin of an existing dep — check changelog for security notes. | High if known CVE in the changed surface. |
| **Plaintext leak in logs** | Tokens, JWTs, plaintext data-encryption keys, PII fields, message bodies written to console/structured logs. | Blocker for credentials, High for PII. |
| **CORS / CSRF** | New API endpoint with permissive CORS, missing CSRF token on a state-changing form. | High. |
| **Rate limiting** | New auth or write endpoint with no rate limit. | Medium unless costed (LLM call), then High. |
| **Inbound webhook adapters** | Webhook secret/signature validation skipped or weakened (messaging platforms, payment providers, etc.). | Blocker. |

Spotting heuristic: anywhere the diff adds an `if user.id == ...` check, look for the corresponding else-branch and confirm it returns 403, not 200-with-empty.

## Lens 3 — Scalability and cost

| Category | What to flag | Severity guide |
| --- | --- | --- |
| **DB query shape** | N+1 (loop with a query inside), full-table scan on a hot path, missing index hint for a new query, `select *` on a wide table. | High if hot path, Medium otherwise. |
| **Model routing** | An expensive model called from a hot user-facing path without documented justification — default to cheaper models on hot paths. Long completions through routes known to time out. | High — directly burns budget per call. |
| **n8n workflow shape** | Synchronous webhook waiting on a multi-step workflow, retries with no backoff, unbounded fan-out. | High. |
| **Cold vs hot path** | Synchronous code in the message-receive path that should be enqueued (e.g., embedding generation, summarization). | Medium-High. |
| **Retries and timeouts** | New HTTP call with no timeout, retry loop with no max, unbounded `while True`. | High. |
| **Cache misuse** | Cache keys set on provider routes that ignore them. Prompt-cache markers set on too-small prompts (<1024 tokens) — no benefit, extra latency. | Low (waste, not break). |
| **Cost per call** | New LLM call without a max_tokens cap. New embedding call without batching. | Medium. |
| **Migration cost** | Migration with no batch size on a large table, no rollback path, no dry-run via `BEGIN..ROLLBACK`. | High. |
| **Unit economics** | Anything that pushes per-customer infrastructure cost above the project's gross-margin floor. | High — needs founder decision. |

Spotting heuristic: search the diff for `for`, `await`, and `model:` together in close proximity — that pattern is usually N+1 against an LLM, which is the most expensive shape.

## Lens 4 — Privacy and data flow

| Category | What to flag | Severity guide |
| --- | --- | --- |
| **KMS DEK boundary** | Code that holds a plaintext DEK across an await boundary, writes it to a temp file, or returns it from an API. KMS unwrap must happen at the encrypt/decrypt call site, not at startup. | Blocker. |
| **Tenant crossing** | Data from tenant A's vault rendered, computed, or stored together with tenant B's. Cross-tenant query without an explicit tenant-scoping filter. | Blocker. |
| **PII to model providers** | Memory, message body, or contact info sent to a third-party model provider without consent. Check which provider routes have a DPA in place. | Blocker for no-DPA routes carrying PII. |
| **Forbidden data categories** | Any data category the project's constraints forbid (e.g., PHI, payment card data) on any path — even self-reported. | Blocker — escalate to founder. |
| **Telemetry payload** | Event payload includes raw user content or full message body instead of an event name + structured fields. | High. |
| **Backup / export** | New backup or export path that includes plaintext encrypted-vault fields. | Blocker. |
| **Right to delete** | New table that stores user data but isn't covered by the existing account-deletion path. | High. |
| **Region pinning** | Storage in a region that violates the user's residency choice. | High. |

Spotting heuristic: every `INSERT` or `UPDATE` against a user-data table should have a `tenant_id` (or equivalent scoping key) in scope. If you can't trace where it came from, that's a finding.

## Severity definitions

| Severity | Means | What the report says |
| --- | --- | --- |
| **Blocker** | Cannot ship this PR. Security, privacy, hard-constraint violation, or correctness break. | "Must fix before merge." |
| **High** | Will cause production pain — money, latency, future migration. | "Should fix in this PR; document if deferred." |
| **Medium** | Real issue, can be filed as a follow-up. | "Recommend fixing or filing an issue." |
| **Low** | Minor — readability, small inefficiency. | "Optional; bundle if convenient." |
| **Nit** | Style or preference, no functional impact. | "Take or leave." |

## Business and financial implications

For every Blocker and High finding, also state — in one line — the business or financial impact:

- Money: per-call cost, per-month projection, customer-facing pricing implications.
- Time: engineering time to fix later vs now.
- Risk: who pays if this lands and breaks (founder personally? customers? a partner or employer relationship?).
- Reputation: visible to customers / investors / Linear watchers?

If the impact is "low" across all four, downgrade the severity.

## When findings disagree across lenses

A single change can be flagged by multiple lenses with different severities (e.g., a new LLM call is High for cost and Medium for privacy). Take the *highest* severity and list all attributing lenses on the finding row.

## Lens 5 — Evals and CI shape

A PR can "pass review" while quietly weakening the checks that would have caught the next bug. This lens catches that. Run it on every PR; flag aggressively on the regression-direction items because they're easy to slip past humans.

| Category | What to flag | Severity guide |
| --- | --- | --- |
| **CI weakening — failure masking** | New `continue-on-error: true`, `if: always()` on a step that should fail-fast, `--ignore-scripts`, `npx ... \|\| true`, `-e` removed from a bash CI step, `set +e` added. | High — any of these can turn a red build green silently. |
| **CI weakening — required check removal** | Removed step from `.github/workflows/ci.yml` that's wired to branch protection, removed matrix leg, narrowed `paths:` filter so the job no longer runs on the changed area. | Blocker — breaks the contract the rest of the team relies on. |
| **CI weakening — timeout shrink** | Test or job timeout reduced (e.g., `timeout-minutes: 30` → `15`) in a way that could kill slow tests rather than failing them. | High. |
| **Eval coverage delta** | Test files deleted with no replacement, `it.skip` / `xit` / `describe.skip` / `@Ignore` / `#[ignore]` added, snapshot tests accepted (`-u` / `--update-snapshot`) without commit message rationale. | High when net test count drops on the changed area. |
| **Regression threshold direction** | Coverage floor lowered (jest `coverageThreshold`, vitest, codecov yaml), pass-rate threshold lowered in an eval config (`min_pass_rate`, `min_score`), latency/perf budget raised (p95/p99), error-budget widened. | Blocker for direction-of-travel; "we're making the bar lower" needs founder sign-off. |
| **Multi-model review pipeline drift** | Council/ensemble output format changed without a corresponding update to the parser that consumes it. A voice removed from the ensemble without explicit rationale. A new voice added without updating synthesis. | High — the council loses comparability across sessions. |
| **n8n eval workflow drift** | Workflow nodes deleted, reordered, or re-triggered without exporting the JSON to source. Cron schedule or webhook path changed in code but not in the workflow file. | High. |
| **Gitleaks / compliance scanner weakening** | New allowlist entry in `.gitleaks.toml` or a custom compliance-scanner workflow without a one-line rationale on the same commit. A scanning regex narrowed or broadened without rationale. Whole rule deleted. Scanner workflow disabled or made `continue-on-error`. | Blocker — these are the project's hard-constraint guardrails. |
| **Eval prompt distribution** | New eval prompts added that all share a single shape (clustering) and don't cover existing edge cases. Edge-case prompts removed without note. | Medium. |
| **Verification proof removed** | Existing `verification.md`, `evals/evals.json`, `benchmark.json`, or grading output deleted as part of the PR. | High — the proof that earlier work was checked goes away with it. |
| **Branch protection changes** | `.github/branch-protection.yml` or admin script edits that relax required reviewers, required checks, or signed-commit enforcement. | Blocker. |
| **Secret-scanning weakening** | Pre-commit hook removed or scoped out, gitleaks pre-commit disabled, secret-detection PR check made advisory. | Blocker. |

Spotting heuristic: grep the diff for `skip`, `ignore`, `continue-on-error`, `always()`, `--no-verify`, `|| true`, `set +e`, `disabled:`, `enforcement: off`, `coverageThreshold`, `min_pass_rate`. Each match needs a one-line justification in the commit message or it's a finding.

### Direction-of-travel rule

For numeric thresholds, the lens cares about *direction*, not value. A coverage floor going from 80% to 75% is a finding regardless of "but we're still above the industry average." If the user wants to lower a bar, that's a founder decision (`needs-decision`), not a fix the skill applies. The skill never silently lowers a threshold to make a build pass.

### What this lens does NOT catch

- Whether the existing tests are good tests. (Out of scope — the skill assumes the tests in the base branch are baseline-correct.)
- Whether the eval prompts in `evals.json` are realistic. (Covered by skill-creator's separate optimization loop, not this skill.)
- Performance regressions in product code that don't show up in a perf budget. (Lens 3 covers some of this.)
