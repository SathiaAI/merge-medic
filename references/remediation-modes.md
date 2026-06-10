# Remediation modes

Three fix-authority modes. Each has a specific deliverable, a clear safety profile, and the same verification protocol.

## The critical-tier auto-downgrade rule

Before applying any mode, check whether the PR touches any path in this list:

- Permission-gate / classifier services (security-critical)
- Orchestrator or router code paths
- KMS / DEK / encryption code (any file matching `kms`, `dek`, `encrypt`, `vault` in name)
- Auth (sign-in, OAuth, JWT verification, RLS policy SQL)
- Billing / Stripe / pricing constants
- Channel adapter send/receive core
- Model routing / model selection
- Migration files in `supabase/migrations/`
- CI workflow files in `.github/workflows/`
- Anything under `secrets/` or `.env*`

If the diff touches any of those, **silently downgrade `apply-to-tree` and `branch-and-commit` to `propose-only`** and surface a one-line notice in the verdict:

> "Critical-tier paths detected ({list}); downgraded to propose-only per the project's graduated-trust rule. Patches are in `OUTPUTS/.../patches/`."

This is not negotiable — even if the user asked for full apply mode. The founder approves and deploys critical changes.

## Mode 1 — Propose-only (Recommended default)

**Deliverable**: One markdown report + one patch file per logical change, written to:

```
OUTPUTS/YYYY-MM-DD_pr-review-{NNN}/
├── REVIEW.md                # the report from Phase 7
├── patches/
│   ├── 001-{slug}.patch     # unified diff, applies with `git apply`
│   ├── 002-{slug}.patch
│   └── ...
└── verification.md          # what was checked, what couldn't be (since no writes)
```

**What it touches**: nothing outside `OUTPUTS/`. Zero risk to the working tree.

**Verification in this mode**: limited to static checks — patches parse, each patch applies cleanly to a scratch copy of the head commit (use `git apply --check` against a temp clone, never the live working tree), no patch reintroduces strings the project's compliance scanner would reject.

**When to use**: critical-tier paths, ambiguous diffs, anything where the user wants to inspect each change. Also the right choice when the skill is running outside the repo (Cowork desktop with a PR URL but no local checkout).

**Hand-off**: end the response with the patch directory path so the user can `cd` to it and apply with `git apply patches/001-*.patch` in order.

## Mode 2 — Apply to working tree, don't commit

**Deliverable**: Edits applied directly to files in the working tree + the same `OUTPUTS/.../REVIEW.md` report + a `verification.md` log.

**What it touches**: only the files identified in findings. No new files unless a finding requires it (e.g., a missing test). No `git add`, no `git commit`.

**Verification in this mode**:

1. After every Edit, confirm with `git diff <file>` (not a sandbox re-read — FUSE-mount gotcha).
2. Run the repo's typecheck command (auto-detect: `pnpm typecheck`, `npm run typecheck`, `tsc --noEmit`, `cargo check`, `mvn -q compile`, `go build ./...`).
3. Run the repo's lint command if one is in `package.json` scripts or a `.github/workflows/*.yml`.
4. Run tests for the changed packages only — not the full suite — unless the PR is small enough that the full suite finishes in <60s.
5. Re-run the four-lens review on the post-patch diff and confirm no new findings.

**When to use**: non-critical paths, user is at the keyboard reviewing in real time, fixes are mechanical (formatting, missing null check, obvious typo).

**Hand-off**: end with `git status` summary + "review with `git diff`, commit when ready."

## Mode 3 — Branch + commit + push (or update PR)

**Deliverable**: One or more commits on a branch + a remote push + either a PR update or a draft PR + the report + verification log.

**Branch naming**: `claude/pr-{NNN}-remediate-{YYYYMMDD}`. Never push to the user's PR head branch without explicit permission — if asked to update the PR directly, get one-line confirmation first.

**Commit shape**: one logical change per commit. Commit message format:

```
fix(<scope>): <one-line summary>

Source: qa:architect, qa:adversarial, claude:review
Lens: security
Severity: high

<2-3 lines: what was broken, what changed, why this is the minimum>
```

**Verification in this mode**: everything from Mode 2, plus:

6. After all commits, run the full repo CI command if one is defined (e.g., `pnpm ci` or the script in `.github/workflows/ci.yml` build step).
7. Confirm the branch is pushed and visible on the remote (`git ls-remote origin claude/pr-{NNN}-remediate-{YYYYMMDD}` returns a SHA).
8. If updating an existing PR, post a single PR comment with a link to `REVIEW.md` and the resolution map.

**When to use**: PR is the user's, fixes are unambiguous, user is offline / batching, no critical-tier paths touched.

**Hand-off**: end with the branch name, the remote URL, and the verdict from `REVIEW.md`.

## Shared verification protocol

Used by all modes (Mode 1 is static-only; Modes 2 and 3 are full).

### Success criteria (define done)

The remediation is "done" only when ALL of these are true:

1. Every Blocker and High finding is either resolved in the patch, dropped with explicit written rationale, or escalated `needs-decision`.
2. Every QA reviewer comment is either resolved, explicitly disputed with reasoning, or marked `out-of-scope` with a follow-up issue filed.
3. Build / typecheck passes (Modes 2 and 3 only).
4. Lint passes (Modes 2 and 3 only).
5. Relevant tests pass (Modes 2 and 3 only).
6. No new finding under the four lenses introduced by the patch (re-run lenses against post-patch diff).
7. For projects with a forbidden-string scanner configured: grep its patterns against the post-patch added lines; nothing new appears outside the governance allowlist.

### The verify loop

```
loop:
  failed_checks = run_all_success_criteria()
  if failed_checks is empty:
    return DONE
  if attempt_count >= 2 on the same check:
    return ESCALATE_TO_USER with stuck-point
  attempt_count += 1
  fix(failed_checks)
```

Two attempts on the same check, then stop. Do not invoke heavier models or wider-context retries unless the user explicitly says so. Surface the stuck-point in plain English:

> "Verification failed twice on `pnpm typecheck`: `src/router.ts:42` — type X is incompatible with Y. I'm not confident enough to keep trying without you. Want me to (a) revert to before this finding, (b) keep going with a more aggressive type cast and flag it, or (c) hand it back for you to decide?"

### What "verification ran" looks like in the report

`verification.md` (written every run, every mode) records:

```
## Pre-flight
- Critical-tier check: <pass/fail with list of paths>
- PR diff size: N files, M lines

## Static checks (all modes)
- Patches parse: pass
- Patches apply cleanly to head: pass / fail (which)
- Compliance scanner: pass / fail (which strings)

## Live checks (apply modes only)
- typecheck: pass / fail (last 20 lines of output)
- lint: pass / skip (no config) / fail
- tests: N passed, M failed (which)
- post-patch lens re-run: no new findings / N new findings

## Loop history
- Attempt 1: typecheck failed at router.ts:42; fix applied
- Attempt 2: typecheck passed

## Success criteria
- [x] Blockers resolved (3 of 3)
- [x] QA comments addressed (8 of 8)
- [x] Build green
- [...]
```

This file is the proof. If a user disputes a fix later, this is the trace.

## When verification can't run

If the runtime can't execute the repo's build (e.g., Cowork desktop with no checkout, missing dependencies, language toolchain not installed):

1. Note the limitation in `verification.md` explicitly. Don't fake it.
2. Drop the live-check criteria but keep static checks.
3. Auto-downgrade Modes 2 and 3 to Mode 1 (propose-only).
4. Tell the user: "Couldn't run live verification here; patches are static-checked. Apply locally and run `<typecheck command>` to confirm."

## After everything

When all success criteria are met, append a one-line summary to the user's linked tracker issue (if one was found) and stop. Don't keep going to add documentation, refactor adjacent code, or update CHANGELOG entries unless a finding explicitly required it.
