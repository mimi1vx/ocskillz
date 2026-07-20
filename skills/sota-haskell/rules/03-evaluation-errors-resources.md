# 03 - Evaluation, Errors, and Resources

Haskell separates demand from source order. That power affects memory,
termination, exception timing, and resource lifetime. Make evaluation boundaries
intentional, model expected failure in results, and acquire resources only
inside exception-safe scopes.

## 1. Reason in demand, WHNF, and normal form

Evaluating a value to weak-head normal form (WHNF) reveals only its outer
constructor. It does not recursively evaluate fields:

```haskell
value = Just (expensiveComputation input)

-- Forces Just, not expensiveComputation.
evaluate value

-- Forces all fields when a lawful NFData instance exists.
evaluate (force value)
```

- Source binding order is not evaluation order. A `let` does not run work; a
  consumer creates demand.
- Pattern matching forces enough to choose a constructor. Matching `Just x`
  need not force `x`.
- `seq` forces its first argument only to WHNF. `deepseq` uses `NFData` and may
  traverse far more data than intended.
- Exceptions in pure thunks are raised where the thunk is evaluated, possibly
  far from construction and on another thread.
- Bottom includes explicit errors, failed patterns, nontermination, and some
  exceptional computations. A type alone does not prove termination.

## 2. Apply strictness at ownership boundaries

Laziness supports producer/consumer composition and finite-memory streaming.
Uncontrolled laziness accumulates thunks or retains inputs. Strictness is a
specific evaluation policy, not a global quality setting.

```haskell
-- BAD: a large chain of (+) thunks can accumulate.
total = foldl (+) 0 values

-- GOOD for a finite collection and strict numeric accumulator.
total = foldl' (+) 0 values
```

- Use `foldl'`, strict fields, `BangPatterns`, `modifyIORef'`, and `modifyTVar'`
  where the accumulator/state owner requires evaluated state.
- A bang or `seq` reaches WHNF only. `!(Maybe Large)` forces `Just`, not `Large`.
- `StrictData` changes field defaults for a whole module and can alter
  termination, exception timing, and streaming. Do not enable it as folklore.
- Force work before publishing it into shared state when consumers should not
  inherit unpredictable latency or exceptions. Choose WHNF or NF deliberately.
- Do not force an infinite structure or entire stream. Strictness can convert a
  bounded pipeline into nontermination or unbounded memory use.

## 3. Diagnose space leaks from retention evidence

A space leak is live data retained longer than needed, not simply high
allocation. Common causes include lazy accumulators, closures capturing large
inputs, holding a list head while traversing its tail, unevaluated state updates,
lazy I/O, unbounded caches, and slices retaining large backing buffers.

```haskell
-- BAD: closure can retain the complete request while queued.
enqueue $ \_ -> writeAudit (renderRequest request)

-- BETTER: compute/copy the small owned value before enqueueing.
let !auditLine = renderAuditFields request
enqueue $ \_ -> writeAudit auditLine
```

- Start with `+RTS -s`; compare allocation, maximum residency, copied bytes, and
  GC productivity under representative load.
- Use heap/retainer profiles to establish what remains reachable and why. Do not
  sprinkle bangs until one benchmark happens to improve.
- Copy a small `ByteString` slice when it would otherwise retain a very large
  buffer for a long lifetime; copying every slice can be worse.
- Bound caches and queues. Strict values in an unbounded container still exhaust
  memory.
- Recheck semantics after changing demand: termination and which exception wins
  can change even when successful outputs match.

## 4. Eliminate partiality at ordinary boundaries

Partial functions turn expected input cases into process exceptions:

```haskell
-- BAD: malformed input throws ErrorCall.
port = read input :: Int

-- GOOD: parsing failure is explicit and range validation follows parsing.
parsePort :: Text -> Either PortError Port
parsePort input = do
  value <- first InvalidDecimal (decimal input)
  mkPort value
```

- Replace `head`/`last` with pattern matching or `NonEmpty`, indexing with safe
  lookup, `read` with a parser, and `fromJust` with explicit branching.
- Compile with warnings for incomplete patterns and record updates. Treat
  exhausted ADT cases as part of API evolution.
- An internal partial helper is acceptable only when its precondition is proven
  immediately by nearby code and cannot be invalidated by later refactoring;
  prefer encoding the proof in a type.
- Never use `error` for malformed network, file, database, or user input.
- Avoid `fail` as an application error channel. In parser/monadic APIs where it
  is conventional, understand the concrete `MonadFail` behavior.

## 5. Use Maybe, Either, and exceptions for distinct jobs

Use `Maybe` when one unsurprising absence needs no diagnostic. Use
`Either DomainError a` for expected failures callers should inspect. Use
exceptions in `IO` for exceptional environmental failure, cancellation, and
interfaces that conventionally throw.

```haskell
data CreateUserError
  = InvalidName NameError
  | EmailAlreadyUsed
  | StorageUnavailable StorageError

createUser :: NewUser -> ExceptT CreateUserError IO User
```

- Prefer a small domain error ADT over `Either Text a`; constructors permit
  exhaustive handling while rendering can remain at the presentation boundary.
- Do not expose database-driver or HTTP-client exception types as stable domain
  API accidentally. Translate where ownership changes.
- `ExceptT` makes ordinary failure explicit but does not catch `IO` exceptions.
  Resource errors and asynchronous cancellation still require exception-safe IO.
- Preserve useful context when translating errors, without logging secrets or
  collapsing every cause into one undiagnosable message.
- Do not use exceptions as routine loop control or catch errors solely to return
  a magic default.

## 6. Distinguish synchronous and asynchronous exceptions

Synchronous exceptions arise from the current action, such as file-open failure.
Asynchronous exceptions are delivered from another thread or the runtime, such
as cancellation. Catching `SomeException` catches both.

```haskell
-- BAD: swallows cancellation and can prevent shutdown.
forever $ processOne `catch` \(_ :: SomeException) -> pure ()

-- GOOD: catch the expected operation-specific failure.
processOne `catch` \(err :: IOException) -> reportIoFailure err
```

- Catch the narrowest exception type at the boundary that can recover.
- If a top-level boundary catches `SomeException` to log, preserve/rethrow
  asynchronous exceptions according to an explicit policy. Do not resume normal
  work after arbitrary corruption-like failures.
- `try` is `catch` in result form; `try @SomeException` has the same cancellation
  hazard as broad `catch`.
- Pure exceptions forced within `IO` are still synchronous exceptions, but
  laziness makes their location surprising. Use `evaluate` at a deliberate
  boundary when the exception must be attributed there.
- `throwIO` sequences exception raising in `IO`; prefer it to `throw` for IO
  control flow. Typed ordinary failures are still preferable where expected.

## 7. Acquire, use, and release with bracket

Manual acquire/use/release has exception windows. Use `bracket`, `bracketOnError`,
`finally`, `onException`, or a library's `withX` combinator:

```haskell
-- BAD: open failure aside, any exception before close leaks the handle.
h <- openFile path ReadMode
result <- consume h
hClose h
pure result

-- GOOD: release runs on success, synchronous failure, or cancellation.
withFile path ReadMode consume

withConnection :: Pool -> (Connection -> IO a) -> IO a
withConnection pool = bracket (acquire pool) (release pool)
```

`bracket` masks asynchronous exceptions while acquiring and installing cleanup,
restores the caller's previous masking state during use, and masks cleanup.
Cleanup can still block at interruptible operations and can itself fail.

- Release must tolerate partially failed use and should be idempotent when
  independent shutdown paths can converge.
- Decide what to do if both use and cleanup fail; avoid silently losing the
  primary failure or cleanup evidence.
- Do not return a handle, pointer, lazy stream, or callback whose validity ends
  with the `withX` scope.
- Finalizers are nondeterministic backstops, not prompt resource management.

## 8. Mask only to protect small state transitions

Use `mask` when implementing a resource or concurrency primitive that must make
an acquisition and handler installation atomic with respect to async exceptions.
Most application code should use existing bracketed combinators instead.

```haskell
withRegistered registry action = mask $ \restore -> do
  token <- register registry
  restore (action token) `finally` unregister registry token
```

- `restore` restores the caller's previous masking state, not always `Unmasked`.
- Masking state is inherited by child threads. Avoid spawning while masked unless
  the child contract requires it.
- Masked code can receive async exceptions at interruptible operations.
- `uninterruptibleMask` can make shutdown hang forever. Never wrap network I/O,
  foreign calls, STM waits, `takeMVar`, or other potentially blocking actions.
- Keep masked sections allocation-light, short, and auditable.

## 9. Stream resources explicitly

Lazy `readFile`, `hGetContents`, lazy `ByteString` I/O, and
`unsafeInterleaveIO` tie handle lifetime and I/O exceptions to later demand.
They can be suitable in tightly controlled whole-file scripts, but they are a
poor default for services and reusable APIs.

```haskell
-- BAD: returned contents may still depend on a closed handle.
load path = withFile path ReadMode hGetContents

-- GOOD for a known-small, bounded file: consume strictly in scope.
loadSmall path = withFile path ReadMode $ \h -> do
  bytes <- BS.hGet h maxBytes
  ensureEofOrReject h bytes
```

For large or unbounded data, use a maintained streaming library already present
in the project, such as `conduit`, `pipes`, or `streaming`, and keep acquisition
inside the stream's resource scope.

- Define byte/item/time limits and backpressure. Streaming syntax does not make
  an unbounded sink, queue, `toList`, or `sinkList` safe.
- Ensure early consumer termination releases upstream handles and connections.
- Specify whether producer, transformer, or consumer owns and reports errors.
- Do not return a lazy value that captures a database cursor or response body
  after its bracket closes.
- Test normal exhaustion, early stop, parser failure, cancellation, and slow
  consumers.

## 10. Use Text for text and ByteString for bytes

`Text` is Unicode text. `ByteString` is an octet sequence. Keep protocol bytes
as bytes until a specified encoding boundary, then decode explicitly.

```haskell
decodeName :: ByteString -> Either UnicodeException Text
decodeName = decodeUtf8'

encodeName :: Text -> ByteString
encodeName = encodeUtf8
```

- Avoid `String` in data-heavy production paths unless ecosystem API or small
  scale makes it appropriate; linked lists of characters are allocation-heavy.
- Use strict `Text`/`ByteString` for bounded payloads. Lazy variants are chunked
  representations, not memory or input limits.
- Choose strict decoding (`decodeUtf8'`) for untrusted bytes unless replacement
  behavior is explicitly part of the protocol. Do not silently corrupt invalid
  input with lenient decoding.
- Use builders for large output assembled from many pieces; repeated `(<>)` may
  retain or copy unexpectedly depending on representation and association.
- Beware slices retaining large backing storage and repeated encode/decode at
  layer boundaries. Measure before copying or changing representation.
- File paths are platform strings, not necessarily Unicode text or protocol
  bytes. Preserve the platform/API representation rather than round-tripping
  through an assumed UTF-8 encoding.

## 11. Make top-level failure and shutdown policy explicit

At executable boundaries, classify domain failure, expected operational error,
programmer defect, and cancellation. Emit actionable diagnostics, select a
meaningful exit status, and release owned resources before exit.

- Do not catch everything around `main` and return success.
- Avoid printing raw exception values when they may contain credentials, paths,
  queries, or personal data; render a safe diagnostic with correlation context.
- Let supervised child failure reach the owner. Detached exceptions must not
  disappear silently.
- Give shutdown a bounded deadline and escalation path; cleanup that waits
  forever is not graceful.
- Test failures during acquisition, use, forced evaluation, cleanup, streaming
  early termination, and cancellation.

## References

- https://downloads.haskell.org/ghc/latest/docs/users_guide/using-optimisation.html#strictness
- https://downloads.haskell.org/ghc/latest/docs/users_guide/runtime_control.html
- https://hackage.haskell.org/package/base/docs/Control-Exception.html
- https://hackage.haskell.org/package/deepseq
- https://hackage.haskell.org/package/text
- https://hackage.haskell.org/package/bytestring
- https://hackage.haskell.org/package/conduit
- https://hackage.haskell.org/package/pipes
- https://hackage.haskell.org/package/streaming

## Audit checklist

```bash
# Partiality and incomplete matching
rg -n '\b(head|tail|init|last|read|fromJust|fromRight|fromLeft|maximum|minimum)\b|!!|\berror\b|undefined' --glob '*.{hs,lhs}'
rg -n 'IncompletePatterns|-Wno-incomplete|MonadFail|\bfail\b' --glob '*.{hs,lhs,cabal,project}'

# Evaluation, strictness, and retention leads
rg -n '\b(foldl|foldl\x27|seq|deepseq|force|evaluate|rnf)\b|BangPatterns|StrictData|modify(IORef|TVar)\x27?' --glob '*.{hs,lhs}'
rg -n 'hGetContents|unsafeInterleaveIO|lazy|toList|sinkList|cache|memo|ByteString.*(drop|take)' --glob '*.{hs,lhs}'

# Exception breadth, masking, and resource scopes
rg -n '\b(catch|catches|try|handle|throw|throwIO|SomeException|AsyncException)\b' --glob '*.{hs,lhs}'
rg -n '\b(bracket|bracketOnError|finally|onException|mask|mask_|uninterruptibleMask|withFile|openFile|hClose)\b' --glob '*.{hs,lhs}'

# Text/bytes conversion and explicit streaming bounds
rg -n '\b(String|Text|ByteString|Lazy\.Text|Lazy\.ByteString|encodeUtf8|decodeUtf8|decodeUtf8With|Builder)\b' --glob '*.{hs,lhs}'
rg -n '(Conduit|Pipes|Streaming|sourceFile|sinkFile|responseBody|maxBytes|limit|timeout)' --glob '*.{hs,lhs}'

# Reproduce memory behavior with representative input before changing demand
cabal build all
cabal test all --test-show-details=direct
```

Grep hits are leads, not findings. Trace demand, ownership, exception type,
masking state, resource scope, stream termination, and input bounds in context.
A bang, lazy value, broad catch, or strict bytestring may be correct; require an
observable failure mode or violated contract before changing evaluation or error
behavior.
