# The state machine examples run

Status: pending. Written 2026-10-27. The scope is the owner's; the machines, the
names and the steps are proposed.

## The ask

The owner, 2026-10-27: "the projectured-julia FSM examples are pretty lame, we
should have better ones". To the proposal (a traffic light, the alternating bit
protocol, TCP with its helpers, a test that runs each example) and the question
"only the examples, or also a live run in the gallery?": "just the examples".

## The problem

The facts at `main` `0319c78cb`. Find each function by its name in
`example/domain/fsm/FsmDocumentExample.jl`.

1. **The toggle does not toggle.** In `ON`, `PRESSED` is a stay that counts the
   press. No code starts `blink_timer`, so `on timeout(blink_timer)` never fires.
2. **The diagram example is the toggle.** It draws two boxes, and the label of
   an edge is wider than the gap between them
   (`asset/image/example/fsm-diagram.png`, made 2026-09-18).
3. **The TCP machine can not run.**
   - Its actions call 13 functions that no helper defines: `select_initial_seq_num!`,
     `send_syn!`, `send_syn_ack!`, `send_ack!`, `send_fin!`, `send_rst!`,
     `send_data!`, `accept_syn!`, `start_conn_estab_timer!`,
     `start_fin_wait_2_timer!`, `indicate_timed_out!`, `indicate_reset!`,
     `connection_established!` and `cancel_all_timers!`. The header comment says
     that everything it references is in its own `helpers`.
   - `analyse_segment` returns `RCV_RST` and the other bare event names, but the
     generator names the constants `E_RCV_RST` and so on. It returns `IGNORE`,
     which nothing defines; `0` means no event.
   - The entry of `TIME_WAIT` passes `expire_msl2`, but the generator names the
     callback `expire_msl2_timer!`, and it takes `m` as its argument.
   - `analyse_segment` reads `seg.ack` as a flag, and `ack_acceptable` reads it as
     a number.
   - No action sets `fin_ack_rcvd`, so `RCV_FIN_ACK` never comes.
4. **No test runs an example.** `test_fsm_to_julia_code()` only searches the
   generated text of the examples. Only its own probe component runs on
   `ProbeRuntime`.

## The decision

- **The toggle stays, under its name, and becomes correct.**
  `make_fsm_toggle_document_example` and `fsm_toggle_example` are exports of
  `ProjecturedFSMExample` and `ProjecturedExample`, which are released at 0.1.0.
  A removed export needs a minor version step. So the toggle keeps its name and
  becomes a lamp with a button: `PRESSED` turns it on and off, and `off_timer`,
  which the entry of `ON` starts, turns it off after `AUTO_OFF` seconds.
- **`fsm_crossing`: a traffic light with a pedestrian button.** It is the new
  diagram example: `make_fsm_diagram_document_example` returns its machine.

  ```
  machine Light initial START ignoring unhandled
    state START
      -> CARS_GREEN
    state CARS_GREEN
      entry / start_timer!(ctx, m, m.min_green_timer, MIN_GREEN_TIME, expire_min_green_timer!)
      on BUTTON stay / m.requested = true
      when m.requested && !is_scheduled(m.min_green_timer) -> CARS_YELLOW
    state CARS_YELLOW      entry starts yellow_timer;   on timeout(yellow_timer) -> ALL_RED
    state ALL_RED          entry starts all_red_timer;  on timeout(all_red_timer) -> WALK
    state WALK             entry clears m.requested and starts walk_timer;
                           on timeout(walk_timer) -> WALK_FLASHING
    state WALK_FLASHING    entry starts flashing_timer; on BUTTON stay / m.requested = true;
                           on timeout(flashing_timer) -> CARS_GREEN
  ```

  `START` exists because the entry of the initial state does not run at startup
  (rule 6 of the execution contract). The dispatch of event `0` fires its
  condition-only transition, so the entry of `CARS_GREEN` starts the minimum green.
  `min_green_timer` is no trigger, so its expiry dispatches event `0`, and the
  condition-only transition reads it with `is_scheduled`, as the guide describes.
- **`fsm_alternating_bit`: the alternating bit protocol.** One component holds
  two machines, `Sender` (`WAIT_SEND_0`, `WAIT_ACK_0`, `WAIT_SEND_1`,
  `WAIT_ACK_1`) and `Receiver` (`WAIT_FRAME_0`, `WAIT_FRAME_1`). Events: `SEND`,
  `FRAME`, `ACK`; one timer: `retransmit_timer`. The helpers `send_frame!` and
  `send_ack!` give the frame and the acknowledgement to the other machine with
  `fsm_defer!`. They drop one frame or one acknowledgement when
  `m.drop_next_frame` or `m.drop_next_ack` is set. Both machines use `:error`: a
  `SEND` while the sender waits for an `ACK` is an error of the user of the
  component. A late `ACK` is an `ignore`, and a duplicate `FRAME` is a stay that
  sends the last `ACK` again. `fsm_alternating_bit_diagram` draws `Sender`.
- **TCP gets its helpers.** The send helpers put each segment in `m.outbox`, so a
  test reads what the machine sends. A segment has the flags `syn`, `ack`, `fin`,
  `rst` and the number `ack_number`. `analyse_segment` sets `fin_ack_rcvd` when a
  segment acknowledges the FIN of the machine. The names of RFC 793 and INET stay
  (`snd_una`, `conn_estab_timer`). A helper name that breaks the naming rules
  changes: `select_initial_sequence_number!`, `indicate_established!`.
- **A test runs each example.** `ProbeRuntime` gets `schedule_timer!(ctx, delay,
  module_id, h, action, argument)`, `cancel_timer!(ctx, h)` and `is_scheduled(h)`,
  with the signatures of the real runtime. A test fires a timer when it calls its
  `expire_<timer>!`. A test adds `using ..ProbeRuntime` to the `usings` of a fresh
  example, as an embedder adds its runtime.

## The steps

The work is on the branch `fsm-examples`, in a worktree.

1. **The run test and the toggle.** `ProbeRuntime` gets the three timer
   functions. The toggle becomes the lamp, and a test plays `PRESSED`,
   `PRESSED`, `PRESSED` and the expiry of `off_timer`. The notation test and the
   code test read the new toggle. Run `test_fsm()`.
2. **The crossing.** The document, `fsm_crossing`, and `fsm_diagram` draws its
   machine. A run test: a press in `CARS_GREEN` waits for the minimum green, and
   the cycle comes back to `CARS_GREEN` with `m.requested` false. The diagram test
   counts six boxes and six edges. Run `test_fsm()` and `test_example` for
   `fsm_crossing` and `fsm_diagram`.
3. **The alternating bit.** The document, `fsm_alternating_bit` and
   `fsm_alternating_bit_diagram`. A run test sends three items with one dropped
   frame and one dropped acknowledgement: the receiver delivers each item once,
   in order, and a `SEND` in `WAIT_ACK_0` throws. Run `test_fsm()` and
   `test_example` for the two examples.
4. **TCP runs.** The helpers and the corrected names. A run test plays the active
   open and the active close to `CLOSED` through `TIME_WAIT`, and the passive open
   and the passive close. Run `test_fsm()` and `test_example(fsm_example)`.
5. **Sweeps, pictures and guides.** The example sweeps in
   `test/projectured/editor/ExampleSweeps.jl`: each new notation example stays in
   the navigation sweep if its walk takes less than a minute, and the diagram
   examples go to the skip list of `fsm_diagram`, for its reason.
   `generate_example_screenshots` for the FSM examples. The guides: `fsm.md` and
   `examples-tour.md`. Then the plan moves to `plan/done/`.

Not in this plan: a live run of a machine in the gallery; a diagram of TCP; the
names that the generator calls (`fsm_drain!`, `fsm_enter!`) differ from the real
runtime (`drain_fsm!`, `enter_fsm!`); the recorded precompile statements of the
new examples.
