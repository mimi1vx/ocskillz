# 05 - Security, FFI, and Supply Chain

Haskell's type system does not validate hostile input, constrain resources, or
make native code safe. Treat network data, paths, environment, package metadata,
build scripts, plugins, and FFI results as trust-boundary inputs. Apply the
general controls from `sota-code-security`; use `sota-sandboxing` when compiling
or running untrusted code or parsers needs OS-enforced isolation.

## 1. Contain unsafe escape hatches

`unsafePerformIO` and `unsafeCoerce` erase guarantees on which optimizations and
callers rely. Their names are not a sufficient safety argument.

```haskell
-- BAD: evaluation order, duplication, and sharing change observable behavior.
nextId :: Int
nextId = unsafePerformIO (atomicModifyIORef' counter (\n -> (n + 1, n)))

-- GOOD: expose effects and ownership in the type.
nextId :: IORef Int -> IO Int
nextId counter = atomicModifyIORef' counter (\n -> (n + 1, n))
```

- Prefer a normal `IO` API, `ST`, typed wrappers, or a proven library.
- If `unsafePerformIO` is unavoidable for a process-wide immutable cache,
  document purity, thread safety, exception behavior, and initialization. Use
  `NOINLINE` where required, but understand that a pragma does not prove
  referential transparency.
- `unsafeDupablePerformIO` is even stronger: the action may run multiple times
  or concurrently. Never use it for allocation with unique identity, mutation,
  file/network I/O, finalizers, or secrets.
- `unsafeCoerce` requires a representation proof covering roles, levity,
  runtime representation, newtype abstraction, and compiler/version changes.
  Prefer `coerce`/`Coercible`, `Typeable.cast`, or explicit serialization.
- `unsafeInterleaveIO` hides I/O behind laziness; resource lifetime and
  exception timing become non-local. Prefer explicit streaming.

Keep unavoidable unsafe code in a tiny module with a safe exported API,
property tests, and a comment stating the invariant and why supported APIs are
insufficient.

## 2. Execute programs with argv, never a variable shell command

Use `System.Process.proc`, `createProcess`, or a maintained typed process API.
Do not concatenate untrusted data into `shell`, `system`, `callCommand`, or
`readCreateProcess (shell ...)`.

```haskell
-- BAD: name can inject shell syntax.
callCommand ("convert " <> name <> " output.png")

-- GOOD: direct executable plus distinct argv entries.
let cp = (proc "/usr/bin/convert" ["--", name, "output.png"])
           { env = Just [("PATH", "/usr/bin:/bin"), ("LANG", "C")]
           , cwd = Just workDir
           }
withCreateProcess cp $ \_ _ _ ph -> do
  exit <- waitForProcess ph
  unless (exit == ExitSuccess) (throwIO (CommandFailed exit))
```

- Fix or allowlist executable paths. PATH lookup is a trust decision.
- `proc` prevents shell metacharacter injection, not option injection or
  application-specific filename syntaxes. Use `--` only where the child
  supports it and validate operands against that program's complete grammar.
- Set a minimal environment, working directory, privilege, deadline, and output
  limit. Check launch errors, exit status, signal termination, and partial
  output.
- Drain stdout and stderr concurrently or redirect them; reading one pipe to
  EOF before the other can deadlock. Bound captured output.
- Avoid passing secrets in argv: process listings and diagnostics may expose
  them. Prefer a protected descriptor or purpose-built credential channel.

## 3. Harden parsers and resource use

Parsing success is not authorization or semantic validation. Bound bytes before
decoding, then bound nesting, element count, lengths, expansion, and time.

```haskell
-- BAD: consumes an unbounded lazy request body before parsing.
body <- LBS.hGetContents handle
either fail use (Aeson.eitherDecode body)

-- GOOD: reject/stream at the transport boundary, then validate the value.
body <- readAtMost (1024 * 1024) handle
value <- either (throwIO . InvalidJson) pure (Aeson.eitherDecodeStrict' body)
request <- either (throwIO . InvalidRequest) pure (validateRequest value)
```

- Lazy `ByteString` does not impose a memory limit; consumers can eventually
  retain or force all chunks.
- Length prefixes require checked conversion and arithmetic before allocation.
  Reject negative, overflowing, and policy-exceeding values.
- Limit decompressed output and ratio, archive members and total extracted
  bytes, image dimensions, parser recursion, and duplicate/map keys where the
  format permits them.
- Avoid partial functions (`read`, `head`, `tail`, `fromJust`, `!!`) on
  attacker-reachable data. Use total parsers and explicit errors.
- Backtracking parser combinators can consume excessive CPU. Commit after an
  unambiguous prefix, avoid broad `try`, measure hostile near-matches, and fuzz
  public parsers.
- Do not deserialize functions, closures, arbitrary types, or trusted internal
  constructors from external data.

## 4. File paths, containment, and TOCTOU

`FilePath` is a string, not a capability. `normalise`, `(</>)`, `makeRelative`,
and string-prefix checks do not establish containment in the presence of
absolute paths, `..`, symlinks, mount points, or concurrent renames.

```haskell
-- BAD: prefix confusion and symlink swaps remain possible.
let target = normalise (root </> userPath)
BS.readFile target

-- BETTER for low-risk, non-adversarial trees: canonicalize existing paths and
-- compare path components, while recognizing the reopen race.
root' <- canonicalizePath root
target' <- canonicalizePath (root </> userPath)
```

For hostile writable trees, do not authorize a pathname and later reopen it.
Use opaque server-side IDs or descriptor-relative operations (`openat`-style),
reject symlink traversal with platform flags such as `O_NOFOLLOW`, and keep the
trusted parent descriptor open. Haskell libraries may require carefully
reviewed `unix`/FFI wrappers for these OS primitives.

- Reject absolute paths, parent components, NUL, alternate separators/volumes,
  and unsupported file types before access.
- Create files atomically with exclusive creation in a trusted directory and
  restrictive permissions. Predictable temp names and check-then-create are
  races; use `openBinaryTempFileWithDefaultPermissions` only after reviewing
  its permission and directory guarantees for the deployment.
- Archive extraction must reject absolute/traversing member names, links and
  special files unless explicitly supported, and enforce total decoded limits.
- Permission checks and the eventual operation should use the same open object
  where the OS API allows it.

## 5. Keep secrets out of ordinary data flows

- Obtain secrets from a secret manager, protected file descriptor, or narrowly
  injected environment. Do not put them in source, `.cabal` files,
  `cabal.project`, freeze files, command lines, tests, eventlogs, heap profiles,
  or build logs.
- Do not derive `Show`, `Generic`-based logging, JSON encoders, or broad record
  dumps for secret-bearing types. Define redacted instances and explicit
  serialization.
- Keep secret lifetime and copies small. Immutable `ByteString`/`Text` values
  may be copied, retained by thunks, or preserved in heap/core dumps; garbage
  collection is not secure erasure.
- Use maintained cryptographic libraries and OS CSPRNG sources. Do not design
  crypto or compare authenticators with ordinary `Eq` when a constant-time
  verification API exists.
- Disable or protect core dumps, profiling artifacts, and crash uploads in
  secret-bearing processes. Rotate any credential that enters an artifact.

## 6. Treat builds as code execution

Building a Haskell dependency can execute code through `Setup.hs`, custom
`build-type`, Template Haskell splices, compiler plugins, preprocessors, C
toolchains, and package-manager hooks. Source dependencies therefore have the
builder's privileges and network/filesystem access.

```haskell
-- Build-time execution in the compiler process.
{-# LANGUAGE TemplateHaskell #-}
embedded <- $(runIO (readFile "/etc/build-secret") >>= lift)
```

- Review new and changed `Setup.hs`, `build-type: Custom`, `build-tool-depends`,
  `custom-setup`, `default-extensions: TemplateHaskell`, `-fplugin`, foreign
  sources, and generated code.
- Build untrusted or newly introduced packages in an ephemeral, unprivileged
  environment with no production secrets, restricted egress, read-only source,
  bounded CPU/memory/processes, and controlled artifact export. See
  `sota-sandboxing` for the isolation boundary; a container alone is not always
  sufficient for hostile compilation.
- Never run a downloaded installer via `curl | sh`. Verify the toolchain source,
  checksums/signatures where published, and CI action revisions.
- Template Haskell output is part of the program. Review generated declarations
  or compiler dumps when a splice affects authorization, serialization, or FFI.

## 7. Safe Haskell is not a sandbox

Safe Haskell can restrict imports and unsafe language features for modules
compiled with the relevant safety mode and package trust configuration. It does
not limit CPU, memory, filesystem, network, syscalls, or ordinary permitted
`IO`, and it is not an isolation boundary for hostile code.

- Safety depends on how every relevant module and package was compiled and on
  the package trust database. A source pragma does not retroactively establish
  the provenance of precompiled objects.
- Compilation itself may execute Template Haskell, plugins, preprocessors, or
  `Setup.hs` before code is ever run. Safe Haskell is not protection for a
  machine compiling untrusted source.
- `Trustworthy` is an assertion by the package author and requires review of
  the module's abstraction boundary and transitive trust.
- Compiler support and feature interactions evolve. Check the GHC version's
  current Safe Haskell documentation; do not base a new sandbox architecture on
  it.

Use an OS sandbox or stronger isolation for untrusted compilation/execution,
with least privilege and denied-by-default network/filesystem access.

## 8. FFI call safety is a scheduling and callback contract

For `foreign import ccall`, the `safe`/`unsafe` annotation does not mean memory
safety.

```haskell
-- BAD if c_parse can block for long or call back into Haskell.
foreign import ccall unsafe "parse" c_parse :: Ptr Word8 -> CSize -> IO CInt

-- GOOD only when the C contract permits callbacks/long blocking as declared.
foreign import ccall safe "parse" c_parse :: Ptr Word8 -> CSize -> IO CInt
```

- `unsafe` has lower call overhead but assumes a short call that will not call
  back into Haskell; it can block progress on the capability running it.
- With the threaded runtime, `safe` permits callbacks and allows other Haskell
  work to proceed, at higher overhead. Without `-threaded`, a blocking `safe`
  call can still block other Haskell threads. It does not add bounds checks or
  make C memory-safe.
- `interruptible` permits async interruption of certain blocking foreign calls
  and needs an exact C/API cancellation contract; interruption can leave native
  state partially changed.
- Validate lengths before conversion to `CSize`/`CInt`; use checked conversions
  and pair every pointer with a proven live allocation of sufficient size and
  alignment.
- Keep `ByteString`/`ForeignPtr` storage alive across the call (`withForeignPtr`,
  `useAsCStringLen`, `touchForeignPtr` where genuinely needed). Never retain a
  pointer beyond the dynamic extent unless ownership is explicitly transferred.
- Match C ABI, calling convention, struct layout, signedness, nullability, errno,
  allocator, and thread-affinity rules. Test all supported platforms with
  sanitizers on the native side.

## 9. StablePtr, callbacks, and finalizers

`StablePtr` keeps a Haskell value reachable for foreign code. It is a manually
managed root, not automatic lifetime tracking.

- Call `freeStablePtr` exactly once, only after native code can no longer use or
  callback with it. Early free is use-after-free; missing free is a leak.
- A callback `FunPtr` created by a `wrapper` import must remain alive until the
  foreign library unregisters it and all concurrent callbacks have finished;
  then call the matching `freeHaskellFunPtr` exactly once.
- Never let a Haskell exception unwind through C. Catch at the callback boundary
  and translate to a documented error result.
- Finalizers are nondeterministic, may run on unexpected threads, and may never
  run before process exit. They must not be required for prompt release,
  security erasure, transaction commit, or ordering-sensitive shutdown.
- `Foreign.Concurrent.newForeignPtr` finalizers can run Haskell code but retain
  the same nondeterminism and resurrection/deadlock hazards. Prefer explicit
  `bracket` ownership, with finalizers only as a leak backstop.

## 10. Dependency and advisory review

Hackage Security protects repository metadata with a TUF-derived design,
including authenticated package hashes and rollback/freeze defenses. It does
not prove that package source is non-malicious or that a maintainer account was
not compromised.

```bash
cabal update
cabal build all --dry-run
cabal freeze
cabal outdated --freeze-file
cabal list --installed
```

- Commit and review `cabal.project.freeze` for applications. Libraries should
  test supported dependency ranges, but release/deployment jobs still need a
  reproducible resolved plan.
- Set an intentional `index-state` for reproducibility, update it in reviewed
  dependency PRs, and build with the expected freeze file. A freeze file pins
  versions, not source provenance by itself.
- Review the solver plan (`dist-newstyle/cache/plan.json` or `cabal-plan`), new
  maintainers, release history, source repository match, flags, transitive
  dependencies, native code, vendored artifacts, and build-time execution.
- Check the Haskell Security Response Team advisory database and GitHub
  advisories on every dependency change and on a schedule; advisories can be
  published without a lockfile change. Document time-bounded exceptions.
- Use least-privilege CI tokens, pin third-party CI actions by immutable commit,
  and separate dependency builds from release-signing credentials.

## References

- https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/safe_haskell.html
- https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/ffi.html
- https://hackage.haskell.org/package/process
- https://hackage.haskell.org/package/directory
- https://github.com/haskell/hackage-security
- https://github.com/haskell/security-advisories
- https://www.haskell.org/ghcup/about/#security

## Audit checklist

```bash
# Unsafe language/runtime boundaries: require a local written invariant
rg -n '\b(unsafePerformIO|unsafeDupablePerformIO|unsafeInterleaveIO|unsafeCoerce)\b' --glob '*.{hs,lhs}'
rg -n 'LANGUAGE.*(TemplateHaskell|Unsafe)|OPTIONS_GHC.*-fplugin|Trustworthy|Safe-Inferred' --glob '*.{hs,lhs}'

# Shell/argv and secret-bearing process surfaces
rg -n '\b(callCommand|readCreateProcess|createProcess|proc|shell|system|rawSystem)\b' --glob '*.{hs,lhs}'
rg -ni "(api[_-]?key|secret|password|token).*[=:].*['\"][^'\"]{8,}" --glob '*.{hs,lhs,cabal,project,yaml,yml,json}'

# Partial parsing, unbounded input, paths, archives, and temp files
rg -n '\b(read|head|tail|init|last|fromJust)\b|!!|hGetContents|readFile|decode|decompress|extract' --glob '*.{hs,lhs}'
rg -n 'canonicalizePath|normalise|makeRelative|isPrefixOf|\.\./|openTempFile|createDirectory|renameFile' --glob '*.{hs,lhs}'

# FFI declarations and manual lifetime management
rg -n 'foreign (import|export)|ccall (unsafe|safe|interruptible)|StablePtr|newStablePtr|freeStablePtr|freeHaskellFunPtr' --glob '*.{hs,lhs,hsc,chs}'
rg -n 'ForeignPtr|newForeignPtr|addForeignPtrFinalizer|touchForeignPtr|withForeignPtr|CString|Ptr ' --glob '*.{hs,lhs,hsc,chs}'

# Build-time execution and supply-chain changes
rg -n 'build-type: *Custom|custom-setup|build-tool-depends|TemplateHaskell|-fplugin|c-sources|cxx-sources' . --glob '*.{cabal,hs,lhs,project}'
rg -n 'source-repository-package|repository |index-state|active-repositories|allow-newer|constraints' --glob 'cabal.project*'
cabal build all --dry-run
cabal outdated --freeze-file
```

Grep hits are leads, not findings. Trace data origin, bounds, ownership,
compiler/build behavior, native contracts, and mitigations before assigning a
security issue; `safe` FFI, Safe Haskell, canonicalization, and argv APIs each
solve only a specific part of the threat model.
