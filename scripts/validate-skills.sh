#!/usr/bin/env bash
# Validate the contents of this repository.
#
# Phase 1 - skills/<name>/SKILL.md:
#  - file exists and is non-empty
#  - frontmatter contains `name:` and `description:`
#  - frontmatter `name` matches the directory name
#
# Phase 2 - agents/<name>.md and commands/<name>.md:
#  - frontmatter parses and carries a non-empty `description:`
#  - body (the agent prompt / command template) is non-empty
#  - agents: no legacy V1 fields (name, permission, disable, prompt, tools,
#    maxSteps, temperature, top_p, variant), `mode` is explicit and valid,
#    and `permissions` (if present) uses current V2 actions and rule syntax
#  - commands: `agent` names a known primary-capable agent
#
# Phase 3 - live registration through the opencode V2 plugin API:
#  - the plugin is active and every skill, agent stub, and command actually
#    reaches opencode's registries. Skipped with a notice when its
#    prerequisites are missing or the environment can't confirm live state.
#
# Exits non-zero on any failure. Prints a summary.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$ROOT/skills"
AGENTS_DIR="$ROOT/agents"
COMMANDS_DIR="$ROOT/commands"

if [[ ! -d "$SKILLS_DIR" ]]; then
	echo "FAIL: skills directory not found at $SKILLS_DIR" >&2
	exit 2
fi

errors=0
checked=0

# Print the frontmatter of a markdown file (between the first two '---' lines).
frontmatter_of() {
	awk '
    /^---$/ { count++; next }
    count == 1 { print }
    count == 2 { exit }
  ' "$1"
}

# Print the body of a markdown file (everything after the closing '---').
body_of() {
	awk '
    /^---$/ && count < 2 { count++; next }
    count >= 2 { print }
  ' "$1"
}

# Read a top-level scalar key out of frontmatter. Leading whitespace is
# required to be absent, so nested keys (permission rule fields, for example)
# are never mistaken for top-level ones.
fm_value() {
	printf '%s\n' "$1" | sed -n "s/^$2:[[:space:]]*//p" | head -1 | tr -d '"' | tr -d "'"
}

# True if frontmatter declares the given top-level key at all (scalar or not).
fm_has_key() {
	printf '%s\n' "$1" | grep -qE "^$2:"
}

is_blank() {
	[[ -z "$(printf '%s' "$1" | tr -d '[:space:]')" ]]
}

# ---------------------------------------------------------------- phase 1
for dir in "$SKILLS_DIR"/*/; do
	[[ -d "$dir" ]] || continue
	skill_name="$(basename "$dir")"
	skill_file="$dir/SKILL.md"
	checked=$((checked + 1))

	if [[ ! -f "$skill_file" ]]; then
		echo "FAIL [$skill_name]: SKILL.md missing"
		errors=$((errors + 1))
		continue
	fi

	if [[ ! -s "$skill_file" ]]; then
		echo "FAIL [$skill_name]: SKILL.md is empty"
		errors=$((errors + 1))
		continue
	fi

	frontmatter="$(frontmatter_of "$skill_file")"

	if [[ -z "$frontmatter" ]]; then
		echo "FAIL [$skill_name]: no YAML frontmatter found"
		errors=$((errors + 1))
		continue
	fi

	fm_name="$(fm_value "$frontmatter" name)"
	fm_desc="$(fm_value "$frontmatter" description)"

	if [[ -z "$fm_name" ]]; then
		echo "FAIL [$skill_name]: frontmatter missing 'name'"
		errors=$((errors + 1))
		continue
	fi

	if [[ -z "$fm_desc" ]]; then
		echo "FAIL [$skill_name]: frontmatter missing 'description'"
		errors=$((errors + 1))
		continue
	fi

	if [[ "$fm_name" != "$skill_name" ]]; then
		echo "FAIL [$skill_name]: frontmatter name '$fm_name' != directory '$skill_name'"
		errors=$((errors + 1))
		continue
	fi

	echo "ok   [$skill_name]"
done

# ---------------------------------------------------------------- phase 2
known_agents=" build plan general explore "
for file in "$AGENTS_DIR"/*.md; do
	[[ -f "$file" ]] || continue
	known_agents+="$(basename "$file" .md) "
done

# Fields V1 agents used that have no place in native V2 frontmatter. The
# agent's V2 ID always comes from its filename, `permission` is renamed to
# `permissions`, and `disable`/`prompt`/`tools`/`maxSteps`/`temperature`/
# `top_p`/`variant` moved to `disabled`/(body)/`request.body`/`steps`/etc.
legacy_agent_fields="name permission disable prompt tools maxSteps temperature top_p variant"
v2_agent_actions="read edit glob grep shell subagent skill question webfetch websearch external_directory execute"

agent_mode() {
	case "$1" in
	build | plan) printf '%s\n' primary ;;
	general | explore) printf '%s\n' subagent ;;
	*)
		local file="$AGENTS_DIR/$1.md"
		[[ -f "$file" ]] && fm_value "$(frontmatter_of "$file")" mode
		;;
	esac
}

for file in "$AGENTS_DIR"/*.md; do
	[[ -f "$file" ]] || continue
	agent_name="$(basename "$file" .md)"
	checked=$((checked + 1))

	frontmatter="$(frontmatter_of "$file")"
	if [[ -z "$frontmatter" ]]; then
		echo "FAIL [agent: $agent_name]: no YAML frontmatter found"
		errors=$((errors + 1))
		continue
	fi

	if [[ -z "$(fm_value "$frontmatter" description)" ]]; then
		echo "FAIL [agent: $agent_name]: frontmatter missing 'description'"
		errors=$((errors + 1))
		continue
	fi

	if is_blank "$(body_of "$file")"; then
		echo "FAIL [agent: $agent_name]: body is empty (agents need a system prompt)"
		errors=$((errors + 1))
		continue
	fi

	legacy_found=""
	for field in $legacy_agent_fields; do
		if fm_has_key "$frontmatter" "$field"; then
			legacy_found+="$field "
		fi
	done
	if [[ -n "$legacy_found" ]]; then
		echo "FAIL [agent: $agent_name]: legacy V1 field(s) present: $legacy_found"
		errors=$((errors + 1))
		continue
	fi

	fm_mode="$(fm_value "$frontmatter" mode)"
	if [[ -z "$fm_mode" ]]; then
		echo "FAIL [agent: $agent_name]: frontmatter missing explicit 'mode'"
		errors=$((errors + 1))
		continue
	fi
	if [[ "$fm_mode" != "primary" && "$fm_mode" != "subagent" && "$fm_mode" != "all" ]]; then
		echo "FAIL [agent: $agent_name]: mode '$fm_mode' is not primary|subagent|all"
		errors=$((errors + 1))
		continue
	fi

	expected_mode=""
	case "$agent_name" in
	code-reviewer | planner) expected_mode="primary" ;;
	refactor) expected_mode="subagent" ;;
	esac
	if [[ -n "$expected_mode" && "$fm_mode" != "$expected_mode" ]]; then
		echo "FAIL [agent: $agent_name]: mode '$fm_mode' must be '$expected_mode'"
		errors=$((errors + 1))
		continue
	fi

	if fm_has_key "$frontmatter" "permissions"; then
		# A native V2 ruleset is a block sequence: the line after "permissions:"
		# starts a "- action: ..." entry, not another mapping key at the same level.
		first_rule_line="$(printf '%s\n' "$frontmatter" | awk '/^permissions:/{found=1;next} found && NF{print;exit}' | sed 's/^[[:space:]]*//')"
		if [[ "$first_rule_line" != -* ]]; then
			echo "FAIL [agent: $agent_name]: 'permissions' is not a sequence of {action, resource, effect} rules"
			errors=$((errors + 1))
			continue
		fi

		invalid_actions=""
		while IFS= read -r action; do
			[[ -n "$action" ]] || continue
			if [[ " $v2_agent_actions " != *" $action "* ]]; then
				invalid_actions+="$action "
			fi
		done < <(printf '%s\n' "$frontmatter" | sed -n 's/^[[:space:]]*- action:[[:space:]]*//p' | tr -d '"' | tr -d "'")
		if [[ -n "$invalid_actions" ]]; then
			echo "FAIL [agent: $agent_name]: unsupported V2 permission action(s): $invalid_actions"
			errors=$((errors + 1))
			continue
		fi
	fi

	echo "ok   [agent: $agent_name]"
done

for file in "$COMMANDS_DIR"/*.md; do
	[[ -f "$file" ]] || continue
	command_name="$(basename "$file" .md)"
	checked=$((checked + 1))

	frontmatter="$(frontmatter_of "$file")"
	if [[ -z "$frontmatter" ]]; then
		echo "FAIL [command: $command_name]: no YAML frontmatter found"
		errors=$((errors + 1))
		continue
	fi

	if [[ -z "$(fm_value "$frontmatter" description)" ]]; then
		echo "FAIL [command: $command_name]: frontmatter missing 'description'"
		errors=$((errors + 1))
		continue
	fi

	if is_blank "$(body_of "$file")"; then
		echo "FAIL [command: $command_name]: body is empty (commands need a template)"
		errors=$((errors + 1))
		continue
	fi

	fm_agent="$(fm_value "$frontmatter" agent)"
	if [[ -n "$fm_agent" && "$known_agents" != *" $fm_agent "* ]]; then
		echo "FAIL [command: $command_name]: agent '$fm_agent' is not a known agent"
		errors=$((errors + 1))
		continue
	fi
	if [[ -n "$fm_agent" && "$(agent_mode "$fm_agent")" == "subagent" ]]; then
		echo "FAIL [command: $command_name]: agent '$fm_agent' is subagent-only"
		errors=$((errors + 1))
		continue
	fi

	echo "ok   [command: $command_name]"
done

# ---------------------------------------------------------------- phase 3
skip_reason=""
if ! command -v opencode >/dev/null 2>&1; then
	skip_reason="opencode is not on PATH"
elif ! command -v python3 >/dev/null 2>&1; then
	skip_reason="python3 is not on PATH (needed to read opencode's JSON output)"
elif [[ ! -d "$ROOT/node_modules/yaml" ]]; then
	skip_reason="dependencies are not installed (run 'npm install')"
fi

echo ""
if [[ -n "$skip_reason" ]]; then
	echo "registration: SKIPPED - $skip_reason"
else
	workdir="$(mktemp -d)"
	trap 'rm -rf "$workdir"' EXIT

	cat >"$workdir/opencode.json" <<EOF
{
  "\$schema": "https://opencode.ai/config.json",
  "plugins": ["$ROOT"],
  "agents": {
    "code-reviewer": { "mode": "primary" },
    "planner": { "mode": "primary" },
    "refactor": { "mode": "subagent" }
  }
}
EOF

	# A private --standalone server isolates this check from the developer's
	# shared background service and its real global configuration.
	(
		cd "$workdir" || exit 1
		opencode api get /api/plugin --standalone >"$workdir/plugin.json" 2>"$workdir/plugin.err"
		opencode api get /api/skill --standalone >"$workdir/skill.json" 2>"$workdir/skill.err"
		opencode api get /api/agent --standalone >"$workdir/agent.json" 2>"$workdir/agent.err"
		opencode api get /api/command --standalone >"$workdir/command.json" 2>"$workdir/command.err"
	)

	registration_output="$(
		python3 - "$ROOT" "$workdir" <<'PY'
import json, os, sys

root, workdir = sys.argv[1:3]


def load(name):
    path = os.path.join(workdir, name)
    try:
        with open(path) as handle:
            return json.load(handle)
    except Exception as error:
        print(f"registration: SKIPPED - could not parse {name} from opencode api ({error})")
        return None


plugin_doc = load("plugin.json")
skill_doc = load("skill.json")
agent_doc = load("agent.json")
command_doc = load("command.json")
if None in (plugin_doc, skill_doc, agent_doc, command_doc):
    sys.exit(0)

expected_skills = sorted(
    entry
    for entry in os.listdir(os.path.join(root, "skills"))
    if os.path.isfile(os.path.join(root, "skills", entry, "SKILL.md"))
)
expected_commands = sorted(
    name[:-3] for name in os.listdir(os.path.join(root, "commands")) if name.endswith(".md")
)
expected_agents = {
    "code-reviewer": "primary",
    "planner": "primary",
    "refactor": "subagent",
}

plugins = plugin_doc.get("data") or []
if not plugins:
    print(
        "registration: SKIPPED - opencode reported no plugins for this location "
        "(live plugin validation is unavailable in this environment)"
    )
    sys.exit(0)

failures = 0

ocskillz = next((p for p in plugins if p.get("id") == "ocskillz"), None)
if ocskillz is None or ocskillz.get("state", {}).get("status") != "active":
    state = (ocskillz or {}).get("state", {})
    print(f"FAIL [registration] plugin: ocskillz is not active ({state or 'not found'})")
    failures += 1

registered_skills = {s["id"] for s in (skill_doc.get("data") or [])}
registered_agents = {a["id"]: a for a in (agent_doc.get("data") or [])}
registered_commands = {c["name"] for c in (command_doc.get("data") or [])}

for name in expected_skills:
    if name not in registered_skills:
        print(f"FAIL [registration] skill: '{name}' did not reach opencode's registry")
        failures += 1

for name in expected_commands:
    if name not in registered_commands:
        print(f"FAIL [registration] command: '{name}' did not reach opencode's registry")
        failures += 1

for name, mode in expected_agents.items():
    agent = registered_agents.get(name)
    if agent is None:
        print(f"FAIL [registration] agent: '{name}' did not reach opencode's registry")
        failures += 1
    elif not agent.get("system"):
        print(f"FAIL [registration] agent: '{name}' was not hydrated with a system prompt")
        failures += 1
    elif agent.get("mode") != mode:
        print(
            f"FAIL [registration] agent: '{name}' has mode "
            f"'{agent.get('mode')}', expected '{mode}'"
        )
        failures += 1

if "de-slopify" in registered_commands:
    print("FAIL [registration] command: removed 'de-slopify' is still registered")
    failures += 1

print(
    f"registration: {len(expected_skills)} skills, "
    f"{len(expected_agents)} agents, {len(expected_commands)} commands"
)
sys.exit(1 if failures else 0)
PY
	)"

	echo "$registration_output"
	registration_failures="$(printf '%s\n' "$registration_output" | grep -c '^FAIL')"
	errors=$((errors + registration_failures))
fi

echo ""
echo "Checked: $checked  Errors: $errors"

if [[ $errors -gt 0 ]]; then
	exit 1
fi
