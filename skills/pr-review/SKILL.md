---
name: pr-review
description: Pre-PR checklist and reviewer briefing. Summarizes diff scope, flags breaking changes, checks test coverage delta, and suggests changelog entries. Use before opening a pull request or when reviewing one.
license: MIT
---

# PR Review

Pre-flight checklist for opening a pull request, and a structured framework for reviewing one. Pairs with `git-commit` (commit message quality) and the `code-reviewer` agent (line-level findings).

This skill owns PR workflow: diff scope, breaking-change analysis, coverage
delta, and reviewer briefing. Load relevant `sota-*` skills for domain-specific
checklists instead of copying those rules here.

## When to Use This Skill

- About to open a PR — sanity-check before pushing
- Reviewing someone else's PR — structured walkthrough
- Preparing PR description text
- Auditing a PR for breaking changes before merge to `main`

## When NOT to Use This Skill

- Trivial single-line PRs (typos, version bumps) — use judgment.
- Draft PRs intended only to share early ideas.

## Pre-PR Checklist

Run these checks in order before opening the PR:

### 1. Diff scope sanity

```bash
git fetch origin
git diff --stat origin/main...HEAD
git log --oneline origin/main..HEAD
```

Ask:
- Does the diff size match the stated goal?
- Are there unrelated changes (formatting, refactors) mixed in?
- Are there commits that should be squashed or split?

If unrelated changes are present → either split the PR or move them to a follow-up.

### 2. Breaking change scan

Look for:
- Public API signature changes (function args, return types, exported names)
- Schema migrations (DB, API contracts, config files)
- Renamed or deleted exports
- Default-value changes
- Behavioral changes that callers might depend on

```bash
# Grep for exported symbols changed
git diff origin/main...HEAD -- '*.ts' '*.py' | grep -E '^[-+](export|def |class )'
```

For every breaking change, the PR description must:
- Call it out under a **Breaking Changes** heading
- Include a migration note for callers

### 3. Test coverage delta

```bash
# Did tests change in proportion to code?
git diff --stat origin/main...HEAD | grep -E '(test|spec)'
```

Ask:
- Is there a test for every behavioral change?
- Is there a regression test for every bug fix?
- For new features: at least one happy-path and one error-path test.

If coverage didn't move with the code, justify it in the PR description.

### 4. Changelog / release notes

If the project keeps a CHANGELOG.md or release notes:
- User-visible change → add an entry now (don't defer).
- Use the `changelog-generator` skill to draft it.

### 5. Lint / type / test gates pass locally

Don't let CI tell you what `bun run ci` or `make check` could have told you 2 minutes ago.

### 6. Self-review the diff

Read your own diff top to bottom. You'll catch 30% of issues yourself.

## PR Description Template

```markdown
## Summary
<one-paragraph: what and why>

## Changes
- <bullet>
- <bullet>

## Breaking Changes
<none / list with migration notes>

## Testing
<how was this verified — tests added, manual steps, screenshots>

## Related
<issue links, design docs, prior PRs>

## Reviewer notes
<things you want the reviewer to look at carefully>
```

Keep the description scannable. Reviewers triage by skimming.

## Reviewing Someone Else's PR

A two-pass approach:

### Pass 1 — Big picture (5 minutes)

- Read the description. Does it answer *what* and *why*?
- Look at the file tree of changes. Does scope match description?
- Read the tests. They tell you what behavior is being claimed.
- Form an opinion: should this PR exist as written?

If pass 1 raises structural concerns, raise them **before** doing pass 2. Don't waste time on line-level nitpicks for a PR that needs to be split.

### Pass 2 — Line by line

For each changed file:
- Does each change trace to the stated goal?
- Are there obvious bugs, edge cases, security issues?
- Are names clear? Comments accurate?
- Do tests cover the change?

Use the `code-reviewer` agent for systematic line-level review.

## Output Categories

When leaving review comments, label them:

| Label | Meaning |
|-------|---------|
| **blocking** | Must fix before merge |
| **non-blocking** | Should fix, but don't block on it |
| **nit** | Style/preference, take or leave |
| **question** | Asking for clarification, not requesting change |
| **praise** | Genuine — call out good work |

Mixing these labels makes intent clear and avoids "is this a request or just a thought?" ambiguity.

## Anti-Patterns

| Don't | Why |
|-------|-----|
| Bundle refactors with feature changes | Reviewers can't tell what's the feature vs the refactor |
| "LGTM" without reading | Wastes the request |
| Block on style preferences without a label | Frustrates author; use `nit:` |
| Demand tests after the fact when none existed before | Discuss as a separate effort |
| Approve and immediately request changes | Use one signal at a time |

## Quick Commands Reference

```bash
gh pr create --fill                 # use commits as PR body
gh pr create --web                  # open in browser
gh pr checkout <number>             # check out a PR locally
gh pr diff <number>                 # show diff
gh pr review <number> --comment -b "..."
gh pr review <number> --approve
gh pr review <number> --request-changes -b "..."
```
