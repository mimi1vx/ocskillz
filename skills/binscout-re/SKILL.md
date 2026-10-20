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
| `project_info` | `binscout load` (also warms the sidecar) |
| `rename`, `comment`, `annotation` (read) | `binscout annotate <binary> <addr> [--rename <name> \| --comment <text>]`; no flag reads |
| `set_type_hint`, `get_type_hint` | `binscout type-hint` |

Prefer the MCP; use the CLI for scripting or when the MCP is not connected.
Check `binscout --version` when behavior differs from this skill (verified
against 0.8.0).

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
- **Page everything, and know the shape.** Default page is 50, max `limit` is
  1024. Most list tools return `{items, total, next_offset}`. Exceptions:
  `xrefs` returns `{total, xrefs}`; `strings`, `functions`, `stack_strings`,
  and `go_funcs` return a **bare array with no total**. Pass `envelope: true`
  to `strings`/`functions` to get `total` and `next_offset`. Never assume a
  first page is complete.
- **Repeat the mapping on every call.** `fat_arch` (fat Mach-O) and `raw`
  (headerless blobs) are per-call arguments, not session state. Pass the same
  mapping on every call against that binary.
- **State confidence.** Separate what binscout reported (fact) from what you
  infer (hypothesis). Name evidence by address.
- **Writes are explicit.** `rename`, `comment`, `define_func`,
  `undefine_func`, `set_type_hint`, `annotations_import` change the project DB.
  `patch` only exports bytes and never touches the binary. `batch` rejects
  every write tool and `diff`.

## Workflow

### 1. Orient

1. `project_info` — arch, format, entry, counts. A fat Mach-O fails with
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
5. `diagnostics` — unresolved indirect jumps/calls and decode failures. Many
   decode failures in code sections means data in code, obfuscation, or a
   wrong arch/base. Stubs with one unresolved indirect jump and a lone decode
   failure at a Mach-O image base are normal.
6. `go_funcs` — for a stripped Go binary, recovers names and exact bounds from
   `pclntab` (empty array when there is no table).

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
  instruction that reaches it.
- **Import → code:** `symbols` gives each import an `address_hex` (on Mach-O
  this is the stub). Then `callers` on it, or `xrefs` with `to` and
  `kind: "import"`.
- **Crypto constants:** `crypto_scan` finds AES/SHA/MD5 tables, ChaCha sigma,
  Blowfish P-array, and TEA delta with xref counts. Filter with `name` (e.g.
  `aes-sbox`) or `section`.
- **Byte signatures:** `search_bytes` with `pattern` such as
  `"48 8b ?? ?? e8"`, scoped by `section` or `range_start`/`range_end`. Use it
  for magic values and unresolved references.
- **YARA:** `scan_yara` with `rules` (local file path). It needs a binscout
  built with the `yara` cargo feature and fails otherwise.
- **Names:** `functions` with `query` (case-insensitive substring over
  rename-resolved names), `caller`/`callee` filters, or `range_lo`/`range_hi`.
- **Library code:** `flirt_hints` suggests names for known library functions;
  they are hints, so check one before trusting a batch. `sig_gen` emits a
  signature document from a binary with known names; feed it back through
  `flirt_hints` `sigs` on a stripped build (an IDA `.pat` file also works).

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
8. `bytes` — raw data with provenance. `as` selects a typed view (`u8`..`u64`,
   `ptr`, `cstr`, `utf16`; `endian: "be"` for big-endian).

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
`old_hex`, `new_hex`, `size_ok`. It is **x86 only** (aarch64 fails with
`patch is x86-only`). Give exactly one of `asm` (`nop`, `ret`, `int3`,
`jmp ADDR`, `call ADDR`) or `bytes` (hex pairs). Shorter replacements are
NOP-padded to the instruction boundary; `size_ok: false` means it does not
fit. `out` writes a `json` or `ips` patch file (`format`), which must differ
from the binary; the binary is never written. Applying the patch is the
user's step.

## Batching

`batch` runs up to 32 read-only ops over one open project, in order:

```
batch({binary, db, fat_arch?, raw?, ops: [{tool: "func", params: {addr: "0x…"}}, …]})
→ {results: [{ok: …} | {error: "…"}]}
```

- Use it for orientation (`headers`, `sections`, `symbols`, `diagnostics`) and
  for reading several functions (`func` + `callees` + `structure` per entry).
- The envelope `binary`/`db`/`raw`/`fat_arch` applies to every op, so leave
  them out of `params`.
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

## Debug info (CLI only)

The CLI accepts `--pdb <PATH>` (PE) and `--debug-file <PATH>` (external DWARF,
such as a dSYM DWARF file or an unstripped copy) to seed function starts and
names. Local files only; nothing is fetched. The MCP tools do not expose
them. `project_info` reports `debug_funcs`; check it is non-zero to confirm the
debug info was applied. Not verified: whether later MCP calls on the same `db`
keep the debug names.

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

## Gotchas (binscout 0.8.x)

- **aarch64 `adrp` leaves page-base noise.** Each `adrp` adds a `Data` xref
  to the 4 KiB page base (often the image base, e.g. `0x100000000`). The real
  target is the `Data`/`String` xref on the following `add`/`ldr`. Ignore
  page-base hits when counting references.
- **Mach-O stubs.** Stubs in `__stubs` are named after their import (`_puts`)
  and `symbols` gives imports an address, but stubs still hold an unresolved
  indirect jump in `diagnostics`; this is expected. The stub's `Data` xrefs hit
  its `__got` slot. Treat any stub that still shows `name: null` as unresolved:
  infer the target from call context, label it with `rename`, and mark it as
  inferred.
- **`slice` is not an error on a dead root.** `addr` is the root that other
  instructions must reach; an address nothing reaches returns an empty page.
  Older versions took `to`; use `addr`.
- **`slice` is wide.** A string root can pull in most of the referencing
  function's instructions back to its entry. Set `depth` and `limit`.
- **Hidden code-section strings.** `strings` hides hits in executable memory
  unless `pattern`, `section`, or `include_code: true` is given.
- **Range arguments differ.** `functions` uses inclusive `range_lo`/`range_hi`
  (entry ≥ lo and ≤ hi). `search_bytes` uses half-open `range_start`/`range_end`
  over match addresses. The other pair of names on each tool is a deprecated
  alias that warns on stderr; use the primary names above.
- **JSON numbers are lossy above 2^53.** Prefer `*_hex` fields and
  `bytes_hex`; do not do arithmetic on decimal addresses.
- **`patch` is x86 only** (and `asm` accepts just five forms). On other
  arches use `bytes` and assemble elsewhere.

## Reporting

Lead with the answer to the user's question, then the evidence chain as
addresses (`0x…` entry → call site → string/constant). Include the `sha256`
from `headers`. Mark each conclusion as observed or inferred, and list open
questions and anything binscout could not resolve (`diagnostics`, unsupported
format, unlifted ranges).
