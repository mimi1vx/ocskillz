---
description: Walk through code changes one behavioral topic at a time
agent: plan
---

Load the `change-walkthrough` skill and use it for this session.

Resolve the target from the argument below:
- A PR number → `gh pr diff <number>`
- A git ref or range (branch name, commit range) → `git diff <ref>`
- Nothing given → uncommitted changes; if there are none, diff against the
  default branch (`git diff origin/main...HEAD` or equivalent)

Then walk through the resulting diff following the skill's rhythm: pick
behavioral topics, announce `Step X of Y: <topic>` when starting each one,
explain it, and stop for the reader.

Target: $ARGUMENTS
