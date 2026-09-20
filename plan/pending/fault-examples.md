# Fault examples

> **Kind:** plan · **Status:** pending · **Written:** 2026-09-20
> **Stands on:** [the-editor-survives-a-fault.md](../done/the-editor-survives-a-fault.md)

Two jobs. First, fix the regression that breaks every SDL gallery run: the
fault panel sits at the wrong altitude. Second, fill the empty
`ProjecturedFaultExample` with one runnable example per fault category, so a
person can watch each barrier work from the REPL.

## 1. The regression

`run_example(json_example)` dies with `write_to_devices(::SdlBackend, …,
::GraphicsCanvas)`. `FaultLogOverlayProjection` composes canvases — its
docstring says so — but the gallery wraps `make_fault_tolerant_projection`
around the **multi-window** projection, whose output is a `ScreenDocument`.
The overlay then hands the backend a canvas. The barrier's substitute has the
same type error in the fault path: `FaultToGraphics` answers a canvas where a
`ScreenDocument` is owed.

The gesture log solved the same problem already: the **recorder** sits at the
root, the **panel** wraps each window's content, at canvas altitude. The fix
mirrors it:

1. One shared `fault_log` before the per-example loop.
2. Inside the loop, after the gesture-log overlay:
   `projection, _ = make_fault_tolerant_projection(projection; log = fault_log)` —
   the barrier and the panel per window, where the output is a canvas.
3. The root-level `compose` wrap goes; the `on_start` that attaches the log
   to `editor.faults` stays.

## 2. The examples — one per fault category

`FaultRecord.site` names the categories: `:print`, `:read`, `:evaluate`,
`:map`, `:device`, `:tool`. The stub `package/ProjecturedFaultExample` gets a
tiny self-contained demo domain in `example/fault/`:

- `FaultDemo` — a document holding a `CellVector` of strings; the string
  `"broken"` is the node the demo breaks on.
- `FaultDemoToSyntax` — a projection with a `broken::Symbol` knob. Per knob it
  throws in exactly one place: `:print` throws in the printer of the broken
  node, `:read` throws in the reader on the F8 key, `:map` throws in the
  reference mappers of the broken node. Each child is wrapped in
  `FaultCatchingProjection(substitute = FaultToSyntax())`, so a print fault
  stands as one mark while the siblings draw.
- `ThrowFromEvaluationOperation` — bound to F9; its `evaluate_operation`
  throws after it moved the selection, so the repair (re-print, selection
  reset) is what the person watches.

Four gallery entries, run like any example:

    run_example(fault_print_example)      # one mark, siblings draw, one panel line
    run_example(fault_read_example)       # F8: the gesture dies, the editor lives
    run_example(fault_evaluate_example)   # F9: half an operation, then the repair
    run_example(fault_map_example)        # select the broken node: the mappers decline

Two categories do not fit the `Example` shape and get runner functions:

- `run_fault_device_example()` — an SDL run behind a `BrokenWriteBackend`
  wrapper (in the example package) whose `write_to_devices` throws; the
  circuit breaker degrades the seam after its limit, the screen freezes on
  the last frame, and Escape still quits because `read_from_devices` keeps
  running.
- `run_fault_tool_example()` — registers a tool that throws and calls it once
  through the tool set after the first frame; the fault reaches the same
  panel as everything else.

## 3. Verification

- The gallery regression: `run_example(json_example)` with an auto-quit
  `on_start` runs to a clean end under SDL, with an empty fault log.
- Each example: a headless printer walk where the category allows it, and an
  SDL auto-quit run; the read/evaluate/map categories drive their gesture
  through the scripted playback or the reader driver and assert the log line
  and the surviving editor.
- The suites: kernel at baseline, `test_fault()`, the export and
  documentation guards.

## 4. The phases

1. ⬜ Fix the gallery altitude; verify under SDL.
2. ⬜ The demo domain and the four projection-category examples.
3. ⬜ The two runner functions.
4. ⬜ Tests and registration; the plan records what each example shows.
