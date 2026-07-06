# merge-medic

**Diagnose, triage, and treat pull requests.** A Claude skill that synthesizes every QA voice you already have on a PR — architect review, adversarial review, multi-model council outputs, issue-tracker comments, pasted notes — into a single remediation plan, finds adjoining issues the reviewers missed, and applies fixes in the safety mode you choose.

The point isn't to repeat what reviewers said. The point is to reconcile voices that disagree, catch the second-order issues that no single reviewer's window covered, and apply fixes that don't break adjacent code.

## Who this is for

**Claude Code and Cowork users.** You have a PR. You have multiple review voices. You want one report, one decision per finding, and an option to apply the fixes — with verification, without breaking the working tree.

**AI engineers running multi-model review pipelines.** You're already running architect + adversarial + multi-model council reviews. They disagree. They each see only their slice of the diff. merge-medic is the synthesizer that turns four parallel reviews into one actionable plan.

**Founders and solo builders.** You don't have a senior engineer reviewing your AI's PR work. You need the AI to apply review fixes safely — propose-only by default, never silently lowering a quality bar, and always proving verification ran.

## Install

### Cowork desktop

Download `merge-medic.skill` from the [releases page](https://github.com/SathiaAI/merge-medic/releases), then click it. The Cowork app will install it under `~/Library/Application Support/Claude/...skills/`.

### Claude Code (CLI)

```bash
git clone https://github.com/SathiaAI/merge-medic.git ~/.claude/skills/merge-medic
```

Or, in a project-local checkout:

```bash
mkdir -p .claude/skills
git clone https://github.com/SathiaAI/merge-medic.git .claude/skills/merge-medic
```

### Build from source

```bash
git clone https://github.com/SathiaAI/merge-medic.git
cd merge-medic
./build.sh
# produces merge-medic.skill in the current directory
```

## What it does

A 7-phase workflow. Phase 2 asks you which fix-authority mode to use. The rest runs without further prompts unless verification stalls.

| Phase | What happens |
| --- | --- |
| 1. Identify the PR | Resolve URL/branch/diff. Pull the linked issue. Cap large file reads. |
| 2. Ask for fix authority | One question, three options. Critical-tier paths auto-downgrade to propose-only regardless. |
| 3. Review through five lenses | (1) Project-specific locked decisions, (2) Security and vulnerabilities, (3) Scalability and cost, (4) Privacy and data flow, (5) Evals and CI shape. |
| 4. Synthesize | Reconcile disagreeing reviewers. Scan the blast radius of each finding for adjoining issues. Group by root cause. Flag what can't be safely auto-fixed. |
| 5. Apply fixes | Per chosen mode. Minimum diff. No drive-by refactors. No disabling tests to make builds pass. |
| 6. Verify | Defined success criteria. Loop until met. Stop after 2 failed attempts on the same check and escalate. |
| 7. Report out | Plain-English verdict, decisions-needed, what was applied, full findings table, QA resolution map, verification log. |

## The five lenses

1. **Project-specific locked decisions** — pricing, brand voice, regulatory posture, vendor lock-ins, architectural splits. Loaded from `.merge-medic/constraints.md` or your existing decisions log.
2. **Security and vulnerabilities** — auth boundaries, RLS coverage, secret handling, injection (SQL/prompt/command), dependency CVEs, plaintext leaks in logs, CSRF/CORS, rate limiting.
3. **Scalability and cost** — DB query shape (N+1, missing index), model/API routing choices, workflow runner shape, cold/hot path placement, retries and timeouts, unbounded loops.
4. **Privacy and data flow** — encryption key boundaries, tenant crossings, PII to third-party providers, regulated data on forbidden paths.
5. **Evals and CI shape** — CI weakening (failure masking, removed required checks), eval coverage delta, regression-threshold direction-of-travel, secret-scanning weakening, verification proof removed.

The direction-of-travel rule on Lens 5: merge-medic never silently lowers a quality threshold to make a build pass. Lowering a bar is always escalated as `needs-decision`.

## The three fix-authority modes

| Mode | What gets written | Verification |
| --- | --- | --- |
| **propose-only** *(default)* | Markdown report + per-file `.patch` files under `<outputs>/merge-medic/`. Zero changes to working tree. | Static checks (patches parse, apply cleanly to head, forbidden-string scan). |
| **apply-to-tree** | Edits applied to files in place. No commits. | Build/typecheck, lint, relevant tests, post-patch lens re-run. |
| **branch-and-commit** | New branch off PR head with one commit per logical change. Pushes to remote. Updates existing PR or opens draft. | All of the above + full CI command if defined. |

Critical-tier paths (auth, KMS, billing, secrets, CI workflows, migrations) auto-downgrade `apply-to-tree` and `branch-and-commit` to `propose-only`. This is not negotiable — humans approve and deploy changes to those paths.

## Customize for your project

Drop a `.merge-medic/constraints.md` at your repo root listing the locked decisions merge-medic should check on every PR:

```markdown
| ID | Rule | Severity | Spotter |
| --- | --- | --- | --- |
| BR-01 | No third-party tracking SDKs in client bundles. | Blocker | grep added JS/HTML for `googletagmanager\|gtag\|fbq\|mixpanel\|amplitude` |
| PRC-02 | Pricing strings must match docs/pricing.md. | High | grep added text for `\$\d+/mo` and diff against pricing.md |
| ARC-03 | New tables require RLS policies on the same migration. | Blocker | new `CREATE TABLE` in supabase/migrations/* without matching `ENABLE ROW LEVEL SECURITY` |
```

If `.merge-medic/constraints.md` isn't there, merge-medic falls back to any `STRATEGY/Decisions_Log.md`, `docs/decisions/`, `ARCHITECTURE.md`, or `CONSTRAINTS.md` it finds. If none of those exist, Lens 1 is skipped explicitly (and the report says so).

## Why "merge-medic"

A medic doesn't write the policy. A medic shows up when something's bleeding, triages what's actually critical vs. what looks dramatic, treats what they can on the spot, and tells the people in charge what needs decisions they can't make from the gurney.

That's the model. Reviewers do the policy work (architecture decisions, design choices). merge-medic does the triage and the field treatment, and surfaces the calls humans need to make.

## Verification proof

Every run writes a `verification.md` log alongside the report. Whatever success criteria ran, whatever passed, whatever failed, full attempt history. If someone disputes a fix later — including future-you — the log is the trace.

## What merge-medic doesn't do

- Doesn't auto-merge a PR. Ever.
- Doesn't run destructive operations (migrations, deploys, secret rotations) — only proposes them.
- Doesn't escalate to heavier/more expensive models unless you ask or the project's constraints define escalation conditions.
- Doesn't rewrite documentation that wasn't in the PR diff unless a finding directly requires it.

## Contributing

Issues and PRs welcome. The skill itself is small (two reference files under `references/`). If you add a check pattern that catches issues in your project, propose it back — Lens 5 in particular benefits from more spotting heuristics.

Style guide for new content: state the *direction* of the rule (what gets flagged, what severity), give a one-line spotting heuristic, and explain *why* it matters in one sentence. Don't add MUST-shaped rules without a why.

## License

MIT. See [LICENSE](LICENSE).

## Credits

Built by [Paul Poulose](https://github.com/pjpoulose), generalized from a private project's build-loop for public sharing. Patterns drawn from the [Anthropic skill-creator](https://github.com/anthropics/skills) and a multi-model adversarial-review (council) pipeline.
