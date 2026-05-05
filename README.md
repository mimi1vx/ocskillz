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
| [python-tooling](./skills/python-tooling/SKILL.md) | Python project setup, migrating from pip/black/mypy | Modern stack: uv, ruff, ty. |
| [python-testing-patterns](./skills/python-testing-patterns/SKILL.md) | Writing Python tests | pytest, fixtures, mocking, parametrize, async, coverage. Slim index + topic references. |
| [typescript-tooling](./skills/typescript-tooling/SKILL.md) | TypeScript project setup or modernization | Bun + Biome + tsc. Includes monorepo guidance. |

### Agents (`agents/`)

| Agent | Tool access | Purpose |
|-------|-------------|---------|
| [code-reviewer](./agents/code-reviewer.md) | read-only + git diff/log | Reviews recent changes; outputs Critical / Warnings / Suggestions. |
| [refactor](./agents/refactor.md) | read + edit (with `ask`); bash limited | Cautious behavior-preserving refactors. Embeds karpathy-guidelines. |
| [planner](./agents/planner.md) | read-only | Planning agent with strong clarifying-question discipline. Custom personality on top of opencode's built-in `plan` mode. |

opencode also ships built-in `build` and `plan` agents — referenced by some commands below.

### Commands (`commands/`)

| Command | Agent | Purpose |
|---------|-------|---------|
| [test](./commands/test.md) | `build` (built-in) | Run pytest with coverage; prefers `uv run pytest`, falls back to `python3 -m pytest`. |
| [clean-init](./commands/clean-init.md) | `build` (built-in) | Analyze codebase and write/update `AGENTS.md`. |

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
Checked: 9  Errors: 0
```

## Installation

These configurations are designed for opencode. Place this repository at `~/.config/opencode/` or symlink it:

```bash
ln -s /path/to/ocskillz ~/.config/opencode
```

## License

MIT. All bundled skills declare `license: MIT` in their frontmatter for consistency.
