---
name: deep-project-primer
description: Orient on an unfamiliar project before changing it. Reads AGENTS.md and README.md in full, then investigates the code to map purpose, architecture, entry points, and build/test commands, and reports a short primer. Use at the start of work on a project, or when asked to "prime", "get familiar with", "onboard onto", or "understand" a codebase.
---

# Deep Project Primer

Build an accurate mental model of the project before touching it. The output is
understanding, not changes: do not edit files while priming.

## 1. Read the instructions in full

Read every line of these, in this order, when they exist:

1. `AGENTS.md` (and any nested `AGENTS.md` in directories you will work in;
   also `CLAUDE.md` / `.github/copilot-instructions.md` if that is what the
   project uses)
2. `README.md`
3. `CONTRIBUTING.md`, `docs/` index, ADRs (`docs/adr/`, `adr/`)

Instructions here override your defaults: toolchain, test commands, style,
forbidden actions, and approval rules. Note any you must follow.

If the session has a persistent memory store, search it for this project
before exploring; recalled constraints are cheaper than rediscovered ones.

## 2. Map the code

Use the project's preferred search and code-intelligence tools (AGENTS.md
usually names them). For a large tree, delegate breadth-first exploration to an
explore subagent and keep the main context for synthesis.

Establish, with file paths as evidence:

- **Purpose** — what the project does and who uses it.
- **Shape** — top-level layout, languages, manifests (`package.json`,
  `pyproject.toml`, `Cargo.toml`, `*.cabal`, `cpanfile`, `go.mod`, …).
- **Entry points** — binaries, `main`, plugin/handler registration, routes,
  CLI commands, exported API.
- **Data flow** — how a typical request, job, or input moves through the
  modules; where state lives (DB, files, caches).
- **Gates** — the exact build, lint, type-check, and test commands, from CI
  config and the task runner, not from guesses.
- **Conventions** — error handling, logging, test layout, naming, and any
  pattern the codebase repeats that new code should match.
- **Hazards** — generated files, vendored code, migrations, secrets handling,
  anything marked "do not edit".

Read code, not just file names. Trace at least one representative path end to
end.

## 3. Verify cheaply

When it is safe and fast, run the documented test or build command once to
confirm the baseline state. Record failures as pre-existing; do not fix them
during priming.

## 4. Report

Close with a primer of at most ~25 lines:

```
Purpose:      <one sentence>
Stack:        <languages, frameworks, runtime>
Layout:       <key dirs → role>
Entry points: <file:line list>
Flow:         <2–4 lines>
Commands:     build / lint / types / test — exact invocations, baseline result
Conventions:  <patterns new code must match>
Hazards:      <generated, vendored, do-not-edit, approval gates>
Open questions: <what the docs and code did not answer>
```

State uncertainty plainly. If docs and code disagree, say so and trust the
code; suggest `readme-reviser` if the drift is worth fixing.
