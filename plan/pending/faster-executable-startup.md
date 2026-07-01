# Faster executable startup — beyond precompilation

## Goal

Make the native binary produced by `build_executable`
([package/executable/Builder.jl](../../package/executable/Builder.jl)) reach an
interactive editor as fast as possible. The app is *already* a PackageCompiler
`create_app` sysimage with a precompile workload, so "precompiled" is the
baseline — this plan is about the layers **on top of** precompilation.

## Where we are today

- **Julia 1.12.6**, **PackageCompiler 2.2.5**, `create_app`.
- Precompile workload: [`Precompile.jl`](../../package/executable/src/Precompile.jl)
  → `ProjecturedExecutable.precompile_warmup()`.
- `create_app` is invoked with **no** tuning args
  ([Builder.jl:192-195](../../package/executable/Builder.jl#L192-L195)): no
  `cpu_target`, `filter_stdlibs`, `incremental`, or `sysimage_build_args`.
- `__init__` work is light: SDL installs a display-size provider; Adaptagrams
  `dlopen`s its shim lazily. Startup is **not** dominated by module init.

### What actually costs time at startup (hypotheses to confirm in Tier 0)

1. **Sysimage mmap / page-faulting** the `.so` off disk — grows with image size;
   the portable multi-versioned `cpu_target` default bakes ~3 copies of native
   code. Dominates the *cold* (post-boot, cold page-cache) launch.
2. **Residual JIT (TTFX)** on the first *real* interaction — window creation,
   event dispatch, first keystroke/edit, save/load.
3. **Runtime/library init** — Julia bootstrap, OpenBLAS/thread-pool spin-up,
   SDL2/SDL_ttf + font opens, X11/Wayland/GPU context creation.

## Tier 0 — Measure first (do this before any change)

Never optimize startup blind. Establish a baseline and a repeatable harness.

- [ ] Add a hidden `--startup-timing` flag (or `PROJECTURED_STARTUP_TIMING=1`)
      to `julia_main` that stamps `Base.time_ns()` at phase boundaries: entry →
      args parsed → document+projection built → `display_size()` → backend
      created → **first frame presented** → editor loop entered. Print the deltas
      to stderr on exit.
- [ ] Wrap the binary in a bench script that runs it N times and reports
      **cold** (drop page cache) vs **warm** medians. Cold vs warm separates
      "reading the .so off disk" (Tier 1) from "compute/JIT after it's mapped"
      (Tiers 2-3).
- [ ] One-off `strace -tt -T -e trace=mmap,openat,read` and `perf stat` on a
      launch, to attribute time to mmap/dlopen vs CPU.
- [ ] Build with `--trace-compile=stderr` and capture **what still compiles** on:
      opening a real window, the first keypress, an edit, and a save. That list
      drives Tier 2.

## Tier 1 — Shrink & target the sysimage (highest ROI, lowest risk)

Add build knobs to `BuildSpec` and pass them through to `create_app`.

- [ ] **`cpu_target = "native"`** for self-use builds (expose as
      `BuildSpec(; portable::Bool=false)`). Trade-off: a native image only runs on
      this CPU microarch class.
- [ ] **`sysimage_build_args = \`--strip-metadata --strip-ir\`**` — drop
      docstrings/IR/debug metadata. Trade-off: worse backtraces, no further codegen
      of stripped methods.
- [ ] **`filter_stdlibs = true`** — drop unused stdlibs. Risk: must confirm every
      stdlib actually reached at runtime is retained; gate behind Tier 0 trace +
      a smoke run of the produced binary.
- [ ] Record image size + cold/warm timings after **each** flag independently.

## Tier 2 — Close the precompile-coverage gap (kill residual TTFX)  ✅ DONE (initial pass)

**Status: implemented on branch `faster-startup-warmup`.**

The offscreen `write_image` warm-up only covered the initial *paint*, never
interaction — so the first keystroke of the built binary JIT-compiled the whole
reader + evaluator + reprint. Closed by adding a headless interaction warm-up.

**What was built**

- `warm_file_editor(domain; workbench=false)` in
  [package/example/src/FileEditor.jl](../../package/example/src/FileEditor.jl)
  (exported from `ProjecturedExample`). It drives the **exact windowed pipeline
  `run_file_editor` runs** — `_build_window_scene` + `_multi_window_projection`
  over a `ScreenDocument` — through one print and a spread of synthetic events,
  **without opening a window**:
  - Builds a real `Editor` but never `init!`s it and never calls
    `write_to_devices`, so no window/GPU context is created.
  - Uses the window-free **console backend** as the `Editor.backend` field
    (`evaluate_operation` dispatches on the *operation*, not the backend).
  - Faithful reader entry: `EventEnvelope(window_id, event)` →
    `projection_read(composed, nothing, Change(env), iomap)` — the same path live
    input takes (mirrors `Editor.read!` / `_timeline_operation`).
  - `_force_reactive!` walks the printed iomap forcing every `Cell` (with
    depth/node caps), so the printer **cell bodies** compile, not just graph
    assembly. Self-contained (no dependency on the test package's `_walk!`).
  - Wrapped in try/catch → `@warn`: a warm-up miss can never fail the build.
- `_WARMUP_EVENTS`: Ctrl+Home (seed caret), arrow nav, Ctrl+End, two `KeyPress`
  (type), backspace, delete.
- `precompile_warmup()` in
  [package/executable/src/ProjecturedExecutable.jl](../../package/executable/src/ProjecturedExecutable.jl)
  now calls `warm_file_editor(APP_DOMAIN; workbench=APP_WORKBENCH)` after the
  offscreen render. Runs for **every** baked backend (the reader/evaluator are
  backend-independent), not just SDL.

**Key discovery — the warm-up is fully backend-independent.** The windowed
pipeline measures text via `truetype_measure_text` (`= pdf_measure_text` in the
domain package — pure-Julia FreeType), *not* SDL_ttf. So `warm_file_editor` needs
no SDL, no display, no window.

**Verification** (`julia --project=.`, no `ProjecturedSdl` loaded): the JSON
default (`JsonInsertion`) warm-up returns `nothing` with no window; 7/10 synthetic
events produced operations — `ReplaceSelectionOperation` (navigation),
`CompoundOperation` (typing), `NumberReplaceRangeOperation` (backspace/delete).
The 3 no-ops (up/down at edge, letter into a number field) still exercise the
reader. Confirms read → evaluate → reprint is genuinely compiled into the image.

**Follow-ups (not yet done)**

- [ ] Warm **save/load/export** once those are wired (`APP_FILE_BACKED`).
- [ ] Add a **MousePress** event (pointer → reference mapping) — deferred: needs a
      real hit coordinate from the iomap geometry to be non-trivial.
- [ ] After Tier 0's `--trace-compile`, confirm no *residual* interaction JIT
      remains and extend `_WARMUP_EVENTS` if the trace shows gaps (e.g. structural
      edits, clipboard, workbench tab clicks).

## Tier 3 — Trim & reorder the runtime path (perceived latency)

- [ ] **Present a window ASAP** — reorder `run_file_editor` so the window + first
      frame appear before heavier warm-up the user is waiting on.
- [ ] **Bound thread/BLAS spin-up** (32-core box; a UI doesn't need 32 BLAS
      threads).
- [ ] **Defer non-critical subsystems** (MCP when `APP_MCP`; Adaptagrams is already
      lazy — keep it so).

## Tier 4 — Go beyond precompilation: keep a process warm

### 4a — Resident editor daemon + thin client (recommended headline)

Emacs `--daemon` / `emacsclient` model: a background `projectured-daemon` boots
once to a warm state on a unix socket; the `projectured` binary becomes a thin
client that hands the file to the daemon (instant window) or starts it (the one
slow launch). Fits the existing multi-window scene (`_run_window_scene` takes
`Any[document]` vectors) and the `mcp` server-loop notion. Biggest payoff for
*repeated* launches.

### 4b — Process snapshot / restore (research spike)

CRIU checkpoint/restore on Linux. Caveat: SDL holds X11/Wayland/GPU/DRM fds that
CRIU restores poorly — checkpoint at a **headless** point (all init + document
built, before window creation) and open the window post-restore. Validate the win
over a good sysimage before investing.

## Evaluated but deferred

- **`juliac --trim` (Julia 1.12 experimental AOT):** whole-program DCE could
  shrink the binary a lot, but `--trim` demands type-stable, no-dynamic-dispatch
  entry paths; a projectional editor on generic dispatch won't satisfy it today.
  Re-evaluate as the toolchain matures.

## Suggested sequencing

1. **Tier 0** (measure) — mandatory foundation.
2. **Tier 1** (sysimage flags) — biggest cold-start win for least effort.
3. **Tier 2** (warm-up coverage) — ✅ initial pass done; extend after Tier 0 trace.
4. **Tier 3** (present-window-first) — cheap perceived-startup win.
5. **Tier 4a** (daemon) — structural win for repeated launches; largest scope.

Each step is gated on a before/after entry in the Tier 0 timing table.

## Risks & trade-offs to track

- `cpu_target=native` / `filter_stdlibs` reduce portability / can drop a needed
  stdlib — always smoke-test the produced binary.
- `--strip-ir/--strip-metadata` degrades backtraces — acceptable for a shipped app.
- The daemon adds a lifecycle/IPC surface — design for idle-shutdown and clean
  reconnection.
