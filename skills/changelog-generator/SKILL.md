---
name: changelog-generator
description: Creates user-facing changelogs and release notes from git history. Collects commits (and PR titles when available) for a range, groups them into categories, drops internal noise, and rewrites technical commits in plain user language, matching the project's existing CHANGELOG format. Use for "create a changelog", "release notes", "what changed since v1.2", "update CHANGELOG.md".
license: MIT
---

# Changelog Generator

Turn commit history into release notes that users understand. A changelog is
change-relative and dated; for docs that describe the current state, use
`readme-reviser` instead.

## 1. Establish the range

Use the range, tag, version, or dates the user gives. Otherwise default to
"since the last release tag" and say so.

```bash
git describe --tags --abbrev=0                 # last tag
git log --no-merges --format='%h %s%n%b%n---' <last-tag>..HEAD
git log --merges --format='%h %s' <last-tag>..HEAD   # PR merge titles
```

If the GitHub CLI is available and the repo uses PRs, PR titles and labels are
often better source text than raw commits:
`gh pr list --state merged --search "merged:>=<date>" --json number,title,labels`.

## 2. Match the existing format

If `CHANGELOG.md` exists, copy its structure exactly: heading style, version
and date format, category names, link style, emoji or not. If a style guide
exists (`CHANGELOG_STYLE.md`, `CONTRIBUTING.md`), follow it. With no existing
file, use [Keep a Changelog](https://keepachangelog.com/) categories.

## 3. Categorize

Map Conventional Commit types where present; read the diff when the subject is
unclear.

| Source | Category |
|--------|----------|
| `feat` | Added |
| behavior change, `perf`, user-visible `refactor` | Changed |
| `fix` | Fixed |
| removed feature or flag | Removed |
| `deprecate` notice | Deprecated |
| CVE, security fix, dependency bump fixing a vuln | Security |
| `!` after type, `BREAKING CHANGE:` footer | **Breaking** — list first, with a migration note |

Drop internal noise unless it affects users: `test`, `ci`, `chore`, `style`,
`docs` for contributor docs, pure refactors, lockfile churn, reverted pairs.

## 4. Rewrite for users

- Describe the effect, not the implementation: "Search includes file
  contents" — not "add content index to SearchService".
- One entry per user-visible change; merge commits that are one change.
- Keep issue/PR references if the project's changelog uses them.
- Never invent benefits, numbers ("2x faster"), or features. Every entry must
  trace to at least one commit; if the impact is unclear, ask or flag it.

## 5. Deliver

Show the draft in chat first. Write to `CHANGELOG.md` (newest version on top,
under any `Unreleased` section convention) only when the user asks. Close
with the commit range used and a list of commits you dropped as internal, so
the user can rescue any that matter.

## Example

```markdown
## [2.5.0] - 2026-03-15

### Breaking
- The `--format` flag is replaced by `--output`. Rename it in scripts;
  `--format` now exits with an error.

### Added
- Team workspaces: group projects and invite members per workspace.
- Press `?` to see all keyboard shortcuts.

### Fixed
- Large images no longer fail to upload.
- Scheduled posts use the account's time zone.
```

Inspired by Manik Aggarwal's use case from Lenny's Newsletter.
