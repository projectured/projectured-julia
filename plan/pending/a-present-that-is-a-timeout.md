# A present that is a timeout, and an editor that draws once a second

The editor draws **one frame a second** on this machine. Not a slow document, not
a heavy projection: a static JSON example, with nothing else running, draws one
frame a second and spends 989 milliseconds of every second inside
`SDL_RenderPresent`.

Everything animated is therefore not animated. Anything driven by
`get_reactive_clock_time` — the rotating vector, an in-flight drag, a paced
simulation clock — recomputes exactly once a frame, which is correct, and is
then shown once a second, which is not.

## What was measured

The editor's loop is `set_clock_time!` → `drain_operations!` → `run_frame!` →
`sleep(0.01)`, which is a hundred frames a second on paper. Timed, on
`run_example("json")` with a static document and no simulation:

| | |
| --- | --- |
| frames a second | **1** |
| `read!` + `evaluate!` | 0.0 ms |
| `print!` | **990 ms** |
| `sleep(0.01)` | 11 ms — correct |

`print!` is the whole of it, and inside `print!`:

| stage of `_render_window!` | a second's worth |
| --- | --- |
| `_render_canvas!` — the actual drawing | 0.5 ms |
| `_back_buffer_age` | 0.0 ms |
| `SDL_RenderCopy` | 0.0 ms |
| **`SDL_RenderPresent`** | **989 ms** |

The frame is drawn in half a millisecond and then waits a second to be shown.

## Why

`_open_native_window!` creates the renderer with
`SDL_RENDERER_ACCELERATED | SDL_RENDERER_PRESENTVSYNC`, so `SDL_RenderPresent`
waits for the vertical blank. That is right on a display that HAS one: the frame
rate settles at the refresh rate and nothing tears.

**This display has none.** `xrandr` reports a screen and no output, and
`XDG_SESSION_TYPE` is `tty` — a headless or virtual X server. The wait is then
not a refresh, it is a timeout, and it is about a second long.

Dropping `SDL_RENDERER_PRESENTVSYNC` and changing nothing else:

| | with vsync | without |
| --- | --- | --- |
| frames a second | 1 | **82** |
| present, per frame | 989 ms | 0.38 ms |

82 a second is the loop's own `sleep(0.01)` cadence plus about two milliseconds
of work — the editor doing exactly what it was written to do.

## The fix, and why it is not "turn vsync off"

Vsync is right where it works, so it is kept where it works. The present is
**timed once, at the window that is about to use it**, and vsync is switched off
only when the number is impossible:

```julia
const _VSYNC_PRESENT_LIMIT = 0.1     # seconds
const _VSYNC_PROBE_FRAMES  = 3
```

The threshold sits far above any real refresh and far below the fault. The
slowest real panel is 24 Hz, which is 42 ms; the fault is 989 ms, which is
twenty times the limit. Nothing on a real display goes near it.

Three alternatives were considered and rejected:

- **Turn vsync off always.** The editor already limits itself to a hundred
  frames a second, so vsync buys little — but it buys tear-free frames on a real
  monitor for nothing, and throwing that away to fix a virtual display is the
  wrong trade.
- **Ask the display what it is.** SDL and X will both answer, and neither answer
  is the question: what matters is how long a present takes, and that is
  measurable directly.
- **Make it an option, like `partial_render`.** An option is a thing a person
  has to know about. Somebody meeting a one-frame-a-second editor does not know
  that vsync is a thing, and the editor can find out by itself in three frames.

## The parts

- [x] **1. Time the present at window open, and drop vsync when it is a
  timeout.** `_drop_pathological_vsync!` in
  [ProjecturedSdl.jl](../../package/ProjecturedSdl/src/ProjecturedSdl.jl), called from
  `_open_native_window!`. It says so once when it fires, because a person
  wondering why their frames tear deserves to find the reason in the log.

- [ ] **2. A frame-rate reading the editor can show.** Nothing in the editor
  counts its own frames, which is why this took a measurement campaign to find
  rather than a glance. `_log_performance_counters!` exists and reports only when an operation was
  applied, so an idle editor at one frame a second reports nothing at all.

## What else the campaign found, and did not fix

**`rotating_vector` does not run.** The repository's own clock-animation
example — the one thing that would have shown this in ten seconds — dies on its
first frame:

```
ERROR: MethodError: no method matching Int64(::Nothing)
  [1] _render_polyline!(renderer, pl::GraphicsPolyline, ox::Int64, oy::Int64)
    @ ProjecturedSdl package/sdl/main/ProjecturedSdl.jl:1253
```

A field of the polyline is `nothing` where the renderer converts it to `Int64`.
It wants its own look: an animation example that cannot be launched is an
animation nobody can check.
