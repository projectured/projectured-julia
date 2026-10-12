# The first turn of an agent starts fast, and says that it starts

> **Status:** done (landed 2026-10-12, the owner: "works well, land it"); ClaudeCodeACP 0.1.8 is landed in its clone and waits for its push and its registration

## Goal

The owner ran `bin/projectured --assistant=acp`, sent a prompt, and saw nothing
for more than a minute. The session of Claude Code shows why: the agent got the
prompt at once, but the two MCP servers in the editor process (the tools of the
editor and the permission tool of ClaudeCodeACP) did not answer within the 30 s
that `claude` gives them, so the agent ran without them, and its answer came
when the owner closed the editor. The first use of the code of the agent
compiles on the thread of the editor, which the HTTP servers share, and the
machine had a load of 50 to 60.

## Steps

- ~~1. A precompile workload covers the path of the first turn of an agent.~~
  Dropped: the cause was not the compilation (see below).
- [x] 2. ClaudeCodeACP 0.1.8 starts `claude` with `MCP_TIMEOUT=120000` unless the
  environment sets it (290f793; 165 tests pass), landed in the clone, not pushed.
- [x] 4. The tasks of the thread of the editor get their share while the loop
  animates (the owner: option 1, "sounds good", 2026-10-12), and an animation
  draws at most 30 frames a second ("can we aim for 30 frame per second at most
  for animation and react to events as fast as today?"):
  - `FRAME_INTERVAL` is 1/30 s.
  - A wait of at most 0.1 s (an animation, or a feed or a timer due soon) waits
    in Julia: it checks the queue of SDL without blocking, and sleeps 1 ms
    (`STEP`) between the checks, so the tasks and their I/O run in the gap; the
    first step comes also when the frame took longer than its interval, so the
    tasks get at least 1 ms after each frame. An input event ends the wait within
    1 ms.
  - A longer wait (idle) blocks in SDL as before, in slices of 10 ms with any
    number of threads (was 100 ms with more than one thread), so an input event
    wakes it at once.
  - A wake from a task (timeout 0) sleeps 1 ms in place of the bare `yield()`.
  - Input that the backend owes still skips the wait.
  Done in a336b87a9. `compute_wait_timeout` answers the whole interval after
  each frame, so the tasks get the whole 33 ms of each gap and no extra share
  after a heavy frame is needed. Tests: `test_kernel` 4374 (2 broken),
  `test_sdl_wait_wake` with two new tests (a short wait gives a task of the
  thread more than 100 turns in 50 ms; a queued event ends a short wait at
  once). Without a window, frames are cheap, and the start with the Assistants
  tab open takes 26 s on main and 25 s on the branch: the gain needs the costly
  frames of a large real window, which the owner tries.
  The owner's try showed a hole: with the Assistants tab open, not even the line
  "Starting Claude Code…" came. A check with the list linked to the window
  (`link_assistant_list!`, which an earlier check left out, so its table was
  empty) showed why: each animated frame changes the display, so it queues a
  `DisplayUpdate`, and `wait_for_input` returned at once for it, with no wait
  and no yield. The loop drew about 56 frames a second, and even the timers of
  the other thread stalled. Now that read comes within one frame of an animation
  (1/30 s) and not at once; owed input still skips the wait. The same check then
  answered 20 s after the submit, at about 28 frames a second. SDL tests 265 of
  272 with the dummy driver, the 7 failures all `PointerShapeTest.jl:64` (no
  system cursors in the dummy driver), which passes 27 of 27 on the display.
- [x] 3. The transcript says "Starting Claude Code…" while the session opens
  (a48fafca1): the turn shows at once with that part, leaves the conversation
  when the session is open, and comes back after the prompt, so a message that
  the person sends meanwhile stays above the answer; a start that fails leaves
  no turn. `test_external_agent_turn` 269 of 269.

## The cause, found 2026-10-12

The owner's second try took four minutes to start `claude`, with the machine
idle, and became fast at once when the owner closed the Assistants tab. The
elapsed column of that table reads the frame clock of the editor while a turn
runs, and `compute_wait_timeout` answers `FRAME_INTERVAL` (0.01 s) while any
cell depends on that clock, so the window redraws without a pause for the whole
turn. The tasks of the agent (the ACP connection, the readers of `claude`, and
the HTTP servers, which HTTP.jl starts in the interactive pool, the thread of
the editor) get only the gaps between those frames. More threads do not help:
with more than one thread the SDL backend waits in 100 ms slices, and the start
took 80 s instead of 37 s.

So step 1 aims at a cause that the evidence does not support. A clock of whole
seconds for a label is wrong (the owner): any document can depend on the clock,
such as a progress bar with no count, which animates. The loop must give the
tasks of its thread their share while it animates: step 4.

## Not in this plan

The tasks of the agent move off the thread of the editor.
