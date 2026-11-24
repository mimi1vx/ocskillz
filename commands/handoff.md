---
description: Compact the current conversation into a handoff document for another agent
---

Write a handoff document summarising the current conversation so a fresh agent can continue the work. Save it to the temporary directory of the user's OS (`$TMPDIR`, else `/tmp`; `%TEMP%` on Windows), not the current workspace.

Include a "suggested skills" section naming which skills the next agent should load with the `skill` tool.

Do not duplicate content already captured in other artifacts (specs, plans under `~/.opencode/plan/`, beads issue IDs, issues, commits, diffs). Reference them by path, ID, or URL instead.

Redact any sensitive information, such as API keys, passwords, or personally identifiable information.

If the arguments below are not empty, treat them as a description of what the next session will focus on and tailor the document to it.

Next session focus: $ARGUMENTS
