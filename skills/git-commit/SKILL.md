---
name: git-commit
description: Generates storytelling-focused Conventional Commits messages then commits. Use when the user says "commit", "git commit", or asks to commit changes, wants to create a commit, or when work is complete and ready to commit.
allowed-tools: bash(git status:*), bash(git diff:*), bash(git add:*), bash(git branch:*), bash(git log:*), AskUserQuestion
license: MIT
---

# Git Commit

Generate Conventional Commits messages that tell a complete story for future code archeology.

**Core principle: emphasize WHY over WHAT.** The diff already shows WHAT — the commit message must explain WHY. Future readers can read the code; they cannot read your mind.

## Critical Rules

- **NEVER add Co-Authored-By or mention any agent** in the commit message.
- **Never use `git add -A` or `git add .`** — commit only files already staged and understood.
- **The user MUST confirm before `git commit` or `git push`.** These are intentionally not in `allowed-tools`.

## Workflow

### 1. Gather Context

```bash
git status
git diff --staged
git log --oneline -5
git branch --show-current
```

### 2. Ask WHY (Human-in-the-Loop)

**ALWAYS use AskUserQuestion to ask why the change was made.** Generate 3–4 plausible options based on the diff (and any Jira context) — specific, not generic. The user can always pick "Other".

Wait for the answer and incorporate it into the message.

### 3. Analyze Technical Changes

Briefly note what changed (files, functions, deps, config) — this becomes the short WHAT section.

### 4. Compose the Message

**The WHY sections are the heart of the message — invest the most thought there. The WHAT section should be brief.**

```
type(scope): concise subject line

Why this change was needed:
[PRIMARY FOCUS — motivation, trigger, constraints, user explanation, Jira context]

Problem solved:
[PRIMARY FOCUS — the business/technical problem and why it mattered]

What changed:
[Brief technical summary — the diff shows the details]
```

**Conventional Commits types:** `feat`, `fix`, `docs`, `style`, `refactor`, `test`, `chore`, `perf`, `ci`.

### 5. Commit (After User Approval)

Use a heredoc for multi-line messages:

```bash
git commit -m "$(cat <<'EOF'
type(scope): subject line

Why this change was needed:
...

Problem solved:
...

What changed:
...
EOF
)"
```

## Example

```
feat(mcp): add tool execution timeout handling

Why this change was needed:
Tools were hanging indefinitely when external APIs failed to respond,
blocking the entire MCP server and causing user-facing timeouts in the
chat interface.

Problem solved:
External API failures no longer block the MCP server. Users now receive
clear timeout errors instead of indefinite hanging.

What changed:
- Configurable timeout wrapper around tool execution
- Graceful timeout error messages
- Per-tool timeout configuration in the tool registry
```

## Reminders

- **Never skip the "why" question** — it is the primary value of the commit message.
- **WHY over WHAT** — spend most of the message on motivation and problem context, not on restating the diff.
- **Think about the reader** — someone debugging this code in 6 months.
- **Only staged changes matter** — don't pull in new or unstaged files.
