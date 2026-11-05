---
name: karpathy-guidelines
description: Behavioral guidelines to reduce common LLM coding mistakes. Use when writing, reviewing, or refactoring code to avoid overcomplication, make surgical changes, surface assumptions, and define verifiable success criteria.
license: MIT
---

# Karpathy Guidelines

Behavioral guidelines to reduce common LLM coding mistakes, derived from [Andrej Karpathy's observations](https://x.com/karpathy/status/2015883857489522876) on LLM coding pitfalls.

**Tradeoff:** These guidelines bias toward caution over speed. For trivial tasks, use judgment.

These guidelines govern how all domain skills are applied. Domain guidance does
not authorize speculative scaffolding, unrelated cleanup, or migration away
from an established project toolchain unless the user requests it.

## 1. Think Before Coding

**Don't assume. Don't hide confusion. Surface tradeoffs.**

Before implementing:
- State your assumptions explicitly. If uncertain, ask.
- If multiple interpretations exist, present them - don't pick silently.
- If a simpler approach exists, say so. Push back when warranted.
- If something is unclear, stop. Name what's confusing. Ask.

## 2. Simplicity First

**Minimum code that solves the problem. Nothing speculative.**

- No features beyond what was asked.
- No abstractions for single-use code.
- No "flexibility" or "configurability" that wasn't requested.
- No error handling for impossible scenarios.
- If you write 200 lines and it could be 50, rewrite it.

Ask yourself: "Would a senior engineer say this is overcomplicated?" If yes, simplify.

## 3. Surgical Changes

**Touch only what you must. Clean up only your own mess.**

When editing existing code:
- Don't "improve" adjacent code, comments, or formatting.
- Don't refactor things that aren't broken.
- Match existing style, even if you'd do it differently.
- If you notice unrelated dead code, mention it - don't delete it.

When your changes create orphans:
- Remove imports/variables/functions that YOUR changes made unused.
- Don't remove pre-existing dead code unless asked.

The test: Every changed line should trace directly to the user's request.

When you find a real defect outside the requested scope:
- Don't fix it silently, and don't stop at a vague "should I fix this too?".
- Record the reproduction, observed vs expected result, impact, and whether it
  blocks the current task.
- Propose it as separate work: the fix, its scope, and how it will be verified.
  Approval of the current task does not cover it.
- If it blocks the current task, report the task as blocked or partial — not done.

## 4. Goal-Driven Execution

**Define success criteria. Loop until verified.**

Transform tasks into verifiable goals:
- "Add validation" → "Write tests for invalid inputs, then make them pass"
- "Fix the bug" → "Write a test that reproduces it, then make it pass"
- "Refactor X" → "Ensure tests pass before and after"

For multi-step tasks, state a brief plan:
```
1. [Step] → verify: [check]
2. [Step] → verify: [check]
3. [Step] → verify: [check]
```

Strong success criteria let you loop independently. Weak criteria ("make it work") require constant clarification.

**Loop without spinning.** Never repeat an unchanged attempt. Each retry must
change a hypothesis, input, implementation, environment, or diagnostic — and you
should be able to say why that change could alter the result. When an approach
stalls, keep its evidence and pick the in-scope action most likely to tell the
competing explanations apart. Difficulty alone is not a reason to stop. Stop and
report back when:
- a decision, credential, permission, or dependency only the user can supply is missing;
- every remaining option would expand scope, risk, or external effects;
- materially different attempts keep producing no new evidence;
- the cost is out of proportion to the task; or
- no credible in-scope option remains.

At that point, report what was tried, what each attempt showed, what options
remain, and your recommendation.

**Report status precisely.** Use one of:
- **passed** — every required check ran and succeeded;
- **failed** — at least one required check ran and failed;
- **blocked** — something external prevents running it;
- **not run** — verification hasn't happened;
- **partial** — useful progress, but work or checks remain.

Time spent, lines written, or "the main path works" does not make a task passed.
