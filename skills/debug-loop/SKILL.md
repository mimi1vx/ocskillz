---
name: debug-loop
description: Systematic debugging methodology. Build a red-capable feedback loop first, then isolate → hypothesize → write a failing test → fix → verify. Use when chasing bugs, especially intermittent or hard-to-reproduce ones.
license: MIT
metadata:
  adapted-from: mattpocock/skills@abeeaf9 (diagnosing-bugs)
---

# Debug Loop

A disciplined debugging methodology. Pairs naturally with `karpathy-guidelines` (smallest change, verifiable success).

This skill owns the debugging sequence: reproduce, isolate, hypothesize,
encode the regression, fix, and verify. Use `sota-testing` for test-design
quality rather than duplicating its strategy here. Read the project's domain
vocabulary (GLOSSARY.md, AGENTS.md or docs, if present) before exploring.

## Redact

This skill has you show commands, outputs, and captured artifacts. **Redact every
secret first**: write `<REDACTED>` in its place. Build loops against environment
variables so the credential stays in the environment, not in what you show.
Captured artifacts carry auth headers: quote only the lines that carry the signal.
If the redacted output is not enough to diagnose the bug, say so and ask the user.

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
│  1. Reproduce          (red-capable loop)       │
│  2. Isolate            (smallest failing case)  │
│  3. Hypothesize        (3-5 ranked, falsifiable)│
│  4. Failing test       (encode the bug)         │
│  5. Fix                (smallest change)        │
│  6. Verify             (test passes; no regress)│
│  7. Document           (commit message / note)  │
└─────────────────────────────────────────────────┘
```

If you skip steps, you'll come back to this bug in 6 months.

## Step 1 — Reproduce

**Goal:** A feedback loop: one command that goes red on this bug. This step is the
skill. With a tight pass/fail signal you will find the cause, because bisection,
hypothesis-testing, and instrumentation all consume it. Without one, no amount of
reading code saves you. Spend disproportionate effort here.

Start with the exact error message, full stack trace, and version info (language,
dependencies, OS, environment).

### Ways to build the loop, roughly in this order

1. **Failing test** at whatever seam reaches the bug: unit, integration, e2e.
2. **Curl / HTTP script** against a running dev server.
3. **CLI invocation** with a fixture input, diffing stdout against a known-good snapshot.
4. **Headless browser script** (Playwright / Puppeteer) that drives the UI and asserts on DOM, console, or network.
5. **Replay a captured trace.** Save a real request, payload, or event log to disk and replay it through the code path in isolation.
6. **Throwaway harness.** A minimal subset of the system (one service, mocked dependencies) that exercises the bug path with a single call.
7. **Property / fuzz loop.** For "sometimes wrong output", run 1000 random inputs and look for the failure mode.
8. **Bisection harness.** For a bug that appeared between two known states (commit, dataset, version), automate "boot at state X, check, repeat" so `git bisect run` can drive it.
9. **Differential loop.** Run the same input through old and new versions (or two configs) and diff the outputs.
10. **HITL script.** Last resort. If a human must click, drive them with [`scripts/hitl-loop.template.sh`](scripts/hitl-loop.template.sh) so the loop stays structured and the captured output comes back to you.

### Tighten the loop

Treat the loop as a product. Once you have one, make it faster (cache setup, skip
unrelated init, narrow the scope), sharper (assert on the specific symptom, not
"didn't crash"), and more deterministic (pin time, seed RNG, isolate the filesystem,
freeze the network). A 2-second deterministic loop is a debugging superpower; a
30-second flaky one is barely better than none.

For a non-deterministic bug, raise the reproduction rate instead of chasing a clean
repro: loop the trigger 100×, parallelise, add stress, narrow timing windows, inject
sleeps. A 50% flake is debuggable; keep raising a 1% one.

### Done when

Step 1 is done when you can name **one command** (script path, test invocation, curl)
that you have **already run at least once** (show the invocation and its redacted
output) and that is:

- [ ] **Red-capable**: it drives the real bug path and asserts the user's exact symptom, so it can go red on this bug and green once fixed. "Runs without erroring" does not qualify.
- [ ] **Deterministic**: same verdict every run (flaky bugs: a pinned, high reproduction rate).
- [ ] **Fast**: seconds, not minutes.
- [ ] **Agent-runnable**: you run it unattended; a human joins only through the HITL script.

No red-capable command, no hypothesis: if you catch yourself reading code to build a
theory before this command exists, stop.

If you cannot build a loop, **stop**. List what you tried, and ask the user for (a)
access to an environment that reproduces it, (b) a redacted captured artifact (HAR,
log dump, core dump, timestamped recording), or (c) permission to add temporary
production instrumentation. Do not "fix" what you cannot see fail.

## Step 2 — Isolate

**Goal:** Smallest possible failing case. Watch the loop go red, and confirm it shows
the failure the **user** described, not a nearby one (wrong bug = wrong fix), at a
reproducible rate, with the exact symptom captured so later steps can check the fix
addresses it.

Then **minimise**: cut inputs, callers, config, data, and steps one at a time,
re-running the loop after each cut, and keep only what is load-bearing. Done when
removing any remaining element turns the loop green. The minimal repro shrinks the
hypothesis space and becomes the regression test in step 4.

- Binary search the test data; comment out branches that don't matter.
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

**Goal:** 3–5 ranked hypotheses before testing any of them; a single hypothesis
anchors on the first plausible idea.

Each must be **falsifiable**: state the prediction it makes.

> "If <X> is the cause, then <changing Y> will make the bug disappear / <changing Z> will make it worse."

Bad: "Something with the cache." Good: "If the TTL comparison uses `>` instead of `>=`,
then comparing at exactly the TTL will return a hit once flipped." A hypothesis
without a prediction is a vibe: sharpen or discard it. If you cannot articulate any
precisely, you don't understand the bug yet: go back to step 2.

**Show the ranked list to the user before testing.** They often know a recent deploy
or a ruled-out cause that re-ranks it instantly. Don't block on it if they are away.

### Instrument

Each probe maps to one prediction. Change one variable at a time.

1. **Debugger / REPL** if the environment supports it: one breakpoint beats ten logs.
2. **Targeted logs** at the boundaries that distinguish hypotheses, never "log everything and grep".

Tag every debug log with a unique prefix such as `[DEBUG-a4f2]` so cleanup is one
search. For performance regressions, logs are usually wrong: measure a baseline
(timing harness, profiler, query plan), then bisect. Measure first, fix second.

## Step 4 — Failing Test

**Goal:** A test that fails *because of the bug*, not for any other reason.

This is the most-skipped, most-valuable step. Write it before the fix, at a **correct
seam**: one where the test exercises the real bug pattern as it occurs at the call
site. A seam that is too shallow (a single-caller test for a multi-caller bug) gives
false confidence. If no correct seam exists, **that is itself a finding**: the
architecture prevents the bug from being locked down. Note it and flag it.

```python
def test_cache_entry_lives_until_exact_ttl():
    """Regression test for issue #123: entry expired one tick early."""
    cache = Cache(ttl_seconds=10)
    cache.set("k", "v")
    with freeze_time("2026-01-01 00:00:10"):  # exactly at TTL
        assert cache.get("k") == "v"  # currently fails
```

Watch it fail. If you forced the red by mutating code or a fixture, diff against a
pristine copy to prove the mutation landed before you trust it.

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
- Re-run the step 1 loop against the original, un-minimised scenario. No failure.
- If the bug was flaky, run the repro 50–100 times again and measure.
- Remove all `[DEBUG-...]` instrumentation (search for the prefix).
- Delete throwaway prototypes, or move them to a clearly marked debug location.

If anything is red, **revert and rethink**. Don't pile on more changes.

## When a Hypothesis Fails

Returning to step 2 or 3 is normal. Going round in circles is not.

- **Never rerun an unchanged attempt.** Every new cycle must change something:
  the hypothesis, input, code, environment, or diagnostic. Say why that change
  could give a different result.
- **Keep a short attempt log**: hypothesis → action → result. It stops you
  retrying dead ends and becomes the handoff if you have to stop.
- **Choose the next step for what it tells you.** Prefer the experiment that
  separates two remaining explanations (a bisect step, a log line, a smaller
  input) over the one that is merely the next thing to try.
- **A hard bug is not a blocker.** Exhaust reasonable options first.

Stop and hand back to the user when a missing input, credential, environment,
or decision is needed; when the remaining options would grow the fix beyond the
bug; when several materially different attempts produce no new evidence; or
when the cost is out of proportion to the bug. Report the attempt log, what
remains untested, and your recommendation.

If you find a different bug along the way, record its repro and propose it as
separate work instead of folding it into this fix.

## Step 7 — Document

**Goal:** Future-you (or the next dev) can understand what happened.

- Commit message includes: symptom, root cause, fix, and the hypothesis that turned out correct.
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
| Rerunning the same attempt hoping it passes | Produces no new evidence; flaky passes hide the bug |

## Output Template (for handoff)

```
## Bug
<one-line symptom>

## Status
<passed | failed | blocked | not run | partial>

## Root cause
<one-paragraph explanation>

## Reproduction
<the red-capable command, redacted; minimised scenario>

## Fix
<file:line> — <what changed and why>

## Test
<file:line> — <name of new test>

## Verified
- [ ] New test passes
- [ ] Full suite passes
- [ ] Original repro no longer fails
- [ ] Debug instrumentation and throwaway prototypes removed

## Attempts (if not passed)
<hypothesis → action → result, one line each; what remains untested>
```
