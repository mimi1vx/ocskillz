---
name: idea-wizard
description: Generate, evaluate, and plan ideas to improve the project. Brainstorms 30 one-line ideas, critically filters them, ranks the survivors by impact, confidence, and effort, writes concrete plans for the best, and implements only the ones the user approves. Use for "generate ideas", "how could we improve this project", "brainstorm improvements".
---

# Idea Wizard

Find the few improvements that are clearly worth doing, and prove it before
writing code.

## 0. Understand the project first

If you have not primed on this project in the current session, run
`deep-project-primer` first. Ideas that ignore the project's purpose,
conventions, or AGENTS.md rules are noise.

Ask the user for a focus if none was given and the project is large
(performance, DX, reliability, UX, docs, tests, security). Otherwise cover all.

## 1. Generate — 30 one-liners

List 30 ideas, one line each, numbered. Aim for breadth: bugs and sharp edges,
missing tests, performance, simplification and deletion, developer experience,
docs, security, observability, user-facing features. Ground each in something
you actually saw in the code (cite `file` when possible). No duplicates, no
generic advice ("add more tests").

## 2. Filter — be ruthless

Evaluate every idea and reject those that are:

- speculative ("might be useful someday") or add unrequested configurability
- already done, or contradicted by the code or AGENTS.md
- high churn for low gain, or a migration away from the established toolchain
- unverifiable — no way to tell whether it worked

Show the verdict compactly: `#n keep|reject — reason`. Expect most to fail.

## 3. Rank the survivors

Score each kept idea and sort by `(Impact × Confidence) / Effort`:

| # | Idea | Impact 1–5 | Confidence % | Effort S/M/L | Downside |
|---|------|-----------|--------------|--------------|----------|

Confidence is your honest probability that it measurably improves the project.

## 4. Plan the top ideas

For the top 3–5, give a concrete plan: files to touch, the change (snippets
where they clarify), how success is verified (test, benchmark, command), the
risks, and what you would deliberately not do.

## 5. Implement only with approval

Stop and ask which ideas to implement — never implement on your own initiative.
Then build each approved idea as its own surgical change, following
`karpathy-guidelines`: one idea per change, verify it against its success
check, run the project's gates, and report the result before moving on.
