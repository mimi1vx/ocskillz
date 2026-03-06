# ocskillz

Custom skills, agents, and commands for opencode (and other coding agents).

## Overview

This repository contains personalized extensions that enhance coding agent capabilities:
- **Skills** - Specialized workflows for common tasks
- **Agents** - Reusable agent definitions with specific tool access
- **Commands** - Quick actions triggered with arguments

## Skills

### git-commit
Generates storytelling-focused Conventional Commits messages with human-in-the-loop context gathering. Creates detailed commit messages that answer "what", "why", and "what problem it solves" for future code archeology.

**Triggers:** User types "commit", "git commit", or asks to create a commit

### python-testing-patterns
Comprehensive guide to implementing robust testing strategies in Python using pytest, fixtures, mocking, parameterization, and test-driven development practices.

**Triggers:** User writes Python tests, sets up test suites, or asks about testing patterns

### spec-to-plan
Transforms project descriptions and feature requests into comprehensive specifications and actionable task lists. Uses a 5-phase workflow:
1. Create initial specification
2. Clarify questions
3. Generate markdown spec
4. Create comprehensive todo
5. Output plan markdown

### changelog-generator
Automatically creates user-facing changelogs from git commits. Categorizes changes (features, improvements, bug fixes) and translates technical commits into customer-friendly release notes.

## Agents

### code-reviewer
Reviews code for quality, security, and adherence to project conventions. Outputs findings by priority (Critical, Warnings, Suggestions).

## Commands

### test
Runs Python test suite with coverage using pytest. Activates the `build` agent.

### clean-init
Analyzes codebase and creates/updates AGENTS.md with build commands, code style guidelines, and conventions. Activates the `build` agent.

## Installation

These configurations are designed for opencode. Place this repository at `~/.config/opencode/` or link it:

```bash
ln -s /path/to/ocskillz ~/.config/opencode
```

## License

MIT
