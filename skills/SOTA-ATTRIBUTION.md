# SOTA Skills Attribution

The externally sourced `sota-*` skills in this directory are adapted from
**SOTA Engineering Skills** by Martin Holovsky:

- Source: https://github.com/martinholovsky/SOTA-skills
- Imported commit: `a02c19971ad39254846890f87300a46b19e3e82e`
- License: [Creative Commons Attribution 4.0 International](https://creativecommons.org/licenses/by/4.0/)
- Upstream license text and warranty disclaimer: https://github.com/martinholovsky/SOTA-skills/blob/a02c19971ad39254846890f87300a46b19e3e82e/LICENSE

Adapted skills: `sota-code-security`, `sota-data-engineering`,
`sota-llm-engineering`, `sota-ml-engineering`, `sota-observability`,
`sota-privacy-compliance`, `sota-python`, `sota-rust`, `sota-sandboxing`,
`sota-testing`, `sota-async-concurrency`, and `sota-architecture`.
`sota-architecture` omits upstream `rules/08-nats-jetstream.md`.

Local modifications adapt the material for opencode, make repository
instructions authoritative, consolidate overlapping skills, and set uv, Ruff,
and ty as the preferred new-project Python toolchain.

`sota-perl` is an original local synthesis from Perl core documentation,
MetaCPAN project documentation, and CPAN Security Group guidance. It is
MIT-licensed and is not derived from the upstream SOTA Engineering Skills
repository.

`sota-typescript` is an original local synthesis from TypeScript, Bun, Node.js,
and Biome documentation and TC39 proposal material. It is MIT-licensed and is
not derived from the upstream SOTA Engineering Skills repository. It supersedes
the earlier `typescript-tooling` skill, whose reference material was folded into
its rule files.

## Manual Refresh

1. Fetch the upstream repository and check out the desired commit.
2. Compare only the externally sourced `sota-*` directories against that
   commit; exclude `sota-perl` and `sota-typescript`.
3. Reapply the local integration policies and canonical ownership boundaries.
4. Preserve the Python defaults and established-project exception.
5. Restore refs to newly imported skills and scrub upstream-repo internals.
6. Update the imported commit above and in each imported `SKILL.md`.
7. Run `./scripts/validate-skills.sh` and check local Markdown links before
   accepting the refresh.
