---
name: debug-loop
description: Systematic debugging methodology. Reproduce → isolate → hypothesize → write a failing test → fix → verify. Use when chasing bugs, especially intermittent or hard-to-reproduce ones.
license: MIT
---

# Debug Loop

A disciplined debugging methodology. Pairs naturally with `karpathy-guidelines` (smallest change, verifiable success).

## When to Use This Skill

- Bug reports without a clear root cause
- Intermittent / flaky failures
- "It works on my machine" situations
- Regressions discovered in CI
- Performance regressions

## When NOT to Use This Skill

- Trivial typos or obvious off-by-one errors — just fix them.
- Bugs the user has already root-caused and only wants you to fix.

## The Loop

```
┌─────────────────────────────────────────────────┐
│  1. Reproduce          (deterministic recipe)   │
│  2. Isolate            (smallest failing case)  │
│  3. Hypothesize        (what's the cause?)      │
│  4. Failing test       (encode the bug)         │
│  5. Fix                (smallest change)        │
│  6. Verify             (test passes; no regress)│
│  7. Document           (commit message / note)  │
└─────────────────────────────────────────────────┘
```

If you skip steps, you'll come back to this bug in 6 months.

## Step 1 — Reproduce

**Goal:** A command or sequence that reliably fails.

- Get the exact error message and full stack trace.
- Get version info: language, deps, OS, environment.
- If "it's flaky", run it 50–100 times and measure the failure rate.

If you cannot reproduce, **stop**. Ask the user for:
- Exact steps
- Inputs / fixtures
- Environment differences
- Logs from a failing run

Do not "fix" what you can't see fail.

## Step 2 — Isolate

**Goal:** Smallest possible failing case.

- Strip the input down. Binary search the test data.
- Strip the code path down. Comment out branches that don't matter.
- Use `git bisect` for regressions: find the commit that introduced it.

```bash
git bisect start
git bisect bad                  # current commit fails
git bisect good <known-good-sha> # an old commit that worked
# git checks out commits one by one; mark each:
git bisect good   # or git bisect bad
git bisect reset  # when done
```

## Step 3 — Hypothesize

**Goal:** A specific, testable theory of what's wrong.

Bad: "Something with the cache."
Good: "The TTL comparison uses `>` instead of `>=`, so entries expire one tick early."

Write the hypothesis down. If you can't articulate it precisely, you don't understand the bug yet — go back to step 2.

## Step 4 — Failing Test

**Goal:** A test that fails *because of the bug*, not for any other reason.

This is the most-skipped, most-valuable step.

```python
def test_cache_entry_lives_until_exact_ttl():
    """Regression test for issue #123: entry expired one tick early."""
    cache = Cache(ttl_seconds=10)
    cache.set("k", "v")
    with freeze_time("2026-01-01 00:00:10"):  # exactly at TTL
        assert cache.get("k") == "v"  # currently fails
```

If you can't write this test, you can't verify your fix. Either:
- The bug isn't isolated enough → step 2.
- The hypothesis is wrong → step 3.
- The system is untestable → that's a separate, bigger problem to flag.

## Step 5 — Fix

**Goal:** Smallest change that makes the failing test pass.

- One change at a time.
- Don't bundle "improvements".
- If the fix is large, the hypothesis was probably wrong — revisit.

## Step 6 — Verify

**Goal:** The new test passes AND the rest of the suite still passes.

- Run the new test. Green.
- Run the full suite. Green.
- Re-run the original repro from step 1. No failure.
- If the bug was flaky, run the repro 50–100 times again and measure.

If anything is red, **revert and rethink**. Don't pile on more changes.

## Step 7 — Document

**Goal:** Future-you (or the next dev) can understand what happened.

- Commit message includes: symptom, root cause, fix.
- If the bug exposed a class of issue, note it in code comments at the fix site.
- If the bug should never recur, the test you wrote in step 4 is the guarantee — keep it.

Use the `git-commit` skill for the commit message.

## Anti-Patterns

| Don't | Why |
|-------|-----|
| Add `try/except` to silence the error | Hides the bug, doesn't fix it |
| "It seems to work now" without a test | You'll be back here in a month |
| Big refactor as part of the fix | Untestable; reviewers can't tell what fixed the bug |
| Changing multiple variables to see what helps | Loses the signal; you won't know the real cause |
| Skipping reproduction because "it's obvious" | Often it isn't, and you fix the wrong thing |

## Output Template (for handoff)

```
## Bug
<one-line symptom>

## Root cause
<one-paragraph explanation>

## Reproduction
<exact steps / command>

## Fix
<file:line> — <what changed and why>

## Test
<file:line> — <name of new test>

## Verified
- [ ] New test passes
- [ ] Full suite passes
- [ ] Original repro no longer fails
```
