# 04 - Concurrency, Async I/O, and Processes

Perl offers processes, event loops, futures/promises, and interpreter threads.
Choose one model from workload and framework constraints, then make every
operation's lifetime and cancellation behavior explicit.

## 1. Choose the model deliberately

| Workload | Default direction |
|---|---|
| Isolated CPU work or unsafe native libraries on Unix | supervised worker processes |
| Many sockets/timers/subprocesses in a general service | IO::Async plus Future, if no loop exists |
| Mojolicious application | Mojo::IOLoop and Mojo::Promise |
| Loop-neutral library API | Future::IO or explicit adapter contract |
| Shared-memory threads | avoid by default; justify and test ithreads/XS compatibility |

Perl ithreads clone interpreters, use substantial memory, and complicate shared
state and XS safety. They are not lightweight threads. Preserve a proven
threaded architecture, but do not introduce one merely for parallelism.

Do not mix event loops without a maintained integration layer. The application,
not a low-level library, chooses and starts the loop.

## 2. Fork ownership and child reaping

Every `fork` has exactly one owner responsible for:

- handling fork failure;
- closing pipe/socket ends unused by parent and child;
- recording the PID and expected lifecycle;
- collecting exit status with `waitpid`;
- TERM, deadline, and optional KILL escalation;
- cleanup when parent shutdown begins.

```perl
use POSIX qw(_exit);

my $pid = fork();
die "fork failed: $!" unless defined $pid;

if ($pid == 0) {
    exec {$program} $program, '--', @args;
    warn "exec failed: $!";
    _exit(127);  # Do not run inherited END blocks in the child.
}

waitpid $pid, 0;
my $status = $?;
```

- Never let children fall through into parent control flow. After a failed
  `exec`, report minimally and use `POSIX::_exit` so inherited `END` blocks and
  destructors do not run in the child.
- After fork, close inherited database connections, sockets, and event-loop
  watchers not owned by that process; reconnect where required.
- Avoid fork from a multithreaded process unless the entire native stack is
  designed for it.
- PID reuse makes long-lived bare PID files unsafe; combine process ownership,
  lock/descriptor state, and startup identity.

## 3. Pipes and subprocess I/O

Use argv/list forms and close every unused descriptor immediately. If reading
stdout and stderr concurrently, drain both or use a maintained IPC abstraction;
sequential reads can deadlock when one pipe fills.

- Bound captured output; a child can otherwise exhaust parent memory.
- Check launch, write, `close`, signal termination, core dump, and exit code.
- Handle SIGPIPE or failed writes when the child closes input early.
- Prefer streaming over reading an unbounded command result into one scalar.
- Use process groups when shutdown must include grandchildren.

## 4. Signals

Perl signals are deferred to safe interpreter points. Keep handlers minimal:
set state, notify a loop, or initiate orderly shutdown.

- A long-running regex/opcode can delay signal handling.
- Loop `waitpid(-1, WNOHANG)` for SIGCHLD; multiple child exits can collapse
  into one signal notification.
- Preserve `$!` and `$?` in handlers.
- Do not perform complex I/O on the same handle whose operation was
  interrupted.
- Let the selected event loop own signal watchers where possible.
- SIGKILL cannot be caught; correctness cannot depend on cleanup handlers.

## 5. Structured ownership with Future

An async operation is not fire-and-forget by default. Retain its Future or
Promise, observe failure, and attach it to a request, task group, worker, or
service lifetime.

- Propagate failures to an owner that can decide retry or response.
- Keep concurrency bounded with a queue/semaphore/pool.
- Backpressure producers rather than buffering indefinitely.
- Preserve ordering only when the contract requires it; avoid accidental
  head-of-line blocking.
- Use the framework's combinators rather than hand-maintaining counters and
  completion callbacks.
- Debug unobserved futures/promises with framework diagnostics in tests.

## 6. Timeouts and cancellation

A timeout is a policy deadline, not rollback. Race the operation against a
timer, cancel the loser where supported, and define what happened to partial
work.

- Cancellation is cooperative and may arrive after bytes were transferred or
  remote work committed.
- After timed-out partial protocol I/O, close/discard the connection unless the
  protocol and library prove it remains synchronized.
- Promise rejection does not necessarily cancel underlying work; document the
  distinction.
- Propagate cancellation to child operations and release queue/pool capacity.
- Use monotonic time for deadlines.
- Avoid process-wide `alarm` in event-loop or reusable library code. If legacy
  blocking code requires it, localize SIGALRM, use a unique exception, clear
  the alarm on every path, and rethrow unrelated errors.

## 7. Graceful shutdown

On TERM/INT:

1. stop accepting new work;
2. signal cancellation or close producer queues;
3. allow in-flight work a bounded grace period;
4. close listeners and flush bounded critical output;
5. terminate and reap workers;
6. exit nonzero if invariants or durable delivery failed.

Shutdown must be idempotent: duplicate signals and failures during shutdown are
normal. Do not wait forever for a stuck child or Future.

## 8. Shared state and database handles

- Process workers do not share ordinary memory after fork; use explicit IPC or
  durable stores.
- Do not share DBI handles across fork. Connect per process and understand
  driver-specific async/fork behavior.
- In event loops, blocking DBI, DNS, filesystem, or CPU work stalls all tasks.
  Move it to bounded workers or select an async-aware integration.
- Caches need ownership, synchronization, bounds, and fork invalidation.
- Keep lock hold times short and never await an unrelated event while holding
  a logical lock.

## 9. Testing concurrent code

Test lifecycle behavior, not sleeps:

- child success, nonzero exit, signal death, exec failure, and timeout;
- both stdout/stderr producing enough data to fill buffers;
- cancellation before start, during I/O, and after remote commit;
- bounded fan-out and queue saturation;
- TERM during idle and active work;
- descriptor/child cleanup and no zombies;
- deterministic fake clocks or loop timers where supported.

Run with framework diagnostics such as `PERL_FUTURE_DEBUG=1` or
`MOJO_PROMISE_DEBUG=1` in focused tests where available.

## Audit checklist

```bash
# Process and command surfaces
rg -n '\bfork\b|\bwait(pid)?\b|\bexec\b|\bsystem\b|IPC::Open[23]|open\s+.*[|]-' --glob '*.{pl,pm,t}'
rg -n '\$SIG\{|SIGCHLD|WNOHANG|\balarm\b|kill\s' --glob '*.{pl,pm,t}'

# Async stacks and accidental loop mixing
rg -n 'IO::Async|Future(::IO)?|Mojo::(IOLoop|Promise)|AnyEvent|EV\b|POE\b' --glob '*.{pl,pm,t}' cpanfile
rg -n '->(get|await|wait)\b|run\b|loop_forever|start\b' --glob '*.{pl,pm,t}'

# Ownership, deadlines, cancellation, and bounds
rg -n 'cancel|timeout|deadline|Semaphore|Queue|concurrent|in_flight|max_' --glob '*.{pl,pm,t}'
rg -n 'Future->new|Mojo::Promise->new|then\s*\(' --glob '*.{pl,pm,t}'

# Blocking work inside event-driven code: inspect surrounding call graph
rg -n 'DBI->connect|->execute\b|sleep\s|readline|glob\b|system\b|`[^`]+`|qx[/({]' --glob '*.{pl,pm,t}'

# Thread usage requires explicit justification and platform/XS tests
rg -n 'use threads|threads::shared|lock\s*\(' --glob '*.{pl,pm,t}' cpanfile
```

Each match requires lifecycle analysis. The presence of `fork`, blocking DBI,
or multiple async dependencies is not itself a defect.

## References

- https://perldoc.perl.org/perlipc
- https://perldoc.perl.org/threads
- https://metacpan.org/pod/IO::Async
- https://metacpan.org/pod/Future
- https://metacpan.org/pod/Future::IO
- https://docs.mojolicious.org/Mojo/Promise
