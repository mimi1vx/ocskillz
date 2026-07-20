# ocskillz

Custom skills, agents, and commands for opencode (and other coding agents).

## Overview

This repository contains personalized extensions that enhance coding agent capabilities:
- **Skills** — Specialized workflows for common tasks
- **Agents** — Reusable agent definitions with specific tool access
- **Commands** — Quick actions triggered with arguments
- **Scripts** — Maintenance helpers (e.g. skill validation)

## Inventory

### Skills (`skills/`)

| Skill | Trigger | Description |
|-------|---------|-------------|
| [git-commit](./skills/git-commit/SKILL.md) | "commit", "git commit", "create a commit" | Storytelling-focused Conventional Commits with human-in-the-loop "why" gathering. |
| [changelog-generator](./skills/changelog-generator/SKILL.md) | "create changelog", "release notes" | Turns commit history into user-friendly changelog entries. |
| [karpathy-guidelines](./skills/karpathy-guidelines/SKILL.md) | Writing/reviewing/refactoring code | Guardrails to reduce common LLM coding mistakes: surgical changes, simplicity first, verifiable success. |
| [debug-loop](./skills/debug-loop/SKILL.md) | Bug hunting, especially flaky/intermittent | Reproduce → isolate → hypothesize → failing test → fix → verify. |
| [pr-review](./skills/pr-review/SKILL.md) | Opening or reviewing a PR | Pre-PR checklist + structured review framework. Pairs with `code-reviewer` agent. |
| [spec-to-plan](./skills/spec-to-plan/SKILL.md) | "create a spec", "plan this feature" | 5-phase workflow: spec → clarify → markdown spec → todo → plan. |
| [sota-python](./skills/sota-python/SKILL.md) | Python code, tooling, frameworks, or audits | Production Python guidance with strong new-project defaults for uv, Ruff, and ty. |
| [sota-haskell](./skills/sota-haskell/SKILL.md) | Haskell code, Cabal, GHC, concurrency, FFI, or audits | Type-driven Haskell engineering with GHCup, Cabal, Fourmolu, HLint, profiling, testing, and packaging. |
| [sota-perl](./skills/sota-perl/SKILL.md) | Perl code, CPAN tooling, frameworks, or audits | Perl semantics, dependencies, APIs, async/processes, security, performance, testing, and releases. |
| [sota-rust](./skills/sota-rust/SKILL.md) | Rust code, Cargo, Tokio, unsafe, or audits | Ownership, errors, async, unsafe discipline, security, performance, and CI. |
| [sota-ml-engineering](./skills/sota-ml-engineering/SKILL.md) | Classical ML and MLOps systems | Training, serving, evaluation, drift, reproducibility, and governance. |
| [sota-llm-engineering](./skills/sota-llm-engineering/SKILL.md) | LLM, RAG, prompt, eval, or agent work | Eval-first LLM application quality, retrieval, orchestration, and operations. |
| [sota-testing](./skills/sota-testing/SKILL.md) | Test strategy or suite audits | Language-agnostic test design, doubles, integration, property testing, and suite health. |
| [sota-code-security](./skills/sota-code-security/SKILL.md) | Secure coding or security audits | Trust boundaries, injection, auth, crypto, web, data exposure, and LLM security. |
| [sota-sandboxing](./skills/sota-sandboxing/SKILL.md) | Untrusted code, parsers, or agent isolation | Isolation boundaries, OS/container hardening, privilege separation, and agent containment. |
| [sota-privacy-compliance](./skills/sota-privacy-compliance/SKILL.md) | Privacy, PII, GDPR, or compliance | Data lifecycle, consent, user rights, evidence, and breach readiness. |
| [sota-observability](./skills/sota-observability/SKILL.md) | Logging, metrics, tracing, SLOs, or incidents | Generic telemetry and operational-readiness practices. |
| [sota-data-engineering](./skills/sota-data-engineering/SKILL.md) | Batch, streaming, warehouse, or lakehouse work | Pipelines, CDC, contracts, storage, quality, and governance. |
| [typescript-tooling](./skills/typescript-tooling/SKILL.md) | TypeScript project setup or modernization | Bun + Biome + tsc. Includes monorepo guidance. |
| [deep-performance-audit](./skills/deep-performance-audit/SKILL.md) | "performance audit", "optimize codebase" | Hyper-intensively investigate the codebase to identify gross inefficiencies and propose isomorphic improvements. |
| [deep-project-primer](./skills/deep-project-primer/SKILL.md) | "project primer", "initialize project" | Initialization instructions for any project. Investigates code to understand architecture and purpose. |
| [idea-wizard](./skills/idea-wizard/SKILL.md) | "generate ideas", "improve project" | Generate, evaluate, and implement ideas to improve the project. Generates 30 ideas, filters and plans the top ones. |
| [readme-reviser](./skills/readme-reviser/SKILL.md) | "update readme", "revise docs" | Update the README and other documentation to reflect all of the recent changes to the project. |

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

### Scripts (`scripts/`)

| Script | Purpose |
|--------|---------|
| [validate-skills.sh](./scripts/validate-skills.sh) | Lint every `skills/*/SKILL.md` for required frontmatter (`name`, `description`) and verify `name` matches the directory. Exits non-zero on failure. |

## Validation

Run the skill validator any time you add or modify a skill:

```bash
./scripts/validate-skills.sh
```

Output:

```
ok   [changelog-generator]
ok   [debug-loop]
...
Checked: 23  Errors: 0
```

## Installation

These configurations are designed for opencode. Place this repository at `~/.config/opencode/` or symlink it:

```bash
ln -s /path/to/ocskillz ~/.config/opencode
```

## License

Original local skills, including `sota-haskell` and `sota-perl`, are MIT-licensed where declared
in their frontmatter. The externally adapted `sota-*` skills are CC BY 4.0. See
[SOTA-ATTRIBUTION.md](./skills/SOTA-ATTRIBUTION.md) for source, modification,
pinning, and refresh details.
