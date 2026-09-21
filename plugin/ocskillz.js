/**
 * ocskillz plugin for opencode V2.
 *
 * Registers this package's skills, commands, and agent stubs through V2
 * transforms, so installing the plugin is enough — no symlinking of
 * ~/.config/opencode required.
 *
 * V2 plugins cannot create agents, only update ones the user already declared
 * (see README for the required `agents` stubs). Skills and commands are
 * registered outright, but existing definitions always win: if a skill or
 * command with the same ID is already registered, this plugin leaves it
 * alone.
 */

import fs from "fs"
import path from "path"
import { fileURLToPath } from "url"
import { parse as parseYaml } from "yaml"
import { Agent, Plugin } from "@opencode/plugin"

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")
const SKILLS_DIR = path.join(ROOT, "skills")
const AGENTS_DIR = path.join(ROOT, "agents")
const COMMANDS_DIR = path.join(ROOT, "commands")

const HYDRATED_AGENT_IDS = ["code-reviewer", "planner", "refactor"]

const FRONTMATTER = /^---\r?\n([\s\S]*?)\r?\n---\r?\n?([\s\S]*)$/

/**
 * Split a markdown file into parsed frontmatter and body.
 * Throws if the frontmatter is present but not a YAML mapping.
 */
const parseDocument = (content) => {
  const match = content.match(FRONTMATTER)
  if (!match) return { frontmatter: {}, body: content.trim() }

  const frontmatter = parseYaml(match[1]) ?? {}
  if (typeof frontmatter !== "object" || Array.isArray(frontmatter)) {
    throw new Error("frontmatter is not a mapping")
  }
  return { frontmatter, body: match[2].trim() }
}

const markdownFiles = (dir) => {
  let entries
  try {
    entries = fs.readdirSync(dir)
  } catch {
    return []
  }
  return entries
    .filter((name) => name.endsWith(".md"))
    .sort()
    .map((name) => ({ name: name.slice(0, -3), file: path.join(dir, name) }))
}

const readDocument = (dir, name, file) => {
  let doc
  try {
    doc = parseDocument(fs.readFileSync(file, "utf8"))
  } catch (error) {
    console.warn(`ocskillz: skipped ${path.basename(dir)}/${path.basename(file)}: ${error.message}`)
    return undefined
  }
  if (!doc.body) {
    console.warn(`ocskillz: skipped ${path.basename(dir)}/${path.basename(file)}: body is empty`)
    return undefined
  }
  return doc
}

const loadSkills = () => {
  const skills = []
  let entries
  try {
    entries = fs.readdirSync(SKILLS_DIR, { withFileTypes: true })
  } catch {
    return skills
  }
  for (const entry of entries.sort((a, b) => a.name.localeCompare(b.name))) {
    if (!entry.isDirectory()) continue
    const file = path.join(SKILLS_DIR, entry.name, "SKILL.md")
    if (!fs.existsSync(file)) continue
    const doc = readDocument(SKILLS_DIR, entry.name, file)
    if (!doc) continue
    if (!doc.frontmatter.description) {
      console.warn(`ocskillz: skipped skills/${entry.name}/SKILL.md: missing description`)
      continue
    }
    skills.push({
      id: entry.name,
      name: typeof doc.frontmatter.name === "string" ? doc.frontmatter.name : entry.name,
      description: doc.frontmatter.description,
      path: file,
      content: doc.body,
    })
  }
  return skills
}

const loadHydratedAgents = () => {
  const agents = {}
  for (const id of HYDRATED_AGENT_IDS) {
    const file = path.join(AGENTS_DIR, `${id}.md`)
    const doc = readDocument(AGENTS_DIR, id, file)
    if (!doc) continue
    agents[id] = {
      description: doc.frontmatter.description,
      mode: doc.frontmatter.mode,
      permissions: doc.frontmatter.permissions,
      system: doc.body,
    }
  }
  return agents
}

const loadCommands = () => {
  const commands = []
  for (const { name, file } of markdownFiles(COMMANDS_DIR)) {
    const doc = readDocument(COMMANDS_DIR, name, file)
    if (!doc) continue
    commands.push({
      name,
      description: doc.frontmatter.description,
      agent: doc.frontmatter.agent,
      template: doc.body,
    })
  }
  return commands
}

/** Replace $ARGUMENTS, or append the invocation text after a blank line when the template has no placeholder. */
const expandTemplate = (template, argumentText) => {
  if (template.includes("$ARGUMENTS")) return template.replaceAll("$ARGUMENTS", argumentText)
  return argumentText ? `${template}\n\n${argumentText}` : template
}

export default Plugin.define({
  id: "ocskillz",
  async setup(ctx) {
    await ctx.skill.transform((editor) => {
      const existing = new Set(editor.list().map((skill) => skill.id))
      for (const skill of loadSkills()) {
        if (existing.has(skill.id)) continue
        editor.add(skill)
      }
    })

    // Only hydrate agent IDs the user already declared (V2 plugins cannot create agents).
    // A field is filled only when it still matches the V2 empty-stub default, so a
    // meaningful user override is never clobbered.
    await ctx.agent.transform((editor) => {
      for (const [id, fields] of Object.entries(loadHydratedAgents())) {
        const current = editor.get(id)
        if (!current) continue

        const empty = Agent.Info.default(id)
        editor.update(id, (agent) => {
          if (agent.description === empty.description) agent.description = fields.description
          if (agent.mode === empty.mode && fields.mode) agent.mode = fields.mode
          if (agent.system === empty.system) agent.system = fields.system
          if (JSON.stringify(agent.permissions) === JSON.stringify(empty.permissions)) {
            agent.permissions = fields.permissions
          }
        })
      }
    })

    const existingCommands = new Set((await ctx.command.list()).map((command) => command.name))
    await ctx.command.transform((editor) => {
      for (const command of loadCommands()) {
        if (existingCommands.has(command.name)) continue
        editor.add({
          name: command.name,
          description: command.description,
          execute: async ({ sessionID, prompt, delivery }) => {
            if (command.agent) {
              let target
              try {
                target = await ctx.agent.get({ agentID: command.agent })
              } catch {
                target = undefined
              }
              // Subagent-only agents cannot become the session's active agent.
              if (target && target.mode !== "subagent") {
                await ctx.session.switchAgent({ sessionID, agent: command.agent })
              }
            }
            await ctx.session.prompt({
              ...prompt,
              sessionID,
              text: expandTemplate(command.template, prompt.text),
              delivery,
            })
          },
        })
      }
    })
  },
})
