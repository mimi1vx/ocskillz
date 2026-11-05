# Phase 2: Plan Generation Prompt

Use this prompt after all questions have been answered and clarifications are complete.

---

Based on our full exchange, now produce a markdown plan document (`plan.md`).

Requirements for the plan:
- Include clear, minimal, concise steps.
- Track the status of each step using these emojis:
  - 🟩 Done
  - 🟨 In Progress
  - 🟥 To Do
- Include dynamic tracking of overall progress percentage (at top).
- Do NOT add extra scope or unnecessary complexity beyond explicitly clarified details.
- Steps should be modular, elegant, minimal, and integrate seamlessly within the existing codebase.
- Include important implementation details within the plan.
- List files and parts of files that need to be changed.
- Map every acceptance criterion to a test, command, or reproducible procedure and its expected result.
- Mark every coverage surface as covered or "N/A — reason".

Markdown Template Example:

```markdown
# (Example) Feature Implementation Plan

**Overall Progress:** `0%`

## Decisions (confirmed)
- Key decision 1
- Key decision 2
- Key decision 3

## Tasks

- [ ] 🟥 **Step 1: Setup authentication module**
  - [ ] 🟥 Create authentication service class
  - [ ] 🟥 Implement JWT token handling
  - [ ] 🟥 Connect service to existing database schema

- [ ] 🟥 **Step 2: Develop frontend login UI**
  - [ ] 🟥 Design login page component (React)
  - [ ] 🟥 Integrate component with auth endpoints
  - [ ] 🟥 Add form validation and error handling

- [ ] 🟥 **Step 3: Add user session management**
  - [ ] 🟥 Set up session cookies securely
  - [ ] 🟥 Implement session renewal logic
  - [ ] 🟥 Handle session expiry and logout process

## Acceptance Criteria & Verification

| # | Criterion | Verification | Expected |
|---|-----------|--------------|----------|
| AC1 | Valid credentials return a session | `bun test auth.login` | passes |
| AC2 | Wrong password is rejected | `bun test auth.login.invalid` | passes; 401, no cookie set |
| AC3 | Existing signup still works | `bun test signup` | passes (regression) |

## Coverage

- Functional / failure paths: Steps 1–2 (AC1, AC2)
- Regression: AC3
- User workflow: Step 2
- Documentation: N/A — no public docs for this flow
- Compatibility / migration: N/A — no schema change
- Operations: N/A — no new config or deploy step
- Security / privacy: Step 3 (secure cookies, session expiry)

## Important Implementation Details

- Detail 1
- Detail 2
- Detail 3

## File-level Changes (key insertion points)

- **Add**
  - path/to/new/file.ext - Description of what this file does

- **Modify**
  - path/to/existing/file.ext - Description of changes needed

- **Keep** (unchanged)
  - path/to/unchanged/file.ext - Why it remains unchanged

## Progress Calculations

- Total steps: X major steps
- Completed: 0
- Overall Progress: `0%`
```

Again, for clarity, it's still not time to build yet. Just write the clear plan document. No extra complexity or extra scope beyond what we discussed. The plan should lead to simple, elegant, minimal code that does the job perfectly.

---
