---
name: binscout-re
description: "Static reverse engineering of native binaries (ELF, PE, Mach-O including fat/universal, raw firmware blobs) with binscout, a headless agent-first analyzer exposed as an MCP server and a CLI. Use when asked to reverse engineer, analyze, triage, or understand a compiled binary, executable, library, malware sample, crackme, or firmware image; to find where a string, import, or constant is used; to recover what a function does; to rename functions or annotate addresses; or to diff two builds of a binary. Trigger keywords: reverse engineering, RE, binary analysis, disassemble, disassembly, decompile, pseudo-C, CFG, xrefs, cross-references, call graph, imports, exports, strings, FLIRT, patch diff, binary diff, crackme, malware triage, firmware, x86_64, aarch64, ARM, Thumb, binscout. Not for source-level debugging or dynamic analysis (running the sample)."
---

# Reverse engineering with binscout

binscout analyzes a binary statically and answers one bounded question per
call with one JSON document. It never runs the sample and never modifies the
binary: renames and comments live in a sidecar project DB.

Every tool takes `binary` (path). The same operations exist as MCP tools
(`tools.binscout.<name>`, snake_case) and as CLI subcommands
(`binscout <name>`, kebab-case, e.g. `block-insns`). Exception: the MCP's
`rename` and `comment` are one CLI subcommand,
`binscout annotate <binary> <addr> --rename <name> | --comment <text>`.
Prefer the MCP; use the CLI for scripting or when the MCP is not connected.
Check `binscout --version` when behavior differs from this skill (written
against 0.6.0).

## Ground rules

- **Never execute the sample.** This skill is static only. If dynamic
  analysis is genuinely needed, stop and say so; isolation design is
  `sota-sandboxing`'s job.
- **Pass addresses back as the `*_hex` string**, not the decimal number.
  64-bit addresses exceed JavaScript's safe integer range and silently lose
  precision.
- **Any address inside a function snaps to its entry** for `func`, `blocks`,
  `cfg`, `structure`, `pseudo`, `callers`, `callees`. An address in no
  function fails with `not found: function 0x…` — find the real entry with
  `functions` first.
- **`pseudo` and `structure` are not a decompiler.** Both carry an
  approximation warning: flags and stack are unmodeled. Confirm any claim that
  matters against `disasm` or `block_insns`.
- **Page everything.** List tools return `{items, total, next_offset}` (or
  `total` plus rows). Default page is 50, max `limit` is 1024. Never assume a
  first page is complete — check `next_offset`/`total`.
- **Repeat the mapping on every call.** `fat_arch` (fat Mach-O) and `raw`
  (headerless blobs) are per-call arguments, not session state. Pass the same
  value, spelled identically, on every call against that binary.
- **State confidence.** Separate what binscout reported (fact) from what you
  infer (hypothesis). Name evidence by address.

## Workflow

### 1. Orient

1. `project_info` — arch, format, entry, counts. A fat Mach-O fails with
   `requires a slice selection (available: …)`; pick one and pass `fat_arch`
   (see Fat Mach-O). `supported: false` or `Unsupported file format` ends the
   static path.
2. `sections` — layout and permissions. Writable+executable sections, odd
   names, or a tiny `.text` with a large high-entropy section suggest packing.
3. `symbols` — imports reveal capability (network, crypto, process, registry,
   file I/O). Exports reveal the API of a library.
4. `diagnostics` — unresolved indirect jumps/calls and decode failures. Many
   decode failures in code sections means data in code, obfuscation, or a
   wrong arch/base.

### 2. Find the interesting code

Work from anchors to code, not top-down from the entry:

- **Strings:** `strings` with `pattern` (case-sensitive, or `regex:…`),
  `min_len`, or `section`. Try `decode: "xor:0x??"`, `add:`, or `rot:` to
  reveal single-byte-obfuscated text.
- **String → code:** `xrefs` with `to: <string vaddr_hex>` (add
  `kind: "string"` to drop the duplicate `Data` row), or `slice` with
  `to: <string vaddr_hex>` for every instruction that reaches it.
- **Import → code:** `symbols` gives each import an `address`/`address_hex`
  when binscout can resolve one; otherwise find the stub/thunk (see Gotchas).
  Then `callers` on it.
- **Constants and byte signatures:** `search_bytes` with `pattern` such as
  `"48 8b ?? ?? e8"`, scoped by `section` or `range_start`/`range_end`. Use it
  for crypto constants (e.g. AES S-box `63 7c 77 7b`), magic values, and
  unresolved references.
- **Names:** `functions` with `query` (substring over rename-resolved names),
  `caller`/`callee` filters, or `range_lo`/`range_hi`.
- **Library code:** `flirt_hints` suggests names for known library functions.
  They are hints — check one before trusting a batch.

### 3. Understand one function

Go cheapest to most detailed, and stop when the question is answered:

1. `func` — size and call count. Decide whether it is worth reading.
2. `callees` (depth 1) — what it calls often tells you what it does.
3. `structure` — loops and branch sites.
4. `pseudo` — a quick lossy read. Resolved address computations carry a
   `// => 0x…` suffix naming the target (a string, global, or GOT slot).
5. `blocks` then `block_insns` (or `disasm` with `addr`+`len`) — ground
   truth for anything you will report.
6. `cfg` — the full graph, only when you need all edges at once.
7. `ir` — the lifted IR for a range; check `ir_coverage` for the arch first
   if the lift looks incomplete.

`callers` with `depth` > 1 walks back toward the entry or exported API to
answer "how is this reached".

### 4. Record what you learn

- `rename` a function (`addr` = entry, `name`; empty name clears) once its
  purpose is clear. Later `functions`/`pseudo` output shows the new name,
  which compounds understanding.
- `comment` any address (empty string clears) for evidence and open
  questions.
- `annotations_export` emits a portable document (bound to the binary's
  sha256); `annotations_import` merges one. Import fails on conflicting fields
  unless `overwrite: true` — do not overwrite without the user's consent.

Ask before renaming or commenting in a project DB you did not create; it may
be someone's work. The default DB sits next to the binary as
`<binary>.rsdbg.redb`; pass an explicit `db` when that directory is
read-only or must stay clean.

### 5. Compare builds

`diff` with `binary_a` (baseline) and `binary_b`: functions come back
`matched` (byte-identical), `changed` (with match reason), `added`, or
`removed`. For patch analysis, read `changed` functions with `blocks` /
`block_insns` on both sides. Both projects open read-only. `fat_arch` and
`raw` apply to both sides, so diff two fat builds slice by slice.

## Raw blobs and firmware

For headerless images pass `raw: {arch, base, entry?}` on every call (CLI:
`--raw --arch <arch> --base <addr> [--entry <addr>]`). Arch is one of
`x86_64`, `x86_32`, `aarch64`, `arm32`, `thumb`. A wrong base shows up as
xrefs and string references pointing nowhere; a wrong arch shows up as
decode failures in `diagnostics`. Iterate on both before analyzing.

## Fat (universal) Mach-O

Pass `fat_arch` on every call (CLI: `--fat-arch`): `x86_64`, `x86_32`,
`aarch64`, `arm32`, or a `lipo` alias such as `arm64`. The error for a
missing selection lists the available slices.

- **Give each slice its own `db`.** All slices default to one sidecar
  (`<binary>.rsdbg.redb`). Once one slice has annotations, opening another
  fails with `mapping mismatch … use a separate --db PATH`. Annotations are
  never remapped across slices. Use e.g. `db: "<binary>.x86_64.redb"` from
  the first call.
- **The selection string is stored as written.** `arm64` and `aarch64` pick
  the same slice but count as different mappings, so switching spelling
  triggers the same mismatch. Prefer the canonical name and never vary it.
- **arm64 + arm64e containers are ambiguous.** Both normalize to `aarch64`
  (`matches 2 slices`), and `arm64e` is not accepted. Extract the slice first
  with `lipo -thin arm64e in -output out` and analyze `out` without
  `fat_arch`.

## Gotchas (binscout 0.6.x)

- **Mach-O import stubs are unnamed.** Functions in `__stubs` show
  `name: null`, and `symbols` reports `address: null` for Mach-O imports. The
  stub's `Data` xrefs do resolve to its exact `__got` slot (e.g. `0x100004008`),
  but nothing maps a slot to its import name. Infer the target from call
  context (arguments, strings), label it with `rename`, and mark it as
  inferred.
- **aarch64 `adrp` leaves page-base noise.** Each `adrp` adds a `Data` xref
  to the 4 KiB page base (often the image base, e.g. `0x100000000`). The real
  target is the `Data`/`String` xref on the following `add`/`ldr`. Ignore
  page-base hits when counting references.
- **`slice` takes `to`, not `addr`.** Every other address-rooted tool uses
  `addr`.
- **Hidden code-section strings.** `strings` hides hits in executable memory
  unless `pattern`, `section`, or `include_code: true` is given.

## Reporting

Lead with the answer to the user's question, then the evidence chain as
addresses (`0x…` entry → call site → string/constant). Mark each conclusion
as observed or inferred, and list open questions and anything binscout could
not resolve (`diagnostics`, unsupported format, unlifted ranges).
