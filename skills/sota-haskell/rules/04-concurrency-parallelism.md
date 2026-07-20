# 04 - Concurrency and Parallelism

Haskell's lightweight threads make concurrency cheap, not automatically safe.
Every thread needs an owner, every queue needs a bound, and every shared-state
protocol needs an invariant that survives exceptions and shutdown.

## 1. Give every thread structured ownership

Prefer `withAsync`, `concurrently`, `mapConcurrently`, and `race` from `async`
over detached `forkIO`. Their scopes make lifetime and failure behavior visible.

```haskell
-- BAD: the child outlives its caller; its exception is never observed.
startRefresh :: IO ()
startRefresh = do
  _ <- forkIO refreshForever
  pure ()

-- GOOD: leaving the scope cancels and waits for the child.
runService :: IO ()
runService =
  withAsync refreshForever $ \refresh -> do
    link refresh
    serve `finally` stopAccepting
```

- `withAsync action use` cancels the child when `use` exits, including when
  `use` throws. Its scope cleanup uses uninterruptible cancellation, so a child
  stuck in a blocking foreign call or uninterruptible cleanup can also stall the
  owner. Do not return the `Async` handle from its scope, and isolate work whose
  cancellation cannot be bounded.
- `concurrently left right` owns both actions: if either fails, the other is
  cancelled and the exception is propagated. Use it for a fixed pair.
- `race left right` returns the first result and cancels the loser. A race is
  cancellation, not rollback: the loser may already have written bytes or
  committed remote work.
- `mapConcurrently` is structured but not a concurrency limit. Over a large or
  attacker-controlled collection, use a bounded worker pool or `pooledMapConcurrentlyN`.
- If raw `forkIO` is unavoidable, record the `ThreadId`, report exceptions,
  define who stops it, and wait for completion. `forkFinally` helps report a
  result but does not itself provide ownership.

## 2. Understand wait, cancellation, and failure propagation

`async action` returns immediately. The child keeps running if its handle is
dropped.

- `wait` blocks and rethrows the child's exception in the waiting thread.
- `waitCatch` returns `Either SomeException a`; use it only where the owner can
  classify and report the failure. Do not silently discard `Left`.
- `poll` is an observation, not synchronization for a subsequent action.
- `cancel` sends `AsyncCancelled` and waits for the child to finish. It can
  therefore block if the child masks indefinitely or is stuck in a foreign
  call. Put a deadline around system shutdown rather than assuming cancellation
  is immediate.
- `cancelWith` injects a chosen exception; reserve it for protocols that truly
  need a typed cancellation reason.
- `link` propagates unexpected child failure to its owner and already excludes
  `AsyncCancelled`. Use `linkOnly` only when the protocol needs a different,
  explicit exception filter.

```haskell
-- BAD: neither success nor failure is observed.
void (async writeAuditBatch)

-- GOOD: ownership, failure observation, and cleanup are explicit.
withAsync writeAuditBatch $ \writer -> do
  result <- waitCatch writer
  either reportFailure (const (pure ())) result
```

Avoid broad `catch (\(_ :: SomeException) -> ...)`: it catches asynchronous
exceptions as well as ordinary failures and can accidentally defeat
cancellation. Catch the narrow synchronous exception type where possible; if a
boundary must catch `SomeException`, rethrow asynchronous exceptions or use a
well-reviewed exception policy.

## 3. Async exceptions, masking, and cleanup

An asynchronous exception may arrive at allocation, state transition, or most
blocking operations. Use `bracket`, `finally`, and `onException`; do not
hand-roll acquire/use/release sequences.

```haskell
-- BAD: cancellation between acquire and handler installation leaks the handle.
h <- openFile path ReadMode
consume h `finally` hClose h

-- GOOD: bracket masks acquisition/handler setup and always releases.
withFile path ReadMode consume
```

When implementing a resource combinator, prefer `bracket`, which masks resource
acquisition and handler setup but restores the caller's masking state for use:

```haskell
withLease :: Pool -> (Lease -> IO a) -> IO a
withLease pool = bracket (acquire pool) (release pool)
```

- `mask` defers delivery except at interruptible operations such as many waits.
  Masking is state inherited by child threads; avoid spawning while masked
  unless that is deliberate.
- `restore` returns to the caller's prior masking state, not necessarily
  `Unmasked`.
- `uninterruptibleMask` can make a process impossible to stop. Use it only for
  tiny, provably non-blocking operations; never around I/O, `takeMVar`, STM, or
  foreign calls.
- `throwTo` waits until the target receives the exception. It can block the
  sender and should not be used as an unbounded request/response mechanism.
- Cleanup must be idempotent where duplicate shutdown paths are possible, and
  it must not wait forever.

## 4. Keep invariants inside STM transactions

Use STM when correctness spans multiple pieces of shared state. Read and update
all related `TVar`s in one transaction; do not split a check from its write.

```haskell
-- BAD: another transaction can consume capacity between these transactions.
available <- atomically (readTVar slots)
when (available > 0) $
  atomically $ modifyTVar' slots (subtract 1)

-- GOOD: the invariant is checked and changed atomically.
claimSlot :: TVar Int -> STM ()
claimSlot slots = do
  available <- readTVar slots
  check (available > 0) -- equivalent to unless condition retry
  writeTVar slots (available - 1)
```

- `retry` abandons the transaction and sleeps until one of the `TVar`s it read
  changes. A transaction that calls `retry` before reading relevant state may
  never wake as intended.
- `orElse` tries its right branch only when the left retries, not when the left
  throws. Its read set affects wakeups; keep alternatives small and explicit.
- STM actions may run repeatedly. Do not perform I/O, generate externally
  visible IDs, or rely on evaluation side effects inside `STM`.
- `modifyTVar'` avoids accumulating lazy update thunks. Stored values can still
  hide unevaluated work; force expensive validation before entering the
  transaction when appropriate.
- Large transactions and high-contention `TVar`s repeatedly retry and waste
  work. Measure contention before consolidating or sharding state.

```haskell
readEither :: TQueue a -> TQueue b -> STM (Either a b)
readEither as bs =
  (Left <$> readTQueue as) `orElse` (Right <$> readTQueue bs)
```

`orElse` is left-biased when both branches can proceed. If fairness matters,
encode and test it rather than assuming scheduler fairness.

## 5. Bound queues and apply backpressure

Default to `TBQueue` with a capacity derived from memory budget and acceptable
queueing latency. `TQueue` and `Chan` are unbounded and can turn a slow consumer
into a memory-exhaustion failure.

```haskell
newtype Jobs a = Jobs (TBQueue a)

newJobs :: Natural -> STM (Jobs a)
newJobs capacity = Jobs <$> newTBQueue capacity

submit :: Jobs Job -> Job -> STM ()
submit (Jobs q) = writeTBQueue q -- retries while full: deliberate backpressure
```

- Choose whether producers block, reject, shed, or coalesce when full. Do not
  accidentally make an HTTP handler wait forever on `writeTBQueue`.
- Queue capacity is not a worker limit by itself; size and supervise the worker
  group explicitly.
- If jobs need replies, include a per-job `TMVar (Either Error Result)` and
  define behavior when the requester cancels before reading it.
- Closing is a protocol, not built into `TBQueue`. A sentinel is only safe when
  producer count and ordering are known; a separate shutdown `TVar` composed
  with `orElse` is often clearer.

## 6. Use MVar for narrow ownership protocols

`MVar` is useful for a one-place handoff or short mutable resource guard. It is
easy to build deadlocks and exception holes from several `MVar`s.

```haskell
-- BAD: exception after takeMVar permanently empties the lock.
state <- takeMVar stateVar
state' <- update state
putMVar stateVar state'

-- GOOD: modifyMVar restores the old value if update throws.
modifyMVar stateVar $ \state -> do
  state' <- update state
  pure (state', ())
```

- Prefer `withMVar`/`modifyMVar` over manual `takeMVar`/`putMVar` pairs.
- Do not hold an `MVar` while waiting for another lock, queue, network call, or
  child thread. If unavoidable, define one global lock order and test it.
- `readMVar` is not a snapshot tied to a later write. Use STM for check-then-act
  protocols or multiple variables.
- `tryTakeMVar` loops usually create polling, starvation, or a home-grown lock.
- No runtime detector proves absence of deadlock. Add time-bounded tests that
  force reverse ordering, cancellation, consumer failure, and queue saturation.

## 7. Separate concurrency from parallelism

Compile threaded code with `-threaded`; select capabilities deliberately:

```bash
cabal run service -- +RTS -N2 -s -RTS
cabal test all --test-options='+RTS -N2 -RTS'
```

`+RTS -N` uses all visible processors, which may increase GC overhead,
contention, and memory use. Containers can expose misleading CPU counts. Start
from a measured fixed `-N`, then compare throughput, latency, allocation, and
GC time.

Sparks (`par`, `parList`, `rpar`) are hints, not threads or guarantees. They can
fizzle because work was already evaluated, be garbage-collected, or create too
fine-grained overhead.

```haskell
-- BAD: one tiny spark per element, with unbounded granularity overhead.
sumSquares xs = sum (withStrategy (parList rpar) (map square xs))

-- BETTER: chunk substantial pure work; benchmark chunk size and strategy.
sumSquares xs =
  sum $ withStrategy (parListChunk 4096 rdeepseq) (map square xs)
```

Force the intended result, not merely a lazy spine. Use `pseq` or Strategies to
state evaluation order; do not infer it from source layout. Confirm spark
conversion and balance in an eventlog rather than claiming parallel speedup.

## 8. Graceful shutdown

Use one owner for service lifetime:

1. catch TERM/INT at the top level and signal shutdown through STM;
2. stop accepting and producing new work;
3. let workers drain or cancel them according to the delivery contract;
4. wait for owned `Async`s with a bounded deadline;
5. flush durable state and observability output;
6. report incomplete work and exit with the appropriate status.

Signal handlers should only notify the coordinator. Shutdown must be
idempotent, tolerate a second signal, and have an escalation path for masked,
foreign, or otherwise stuck work. Test idle shutdown, shutdown under load,
worker failure, full queues, and cancellation during resource acquisition.

## References

- https://hackage.haskell.org/package/async
- https://hackage.haskell.org/package/stm
- https://hackage.haskell.org/package/base/docs/Control-Exception.html
- https://hackage.haskell.org/package/parallel
- https://downloads.haskell.org/ghc/latest/docs/users_guide/using-concurrent.html

## Audit checklist

```bash
# Detached threads and ownership: trace every lifetime and exception path
rg -n '\b(forkIO|forkOn|forkFinally|async|withAsync|concurrently|race|link)\b' --glob '*.{hs,lhs}'
rg -n '\b(wait|waitCatch|poll|cancel|cancelWith|throwTo|killThread)\b' --glob '*.{hs,lhs}'

# Exception safety and masking: inspect acquire/use/release boundaries
rg -n '\b(mask|mask_|uninterruptibleMask|restore|bracket|finally|onException|catch)\b' --glob '*.{hs,lhs}'
rg -n 'SomeException|AsyncException|AsyncCancelled' --glob '*.{hs,lhs}'

# Shared state, bounds, and possible blocking cycles
rg -n '\b(TVar|TMVar|TQueue|TBQueue|MVar|Chan|retry|orElse|atomically)\b' --glob '*.{hs,lhs}'
rg -n '\b(takeMVar|putMVar|readMVar|tryTakeMVar|newTQueue|newChan|mapConcurrently)\b' --glob '*.{hs,lhs}'

# Parallel runtime and sparks; confirm behavior with eventlog/profile evidence
rg -n '(-threaded|with-rtsopts|\+RTS|-N[0-9]*|parList|parListChunk|rpar|rdeepseq|pseq)' . --glob '*.{cabal,project,hs,lhs,yaml,yml}'
```

Grep hits are leads, not findings. A raw `forkIO`, unbounded queue, mask, or
`MVar` may be correct only after its owner, exception behavior, capacity,
blocking graph, and shutdown path are established from surrounding code.
