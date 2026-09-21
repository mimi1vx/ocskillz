import { test } from "node:test"
import assert from "node:assert/strict"
import fs from "node:fs"
import path from "node:path"
import { fileURLToPath } from "node:url"
import { Agent } from "@opencode/plugin"
import ocskillz from "../plugin/ocskillz.js"

const ROOT = path.resolve(path.dirname(fileURLToPath(import.meta.url)), "..")

function makeSkillEditor(preexisting = []) {
  const items = [...preexisting]
  return {
    list: () => items,
    get: (id) => items.find((s) => s.id === id),
    add: (skill) => items.push(skill),
    update: () => {},
    remove: () => {},
    items,
  }
}

function makeAgentEditor(declared) {
  const items = new Map(Object.entries(declared))
  return {
    list: () => [...items.values()],
    get: (id) => items.get(id),
    default: () => {},
    update: (id, fn) => {
      const agent = items.get(id)
      if (!agent) return
      fn(agent)
    },
    remove: (id) => items.delete(id),
    items,
  }
}

function makeCommandEditor() {
  const items = []
  return { add: (definition) => items.push(definition), items }
}

/**
 * Build a mock V2 plugin context. `declaredAgents` simulates user config
 * (`agents: {...}` stubs); `builtinAgents` simulates agents that exist
 * regardless of user declarations (built-ins referenced by commands).
 */
function makeContext({ existingSkills = [], declaredAgents = {}, builtinAgents = {}, existingCommandNames = [] } = {}) {
  const skillEditor = makeSkillEditor(existingSkills)
  const agentEditor = makeAgentEditor(declaredAgents)
  const commandEditor = makeCommandEditor()
  const calls = { switchAgent: [], prompt: [] }

  const ctx = {
    skill: { transform: async (cb) => cb(skillEditor) },
    agent: {
      transform: async (cb) => cb(agentEditor),
      get: async ({ agentID }) => agentEditor.get(agentID) ?? builtinAgents[agentID],
    },
    command: {
      list: async () => ({ location: { directory: ROOT }, data: existingCommandNames.map((name) => ({ name })) }),
      transform: async (cb) => cb(commandEditor),
    },
    session: {
      switchAgent: async (args) => calls.switchAgent.push(args),
      prompt: async (args) => calls.prompt.push(args),
    },
  }

  return { ctx, skillEditor, agentEditor, commandEditor, calls }
}

test("exports a stable plugin ID via the default export", () => {
  assert.equal(ocskillz.id, "ocskillz")
  assert.equal(typeof ocskillz.setup, "function")
})

test("registers every bundled skill", async () => {
  const { ctx, skillEditor } = makeContext()
  await ocskillz.setup(ctx)
  assert.ok(skillEditor.items.length > 20)
  assert.ok(skillEditor.items.some((s) => s.id === "git-commit"))
  assert.ok(skillEditor.items.every((s) => s.path && s.content))
})

test("does not replace a pre-existing skill with the same ID", async () => {
  const { ctx, skillEditor } = makeContext({
    existingSkills: [{ id: "git-commit", name: "mine", description: "user's own", path: "/x", content: "keep me" }],
  })
  await ocskillz.setup(ctx)
  const gitCommit = skillEditor.items.find((s) => s.id === "git-commit")
  assert.equal(gitCommit.content, "keep me")
})

test("hydrates only agent IDs the user already declared", async () => {
  const { ctx, agentEditor } = makeContext({
    declaredAgents: {
      "code-reviewer": Agent.Info.default("code-reviewer"),
      unrelated: Agent.Info.default("unrelated"),
    },
  })
  await ocskillz.setup(ctx)

  const reviewer = agentEditor.get("code-reviewer")
  assert.ok(reviewer.description.length > 0)
  assert.ok(reviewer.system.length > 0)
  assert.ok(Array.isArray(reviewer.permissions) && reviewer.permissions.length > 0)

  assert.deepEqual(agentEditor.get("unrelated"), Agent.Info.default("unrelated"))
  assert.equal(agentEditor.get("planner"), undefined)
  assert.equal(agentEditor.get("refactor"), undefined)
})

test("preserves a meaningful user override instead of the bundled value", async () => {
  const { ctx, agentEditor } = makeContext({
    declaredAgents: {
      "code-reviewer": { ...Agent.Info.default("code-reviewer"), description: "custom description" },
    },
  })
  await ocskillz.setup(ctx)
  assert.equal(agentEditor.get("code-reviewer").description, "custom description")
})

test("fills mode only when a bundled agent specifies one", async () => {
  const { ctx, agentEditor } = makeContext({
    declaredAgents: { planner: { ...Agent.Info.default("planner"), mode: "all" } },
  })
  await ocskillz.setup(ctx)
  assert.equal(agentEditor.get("planner").mode, "all")
})

test("converts agent permission maps into native ordered rules", async () => {
  const { ctx, agentEditor } = makeContext({
    declaredAgents: { refactor: Agent.Info.default("refactor") },
  })
  await ocskillz.setup(ctx)
  const rules = agentEditor.get("refactor").permissions
  assert.ok(rules.every((rule) => "action" in rule && "resource" in rule && "effect" in rule))
  assert.ok(!rules.some((rule) => rule.action === "bash" || rule.action === "write" || rule.action === "patch"))
})

test("skips a command name that already exists", async () => {
  const { ctx, commandEditor } = makeContext({ existingCommandNames: ["walkthrough"] })
  await ocskillz.setup(ctx)
  assert.ok(!commandEditor.items.some((c) => c.name === "walkthrough"))
  assert.ok(commandEditor.items.some((c) => c.name === "bug-hunter"))
})

test("registers all six bundled commands when nothing collides", async () => {
  const { ctx, commandEditor } = makeContext()
  await ocskillz.setup(ctx)
  const names = commandEditor.items.map((c) => c.name).sort()
  assert.deepEqual(names, ["bug-hunter", "clean-init", "code-reorganizer", "de-slopify", "test", "walkthrough"])
})

test("replaces $ARGUMENTS with the invocation text", async () => {
  const { ctx, commandEditor, calls } = makeContext({
    builtinAgents: { build: { ...Agent.Info.default("build"), mode: "primary" } },
  })
  await ocskillz.setup(ctx)
  const cleanInit = commandEditor.items.find((c) => c.name === "clean-init")
  await cleanInit.execute({ sessionID: "s1", prompt: { text: "focus on security" }, delivery: "steer" })
  assert.ok(calls.prompt[0].text.includes("focus on security"))
  assert.ok(!calls.prompt[0].text.includes("$ARGUMENTS"))
})

test("appends non-empty arguments after a blank line when there is no placeholder", async () => {
  const { ctx, commandEditor, calls } = makeContext({
    builtinAgents: { build: { ...Agent.Info.default("build"), mode: "primary" } },
  })
  await ocskillz.setup(ctx)
  const bugHunter = commandEditor.items.find((c) => c.name === "bug-hunter")
  await bugHunter.execute({ sessionID: "s1", prompt: { text: "look at auth.ts" }, delivery: "queue" })
  assert.ok(calls.prompt[0].text.endsWith("\n\nlook at auth.ts"))
})

test("switches to the command's configured agent before submitting the prompt", async () => {
  const { ctx, commandEditor, calls } = makeContext({
    builtinAgents: { build: { ...Agent.Info.default("build"), mode: "primary" } },
  })
  await ocskillz.setup(ctx)
  const test_ = commandEditor.items.find((c) => c.name === "test")
  await test_.execute({ sessionID: "s1", prompt: { text: "" }, delivery: "steer" })
  assert.deepEqual(calls.switchAgent[0], { sessionID: "s1", agent: "build" })
})

test("does not switch to a subagent-only agent", async (t) => {
  const file = path.join(ROOT, "commands", "__subagent_only_test__.md")
  fs.writeFileSync(file, "---\ndescription: targets a subagent-only agent\nagent: general\n---\n\nDo it.")
  t.after(() => fs.rmSync(file, { force: true }))

  const { ctx, commandEditor, calls } = makeContext({
    builtinAgents: { general: { ...Agent.Info.default("general"), mode: "subagent" } },
  })
  await ocskillz.setup(ctx)
  const command = commandEditor.items.find((c) => c.name === "__subagent_only_test__")
  await command.execute({ sessionID: "s1", prompt: { text: "" }, delivery: "steer" })
  assert.equal(calls.switchAgent.length, 0)
})

test("preserves prompt attachments and delivery mode", async () => {
  const { ctx, commandEditor, calls } = makeContext({
    builtinAgents: { plan: { ...Agent.Info.default("plan"), mode: "primary" } },
  })
  await ocskillz.setup(ctx)
  const walkthrough = commandEditor.items.find((c) => c.name === "walkthrough")
  const files = [{ uri: "file:///README.md" }]
  await walkthrough.execute({ sessionID: "s1", prompt: { text: "42", files }, delivery: "queue" })
  assert.deepEqual(calls.prompt[0].files, files)
  assert.equal(calls.prompt[0].delivery, "queue")
})

test("isolates a malformed skill document without breaking other registrations", async (t) => {
  const dir = path.join(ROOT, "skills", "__malformed_test__")
  fs.mkdirSync(dir, { recursive: true })
  fs.writeFileSync(path.join(dir, "SKILL.md"), "---\n[not a mapping]\n---\nbody")
  t.after(() => fs.rmSync(dir, { recursive: true, force: true }))

  const { ctx, skillEditor } = makeContext()
  await ocskillz.setup(ctx)
  assert.ok(!skillEditor.items.some((s) => s.id === "__malformed_test__"))
  assert.ok(skillEditor.items.some((s) => s.id === "git-commit"))
})

test("isolates a malformed command document without breaking other registrations", async (t) => {
  const file = path.join(ROOT, "commands", "__malformed_test__.md")
  fs.writeFileSync(file, "---\ndescription: broken\n---\n")
  t.after(() => fs.rmSync(file, { force: true }))

  const { ctx, commandEditor } = makeContext()
  await ocskillz.setup(ctx)
  assert.ok(!commandEditor.items.some((c) => c.name === "__malformed_test__"))
  assert.ok(commandEditor.items.some((c) => c.name === "bug-hunter"))
})
