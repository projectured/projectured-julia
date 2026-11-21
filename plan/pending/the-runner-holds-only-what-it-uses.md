# The runner holds only what it uses

> **Status (2026-11-21): in progress.** The owner, after the land of the plan agents-work-fast:
> "Let's work on the other recommended points first", and "don't notify the other agents yet".

## 1. The purpose

The plan agents-work-fast made the cycle of a warm session take 12 s to 30 s. Its run found
three costs that stay:

- A job of `bounded-run` holds its whole cap, also when its workers use less. The budget of
  the other jobs counts the cap, so they wait: two jobs used 9 GB of their caps of 38 GB, and
  each new job waited, even a small one.
- The first edit of a session took 786 s to 841 s, because the session starts most of its
  workers at that edit, and each new worker compiles the images that the edit made stale.
- A change of the supervisor compiled every test package again, about 10 minutes in each
  depot, because `ProjecturedKernelTest` includes the file of the supervisor.

## 2. Decisions

Each decision is proposed by the assistant. The owner approved the points with the words of the
status above.

- **R1. `bounded-run shrink NAME SIZE` lowers the cap of a running job** (proposed by the
  assistant). The new cap stays at least 512 MiB above the memory that the job uses, so the
  kernel does not reclaim or end a process at once. `grow` stays the command that raises a cap.
- **R2. The runner gives back the memory that it does not need** (proposed by the assistant).
  When a worker ends and no queued part waits, and after each request of a session, the runner
  lowers the cap of its job to the memory of its live workers and 1 GiB for the supervisor.
- **R3. A session starts its workers before the first edit** (proposed by the assistant).
  After each request, the session starts more workers of each package of the request, up to
  the count of its workers, when their memory fits. So the next edit finds them warm. Each
  warm worker holds about 3 GB; R2 gives back the memory of a worker that ends.
- **R4. The supervisor is not part of `ProjecturedKernelTest`** (proposed by the assistant). The
  package keeps the worker, the suite runner, the map and the choice of the parts. The
  supervisor file is included only by `tool/run-tests.jl` (and by the one of omnet-julia) and by
  the test of the supervisor, which includes it at run time into a module of its own. The
  package no longer exports the names of the supervisor; no release of the package had them.

## 3. Steps

Do the work in the worktree `projectured-julia-runner-memory`. Make one commit for each step.

- [ ] 1. **The supervisor leaves the package (R4).** **Done when:** the test of the supervisor
  passes, and a change of `TestSupervisor.jl` compiles no package in the worktree.
- [x] 2. **`bounded-run shrink` (R1).** **Done when:** its selftest passes.
- [ ] 3. **The runner gives memory back (R2).** **Done when:** a test of the supervisor shows a
  lower cap after a worker ends, and a run of all parts gives back its memory at its end.
- [ ] 4. **The session starts its workers (R3).** **Done when:** the first edit of a session
  takes about as long as a later one, measured as in agents-work-fast step 5.
- [ ] 5. **The land.** Run all parts, land, update the seed.

## 4. What the work found

- **Step 2 (2026-11-21).** `bounded-run shrink` lowers the cap with `systemctl set-property
  MemoryMax`, as `grow` raises it. Its selftest passes, with two new checks: a shrink to a size
  above the use, and a shrink that the use stops 512 MiB above it.
