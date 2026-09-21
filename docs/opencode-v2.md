# OpenCode V2 compatibility

ocskillz supports OpenCode V2 only. Its package entrypoint uses `@opencode/plugin`; a V1 plugin entrypoint or the singular V1 `plugin` configuration field cannot load it.

## Installation

Declare the package and all three agent stubs in global or project `opencode.json(c)`:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": ["ocskillz@git+https://github.com/mimi1vx/ocskillz"],
  "agents": {
    "code-reviewer": { "mode": "primary" },
    "planner": { "mode": "primary" },
    "refactor": { "mode": "subagent" }
  }
}
```

The stubs are required because the V2 `AgentEditor` can update and remove existing agents but cannot create them. The plugin hydrates each stub's description, system prompt, mode, and permissions while preserving values that differ from OpenCode's empty-agent defaults.

An explicit override equal to an empty-agent default is indistinguishable from an omitted value and can therefore be hydrated. This is a V2 plugin API limitation.

## Agent behavior

- `code-reviewer` and `planner` are selectable primary agents.
- `refactor` is subagent-only. Ask a primary agent to launch `refactor` through the `subagent` tool.
- Plugin-registered commands cannot declare V2's file-based `subagent` behavior. They execute a callback and may switch only to a primary-capable agent, so no bundled command targets `refactor`.
- The planner treats project files as read-only. When persistence is requested, it writes Markdown only under `~/.opencode/plan/`.

## Migrating configuration

Use native V2 plural fields and ordered permission rules:

| V1 | V2 |
| --- | --- |
| `plugin` | `plugins` |
| `agent` | `agents` |
| `command` | `commands` |
| `permission` | `permissions` |
| permission action `bash` | `shell` |
| permission action `task` | `subagent` |
| permission actions `write` or `patch` | `edit` |
| agent `prompt` | agent `system` or a Markdown agent body |
| agent `disable` | `disabled` |
| agent `maxSteps` | `steps` |

V2 still accepts many V1 file definitions, but the ocskillz plugin implementation itself is V2-only. Preserve unrelated settings when converting configuration.

## Skill schema discrepancy

The V2 plugin guide currently demonstrates `Skill.Info.location`. The released `@opencode/schema` used by `@opencode/plugin` 2.0.12 defines this field as `path`. ocskillz uses `path` so it remains compatible with the installed release. Check the installed type declaration before changing this field for a newer dependency.

## Verification

Install dependencies and run:

```sh
npm test
./scripts/validate-skills.sh
```

The validator checks native frontmatter, explicit agent modes, command-to-agent compatibility, and the five bundled commands. When local OpenCode API inspection is available, it also verifies the hydrated registry. A clearly reported skip means live registry state was unavailable; the static checks still ran.

For direct inspection, start OpenCode in a directory whose configuration contains the stubs above and run:

```sh
opencode debug agents
```

Confirm that `code-reviewer` and `planner` report `primary`, while `refactor` reports `subagent`.
