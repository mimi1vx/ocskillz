# 03 — Unsafe Discipline

`unsafe` does not turn off the rules; it makes **you** the checker. The standard
is: minimal surface, sound encapsulation, documented invariants, and tooling
(Miri, sanitizers) that re-checks what the compiler can't.

## 1. Minimize, then isolate

- First question for any `unsafe`: **is there a safe equivalent?** Most are:
  `split_at_mut`, `MaybeUninit` + `Vec::spare_capacity_mut`, `bytemuck`/`zerocopy`
  for transmutes, `OnceLock`/`LazyLock` for lazy statics, `Cell`/`RefCell` for
  interior mutability, `Pin` APIs instead of raw self-references. The safe
  surface keeps growing — 1.93 stabilized `MaybeUninit` slice APIs
  (`assume_init_ref`/`assume_init_mut`/`write_copy_of_slice`), retiring many
  hand-rolled init loops.
- Performance claims require receipts: an `unsafe` "optimization"
  (`get_unchecked`, skipped UTF-8 checks) without a benchmark showing the safe
  version is the bottleneck is a finding. Bounds checks usually vanish under
  iterators or a single up-front `assert!(len <= buf.len())` hoisting.
- Isolate unsafe in **small modules/crates with a safe public API** whose
  soundness can be argued locally. The privacy boundary is the soundness
  boundary: if a `pub` field or safe method can break the invariant your
  unsafe code relies on, the abstraction is unsound *even if no caller does it
  today*.

```rust
// Sound abstraction: invariant (`init <= N`) is privately owned,
// every safe method maintains it, unsafe is locally justifiable.
pub struct FixedVec<T, const N: usize> {
    buf: [MaybeUninit<T>; N],
    init: usize, // INVARIANT: buf[..init] is initialized
}
impl<T, const N: usize> FixedVec<T, N> {
    pub fn push(&mut self, v: T) -> Result<(), T> {
        if self.init == N { return Err(v); }
        self.buf[self.init].write(v);
        self.init += 1;
        Ok(())
    }
    pub fn as_slice(&self) -> &[T] {
        // SAFETY: buf[..init] is initialized (struct invariant, maintained
        // by push/pop; init never exceeds N).
        unsafe { slice::from_raw_parts(self.buf.as_ptr().cast(), self.init) }
    }
}
```

## 2. SAFETY comments — non-negotiable

**Every `unsafe` block carries a `// SAFETY:` comment proving each obligation
of the called API is met.** Every `unsafe fn` and unsafe trait impl carries a
`/// # Safety` doc section stating what callers/implementors must uphold.

```rust
// BAD
let x = unsafe { *ptr };

// GOOD
// SAFETY: `ptr` comes from Box::into_raw in `Self::new`, is non-null and
// aligned, and is not freed until Drop; no &mut alias exists because we
// hold &self and the field is not otherwise exposed.
let x = unsafe { *ptr };
```

- The comment addresses the **specific preconditions** in the unsafe API's
  docs (non-null, aligned, initialized, valid-for-reads, no aliasing, lifetime
  bounds) — not vibes like "this is fine".
- Enforce mechanically: `#![deny(clippy::undocumented_unsafe_blocks)]`
  (and `clippy::missing_safety_doc`, which is warn-by-default). Edition 2024:
  `unsafe_op_in_unsafe_fn` is warn-by-default — write explicit `unsafe {}`
  blocks inside `unsafe fn` so each obligation site is visible and commented.
- An `unsafe fn` whose safety contract can't be written in one paragraph has
  the wrong API shape — split it.

## 3. The UB catalog — what actually bites

Audit unsafe code against these, in observed-frequency order:

1. **Aliasing violations**: constructing two `&mut` to the same data, or a
   `&mut` while a `&` lives — *creating* the reference is UB even if unused.
   Classic source: `&mut *ptr` twice, casting `&T` → `&mut T` (always UB —
   `clippy::cast_ref_to_mut`/compiler `invalid_reference_casting` lint),
   `Vec`/self-referential pointer invalidated by reallocation.
2. **Uninitialized memory**: `mem::uninitialized()` (deprecated, instant UB
   for most types) and `MaybeUninit::assume_init` before full init. Reading
   uninit bytes is UB even for `u8`. Use `MaybeUninit`, `Vec::spare_capacity_mut`,
   `ptr::write` (not `*ptr = v`, which drops the uninit "old value").
3. **Transmute abuse**: size/alignment mismatch, invalid bit patterns (`bool`
   not 0/1, invalid enum discriminant, null fn pointer, uninhabited types),
   transmuting `&T` lifetimes, transmuting between repr(Rust) types whose
   layout is unspecified. Prefer `bytemuck::{cast, Pod}` / `zerocopy`
   (derive-checked), `f32::from_bits`, `ptr::cast`. Transmuting to extend a
   lifetime is a soundness hole, full stop.
4. **Invalid values & ranges**: producing a `str` with invalid UTF-8 via
   `from_utf8_unchecked` on unvalidated input; out-of-range `char`;
   `NonZero*`/`NonNull` holding zero/null.
5. **FFI lifetimes & ownership**: returning a pointer into a Rust object the C
   side outlives; freeing with the wrong allocator (must round-trip
   `Box::into_raw`/`Box::from_raw`, or expose `mylib_free`); double-free when
   C calls a destructor twice; `CString::new(s).unwrap().as_ptr()` — temporary
   dropped at end of statement, dangling pointer (`temporary_cstring_as_ptr`
   lint). Struct layout across FFI requires `#[repr(C)]`.
6. **Unwinding across FFI** — see rules/02 §5; UB pre-"C-unwind", abort after.
7. **Data races**: `unsafe impl Send/Sync` on types containing raw pointers or
   `Cell`-like internals without an argument; `static mut` (deprecated pattern;
   edition 2024 denies `static_mut_refs`) — use `AtomicX`, `OnceLock`,
   `Mutex`, or `SyncUnsafeCell` with justification.

## 3a. Layout, provenance, and Pin — the subtler contracts

**Layout:** `repr(Rust)` layout is unspecified and may differ between
compilations — any unsafe code assuming field order/offsets needs `#[repr(C)]`
(FFI, byte-casting) or `#[repr(transparent)]` (newtype with identical ABI to
its single field — required for soundly casting `&Wrapper<T>` ↔ `&T`).
Enum-discriminant tricks need explicit `#[repr(u8)]`-style declarations.
`bytemuck::Pod`/`zerocopy::FromBytes` derives verify these statically — prefer
them over manual offset math; for unavoidable offsets use
`core::mem::offset_of!` (stable), never hand-computed constants.

**Pointer provenance:** a pointer is more than an address. Casting ptr→int→ptr
strips provenance and is UB-adjacent under strict provenance; round-trip with
`ptr.with_addr(...)`/`ptr.map_addr(...)` (strict provenance APIs, stable) or
keep it as a pointer. Pointers derived from a `&T` may only access that `T`'s
bytes for that borrow's lifetime — offsetting into a sibling field via a field
reference is UB even if the address is "right". Run Miri with
`-Zmiri-strict-provenance` to catch the class.

**Pin:** `Pin<&mut T>` promises T won't move again until drop. Unsafe code
relying on pinning must uphold the drop guarantee (pinned memory must be
dropped before reuse, can't be deallocated without drop) and never hand out
`&mut T` from `Pin<&mut T>` for `!Unpin` types except via `map_unchecked_mut`
with a SAFETY argument that the projection is structural. Hand-rolled
self-referential types: use `pin-project` (safe projections, checks the rules)
instead of manual `unsafe` projections — hand-rolled pin projections are a
recurring soundness-bug source even in expert crates.

**Drop interaction:** `ManuallyDrop` + `ptr::read` patterns (taking ownership
out of `&mut self` in `Drop`) must guarantee no double-drop on every path
including panics; `mem::forget` is safe but leaks — unsafe code may NOT rely
on Drop running for soundness (leakpocalypse rule: `Rc` cycles + `mem::forget`
make "Drop always runs" a false invariant).

## 4. Miri, sanitizers, fuzzing — CI for the unchecked

Any crate with non-trivial `unsafe` runs **Miri in CI**:

```yaml
# .github/workflows/miri.yml (core job)
- run: rustup toolchain install nightly --component miri
- run: cargo +nightly miri test
  env:
    # many-seeds for nondeterminism; strict provenance catches ptr-int abuse
    MIRIFLAGS: "-Zmiri-strict-provenance"
```

- Miri checks the (Tree Borrows / Stacked Borrows) aliasing model, init,
  alignment, leaks — but **only on executed paths**: unsafe code without tests
  is unaudited code. Write tests that exercise every unsafe branch.
- Miri can't run FFI/syscall-heavy paths; for those use sanitizers:
  `RUSTFLAGS="-Zsanitizer=address" cargo +nightly test` (ASan), TSan for
  concurrency claims, and `loom` for testing lock-free/atomic algorithms
  exhaustively.
- Parsers and any unsafe-touching decoder: fuzz with `cargo fuzz` (libFuzzer)
  — fuzzing + Miri/ASan is the practical soundness net (see rules/05 §6).

## 5. Supply-chain visibility of unsafe

- `cargo geiger` reports unsafe usage across the dependency tree — use it to
  *direct review attention*, not as a verdict (unsafe ≠ unsound; zero-unsafe ≠
  sound). Heavy-unsafe deps doing things std could do = replace.
- Prefer audited foundations: `bytemuck`/`zerocopy` over hand transmutes,
  well-known FFI `-sys` crates over bespoke bindings.
- `#![forbid(unsafe_code)]` in crates that need none — it's a semver-visible
  promise and makes regressions un-mergeable. Workspace-wide:
  `[lints.rust] unsafe_code = "forbid"` with per-crate opt-out.
- Record unsafe review in `cargo vet` audits (criteria `safe-to-deploy` +
  unsafe review) — rules/05 §2.

## 6. Soundness review protocol (for AUDIT mode)

For each `unsafe` block, in order:

1. Identify the exact unsafe operations (deref, call, transmute, impl).
2. List each documented precondition of those operations.
3. Check the SAFETY comment discharges **all** of them (missing comment =
   automatic finding; wrong comment = worse).
4. Hunt invariant escapes: can safe code (pub fields, safe methods, trait
   impls, `Deref`, `Drop`, panics mid-modification, reentrancy via callbacks)
   break the invariant the unsafe block assumes? Panic-safety: if user code
   (closures, `T: Clone`, comparators) can panic while your invariant is
   temporarily broken, Drop/unwinding observes broken state → need guard
   objects or `catch_unwind` reasoning.
5. Check `Send`/`Sync`: any manual `unsafe impl` needs a written argument per
   field; raw pointers suppress auto-derive for a reason.
6. Confirm Miri runs over this code path in CI; if not, that's a finding
   regardless of how correct the code looks.

## Audit checklist

- [ ] `rg 'unsafe' -t rust --count-matches` — map the surface first; unsafe
      outside dedicated modules/crates is a structure finding.
- [ ] Undocumented blocks: `rg -B2 'unsafe \{' -t rust | rg -v 'SAFETY'` (then
      verify by eye); enforce `clippy::undocumented_unsafe_blocks`.
- [ ] `rg 'transmute' -t rust` — each one: why not `bytemuck`/`zerocopy`/
      `from_bits`/`cast`? Lifetime-extending transmute = Critical.
- [ ] `rg 'from_utf8_unchecked|get_unchecked|assume_init|set_len' -t rust` —
      verify the stated invariant actually holds on all paths incl. panics.
- [ ] `rg 'static mut|&mut \*\(|as \*mut' -t rust`; compiler lints
      `static_mut_refs`, `invalid_reference_casting` must be deny.
- [ ] `rg 'unsafe impl (Send|Sync)' -t rust` — require per-field justification
      comment; absence = High.
- [ ] FFI: `rg 'extern "C"' -t rust` — check `#[repr(C)]` on crossing types,
      panic containment, allocator pairing (`into_raw`/`from_raw` symmetry),
      `as_ptr()` on temporaries.
- [ ] Layout assumptions: `rg 'repr\(' -t rust` — byte-casting/FFI types have
      `repr(C)`/`repr(transparent)`; `rg 'as usize as \*|usize as \*' -t rust`
      — int→ptr casts (provenance loss).
- [ ] `rg 'map_unchecked_mut|Pin::new_unchecked|get_unchecked_mut' -t rust` —
      hand-rolled pin projections; prefer `pin-project`. Drop impls using
      `ptr::read`/`ManuallyDrop` checked for panic-path double-drop.
- [ ] CI: Miri job exists and isn't `continue-on-error: true`; fuzz targets
      exist for unsafe parsers; `cargo geiger` output reviewed for the tree.
- [ ] Crates with zero unsafe missing `#![forbid(unsafe_code)]` — Low, but
      free hardening.
- [ ] Severity calibration: reachable UB = Critical; unsound public API (safe
      code can trigger UB) = Critical even if unexercised; missing SAFETY
      comment = Medium; missing Miri CI on unsafe crate = Medium.
