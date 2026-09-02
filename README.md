# ocskillz

Custom skills, agents, and commands for opencode (and other coding agents).

## Overview

This repository contains personalized extensions that enhance coding agent capabilities:
- **Skills** — Specialized workflows for common tasks
- **Agents** — Reusable agent definitions with specific tool access
- **Commands** — Quick actions triggered with arguments
- **Scripts** — Maintenance helpers (e.g. skill validation)
- **Plugin** — opencode plugin that registers all of the above without claiming `~/.config/opencode/`

## Inventory

### Skills (`skills/`)

| Skill | Trigger | Description |
|-------|---------|-------------|
| [git-commit](./skills/git-commit/SKILL.md) | "commit", "git commit", "create a commit" | Storytelling-focused Conventional Commits with human-in-the-loop "why" gathering. |
| [changelog-generator](./skills/changelog-generator/SKILL.md) | "create changelog", "release notes" | Turns commit history into user-friendly changelog entries. |
| [karpathy-guidelines](./skills/karpathy-guidelines/SKILL.md) | Writing/reviewing/refactoring code | Guardrails to reduce common LLM coding mistakes: surgical changes, simplicity first, verifiable success. |
| [debug-loop](./skills/debug-loop/SKILL.md) | Bug hunting, especially flaky/intermittent | Reproduce → isolate → hypothesize → failing test → fix → verify. |
| [pr-review](./skills/pr-review/SKILL.md) | Opening or reviewing a PR | Pre-PR checklist + structured review framework. Pairs with `code-reviewer` agent. |
| [change-walkthrough](./skills/change-walkthrough/SKILL.md) | "walk me through", "explain this PR" | Paced, conversational diff explanation grouped by behavioral effect, one topic at a time. |
| [spec-to-plan](./skills/spec-to-plan/SKILL.md) | "create a spec", "plan this feature" | 5-phase workflow: spec → clarify → markdown spec → todo → plan. |
| [sota-python](./skills/sota-python/SKILL.md) | Python code, tooling, frameworks, or audits | Production Python guidance with strong new-project defaults for uv, Ruff, and ty. |
| [sota-haskell](./skills/sota-haskell/SKILL.md) | Haskell code, Cabal, GHC, concurrency, FFI, or audits | Type-driven Haskell engineering with GHCup, Cabal, Fourmolu, HLint, profiling, testing, and packaging. |
| [sota-perl](./skills/sota-perl/SKILL.md) | Perl code, CPAN tooling, frameworks, or audits | Perl semantics, dependencies, APIs, async/processes, security, performance, testing, and releases. |
| [sota-rust](./skills/sota-rust/SKILL.md) | Rust code, Cargo, Tokio, unsafe, or audits | Ownership, errors, async, unsafe discipline, security, performance, and CI. |
| [sota-typescript](./skills/sota-typescript/SKILL.md) | TypeScript or JavaScript code, tooling, or audits | Bun/Node toolchain, strict typing, idioms, async and cancellation, supply chain, performance, and runner mechanics. |
| [sota-ml-engineering](./skills/sota-ml-engineering/SKILL.md) | Classical ML and MLOps systems | Training, serving, evaluation, drift, reproducibility, and governance. |
| [sota-llm-engineering](./skills/sota-llm-engineering/SKILL.md) | LLM, RAG, prompt, eval, or agent work | Eval-first LLM application quality, retrieval, orchestration, and operations. |
| [sota-testing](./skills/sota-testing/SKILL.md) | Test strategy or suite audits | Language-agnostic test design, doubles, integration, property testing, and suite health. |
| [sota-code-security](./skills/sota-code-security/SKILL.md) | Secure coding or security audits | Trust boundaries, injection, auth, crypto, web, data exposure, and LLM security. |
| [sota-sandboxing](./skills/sota-sandboxing/SKILL.md) | Untrusted code, parsers, or agent isolation | Isolation boundaries, OS/container hardening, privilege separation, and agent containment. |
| [sota-privacy-compliance](./skills/sota-privacy-compliance/SKILL.md) | Privacy, PII, GDPR, or compliance | Data lifecycle, consent, user rights, evidence, and breach readiness. |
| [sota-observability](./skills/sota-observability/SKILL.md) | Logging, metrics, tracing, SLOs, or incidents | Generic telemetry and operational-readiness practices. |
| [sota-data-engineering](./skills/sota-data-engineering/SKILL.md) | Batch, streaming, warehouse, or lakehouse work | Pipelines, CDC, contracts, storage, quality, and governance. |
| [apple-container](./skills/apple-container/SKILL.md) | Apple `container` CLI on macOS, arm64 pinning | Command reference plus forcing `linux/arm64`, catching silent amd64 fallback, and verifying image architecture. |
| [deep-performance-audit](./skills/deep-performance-audit/SKILL.md) | "performance audit", "optimize codebase" | Hyper-intensively investigate the codebase to identify gross inefficiencies and propose isomorphic improvements. |
| [deep-project-primer](./skills/deep-project-primer/SKILL.md) | "project primer", "initialize project" | Initialization instructions for any project. Investigates code to understand architecture and purpose. |
| [idea-wizard](./skills/idea-wizard/SKILL.md) | "generate ideas", "improve project" | Generate, evaluate, and implement ideas to improve the project. Generates 30 ideas, filters and plans the top ones. |
| [readme-reviser](./skills/readme-reviser/SKILL.md) | "update readme", "revise docs", "sync docs", "stale docs" | Add, correct, and remove documentation to match the current code, written in timeless voice. |

### Agents (`agents/`)

| Agent | Tool access | Purpose |
|-------|-------------|---------|
| [code-reviewer](./agents/code-reviewer.md) | read-only + git diff/log + todowrite/question | Reviews recent changes; outputs Critical / Warnings / Suggestions. |
| [refactor](./agents/refactor.md) | read + edit (with `ask`) + todowrite/question | Cautious behavior-preserving refactors. Embeds karpathy-guidelines. |
| [planner](./agents/planner.md) | read-only + todowrite/question + extended bash/br read | Planning agent with strong clarifying-question discipline. Custom personality on top of opencode's built-in `plan` mode. |

opencode also ships built-in `build` and `plan` agents — referenced by some commands below.

### Commands (`commands/`)

| Command | Agent | Purpose |
|---------|-------|---------|
| [test](./commands/test.md) | `build` (built-in) | Run pytest with coverage; prefers `uv run pytest`, falls back to `python3 -m pytest`. |
| [clean-init](./commands/clean-init.md) | `build` (built-in) | Analyze codebase and write/update `AGENTS.md`. |
| [bug-hunter](./commands/bug-hunter.md) | `general` | Randomly explore code to find and fix bugs. |
| [code-reorganizer](./commands/code-reorganizer.md) | `planner` | Propose a reorganization plan for scattered code files. |
| [de-slopify](./commands/de-slopify.md) | `refactor` | Remove AI slop style writing from text. |
| [walkthrough](./commands/walkthrough.md) | `plan` (built-in) | Walk through a PR/diff one behavioral topic at a time using `change-walkthrough`. |

### Scripts (`scripts/`)

| Script | Purpose |
|--------|---------|
| [validate-skills.sh](./scripts/validate-skills.sh) | Lint skills, agents, and commands, then verify they reach opencode's resolved config. Exits non-zero on failure. |

### Plugin (`plugin/`)

| File | Purpose |
|------|---------|
| [ocskillz.js](./plugin/ocskillz.js) | opencode plugin that registers this repo's skills, agents, and commands through the `config` hook. Used by the plugin install below. |

## Validation

Run the validator any time you add or modify a skill, agent, or command:

```bash
./scripts/validate-skills.sh
```

Output:

```
ok   [changelog-generator]
...
ok   [agent: planner]
ok   [command: test]

registration: 25 skills, 3 agents, 6 commands

Checked: 34  Errors: 0
```

Three phases run:

1. **Skills** — `skills/*/SKILL.md` has `name` and `description`, and `name` matches the directory.
2. **Agents and commands** — frontmatter has a `description`, the body is non-empty, agent `name` matches the filename, `mode` is valid, and every command's `agent` names an agent that exists.
3. **Registration** — loads the plugin into a throwaway project and asserts every skill, agent, and command reaches `opencode debug config`.

Phase 3 is skipped with a notice — not a failure — when `opencode` or `python3` is not on `PATH`, or when dependencies are not installed. Install them with `bun install` (or `npm install`) to enable it.

## Installation

Add ocskillz to the `plugin` array in your `opencode.json` (global or project):

```json
{
  "plugin": ["ocskillz@git+https://github.com/mimi1vx/ocskillz"]
}
```

Restart opencode. The plugin registers all skills, agents, and commands from wherever opencode cached the package, leaving `~/.config/opencode/` free for your own configuration.

Anything you define yourself wins: if you already have an agent or command with the same name, the plugin leaves it alone.

## License

Original local skills, including `sota-haskell` and `sota-perl`, are MIT-licensed where declared
in their frontmatter. The externally adapted `sota-*` skills are CC BY 4.0. See
[SOTA-ATTRIBUTION.md](./skills/SOTA-ATTRIBUTION.md) for source, modification,
pinning, and refresh details.

`change-walkthrough` is an original MIT-licensed skill, inspired by the concept
of `rekram1-node/skills`, not derived from its text.
