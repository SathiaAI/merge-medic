---
name: merge-medic
description: Holistically review a pull request and remediate it. Synthesizes GitHub PR review comments, multi-model council or adversarial review outputs, issue tracker comments, and any pasted QA notes into a single remediation plan, finds adjoining issues the reviewers missed, and applies fixes in propose-only / apply-to-tree / branch-and-commit mode without breaking adjacent code. Use when the user mentions reviewing a PR, addressing QA review comments, fixing architect review or adversarial review feedback, auditing a branch for security, scalability, privacy, vulnerabilities, business or financial implications, finding issues reviewers missed, or remediating review feedback safely. Triggers on "review this PR", "address the QA comments", "fix the architect review", "fix adversarial review feedback", "holistic PR review", "PR remediation", "check this PR for X", "find issues reviewers missed", "what else is broken in this PR", "make the fixes from the council review", or any PR URL pasted with a request to act.
---

# PR Review and Remediate

A guided, two-phase workflow: **review** the PR holistically (synthesizing every QA voice plus five built-in lenses), then **remediate** at the authority level the requester chooses, with a verification loop that defines done.

The point of this skill is not to repeat what reviewers already said. The point is to:

1. Reconcile multiple QA voices that may disagree.
2. Find *adjoining* issues that reviewers didn't flag because each saw only part of the diff.
3. Apply fixes that don't introduce new problems — verified, not just written.
4. Keep founder review small: plain-English verdict and decisions, not diffs to skim.

## Activation rules

- This skill must own the full review-and-fix workflow once invoked. Don't shortcut to "here are the issues" without offering remediation.
- Critical-tier paths (anything that touches auth, KMS, billing, secrets, RLS policies, channel adapters, or model routing) auto-downgrade `apply-to-tree` and `branch-and-commit` requests to `propose-only`. See `references/remediation-modes.md`.
- If the repo has project-specific constraints configured (see Lens 1 detection rules), those checks are mandatory, not optional.

## Inputs the user may provide

The skill accepts any combination — never block waiting for all of them.

| Input | Where it lives | How to fetch |
| --- | --- | --- |
| **PR URL or number** | GitHub | Use GitHub MCP if connected; otherwise `gh pr view <N> --json ...` in repo; otherwise read pasted PR body |
| **Repo path / branch / diff** | Local | `git diff <base>..<head>`; if not in repo, ask for a unified diff or patch file |
| **Architect-review comments** | GitHub PR threads | Pull all review comments + general PR comments |
| **Adversarial-review comments** | GitHub PR threads OR multi-model council output files | Same as architect; for projects using a multi-model council, look for files matching `*council*RAW*.md` or `*adversarial*.md` near the PR's session/issue ID |
| **Linear issue + comments** | Linear MCP | If PR mentions an issue ID (e.g., `ABC-123`), pull the issue, its description, and comments |
| **Pasted notes / file path** | Inline | Read as-is |

If the user gave only "review this PR" with a URL, fetch everything reachable; if they pasted text, treat it as authoritative and skip discovery for that source.

## Phase 1 — Identify the PR and gather context

1. **Detect runtime.** If the current working directory contains a `.git` directory whose remote points at the PR's repo, you have full repo access. Otherwise you're working from a PR URL only.
2. **Resolve the PR.** Get title, description, base branch, head SHA, file list, and the full diff. Cap the diff read at 5,000 lines per file — for larger files, read the changed hunks plus surrounding 30 lines.
3. **Identify the linked issue.** Search the PR title, branch name, and body for the project's issue-tracker pattern (e.g., `ABC-\d+`). If found, pull the issue's description, acceptance criteria, and comments. The PR is evaluated against the *current* AC, not stale CHANGELOG entries.
4. **Collect all QA inputs in parallel.** Don't serialize fetches that don't depend on each other. Dedupe by (file_path, line_range, topic) — the same complaint from two reviewers counts once but keeps both attributions.
5. **Confirm gathered inputs with the user in one terse line** before going further: e.g., "Pulled PR #142, 8 review comments (5 architect, 3 adversarial), Linear ABC-218 with 4 comments, and your pasted notes. Anything else?"

## Phase 2 — Ask for fix authority

Use the AskUserQuestion tool with one question and three options:

- **Propose-only** *(Recommended)* — Skill writes a remediation report and per-file `.patch` files into `OUTPUTS/YYYY-MM-DD_pr-review-{NNN}/`. The user applies them. Zero risk to working tree. Required for critical-tier paths regardless of selection.
- **Apply to working tree, don't commit** — Skill edits files in place, runs verification, leaves `git status` dirty for the user to review and commit.
- **Branch + commit + push (or update PR)** — Skill creates a branch off the PR head (or commits directly to it if the user owns it), applies fixes as one or more logical commits, runs verification, pushes, and either updates the existing PR or opens a draft PR.

If the user already specified a mode at invocation ("review this PR and just apply the fixes"), don't re-ask — confirm in one line and proceed.

See `references/remediation-modes.md` for exact behavior, deliverables, and the critical-tier auto-downgrade rule.

## Phase 3 — Review through five lenses

Run all five in the same pass. Don't accept the QA reviewers' framing as ground truth — verify their claims against the diff, and look outward for issues each reviewer's window missed.

1. **Project-specific locked decisions** — pricing, brand voice, regulatory posture, vendor lock-ins, architectural splits. Loaded from `.merge-medic/constraints.md`, the project's decisions log, or fallback files. Skipped explicitly if none configured.
2. **Security and vulnerabilities** — auth boundaries, Supabase RLS coverage, secret handling, injection (SQL, prompt, command), dependency CVEs, plaintext leaks in logs.
3. **Scalability and cost** — DB query shape (N+1, missing index, full scans), model/API routing choices (cheap default model on hot paths, expensive model only when justified), workflow runner shape, cold/hot path placement, retries and timeouts, unbounded loops.
4. **Privacy and data flow** — encryption key boundaries respected, tenant crossings encrypted, no PII written to third-party model providers without consent, no regulated data on paths where the project's constraints forbid it.
5. **Evals and CI shape** — CI workflows haven't been weakened (failure masking, removed required checks, loosened thresholds), eval coverage hasn't dropped silently, regression thresholds aren't quietly relaxed, secret-scanning and security-policy guardrails are intact.

Each finding gets:

- **Lens** that caught it
- **Severity** — Blocker / High / Medium / Low / Nit
- **Source** — `qa:architect`, `qa:adversarial`, `qa:linear`, `qa:pasted`, `claude:review` (combine if confirmed by multiple)
- **Adjoining flag** — `true` if this is an issue Claude found that no QA reviewer named
- **File + line** (or "design-level" if structural)
- **Why it matters** in one sentence
- **Proposed fix** — concrete, minimal, named files and approximate lines

Full rubric, project-constraint format, and per-lens spotting heuristics in `references/holistic-lens.md`.

## Phase 4 — Synthesize and surface adjoining issues

This is the step that makes the skill worth running.

1. **Reconcile disagreements between reviewers.** If architect says "do X" and adversarial says "X is wrong because Y", state both, then take a position. Don't bury it.
2. **Look for the blast radius of each confirmed finding.** If a reviewer flagged "auth check missing on endpoint A", scan sibling endpoints in the same file and similar handlers in adjacent files. Adjoining issues go in the report tagged `adjoining`.
3. **Group findings by root cause where possible.** Three "missing input validation" findings are usually one bug, not three. Fix the pattern, not the symptoms.
4. **Flag what *can't* be safely auto-fixed.** Architectural rewrites, ambiguous intent, decisions that need founder input. These get tagged `needs-decision` and stay out of the patch set regardless of fix authority.

## Phase 5 — Apply fixes per chosen mode

See `references/remediation-modes.md` for the per-mode mechanics. Universal rules:

- **Minimum diff that solves the problem.** No drive-by refactors, no formatting churn, no speculative hardening.
- **One logical change per commit** (branch+commit mode) — easier to revert one piece.
- **Touch only what you must.** If a finding requires changing one function, don't reformat the file.
- **Never disable a test to make a build pass.** If a test fails after a fix, either the fix is wrong or the test needs an explicit update with a one-line rationale in the commit message.

## Phase 6 — Verify (success criteria, loop until met)

Define done explicitly. Don't ship a "remediation" until all of these are true:

- Every Blocker and High finding is either resolved in the patch, dropped with explicit rationale, or escalated `needs-decision`.
- Every QA reviewer comment is either resolved, explicitly disputed with reasoning, or marked `out-of-scope` with the new issue filed.
- In apply modes: build/typecheck passes (`pnpm typecheck`, `tsc --noEmit`, `cargo check`, `mvn compile` — whatever the repo uses).
- In apply modes: lint passes (whatever the repo runs in CI).
- In apply modes: relevant tests pass. If the PR has no tests for the changed area, add one for each Blocker fix.
- No new finding under the five lenses introduced by the patch.
- For projects with custom forbidden-string scanners configured (e.g., compliance allowlists): post-patch `git diff` does not introduce any flagged string.

If verification fails, loop: identify which check failed, fix, re-verify. Don't paper over with skips. After two failed verification rounds on the same check, stop and escalate to the user with the specific stuck-point — do not invoke heavier models speculatively.

When the runtime uses a mounted filesystem (Cowork, remote dev container, FUSE), file reads can be cached or truncated in ways that make verification falsely pass or fail. After every Edit in `apply-to-tree` or `branch-and-commit` mode, confirm the change with `git diff <file>` (not a fresh re-read of the same path) before moving on.

## Phase 7 — Report out

Output goes to a per-project folder — `<project-outputs>/merge-medic/YYYY-MM-DD_pr-{NNN}/` by default, configurable. Plain-English verdict at the top, structured findings below. Format:

```
# PR #{NNN} — Holistic Review and Remediation

## Verdict
[1-2 sentences. Did the PR pass? What changed? Anything the user must decide?]

## Decisions needed from you
[Numbered list. Empty if none. Each item: what, why, options. No code snippets.]

## What was applied
[Mode used. List of files touched, commit SHAs if any, PR/branch URLs.]

## Findings
[Table: Lens | Severity | Source | File:Line | Finding | Status]

## Adjoining issues found
[List of findings no reviewer named, with severity. Empty is fine and worth saying explicitly.]

## QA reviewer comments — resolution map
[For each original QA comment: comment summary, then resolution.]

## Verification results
[Each success criterion: pass / fail / skipped (with reason).]
```

The verdict and decisions sections are the only things the user is expected to read first. Everything else is reference for when they want to drill in.

## What this skill does NOT do

- Does not auto-merge a PR. Ever.
- Does not run destructive operations (DB migrations, deploys, secret rotations) — only proposes them.
- Does not switch to a heavier / more expensive model unless the user explicitly asks or the project's constraints define escalation conditions (e.g., architectural ambiguity, security/permissions decision, or 2 failed verification rounds on the same check).
- Does not rewrite documentation that wasn't in the PR diff unless a finding directly requires it.

## Reference files

- `references/holistic-lens.md` — The five lenses expanded with per-lens spotting heuristics, the project-constraints format, and severity guidance.
- `references/remediation-modes.md` — Exact behavior of each fix authority mode, the critical-tier auto-downgrade rule, and the shared verification protocol with looping logic.
