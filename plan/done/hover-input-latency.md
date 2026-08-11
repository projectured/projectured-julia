# Hover input latency: coalesce motion, drain a frame

The hover highlight follows the pointer with a visible delay in the
omnetpp-julia demo. This plan holds the two input-path fixes. It does not hold
the third and larger fix, which is to take the hover state out of the geometry
cell of a widget.

## What the measurement showed

I drove `MouseMove` events through the real reader of `demo_projection()` on an
open catalog page at 1600x1000, headless.

| Step | Cost |
| --- | --- |
| One `MouseMove` read, no write between reads | 0.007 ms |
| First read after one hover write | 7.2 - 10.7 ms |
| Settle the painted output after one hover write | 0.2 - 0.6 ms |
| Settle the whole IO map graph after one hover write | 15.6 ms |

The hit test and the paint are nearly free. One hover step costs about 10 ms of
reactive recompute, and almost all of that work is in the IO map graph.

Four causes stack up:

1. A widget printer reads `hovered` in the same `build` cell that produces
   `width`, `height`, `elements` and `child_iomaps`. A container `build` reads
   the size of its child canvas, so one row tint invalidates every ancestor up
   to the root. This is the 10 ms. **Not in this plan.**
2. The SDL backend returns the oldest queued motion event and drops the newer
   ones. The highlight lands where the pointer was one frame ago.
3. The editor loop applies one operation per frame, so a burst of motion needs
   one frame for each step.
4. Each frame sleeps 10 ms.

This plan does 2 and 3.

## Step 1 — Deliver the newest pointer sample — DONE

**File**: [package/sdl/main/ProjecturedSdl.jl](../../package/sdl/main/ProjecturedSdl.jl)

`read_from_devices` returns the first motion event that passes the rate limit
and leaves the newer ones in the SDL queue. The next call drops them all. So the
editor always acts on the oldest sample it has.

Collapse a run of motion events into the newest one:

1. Poll the queue. Keep the newest motion event in a local variable. Do not
   return it yet.
2. Stop at the first event that is not motion. If a motion event is held,
   stash the other event on the backend and deliver the motion first, so the
   order that a reader sees does not change. If no motion is held, return the
   other event at once.
3. Deliver the held motion when the queue is empty. A motion with a button held
   is a drag and is never rate-limited.
4. If the rate limit blocks an idle motion, hold it on the backend instead of
   dropping it, and deliver it on a later call. Without this the last sample of
   a pointer that stops is lost, and the highlight stays one row behind.
5. Deliver a held motion even when the rate limit blocks it, if another event
   waits behind it. A click must never arrive before the motion that preceded
   it.

Two fields carry the state, on `SdlBackend` and not at module level, so two
backends in one process do not share it:

- `pending_input` — one event that arrived behind a held motion.
- `pending_motion` — the newest motion not yet delivered.

The 30 ms rate limit itself (`_HOVER_MOTION_INTERVAL`) does not change here. It
exists because a hover step costs 10 ms. Lower it after cause 1 is fixed.

**Result**: `pending_input` and `pending_motion` are fields of `SdlBackend`.
`read_from_devices` answers `pending_input` first, then polls through
`_poll_window_input`, which is the whole of the former body and now answers an
`(other, motion)` pair. `initialize_backend!` and `quit_backend!` clear both
fields, so a backend that is opened again does not answer with an event from its
last life. `InputCoalescingTest` pushes events on the real SDL queue and checks
the three rules: the newest sample wins, a press does not overtake the motion in
front of it, and a blocked sample is held rather than dropped.


## Step 2 — Drain the input of a frame before the paint — DONE

**File**: [package/kernel/main/editor/Editor.jl](../../package/kernel/main/editor/Editor.jl)

`read!` returns as soon as one operation appears, and `run_frame!` then paints.
A burst of input therefore needs one frame for each operation, and the frame
also sleeps 10 ms. Make `run_frame!` read and evaluate until the backend has
nothing left, then paint once.

A bound of `MAX_OPERATIONS_PER_FRAME` operations keeps the frame finite: a
pointer that moves without stop must not hold off the paint.

`perf!` reads `editor.operation` to tell a frame with work from an idle one, and
`read!` sets that field to `nothing` when the input is exhausted. Put the last
applied operation back before the paint, so the performance log still reports.

**Result**: `run_frame!` loops read and evaluate up to
`MAX_OPERATIONS_PER_FRAME` (32) times, then prints once. `@performance_time`
adds into the same key on each pass, so `:read_time` and `:evaluate_time` report
the total of the frame.

One case found during the work and handled: an operation that drops the cached
projection ends the frame. `read!` reads against the stored IoMap and *discards*
an input it has none for, so input behind a whole-root swap must wait for the
repaint that rebuilds the projection. Without the break it would be thrown away.
`FrameDrainTest` covers it, together with the drain, the bound, the idle frame,
and the operation that `perf!` reads.


## Step 3 — Test — DONE

Run the narrow tests that cover the two files:

- `test_sdl()` for the backend.
- `test_kernel()` for the editor loop.

**Result**: `test_sdl()` gives 63 pass and 0 fail, against 50 pass on clean main
— the 13 new assertions, and nothing else moved. `test_kernel()` gives 1472
pass, 3 fail, 2 error, against 1461 pass, 3 fail, 2 error on clean main — the 11
new assertions, and the same five pre-existing Rule C failures of
`DocumentMacro`.

Not tested end to end: the omnetpp-julia demo resolves `projectured-julia`
through `[sources]` to the main checkout, so `run_demo` cannot see a worktree.
Measure the demo after this branch lands on main.


## What this plan does not do

- Cause 1, the hover state in the geometry cell. It is the 10 ms.
- Cause 4, the fixed 10 ms sleep of a frame.
- The 30 ms rate limit of idle motion.
