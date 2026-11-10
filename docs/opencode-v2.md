# OpenCode V2 compatibility

ocskillz supports OpenCode V2 only. Its package entrypoint uses `@opencode/plugin`; a V1 plugin entrypoint or the singular V1 `plugin` configuration field cannot load it.

## Installation

Add the package to `plugins` in global or project `opencode.json(c)`:

```jsonc
{
  "$schema": "https://opencode.ai/config.json",
  "plugins": ["ocskillz@git+https://github.com/mimi1vx/ocskillz"]
}
```

The plugin registers `code-reviewer`, `planner`, and `refactor` itself. `AgentEditor.update(id, fn)` creates a missing agent from `Agent.Info.default(id)` before running `fn`, so no `agents` entry is needed. For an agent that already exists, the plugin fills the description, system prompt, mode, and permissions that still equal that default and preserves every field that differs.

To override a bundled agent, declare it in config; the fields you set win:

```jsonc
{
  "agents": {
    "planner": { "description": "My planner" }
  }
}
```

An explicit value equal to the default is indistinguishable from an omitted value and can therefore be filled. This is a V2 plugin API limitation.

## Agent behavior

- `code-reviewer` and `planner` are selectable primary agents.
- `refactor` is subagent-only. Ask a primary agent to launch `refactor` through the `subagent` tool.
- Plugin-registered commands cannot declare V2's file-based `subagent` behavior. They execute a callback and may switch only to a primary-capable agent, so no bundled command targets `refactor`.
- The planner treats project files as read-only. It reads and writes plan Markdown only under `~/.opencode/plan/`, and changes beads state (`.beads/`) only through `br`, which it may run without prompting. It uses `br` only when the project already has `.beads/`; `br init` is denied.

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

## Verification

Install dependencies and run:

```sh
npm test
./scripts/validate-skills.sh
```

The validator checks native frontmatter, explicit agent modes, command-to-agent compatibility, and the six bundled commands. When local OpenCode API inspection is available, it also verifies the registered skills, agents, and commands. A clearly reported skip means live registry state was unavailable; the static checks still ran.

For direct inspection, start OpenCode in a project whose configuration loads the plugin and run:

```sh
opencode debug agents
```

Confirm that `code-reviewer` and `planner` report `primary`, while `refactor` reports `subagent`.
