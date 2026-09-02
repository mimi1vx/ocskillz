---
name: change-walkthrough
description: Conversational, paced explanation of a diff or PR, grouped by behavioral effect rather than by file. Use for "walk me through", "explain this PR", "explain these changes", "walkthrough of the diff".
license: MIT
---

# Change Walkthrough

A paced, conversational explanation of a set of code changes — one behavioral
topic at a time, waiting for the reader before moving on. This is not a
verdict: use `pr-review` when the ask is a checklist and a merge/no-merge
opinion, the `code-reviewer` agent when the ask is line-level findings, and
`debug-loop` when the ask is root-causing a bug. This skill only explains.

## When to Use This Skill

- Onboarding onto an unfamiliar PR before working on it
- Understanding a colleague's change before approving or building on it
- Reviewing a large diff where a full dump would drown the reader
- Handover of work an agent did in an earlier session, for a human to absorb

## When NOT to Use This Skill

- Trivial diffs (a typo, a version bump) — just say what changed in a sentence.
- The user wants a verdict, not an explanation — use `pr-review`.
- The user wants the change fixed or extended — switch to build mode instead.

## Choosing the Topics

Group by behavioral effect, not by file or hunk. Two files touched for one
reason are one topic; one file touched for two reasons is two topics.

Prioritize consequences the stated goal doesn't already imply: changed failure
handling, retained or migrated state, compatibility breaks, side effects
outside the obvious call path, and tradeoffs the author made implicitly.

Skip pure bookkeeping — version bumps, lockfile churn, import reordering,
rename-only diffs — unless it's hiding a real consequence (a rename that also
changes a public API, say).

Order topics foundational-first: the piece other topics depend on to make
sense comes first, even if it's not the biggest or the newest.

## Rhythm

Announce `Step X of Y: <topic>` only when starting a new topic, not on every
message. Explain one change, then stop: what it did before, what it does now,
why it matters. Wait.

- "okay" / "got it" / similar → advance to the next topic.
- A question → stay on the current topic and go deeper; don't advance.
- "come back to this" → defer the topic, keep going, and surface it again at
  the end.

Never quiz the reader to check comprehension, and never ask permission to
continue after every single step — the pacing itself is the interaction.

## Style

Keep it short and scannable. Plain language over jargon; define any term the
reader might not know on first use. Reach for a small snippet or a table only
when it earns its place over prose. Cite exact locations (`file:line`) instead
of describing code by feel.

Distinguish behavior that's actually new from behavior that already existed
elsewhere and is just newly visible in this diff. Verify claims against the
implementation before stating them — don't narrate what a diff looks like it
does without checking. State uncertainty plainly rather than smoothing over
it. Flag risks the way a careful colleague would, not the way the change's
author would defend it.

## Anti-Patterns

| Don't | Why |
|-------|-----|
| Walk the diff file-by-file | Files rarely match behavioral units; the reader loses the thread |
| Dump every topic in one message | Defeats the pacing that makes a large diff digestible |
| Ask "shall I continue?" after every step | Slows the reader down; "okay" already means continue |
| Explain what the code does line by line | The point is the *change*, not a code walkthrough of the result |
| Treat "I understand" as "I approve" | Understanding and approval are different acts — don't conflate them |

This is a discussion, not an edit session — don't change code unless asked.
