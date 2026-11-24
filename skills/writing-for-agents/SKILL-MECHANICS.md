# Skill mechanics

The skill-specific branch of [`writing-for-agents`](SKILL.md): what changes when the document is a skill (frontmatter, skill versus command, routers). Everything else about writing it is the universal reference in `SKILL.md`.

## Skill or command

Two choices, trading the two loads. In opencode every skill is model-reachable: there is no switch that hides a skill's description from the agent.

- A **skill** keeps a `description` that is always loaded, so the agent can fire it autonomously and other skills can reach it through the `skill` tool. The description is the skill's top-level context pointer, forced to stay loaded at all times: permanent context load in exchange for discoverability. A skill whose content is all reference is also one home for shared reference: another skill can load it, so reference needed by several skills lives in one place. Mechanics: a `skills/<name>/SKILL.md` whose frontmatter `name` equals its directory, plus a model-facing `description` carrying the trigger branches (the pointer-writing rules in `SKILL.md` apply in full).
- A **command** is a Markdown template in `commands/<name>.md` that only the human invokes by typing its name. It adds zero context load but spends cognitive load: you are the index that must remember it exists. Mechanics: a `description` that is a one-line human summary (trigger lists stripped), a body that is the prompt, `$ARGUMENTS` for input, and an optional `agent:` to switch the session's agent.

Pick a skill only when the agent must reach it on its own, or another skill must. If it only ever fires by hand, make it a command and pay no context load.

Shared reference that two commands both need can live in neither: a command has no description for the agent to find, so nothing but the human can reach it. Have each command load a skill that holds the reference, or push it into a plain file outside the skill system that any document can point at.

## Splitting by invocation

The invocation cut of splitting (the sequence cut lives in `SKILL.md`): split off a skill when you have a distinct leading word that should trigger it on its own (a trigger word you actually use in your prompts), or another skill must reach it. You pay context load for the new always-loaded description, so that independent reach has to be worth it. Prefer folding the idea into an existing skill whose triggers already overlap.

## Routers

When commands multiply past what you can remember, that piled-up cognitive load is cured by a **router**: one place that names the others and when to reach for each, so the human has one thing to remember instead of many. In this repository the README's skill, agent, and command tables are the router. A router can only hint at commands, never fire them.
