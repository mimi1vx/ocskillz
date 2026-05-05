#!/usr/bin/env bash
# Validate every skills/<name>/SKILL.md:
#  - file exists and is non-empty
#  - frontmatter contains `name:` and `description:`
#  - frontmatter `name` matches the directory name
#
# Exits non-zero on any failure. Prints a summary.

set -u

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SKILLS_DIR="$ROOT/skills"

if [[ ! -d "$SKILLS_DIR" ]]; then
  echo "FAIL: skills directory not found at $SKILLS_DIR" >&2
  exit 2
fi

errors=0
checked=0

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

  # Extract frontmatter (between the first two '---' lines)
  frontmatter="$(awk '
    /^---$/ { count++; next }
    count == 1 { print }
    count == 2 { exit }
  ' "$skill_file")"

  if [[ -z "$frontmatter" ]]; then
    echo "FAIL [$skill_name]: no YAML frontmatter found"
    errors=$((errors + 1))
    continue
  fi

  # Required keys
  fm_name="$(printf '%s\n' "$frontmatter" | sed -n 's/^name:[[:space:]]*//p' | head -1 | tr -d '"' | tr -d "'")"
  fm_desc="$(printf '%s\n' "$frontmatter" | sed -n 's/^description:[[:space:]]*//p' | head -1)"

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

echo ""
echo "Checked: $checked  Errors: $errors"

if [[ $errors -gt 0 ]]; then
  exit 1
fi
