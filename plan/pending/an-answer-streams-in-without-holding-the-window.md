# An answer streams in without holding the window

Status: PENDING, 2026-10-21. Steps 1 and 2 are done, on the branch `answer-stream`.
No decision is open.

## The ask

Step 1 of [guards-keep-the-frame-short-at-any-size.md](guards-keep-the-frame-short-at-any-size.md)
found why the frames of the Assistant pane are slow while an answer streams. The
owner, 2026-10-21, to the question "Do you want me to write a small plan now that
fixes how an answer streams in, before I continue with step 2 of the guards?":
"Yes". On the compile of a first use: "for compilation caused first time slowness
we already have the trace based compiler workload, which may be incomplete but
generally works fine. More UI parts must be covered though."

## The problem

The facts at `frame-guards` `a35a4e2ec`, measured in the real window with a
scripted model that streams about 4_000 words, three words for each delta, one
delta each 30 ms. The numbers are in the As built of the guards plan.

1. **Each delta is a code unit.** The turn of the built-in assistant runs off the
   loop. It posts each `LlmEvent` with `run_on_editor_task!(editor; wait = false)`,
   so each frame that drains a delta runs a code unit, and the loop runs held
   frames meanwhile. With vsync on, the held frames and the frame each present the
   window, and each present waits for the vertical blank. While the turn
   streams, the median frame is 47.92 ms, three refreshes of a 60 Hz display; with
   vsync off it is 2.34 ms. A frame with no delta takes 1.8 ms.
2. **Each delta makes the whole text again.** `_append_text_delta!` makes the
   string of the whole part, appends the delta, and makes a new `TextBlock` from
   it. So the print of the part starts again for each delta. With vsync off, the
   frame of a delta grows from 5.09 ms and 2.01 MB to 16.64 ms and 16.14 MB over
   the answer, and the frames with a garbage collection grow from 2 to 31 in 100
   frames. `_append_thinking_delta!` does the same for a thinking part.
3. **An external agent already uses the door that a stream needs.** The events of
   an agent over ACP go into an `AgentEventQueue`, and `_post_agent_event!` wakes
   the editor. The `AgentEventFeed` applies the whole queue in the next frame,
   with no code unit and so no held frames. The communication guide names this
   door for "data that the producer prepared": the feed.
4. **The recorded workload streams no answer.** `tool/precompile/recording-driver.jl`
   plays gestures over the examples and the application window. It runs no turn
   of the assistant. In the measurement, which did not load the workload of the
   leaf, the first frame of the first turn took 2.98 s, 2.61 s of it in the
   print. With the recorded workload, that number is not measured.

## The model

1. **A turn is a producer of a feed.** The turn of the built-in assistant puts
   each event into a queue of the turn, as a connection to an external agent puts
   its events into the queue of its session. The `AgentEventFeed` applies the
   queue once in each frame, the oldest event first. The two steps that the turn
   posts without a wait, the new turn at its start and its end, go into the same
   queue, so they keep their order with the events.
2. **A call of the turn sees every event before it.** A call that waits for an
   answer, such as the call that makes the messages of the next round, applies
   the events that wait in the queue of the turn first. So the conversation that
   it reads holds every part that the turn streamed before it.
3. **A delta appends.** A delta adds its text to the last line of the text of its
   part, and each newline in it adds a line. The block, the lines before the last
   line, and their print stay as they are. The deltas of one part that one drain
   applies are one append. The thinking part appends in the same way.
4. **No new mechanism.** The queue, the wake and the feed are those of the
   external agents. A source of the feed is a queue with its assistant; the source
   of a turn holds the turn in place of a session.

The `AgentEventFeed` joins the editor as it does now for a session of an external
agent. [the-feeds-of-an-editor-are-its-own.md](the-feeds-of-an-editor-are-its-own.md)
gives every editor its feed through a wrapper; that plan then covers the turn too.

## Keep

1. An answer shows the same text, the same parts and the same Markdown after its
   end as now.
2. A stop of a turn closes the blocks that stream, as now.
3. With no loop, as in a test, an event applies at once on the task that makes
   it, as `_post_agent_event!` does now.
4. Add no event type, no payload and no channel.
5. Each new name follows [naming-rules.md](../../documentation/rule/naming-rules.md).

## Rule of measurement

As in the guards plan: each time in the lane `taskset -c 28,30,31`, the branch
and its base interleaved as A/B/A, with the load beside it. A count of bytes or
of code units needs no idle machine.

## Steps

Do the work in a worktree on a branch of its own, from `frame-guards`, because
the measurement needs the record of a frame. Commit each step. Do not land on
`main` before the owner approves.

1. [x] **The door.** Done; see [As built](#as-built). The queue of a turn, its source in the `AgentEventFeed`,
   the two steps in the queue, and the calls that apply the queue first.
   - Tests: the assistant tests in `test/projectured/editor/AssistantMvpTest.jl`
     and `test/kernel/agent/AgentLoopTest.jl`.
   - A new test: a running editor with a backend that counts its held frames
     streams a turn of 200 deltas. No held frame runs for a delta; only the calls
     of the turn run as code units. The conversation after the turn is the same
     as with the door of today.
   - A new test: a round that follows a round of text reads the text of the first
     round in its messages.
   - Commit.
2. [x] **The append.** Done; see [As built](#as-built). A delta appends to the last line; the deltas of one drain
   are one append; the thinking part too.
   - A new test: an answer of paragraphs of 100 words streams, and the frame of a
     delta at 1_000, 10_000 and 100_000 characters of answer allocates at most 2
     times the bytes at 1_000 characters.
   - The tests of step 1 again. Commit.
3. [ ] **The measurement.** Run `/var/tmp/frame-guards/assistant_frames.jl` on
   the branch and on `frame-guards`, A/B/A, with vsync on and with vsync off. The
   answer of the script gets paragraphs of 100 words. Write in
   [As built](#as-built) the median and the 90th percentile of a frame while the
   turn streams, the frames above 16 ms and above 50 ms, the bytes of a frame of a
   delta at the start and at the end, and the frames with a collection. The
   target: with vsync on, the median frame of the turn is at most one refresh,
   16.7 ms. Commit.
4. [ ] **The recorded workload streams an answer.** The recording driver streams
   a turn of a `ScriptedLlm` in the Assistant pane of the application window,
   with text, thinking and a tool call. Record the statements again, and check
   that the new list holds the old one. Then measure the first turn in the
   application with its workload, as `bin/projectured` loads it: the compile time
   of its first frames, from the record of a frame. Write it in
   [As built](#as-built). Commit.
5. [ ] **The guides.** [assistant.md](../../documentation/package/platform/assistant/assistant.md):
   how an answer streams in. [communication-anatomy.md](../../documentation/design/communication-anatomy.md):
   the producers of the `AgentEventFeed`. Move this plan to `plan/done/`.
   Commit.

## Not in this plan

- The other producers that post a call for each piece of data: the output of a
  terminal and the steps of a formula. They run a code unit with held frames for
  each frame that drains them.
- A code unit that ends within one frame and still runs held frames. A change of
  the held frames would change every tool call.
- The UI parts other than the Assistant pane that the recorded workload does not
  cover. Step 7 of the guards plan finds them.

## Wait on long jobs

- While a build, a test run, a sweep, a CI script or a subagent runs, wait with one foreground `until` loop that checks every 15 s, with a timeout of up to 600000 ms, and repeat only that loop until the job ends.
- Do not end a turn to wait. Do not run filler commands such as `echo ok`. Do not print "Waiting" or any status line while a job runs. Report once, when the job has ended.
- Put this rule verbatim into the prompt of every subagent that may wait on a job.

## As built

The work is on the branch `answer-stream`, from `frame-guards`, in the worktree
`projectured-julia-frame-guards`, which has its environment built.

### Step 1

- **The source of a turn.** `_TurnEventSource` holds the assistant, the queue, the
  turn, the state of the blocks that stream and the tool set, and whether the turn
  is open. `_make_turn_event_source!` posts its join to the feed without a wait,
  before the call that puts the turn into the conversation. `_post_turn_event!` puts
  an event into the queue and wakes the editor; with no loop it applies the event at
  once. `_drain_agent_event_queue!` takes the function that applies an event, so the
  drain of a session and the drain of a turn share the record of a fault.
- **The feed.** `_add_agent_event_source!` adds the feed when the editor has none and
  joins a source; `_register_agent_event_queue!` uses it and adds the `TaskFeed`
  only for a session. The feed drains a source of a turn as it drains a session,
  samples no processes for it, and asks no deadline for it, because each event wakes
  the editor.
- **Decision: the start of the turn stays a call.** The model says "the two steps
  that the turn posts without a wait go into the same queue". The start stays a
  call: the inbox drains before every other feed in a frame, so the call that puts
  the turn into the conversation applies before the events after it. The end, the
  close of the blocks after a stop, and a `finally` that closes the source are calls
  that apply the queue first (`_run_turn_call!`), so every event applies before
  them, also after a turn that failed. Then the steps of `_launch_agent_turn!` after
  the turn, such as the status and the error, apply after every event too.
- **Decision: the end of a round and the result of a tool apply in a call that
  waits.** A tool of a round can write the turn: `ask_person` puts a question into
  it. The inbox drains before the feed, so a tool that runs in a call would come
  before the events that wait. So `LlmTurnEnd` and `AgentToolResult` apply in a call
  that waits and applies the queue first: a tool runs after every part of its round,
  and the next tool after the result of the tool before it. This costs one code unit
  for each round and for each tool, not for each delta.
- **Tests.** `test_assistant_stream()` in `test/projectured/editor/AssistantStreamTest.jl`:
  7 pass. On `main`, the same file fails: a stream of 200 deltas prepares held frames
  151 to 155 times (`155 <= 12` fails); on the branch, 5 times. `test_assistant_mvp()`:
  191 pass, 4 broken, on `main` and on the branch. `test_agent_work()` and
  `test_external_agent_turn()` in `package/ProjecturedPlatformTest`: 158 and 271 pass.
  In `environment/all` they give 95/10/8 and 122/50/30 on `main` and on the branch,
  with the same failing places, a known failure of that environment.
  `test_conversation_editor()`: 40 pass. `AgentLoopTest.jl` is a kernel test, and
  the kernel did not change, so it did not run.

### The review of step 1

A review of the commit of step 1 found four faults. Each is fixed in the commit of
step 2:

1. **A call that waits could time out.** The calls of the end of a round and of
   the result of a tool had the time limit of 30 s of a call. While a code unit
   runs longer, such as an evaluation of the person, the call was withdrawn, the
   turn failed, and the result of a tool was lost. These calls now have no time
   limit (`timeout = Inf`): the turn can not go on before them, and the end of the
   loop answers a call that waits.
2. **The parse at the end of a text block ran in the frame.** `LlmTextStop` came
   through the queue, so `parse_markdown_blocks` ran in the drain of the feed, with
   no busy bar. It now applies in a call that waits, as before the change: a code
   unit with held frames, once for each block.
3. **A source could stay open.** The source joined the feed in one call and the
   turn joined the conversation in another, and the `try` that closes the source
   began after `Agent(...)`. Now one call joins the source and puts the turn into
   the conversation, and the `try` begins right after it.
4. **With no loop, closed sources stayed in the feed.** The end of a turn now
   removes its source from the feed at once (`_remove_agent_event_source!`), also
   in an editor whose feeds no loop drains.

The review also found that the test of the messages of a round passed before the
change too. It now also checks the order of the parts: the text of the first
round, the call of its tool, and the text of the second round. The test of 200
deltas has a lower bound, at least 3 code units, so it can not pass with no held
frames at all. Two new tests: a turn that fails shows its text before the error
and leaves no source; with no loop, two turns leave no source.

### Step 2

- **`append_text!(block, text)`** in `TextDocument.jl`, exported by `TextModule`:
  the text up to the first newline goes at the end of the last run of the last
  line, and each line after a newline is a new line of one run in the font and the
  colour of that run. `_append_text_delta!` and `_append_thinking_delta!` use it, and
  make the block again only for a content that is no `TextBlock`.
- **The deltas of one drain are one append.** `_join_stream_deltas` joins each run
  of text deltas and each run of thinking deltas into one delta.
  `_apply_agent_events!` holds the loop with the record of a fault, which the drain
  of a session and the drain of a turn share.
- **Decision: the test measures the print, not the bytes of a frame.** A frame on
  the `HeadlessBackend` reads every part of the output, so its bytes grow with the
  answer whatever the print does. So the test measures with
  `measure_printer_locality` the output objects that one delta makes again:

  | Paragraphs of 100 words | Objects made again, new | Objects made again, old way |
  |---|---|---|
  | 10 | 184 | 535 |
  | 100 | 184 | 2_785 |
  | 1_000 | 184 | 25_285 |

  The invalidated cells are 51 with the new append and 41 with the old way, at each
  size: the old way invalidates few cells and makes everything below them again.
  The test asserts at most 2 times the count at 10 paragraphs, plus 10.
- **Tests.** `test_assistant_stream()` 19 pass; `test_assistant_mvp()` 191 pass and
  4 broken, as on `main`; `test_conversation_editor()` 40 pass; in
  `package/ProjecturedPlatformTest`, `test_text()` with the new testset (9 pass),
  `test_agent_work()` 158 pass and `test_external_agent_turn()` 271 pass.
