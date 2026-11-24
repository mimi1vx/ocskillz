---
description: Retrospective on a coding session, with suggested improvements to the agent's environment
---

Run a **retrospective**. Suggest improvements to the coding agent's **environment** to improve future runs. Suggest only: make no edits.

## Steps

1. Load the `writing-for-agents` skill for the writing style guide.

2. Read the primary sources for the session the user names. This may mean searching session logs on this machine. With no session named, use the current one. Target: $ARGUMENTS

3. Look for candidates for improvement in these categories:

- **Navigation**: how easy was it for the agent to find the right files? Are there hidden dependencies between files? Would a **navigation pointer** help? *Use when* the session took long to find a piece of information.
- **Automated checks**: could an automated check (lint, types, tests, filesystem linters) have caught the agent's mistakes? Read the repo's own check scripts and CI workflow first, so a check that already exists but sits unwired or silently broken is the finding, not a reinvention. A repo with no **guardrail** (no pre-commit hook and no CI job running its lint, type, and test commands) is itself a finding. *Use when* the agent made a mistake a check could have caught, or the repo has no guardrail.
- **Coding standards**: should the reviewer agent get a new rule, or should an existing rule be removed or clarified? Classify the violation first. A **mechanical** one (a fixed syntactic pattern, a banned API, an import shape, a file-location rule) gets a deterministic check: a custom linter rule, a pre-commit hook, or a CI job, whichever is cheapest for the repo. Reserve a coding-standards document for genuine **judgement calls** (cross-file consistency, matching surrounding style). *Use when* the reviewer failed to catch a mistake.
- **AGENTS.md and global instructions**: should any steering instruction move to coding standards or an automated check? *Use when* the file is large, in the repo or the user's global scope.
- **Tool economy**: did the agent make expensive tool calls that could be streamlined? Is any custom tooling (CLIs, MCP servers) token-inefficient? *Use when* the agent made an expensive call.
- **No-ops**: find instructions in steering files that do not change the agent's behaviour. *Use when* the steering files are large and unwieldy.
- **Information access**: could the agent get more information (dev server logs teed to a file, read-only access to third-party services)? *Use when* a crucial piece of information was unavailable.

4. Present the candidates to the user, in order of severity.

## Reference

### Implementation versus review

All work passes through two stages. The implementation agent has the most **context pressure**: it explores, writes code, and debugs. The review agent has the least: it receives a diff, needs no exploration, and rarely writes code. So the review agent should impose coding standards, not the implementation agent.

### Files

- `AGENTS.md`: pushed into the context of every agent working in the repo. Use it very sparingly, usually only for **navigation pointers** to other files.
- A coding-standards file: read during review, not implementation. Add navigation pointers to docs folders once it passes 1,000 lines.
- Docs: reference files reached by pointers from other files. Look for existing docs before writing new ones.
- Skills: use a skill for docs (its description goes into the agent's context) and a command for human-invoked flows. Follow `writing-for-agents`.
