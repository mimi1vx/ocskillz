---
name: binscout-re
description: "Static reverse engineering of native binaries (ELF, PE, Mach-O including fat/universal, Go, raw firmware blobs) with binscout, a headless agent-first analyzer exposed as an MCP server and a CLI. Use when asked to reverse engineer, analyze, triage, or understand a compiled binary, executable, library, malware sample, crackme, or firmware image; to find where a string, import, crypto constant, or byte pattern is used; to recover what a function does; to rename functions or annotate addresses; to diff two builds or analyze a patch; or to export a patch. Trigger keywords: reverse engineering, RE, binary analysis, disassemble, disassembly, decompile, pseudo-C, CFG, xrefs, cross-references, call graph, imports, exports, strings, stack strings, crypto constants, YARA, FLIRT, patch diff, binary diff, crackme, malware triage, firmware, Go binary, x86_64, aarch64, ARM, Thumb, RISC-V, MIPS, PowerPC, binscout. Not for source-level debugging or dynamic analysis (running the sample)."
---

# Reverse engineering with binscout

binscout analyzes a binary statically and answers one bounded question per
call with one JSON document. It never runs the sample and never modifies the
binary: renames, comments, function seeds, and type hints live in a sidecar
project DB.

Every tool takes `binary` (path). The same operations exist as MCP tools
(`tools.binscout.<name>`, snake_case) and as CLI subcommands
(`binscout <name>`, kebab-case, e.g. `block-insns`). The names that differ:

| MCP | CLI |
|-----|-----|
| `project_info` or `load` | `binscout load` (also warms the sidecar) |
| `rename`, `comment`, `annotation` (read) | `binscout annotate <binary> <addr> [--rename <name> \| --comment <text>]`; no flag reads |
| `set_type_hint`, `get_type_hint` | `binscout type-hint` |

Prefer the MCP; use the CLI for scripting or when the MCP is not connected.
CLI argument shapes differ from the MCP: `disasm` takes `len` positionally,
`bytes` takes `--len`, and `functions` takes `--range LO HI` (inclusive).
Check `binscout --version` when behavior differs from this skill (verified
against 0.9.0). On 0.8.x and older, list shapes differ; see Gotchas.

## Ground rules

- **Never execute the sample.** This skill is static only. If dynamic
  analysis is genuinely needed, stop and say so; isolation design is
  `sota-sandboxing`'s job.
- **Pass addresses back as the `*_hex` string**, not the decimal number.
  64-bit addresses exceed JavaScript's safe integer range and silently lose
  precision. The same applies to `bytes` `values` for `u64`/`ptr` views: read
  `bytes_hex` instead.
- **Any address inside a function snaps to its entry** for `func`, `blocks`,
  `cfg`, `structure`, `pseudo`, `callers`, `callees`. An address in no
  function fails with `not found: function 0x…` — find the real entry with
  `functions` first.
- **`pseudo` and `structure` are not a decompiler.** Both carry an
  approximation warning: flags and stack are unmodeled. Confirm any claim that
  matters against `disasm` or `block_insns`.
- **Page everything.** Default page is 50, max `limit` is 1024. Every list
  tool returns the same envelope, `{items, total, next_offset, limit, offset,
  protocol}`, including `strings`, `functions`, `xrefs`, `stack_strings`, and
  `go_funcs`. `next_offset: null` means the last page. Never assume a first
  page is complete. (The `envelope` argument is deprecated and ignored.)
- **Repeat the mapping on every call.** `fat_arch` (fat Mach-O), `raw`
  (headerless blobs), and `pdb`/`debug_file` (debug info) are per-call
  arguments, not session state. Pass the same values on every call against
  that binary.
- **State confidence.** Separate what binscout reported (fact) from what you
  infer (hypothesis). Name evidence by address.
- **Writes are explicit.** `rename`, `comment`, `define_func`,
  `undefine_func`, `set_type_hint`, `annotations_import` change the project DB.
  `patch` only exports bytes and never touches the binary. `batch` rejects
  every write tool and `diff`.

## Workflow

### 1. Orient

1. `project_info` — arch, format, entry, counts, `version`, and
   `content_hash_hex` (`stats` adds `content_sha256` and the sidecar size). A
   fat Mach-O fails with
   `requires a slice selection (available: …)`; pick one and pass `fat_arch`
   (see Fat Mach-O). `supported: false` or `Unsupported file format` ends the
   static path.
2. `headers` — triage staples without reading raw bytes: `sha256`/`md5`, PE
   mitigations/imphash/PDB, ELF interpreter/needed libs/RELRO/NX/PIE, Mach-O
   load commands/dylibs/codesign/entitlements. Record the `sha256` in the
   report.
3. `sections` — layout, permissions, entropy. Writable+executable sections,
   odd names, or a tiny `.text` next to a large high-entropy section suggest
   packing.
4. `symbols` — imports reveal capability (network, crypto, process, registry,
   file I/O). Exports reveal the API of a library.
5. `diagnostics` — `unresolved-indirect-jump`/`-call`, `decode-failure`, and
   informational `noreturn-cut` (a call to a noreturn target; the fall-through
   edge is cut on purpose). Filter with `kind` or `func`. Many decode failures
   in code sections means data in code, obfuscation, or a wrong arch/base.
   0.9.0 already drops the benign Mach-O stub and header entries, so treat
   what remains as real: each unresolved jump is a switch table, tail call, or
   obfuscated dispatch you may need to seed with `define_func`.
6. `go_funcs` — for a stripped Go binary, recovers names and exact bounds from
   `pclntab` (empty page when there is no table).

Batch the cheap orientation reads into one `batch` call (see Batching).

### 2. Find the interesting code

Work from anchors to code, not top-down from the entry:

- **Strings:** `strings` with `pattern` (case-sensitive substring, or
  `regex:…`), `min_len`, or `section`. `with_xrefs: true` returns the
  referencing instructions per string and replaces the strings-then-xrefs
  round trip. Try `decode: "xor:0x??"`, `xor:0x<HEXKEY>` (rolling key, 4+ hex
  digits), `add:`, `rot:`, or `base64` to reveal obfuscated text.
- **Stack strings:** `stack_strings` reassembles text built by
  `mov [rsp/rbp+off], imm` runs (x86). Plain `strings` never sees these.
- **String → code:** `xrefs` with `to: <string vaddr_hex>` (add
  `kind: "string"` to drop the duplicate `Data` row; rows carry `from_func_name`
  and `to_string`), or `slice` with `addr: <string vaddr_hex>` for every
  instruction that reaches it. `kind` is one of `code`, `data`, `string`,
  `import`, `inferred-code`.
- **Import → code:** `symbols` gives each import an `address_hex` (on Mach-O
  this is the stub). Then `callers` on it, or `xrefs` with `to` and
  `kind: "import"`.
- **Crypto constants:** `crypto_scan` finds AES/SHA/MD5 tables, ChaCha sigma,
  Blowfish P-array, and TEA delta with xref counts. Filter with `name` (e.g.
  `aes-sbox`) or `section`.
- **Byte signatures:** `search_bytes` with `pattern` such as
  `"48 8b ?? ?? e8"`, scoped by `section` or one range pair (see Gotchas). Use
  it for magic values and unresolved references.
- **YARA:** `scan_yara` with `rules` (local file path). It needs a binscout
  built with the `yara` cargo feature and fails otherwise.
- **Names:** `functions` with `query` (case-insensitive substring over
  rename-resolved names), `caller`/`callee` filters, or one range pair.
- **Library code:** `flirt_hints` suggests names for known library functions;
  they are hints, so check one before trusting a batch. `sig_gen` emits a
  signature document from a binary with known names; feed it back through
  `flirt_hints` `sigs` on a stripped build (an IDA `.pat` file also works).

### 3. Understand one function

Go cheapest to most detailed, and stop when the question is answered:

1. `func` — size, call count, `noreturn`, and `reasons` (why discovery
   created it: `entry`, `export`, `symbol`, `function-starts`, …). Decide
   whether it is worth reading.
2. `callees` (depth 1) — what it calls often tells you what it does.
3. `structure` — loops and branch sites.
4. `pseudo` — a quick lossy read. Resolved address computations carry a
   `// => 0x…` suffix naming the target (a string, global, or GOT slot).
5. `blocks` then `block_insns` (or `disasm` with `addr`+`len`) — ground
   truth for anything you will report.
6. `cfg` — the full graph, only when you need all edges at once.
7. `ir` — the lifted IR for a range; check `ir_coverage` for the arch first
   if the lift looks incomplete.
8. `bytes` — raw data with provenance. `as` selects a typed view (`u8`..`u64`,
   `ptr`, `cstr`, `utf16`; `endian: "be"` for big-endian). Integer views carry
   `values_hex` twins; read those instead of `values` for `u64`/`ptr`.

`callers` with `depth` > 1 walks back toward the entry or exported API to
answer "how is this reached".

### 4. Record what you learn

- `rename` a function (`addr` = entry, `name`; empty name clears) once its
  purpose is clear. Later `functions`/`pseudo` output shows the new name,
  which compounds understanding.
- `comment` any address (empty string clears) for evidence and open
  questions. `annotation` reads both back.
- `define_func` / `undefine_func` fix function discovery: seed code binscout
  missed (jump-table targets, code behind unresolved indirect jumps) or drop a
  false function. Both re-analyze immediately. On 32-bit ARM pass
  `mode: "arm"` or `"thumb"`.
- `set_type_hint` stores a struct layout at an address:
  `{"kind":"struct","name":…,"size":N,"fields":[{"name":…,"offset":…,"size":…}]}`
  (every field needs `size`; `type` is not kept). `bytes` with `as_type: <hint
  addr>` then renders the fields over a range at least `size` long. An empty
  hint clears it.
- `annotations_export` emits a portable document (bound to the binary's
  sha256); `annotations_import` merges one. Import fails on conflicting fields
  unless `overwrite: true` — do not overwrite without the user's consent.

Ask before writing to a project DB you did not create; it may be someone's
work. The default DB sits next to the binary as `<binary>.rsdbg.redb`; pass an
explicit `db` when that directory is read-only or must stay clean.

### 5. Compare builds

`diff` with `binary_a` (baseline) and `binary_b`: functions come back
`matched` (byte-identical), `changed` (with `reason`, e.g. `ir-match`), `added`,
or `removed`; `summary` has the counts. Each list pages on its own through
`offset`/`limit`. Both projects open read-only, so pass `db_a`/`db_b` (not
`db`). `fat_arch` and `raw` apply to both sides.

- `diff_func` with `addr_a`/`addr_b` gives the block-level and per-instruction
  edit script (`same`, changed, added) for one pair. Read it before opening
  either side with `blocks`/`block_insns`.
- `diff` with `transfer_renames: true` embeds the side-A renames mapped onto
  side B as a document for `annotations_import`, so a new build starts named.
  Importing it is a write; get consent first.

### 6. Export a patch (only when asked)

`patch` assembles replacement bytes at `addr` and returns `va`, `file_off`,
`old_hex`, `new_hex`, `size_ok`. It supports **x86 and aarch64** only. Give
exactly one of `asm` or `bytes` (hex pairs). `asm` accepts a short list:
x86 `nop`, `ret`, `int3`, `jmp ADDR`, `call ADDR`; aarch64 `nop`, `ret`,
`brk #IMM`, `b ADDR`, `bl ADDR`. Anything else (`mov x0, #1`) fails with
`invalid opcode`; assemble elsewhere and pass `bytes`. Shorter replacements
are NOP-padded to the instruction boundary; `size_ok: false` means it does
not fit. `out` writes a `json` or `ips` patch file (`format`), which must
differ from the binary; the binary is never written. Applying the patch is
the user's step.

## Batching

`batch` runs up to 32 read-only ops over one open project, in order:

```
batch({binary, db, fat_arch?, raw?, pdb?, debug_file?, ops: [{tool: "func", params: {addr: "0x…"}}, …]})
→ {results: [{ok: …} | {error: "…"}]}
```

- Use it for orientation (`headers`, `sections`, `symbols`, `diagnostics`) and
  for reading several functions (`func` + `callees` + `structure` per entry).
- The envelope `binary`/`db`/`raw`/`fat_arch`/`pdb`/`debug_file` applies to
  every op, so leave them out of `params`.
- One bad op returns its own `{error}` and the rest still run. Write tools and
  `diff` are rejected per op.
- Per-op limits are unchanged and total output is capped at 1 MiB. Keep
  `limit` small on `strings`/`xrefs` ops.

## Raw blobs and firmware

For headerless images pass `raw: {arch, base, entry?}` on every call (CLI:
`--raw --arch <arch> --base <addr> [--entry <addr>]`). Arch is one of
`x86_64`, `x86_32`, `aarch64`, `arm32`, `thumb`, `riscv32`, `riscv64`,
`mips32`, `ppc32`, `ppc64`. A wrong base shows up as xrefs and string
references pointing nowhere; a wrong arch shows up as decode failures in
`diagnostics`. Iterate on both before analyzing. Check `ir_coverage` for the
arch: lift depth varies, and unlifted instructions become NOPs with a warning.

## Debug info

Every MCP tool takes `pdb` (PE only) and `debug_file` (external DWARF, such as
a dSYM DWARF file or an unstripped copy that has DWARF sections); the CLI
globals are `--pdb` and `--debug-file`. They seed function starts and names.
Local files only; nothing is fetched. Pass them on every call, like the
mapping. `project_info` reports `debug_funcs`; check it is non-zero to confirm
the debug info was applied.

Not verified to help on Mach-O: in a 0.9.0 test (stripped arm64 binary plus a
`dsymutil` DWARF file) the flag was accepted but `debug_funcs` stayed 0 and a
stripped local function stayed unnamed. Passing a binary that has only a debug
map as `debug_file` fails with `no DWARF sections`. A `pdb` on a non-PE binary
is rejected. Do not promise debug names; confirm `debug_funcs` first.

## Fat (universal) Mach-O

Pass `fat_arch` on every call (CLI: `--fat-arch`): `x86_64`, `x86_32`,
`aarch64`, `arm32`, or a `lipo` alias such as `arm64`. Aliases are normalized,
so `arm64` and `aarch64` are the same mapping. The error for a missing
selection lists the available slices.

- **Give each slice its own `db`.** All slices default to one sidecar
  (`<binary>.rsdbg.redb`). Once one slice has annotations, opening another
  fails with `mapping mismatch … use a separate --db PATH`. Annotations are
  never remapped across slices. Use e.g. `db: "<binary>.x86_64.redb"` from
  the first call.
- **arm64 + arm64e containers are ambiguous.** Both normalize to `aarch64`
  (`matches 2 slices`), and `arm64e` is not accepted. Extract the slice first
  with `lipo -thin arm64e in -output out` and analyze `out` without
  `fat_arch`.

## Gotchas (binscout 0.9.x)

- **Older binscout returns different shapes.** Before 0.9.0, `strings`,
  `functions`, `stack_strings`, and `go_funcs` returned a bare array with no
  total, `xrefs` returned `{total, xrefs}`, and `strings`/`functions` needed
  `envelope: true`. `slice` did not error on an unmapped root, `patch` was x86
  only, and `pdb`/`debug_file` were CLI only. If a response has no `items`
  key, check `binscout --version`.
- **aarch64 `adrp` leaves page-base noise.** Each `adrp` adds a `Data` xref
  to the 4 KiB page base (often the image base, e.g. `0x100000000`, or a GOT
  page such as `0x100004000`). The real target is the `Data`/`String` xref on
  the following `add`/`ldr`. Ignore page-base hits when counting references,
  and expect `slice` on such a page address to return unrelated code.
- **Mach-O stubs.** Stubs in `__stubs` are named after their import (`_puts`)
  and `symbols` gives imports an address. The stub's `Data` xrefs hit its
  `__got` slot. Treat any stub that still shows `name: null` as unresolved:
  infer the target from call context, label it with `rename`, and mark it as
  inferred.
- **`slice` roots.** `addr` is the root that other instructions must reach.
  A mapped address nothing reaches returns an empty page. An unmapped address
  fails with `not_found: slice root … is not mapped`. Older versions took
  `to`; use `addr`.
- **`slice` is wide.** A string root can pull in most of the referencing
  function's instructions back to its entry. `depth` defaults to 8 (max 64);
  set `depth` and `limit`.
- **Hidden code-section strings.** `strings` hides hits in executable memory
  unless `pattern`, `section`, or `include_code: true` is given.
- **Range arguments.** `functions` and `search_bytes` take one of two pairs;
  give one pair, never both. `range_lo`/`range_hi` is inclusive (`lo <= x <=
  hi`); `range_start`/`range_end` is half-open (`start <= x < end`). Both
  filter on function entry (`functions`) or match address (`search_bytes`).
- **JSON numbers are lossy above 2^53.** Prefer `*_hex` fields and
  `bytes_hex`/`values_hex`; do not do arithmetic on decimal addresses.
- **Writes are rejected inside `batch`.** Run `rename`, `comment`, and the other
  writes as top-level calls.

## Reporting

Lead with the answer to the user's question, then the evidence chain as
addresses (`0x…` entry → call site → string/constant). Include the `sha256`
from `headers`. Mark each conclusion as observed or inferred, and list open
questions and anything binscout could not resolve (`diagnostics`, unsupported
format, unlifted ranges).
