# SOTA Skills Attribution

The externally sourced `sota-*` skills in this directory are adapted from
**SOTA Engineering Skills** by Martin Holovsky:

- Source: https://github.com/martinholovsky/SOTA-skills
- Imported commit: `efeb1dee4d959b51d61dbe4783f22e4110c93ed5`
- License: [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)
- Upstream license text and warranty disclaimer: https://github.com/martinholovsky/SOTA-skills/blob/efeb1dee4d959b51d61dbe4783f22e4110c93ed5/LICENSE

Local modifications adapt the material for opencode, make repository
instructions authoritative, consolidate overlapping skills, and set uv, Ruff,
and ty as the preferred new-project Python toolchain.

`sota-perl` is an original local synthesis from Perl core documentation,
MetaCPAN project documentation, and CPAN Security Group guidance. It is
MIT-licensed and is not derived from the upstream SOTA Engineering Skills
repository.

## Manual Refresh

1. Fetch the upstream repository and check out the desired commit.
2. Compare only the externally sourced `sota-*` directories against that
   commit; exclude `sota-perl`.
3. Reapply the local integration policies and canonical ownership boundaries.
4. Preserve the Python defaults and established-project exception.
5. Update the imported commit above and in each imported `SKILL.md`.
6. Run `./scripts/validate-skills.sh` and check local Markdown links before
   accepting the refresh.
