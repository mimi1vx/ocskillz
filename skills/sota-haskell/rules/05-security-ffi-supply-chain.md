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
- `openTempFile`/`openBinaryTempFile` create a uniquely named file with
  owner-only permissions (`O_CREAT|O_EXCL` on Unix; exclusivity may not hold on
  NFS) and never delete it. The `...WithDefaultPermissions` variants and
  `temporary`'s `openNewBinaryFile` use default permissions (666 instead of
  600): never for secrets or anything another local user must not read.
- Prefer `withSystemTempFile`/`withSystemTempDirectory` (or `withTempFile`/
  `withTempDirectory`) from `temporary`: the path is removed after use, also on
  exceptions. Use `createTempDirectory` for a directory (owner-only on POSIX)
  and create files inside it. Do not invent names under `/tmp` for `writeFile`,
  `createDirectory`, or `renameFile`.
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
- A secret leaks by value through whatever default rendering reaches it:
  `show`/`displayException` of an exception that embeds a request or URL,
  `Debug.Trace`, `printf`/`show` of a config record, and `SomeException`
  logged by a catch-all. Keep secrets out of URLs and query strings, wrap them
  in a newtype whose `Show` prints a fixed marker, and render caught errors
  through a function that picks fields, not through `show`. Check what a
  library's error type prints before logging it (reproduce one failure with a
  fake secret and read the output).
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

Run these checks on every added package, not only on the first one:

- **Identity.** On the Hackage page, confirm that the name, maintainers, home
  page, and source-repository link belong to the project you intend; look-alike
  names, abandoned forks, and re-uploads are common. `cabal get <pkg>-<version>`
  and read the `.cabal` file, `Setup.hs`, and any foreign sources of the exact
  tarball you will build.
- **History.** Check upload dates, release cadence, changelog, maintainer
  changes, deprecation, and open advisories. Reverse-dependency count is a
  scrutiny signal (a popular-sounding name with almost none is suspicious; many
  dependents do not prove safety).
- **Plan delta.** Diff the solver plan before and after the change. Every new
  transitive package, flag flip, and bound change gets the same review.
- **Insecure defaults.** Read what the library does when left unconfigured.
  `http-client`'s `defaultManagerSettings` has no TLS (`https` requests fail
  with `TlsNotSupported`; use `http-client-tls`), its response timeout defaults
  to 30 s for response headers, `redirectCount` defaults to 10, and `httpLbs`
  reads the whole body. A TLS settings value with
  `settingDisableCertificateValidation = True` (`crypton-connection`) turns
  certificate checking off. Warp's default `setHost` is a wildcard preference.
  `Data.Scientific` arithmetic on untrusted exponents can exhaust memory.
  Configure limits, timeouts, and TLS once in a small wrapper module.

## 11. Outbound requests and SSRF

A URL, host, or port that originates outside the trust boundary can steer a
server-side request at loopback, private networks, or cloud metadata
(`169.254.169.254`). Authorize the destination, not the URL string.

```haskell
-- BAD: validates text only; DNS answers, redirects, and proxies are unchecked.
unless (allowedUrl url) (throwIO Forbidden)
req <- parseRequest (T.unpack url)
httpLbs req manager

-- GOOD: the restriction runs where the connection is made.
let publicOnly = addressRestriction $ \addr ->
      if isInternal (addrAddress addr)
        then Just (connectionRestricted ("blocked address " ++) addr)
        else Nothing
(settings, _) <- mkRestrictedManagerSettings publicOnly Nothing Nothing
manager <- newManager settings
```

- Allowlist scheme (`http`/`https`), host, and port. Reject userinfo
  (`allowed.example@evil.example`), parse once, and request the value that was
  validated. `requestFromURI` accepts only `http`/`https`; never pass a user URL
  to `curl`, `wget`, converters, or file APIs through `proc`.
- Judge resolved addresses, for every address a name returns: reject loopback
  (`127.0.0.0/8`, `::1`), unspecified, RFC 1918, `100.64.0.0/10`, link-local
  (`169.254.0.0/16`, `fe80::/10`), unique-local (`fc00::/7`), and IPv4-mapped
  IPv6 forms of those. Compare parsed addresses, not strings.
- Resolve-then-fetch is racy: DNS rebinding returns a public address to the
  check and an internal one to the connection. Check and connect with the same
  address. `ManagerSettings` exposes `managerRawConnection` and
  `managerTlsConnection` for this; `http-client-restricted`
  (`addressRestriction`, `mkRestrictedManagerSettings`) connects to the checked
  address and applies the restriction to each redirect and to the HTTP proxy.
  Review it like any dependency (§10).
- Redirects are followed transparently (`redirectCount`, default 10). Either
  enforce the check inside the connection hook, or set `redirectCount = 0` and
  re-validate and re-resolve each `Location`. `shouldStripHeaderOnRedirect`
  keeps all headers by default: strip `Authorization` and cookies before a
  cross-host hop.
- `defaultProxy` honours `http_proxy`/`https_proxy`; a connect-time check then
  sees the proxy, not the target. Use `managerSetProxy noProxy` or enforce policy
  at the proxy.
- Bound the response: `managerResponseTimeout` covers response headers only.
  Use `withResponse` with `brRead`/`brReadSome`, a byte cap, and a deadline
  instead of `httpLbs`, and do not reflect fetched bodies, status codes, or
  connection errors to a caller when the target is attacker-chosen.
- Egress firewalling and a hardened metadata service are the backstop, not a
  substitute for the checks above.

## 12. Regular expressions on untrusted input

Choose the engine by its worst case and treat the pattern as code.

- `regex-tdfa` is a pure-Haskell POSIX engine without backreferences; its
  README states matching should take O(N) time with memory bounded by the
  pattern. Known slow cases: large character classes combined with `{m,n}`.
  Prefer it for untrusted subjects.
- PCRE-based libraries (`pcre-light`, `regex-pcre`, `regex-pcre-builtin`) use
  PCRE's standard matcher, a depth-first backtracking search. Nested
  quantifiers such as `(a+)+$` can take exponential time on near-matches. Do
  not use them with attacker-supplied patterns, or with unreviewed patterns on
  attacker-sized subjects. `regex-pcre-builtin` bundles PCRE sources (§10).
- Never splice user text into a pattern. Use `T.isInfixOf`/`isPrefixOf` for
  literals, or keep the pattern constant and pass user text as the subject. If
  a quoted literal is unavoidable, escape every metacharacter by hand and
  test it with generated input; neither `regex-tdfa` nor `pcre-light` exports a
  quoting helper.
- Invalid patterns: `=~` in `regex-tdfa` calls `error` on a processing failure and
  `pcre-light`'s `compile` throws. For any non-constant pattern use `=~~` or
  `makeRegexM` (`MonadFail`), or `compileM`.
- Validation means matching the whole input. An unanchored match accepts a valid
  substring of hostile text. With `defaultCompOpt`, `regex-tdfa` has
  `multiline = True`, so `^`/`$` match at embedded newlines: anchor with
  `` \` `` and `\'` (start/end of entire text). In PCRE use `\A` and `\z`; `$`
  also matches before a final newline unless `dollar_endonly` is set.
- Cap subject length first (§3). `System.Timeout.timeout` is an asynchronous
  exception: it is delivered only at allocation points, and a foreign call
  such as a C matcher cannot be timed out. For backtracking or FFI engines it
  is not a defense; use a linear-time engine or a killable subprocess.
- For structured grammars (URLs, dates, versions, config, anything nested) use
  `attoparsec` or `megaparsec` with bounds and a total result type, not a regex.

## 13. Runtime code loading is arbitrary code execution

Code that is loaded, interpreted, or compiled at run time runs with the
process's privileges, secrets, filesystem, and network.

- Surfaces: `hint` (`Language.Haskell.Interpreter`), `plugins`
  (`System.Plugins`, `System.Eval`), `dynamic-loader`, the `ghc` package,
  `System.Posix.DynamicLinker` (`dlopen`/`dlsym`) and `foreign import ccall
  "dynamic"` calls through the resulting pointers.
- Never evaluate, interpret, compile, or load user-supplied expressions,
  modules, library paths, or plugin names. Restricting imports or using Safe
  Haskell is not a sandbox (§7), and an interpreted expression is unbounded in
  CPU and memory (`timeout` cannot stop a non-allocating loop, §12).
- Load native libraries and plugins only from absolute, trusted, non-writable
  locations; pin path and checksum.
- `cast` and `fromDynamic` are checked and are not loaders. An external tag
  that selects a type followed by `unsafeCoerce` is memory misinterpretation
  (§1).
- When extensibility is required, prefer data: a total config format, a small
  language with a total parser and an evaluator limited by fuel and size and
  without `IO`, or statically linked handlers selected by name. If real
  plugins are required, run them in a separate process under resource limits
  and least privilege (`sota-sandboxing`) behind a narrow protocol, and kill
  from outside on a deadline.
- Interpreters in build tooling or test harnesses over trusted source are fine;
  keep them out of release executables (for example behind a Cabal flag).

## 14. Keep debug and profiling surface out of release artifacts

Developer diagnostics write files, expose internals, and leak data.

```cabal
-- BAD: any caller, or the GHCRTS environment variable, can set any RTS flag.
ghc-options: -rtsopts
-- GOOD: fixed flags; callers cannot change them.
ghc-options: -threaded -rtsopts=none "-with-rtsopts=-N2 -T"
```

- RTS options can write files with the process's privileges (`-s <file>`,
  `-S <file>`, `-l`/`-ol`, heap profiles); this is why GHC defaults to
  `-rtsopts=some` (only `-?` and `--info`). `-rtsopts` means `all`, for argv
  and `GHCRTS`. `none` aborts on `+RTS` and ignores `GHCRTS` with a warning;
  `ignoreAll` also ignores `GHCRTS`. `-with-rtsopts` applies regardless. Open
  RTS options suit internal binaries with trusted argv and environment only.
- Do not ship `-debug` (debug RTS: assertions, `-D` flags) or profiling builds.
  `+RTS -xc` prints a stack trace for every exception to stderr and exists only
  in profiling builds.
- `Debug.Trace` (`trace`, `traceShow`, `traceShowId`, `traceM`, `traceIO`) is
  documented as not for production code. Ban it with an HLint `functions` rule
  (`{name: Debug.Trace.trace, within: []}` per function) or a CI grep.
- Monitoring listeners: `ekg`'s `forkServer host port` is reachable by anyone on
  the network unless bound to `"localhost"` or an equivalent; Warp's default
  `setHost` is `HostIPv4`, a wildcard. Bind admin, metrics, and debug listeners
  to `"127.0.0.1"` or an internal interface and authenticate them.
- Error bodies: Warp's `defaultOnExceptionResponse` sends generic 400/500
  responses; `exceptionResponseForDebug` returns the shown exception as a
  `text/plain` 500. Keep it out of release (`setOnExceptionResponse`), and do not
  render `show`/`displayException` output into response bodies; log it with a
  correlation id (03 §11).
- Test the artifact, not the flags: run the release binary with
  `+RTS -s -RTS`; it must abort unless open RTS options are intended.

## References

- https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/safe_haskell.html
- https://downloads.haskell.org/ghc/latest/docs/users_guide/exts/ffi.html
- https://hackage.haskell.org/package/process
- https://hackage.haskell.org/package/directory
- https://hackage.haskell.org/package/temporary
- https://hackage.haskell.org/package/http-client
- https://hackage.haskell.org/package/http-client-restricted
- https://hackage.haskell.org/package/regex-tdfa
- https://hackage.haskell.org/package/pcre-light
- https://hackage.haskell.org/package/base/docs/System-Timeout.html
- https://hackage.haskell.org/package/hint
- https://hackage.haskell.org/package/warp
- https://hackage.haskell.org/package/ekg
- https://downloads.haskell.org/ghc/latest/docs/users_guide/phases.html
- https://downloads.haskell.org/ghc/latest/docs/users_guide/runtime_control.html
- https://github.com/haskell/hackage-security
- https://github.com/haskell/security-advisories
- https://www.haskell.org/ghcup/about/#security

## Audit checklist

```bash
# Unsafe language/runtime boundaries: require a local written invariant
rg -n '\b(unsafePerformIO|unsafeDupablePerformIO|unsafeInterleaveIO|unsafeCoerce)\b' --glob '*.{hs,lhs}'
rg -n 'LANGUAGE.*(TemplateHaskell|Unsafe)|OPTIONS_GHC.*-fplugin|Trustworthy|Safe-Inferred' --glob '*.{hs,lhs}'

# Secret printed by value: derived Show on secret-bearing types, errors rendered with show
rg -n 'deriving.*Show' --glob '*.{hs,lhs}' | rg -i 'secret|token|password|apikey|credential'
rg -n '\bshow\b.*(SomeException|\be\b)|displayException' --glob '*.{hs,lhs}'

# Shell/argv and secret-bearing process surfaces
rg -n '\b(callCommand|readCreateProcess|createProcess|proc|shell|system|rawSystem)\b' --glob '*.{hs,lhs}'
rg -ni "(api[_-]?key|secret|password|token).*[=:].*['\"][^'\"]{8,}" --glob '*.{hs,lhs,cabal,project,yaml,yml,json}'

# Partial parsing, unbounded input, paths, archives, and temp files
rg -n '\b(read|head|tail|init|last|fromJust)\b|!!|hGetContents|readFile|decode|decompress|extract' --glob '*.{hs,lhs}'
rg -n 'canonicalizePath|normalise|makeRelative|isPrefixOf|\.\./|openTempFile|createDirectory|renameFile' --glob '*.{hs,lhs}'

# Temp files: reject fixed names, default-permission variants holding secrets, and paths without scoped cleanup
rg -n 'openTempFile|openBinaryTempFile|WithDefaultPermissions|openNewBinaryFile|createTempDirectory|withSystemTemp|withTempFile|getTemporaryDirectory|"/tmp' --glob '*.{hs,lhs}'

# Outbound requests (SSRF): trace every URL, host, and port to its origin; confirm the check runs at connect time
rg -n 'parseRequest|requestFromURI|parseUrl|httpLbs|httpNoBody|withResponse|newManager|defaultManagerSettings|tlsManagerSettings|redirectCount|managerRawConnection|managerTlsConnection|addressRestriction|managerSetProxy|defaultProxy' --glob '*.{hs,lhs}'
rg -n '\b(proc|shell|callCommand)\b[^\n]*\b(curl|wget)\b' --glob '*.{hs,lhs}'

# Regexes: each non-literal pattern needs an origin; each validation needs whole-text anchors; timeout is not a bound
rg -n 'Text\.Regex|regex-(tdfa|pcre)|pcre-light|\b(makeRegex|makeRegexM|compile|compileM|matchTest)\b|=~~?' --glob '*.{hs,lhs,cabal}'
rg -n 'newSyntax|multiline|dollar_endonly|dotall|\\A|\\z|\\`' --glob '*.{hs,lhs}'
rg -n '\btimeout\b' --glob '*.{hs,lhs}'

# Runtime code loading: every hit needs a trusted-source argument for the code, path, or name loaded
rg -n 'Language\.Haskell\.Interpreter|System\.Plugins|System\.Eval|System\.Posix\.DynamicLinker|\b(dlopen|dlsym)\b|dynamic-loader|build-depends:[^\n]*\b(hint|plugins|ghc)\b|foreign import ccall +"dynamic"|\b(fromDynamic|cast)\b' --glob '*.{hs,lhs,cabal}'

# Debug and profiling surface: open RTS options, trace calls, wildcard listeners, debug error bodies
rg -n -e '-rtsopts|-with-rtsopts|-debug|-prof\b|enable-profiling|profiling:|-eventlog|-fprof' . --glob '*.{cabal,project,yaml,yml,nix}' --glob '*ockerfile*' --glob 'Makefile'
rg -n '\bDebug\.Trace\b|\b(trace|traceShow|traceShowId|traceM|traceShowM|traceIO)\b|forkServer|System\.Remote\.Monitoring|setHost|exceptionResponseForDebug|setOnExceptionResponse|displayException' --glob '*.{hs,lhs}'

# FFI declarations and manual lifetime management
rg -n 'foreign (import|export)|ccall (unsafe|safe|interruptible)|StablePtr|newStablePtr|freeStablePtr|freeHaskellFunPtr' --glob '*.{hs,lhs,hsc,chs}'
rg -n 'ForeignPtr|newForeignPtr|addForeignPtrFinalizer|touchForeignPtr|withForeignPtr|CString|Ptr ' --glob '*.{hs,lhs,hsc,chs}'

# Build-time execution and supply-chain changes
rg -n 'build-type: *Custom|custom-setup|build-tool-depends|TemplateHaskell|-fplugin|c-sources|cxx-sources' . --glob '*.{cabal,hs,lhs,project}'
rg -n 'source-repository-package|repository |index-state|active-repositories|allow-newer|constraints' --glob 'cabal.project*'
cabal build all --dry-run
cabal outdated --freeze-file

# Dependency identity and insecure defaults: for every added package open its Hackage page (name, maintainer, repo, uploads, reverse dependencies) and `cabal get` its source
git diff -U0 -- '*.cabal' 'cabal.project*' | rg '^\+'
rg -n 'defaultManagerSettings|settingDisableCertificateValidation|TLSSettingsSimple|managerResponseTimeout|responseTimeout|setTimeout|setHost' --glob '*.{hs,lhs}'

# Release artifact: open RTS options must be rejected (abort) unless intended
"$RELEASE_BIN" +RTS -s -RTS
```

Grep hits are leads, not findings. Trace data origin, bounds, ownership,
compiler/build behavior, native contracts, and mitigations before assigning a
security issue; `safe` FFI, Safe Haskell, canonicalization, and argv APIs each
solve only a specific part of the threat model.
