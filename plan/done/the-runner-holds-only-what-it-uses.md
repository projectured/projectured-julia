# The runner holds only what it uses

> **Status (2026-11-21): done.** The owner, after the land of the plan agents-work-fast:
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
- **R5. R3 and the compile in the background (A10 of agents-work-fast) go** (proposed by the
  assistant after the measure of step 4, approved by the owner on 2026-11-21: "Agreed"). The
  first run of a part compiles 170-230 s in any fresh worker, so a worker that starts early does
  not make the first edit fast, and it holds about 6 GB of the budget while it waits. The
  compile in the background built images of edits that were taken back, and a later load took
  603 s. Only a compiled test image removes the cost: agents-work-fast step 4.
- **R4. The supervisor is not part of `ProjecturedKernelTest`** (proposed by the assistant). The
  package keeps the worker, the suite runner, the map and the choice of the parts. The
  supervisor file is included only by `tool/run-tests.jl` (and by the one of omnet-julia) and by
  the test of the supervisor, which includes it at run time into a module of its own. The
  package no longer exports the names of the supervisor; no release of the package had them.

## 3. Steps

Do the work in the worktree `projectured-julia-runner-memory`. Make one commit for each step.

- [x] 1. **The supervisor leaves the package (R4).** **Done when:** the test of the supervisor
  passes, and a change of `TestSupervisor.jl` compiles no package in the worktree.
- [x] 2. **`bounded-run shrink` (R1).** **Done when:** its selftest passes.
- [x] 3. **The runner gives memory back (R2).** **Done when:** a test of the supervisor shows a
  lower cap after a worker ends, and a run of all parts gives back its memory at its end.
- [x] 4. **The session starts its workers (R3).** Measured, then removed with the compile in the
  background (R5): the first edit stays slow, because of the first run of each part.
- [x] 5. **The land.** Run all parts, land, update the seed.

## 4. What the work found

- **Step 2 (2026-11-21).** `bounded-run shrink` lowers the cap with `systemctl set-property
  MemoryMax`, as `grow` raises it. Its selftest passes, with two new checks: a shrink to a size
  above the use, and a shrink that the use stops 512 MiB above it.
- **Step 1.** `Module(:SupervisorTests)` has no `include` of its own, and the supervisor file
  includes its two shared files, so the part defines one. The supervisors inside the test saw
  the name of the real job and grew it from 8 GB to 11 GB; the part now hides the job from them.
  After the step, a change of `TestSupervisor.jl` loaded `ProjecturedKernelTest` in 0.0 s.
- **Step 3.** The runner lowers its cap at the top of its loop, when no queued part waits and
  the memory of its live workers changed: to that memory and 1 GiB, in steps of 512 MiB, and
  only when the cap is 1 GiB or more above. The run of the test of the supervisor ended with
  its job at a cap of 1.0 GB, from 8 GB.
- **Step 4, the measure (2026-11-21).** After the warm-up request (26 s), the session started 3
  more workers of `ProjecturedTest` and grew its job from 7 GB to 25 GB. The first edit still
  took 861 s: the request came while the new workers loaded, and the three integration parts
  then compiled 176-230 s each. A second edit took 13.3 s. The same six parts in fresh workers
  of their package, with no session and no Revise, compiled just as long (172-235 s), so the
  cost is the first run of a part in a fresh worker, and a worker that starts early does not
  remove it; only a compiled test image (agents-work-fast step 4) does. In the land run these
  parts compiled 14-72 s because earlier parts in the same worker had compiled the shared code.
- **The compile in the background (A10) costs more than it gives.** After requests B and C, it
  compiled the images of the two edits; when the edit was taken back, they were stale, and the
  first worker of the next run loaded `ProjecturedTest` in 603 s, where it took 26 s before. An
  image of the state after a request helps only a worker that starts before the next edit, and
  a session starts few workers.
- **Step 5.** The run of all 765 parts on the branch is green, 1 h 08 min on 10 cores, with
  `--memory-from auto` from the stored record of `main`. In its tail the job gave back its
  memory in six steps, from 31.0 GB to 6.0 GB. The fast parts of omnet-julia against the branch
  are green, 265 parts in 52 minutes; their run needed a resolve of the manifest of the omnet
  main checkout, which was older than the landed dependencies of four test packages.
