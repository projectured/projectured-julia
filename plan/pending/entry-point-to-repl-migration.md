# Entry points → REPL API

An inventory of every `main`-style entry point across **projectured-julia**,
**omnetpp-julia** and **inet-julia**: where it lives, what it is for, and what it
would take to delete it and reach the same functionality by calling a function
from the REPL.

Scope: anything that only works as `julia <file>.jl` — a `main()`, an
`if abspath(PROGRAM_FILE) == @__FILE__` guard, a top-level `ARGS` script, or a
shell wrapper around `julia -e`.

**Decision (agreed, not yet implemented).** Scripts that *open an editor* become
`Example`s in the owning `<Stem>Example` package, run by the existing gallery
verbs; the driven ones get a `WatchExample` wrapper that adds the one thing the
harness lacks — a background driver (§4.2.1). Scripts that *compute or report*
become ordinary exported functions with keyword arguments (§7). Progress is
tracked in §9.

---

## 1. Scoreboard

| Repo | Process-only entry points | Already REPL-native | Verdict |
|---|---|---|---|
| projectured-julia | 5 `.jl` + 1 `.sh` | the whole example/editor/test API | nearly done — only the build/bench edges are left |
| omnetpp-julia | 37 `.jl` + 1 `.sh` | tests only | the bulk of the work |
| inet-julia | 2 `.jl` | tests only | trivial |

**~44 files** total. Two of them are already broken (§6.3) and would be fixed by
the migration rather than in spite of it.

---

## 2. The target shape (it already exists)

projectured-julia has solved this once and the answer should be copied verbatim
into the other two repos. Three ingredients:

1. **A value that names the thing** — [Harness.jl:15](../../package/kernel/example/Harness.jl#L15)
   `struct Example(name, make_document, make_projection; …)`.
2. **Verbs over that value** — `run_example`, `print_example`,
   `write_example_image`, `write_example_pdf`, `record_example_video`
   ([Examples.jl:40](../../package/projectured/example/Examples.jl#L40)), each
   with a `run_example("json")` string-lookup method against a registry.
3. **A package that exports them** — `ProjecturedExample`, so `using
   ProjecturedExample; run_example("json")` is the entire interface.

Same pattern for the editor (`build_file_editor` / `run_file_editor` /
`warm_file_editor`), for building (`build_executable`) and for testing
(`test_json()`, `test_printer(ex)`, …). Every one of those is a function you can
call, tab-complete, pass keywords to, and compose — and none of them needs a
process boundary.

The harness is also *extensible by wrapping, not by growing*: `LiveExample`
([LiveExamples.jl:28](../../package/sdl/example/LiveExamples.jl#L28)) pairs an
`Example` with a scripted timeline instead of adding a timeline field to
`Example`. The `WatchExample` this plan introduces (§4.2.1) is the same move for
a background driver — a third member of that family, not a change to the first.

Everything below is measured against that bar.

---

## 3. projectured-julia

### 3.1 `package/executable/` — the compiled-binary edge

| Symbol | File | What it is for |
|---|---|---|
| `julia_main(args::Vector{String})::Cint` | [ProjecturedExecutable.jl:147](../../package/executable/main/ProjecturedExecutable.jl#L147) | Parses the binary's runtime args (`FILE`, `--backend`, `-h`, `-v`), resolves the domain from the file extension, calls `run_file_editor`. Returns a process exit code. |
| `julia_main()::Cint` | [ProjecturedExecutable.jl:183](../../package/executable/main/ProjecturedExecutable.jl#L183) | `ARGS` overload. **This is the PackageCompiler entry point** — `Builder.jl:225` names it in `executables = [spec.app_name => "julia_main"]`. |
| `main()` | [ProjecturedExecutable.jl:186](../../package/executable/main/ProjecturedExecutable.jl#L186) | Convenience alias so `julia ProjecturedExecutable.jl` works. |
| `PROGRAM_FILE` guard → `exit(main())` | [ProjecturedExecutable.jl:188](../../package/executable/main/ProjecturedExecutable.jl#L188) | Makes the module file self-executing. |
| `parse_runtime_args`, `resolve_backend`, `resolve_domain` | same file, 67–109 | The CLI surface; pure functions, already testable. |
| `print_help`, `print_version`, `precompile_warmup` | same file, 30/59/122 | Already exported and REPL-callable. |

**Removal.** `julia_main(::Vector{String})` and the no-arg overload **must stay** —
PackageCompiler resolves the app entry by that exact name and requires the `Cint`
return. What can go is the process-only sugar:

- Delete `main()` (line 186) and the guard (188–190). Nothing else references
  them; `Builder.jl` names `julia_main`, and `Precompile.jl` calls
  `precompile_warmup()` directly.
- The REPL equivalent already exists and is strictly better than `julia
  ProjecturedExecutable.jl foo.json`:

  ```julia
  using ProjecturedExample, ProjecturedSdl
  run_file_editor(:json; file="foo.json", backend=SdlBackend())
  ```

  `julia_main` is then *only* the exit-code/argv adapter that PackageCompiler
  needs, which is the honest description of it.

### 3.2 `package/executable/Build.jl` — a script that is a comment about a function

[Build.jl](../../package/executable/Build.jl) redirects stdout to `build.log`,
`Pkg.activate`s the app env, and calls `build_executable(; backends=[SdlBackend])`.
Its own docstring (lines 9–15) tells you to call `build_executable` from the REPL
instead. `regenerate.sh` is the same thing again in bash with a different spec.

**Removal.** Fold both into one exported function in `ProjecturedBuilder`:

```julia
build_executable(spec; logfile = joinpath(exe_dir, "build.log"))   # add the kwarg
```

so the redirect + activate + instantiate happen inside `build_executable` and the
two default specs become named constants:

```julia
using ProjecturedSdl, ProjecturedBuilder
build_executable(DEFAULT_JSON_APP)        # what Build.jl builds
build_executable(WORKBENCH_APP)           # what regenerate.sh builds
```

Delete `Build.jl` and `regenerate.sh`. (`ProjecturedBuilder` is currently a module
inside a loose `Builder.jl` that callers `include`; promoting it to a real
sub-package under `package/executable/` would let `using ProjecturedBuilder` work
without the `include` dance, and is a prerequisite for the above to be one line.)

### 3.3 `package/executable/main/Precompile.jl`

Three lines: `include("ProjecturedExecutable.jl")`, `using .ProjecturedExecutable`,
`precompile_warmup()`. PackageCompiler needs a *file path* for
`precompile_execution_file`, so this file has to exist as a file — but its body
should stay exactly one call into the already-REPL-callable
`precompile_warmup()`. **Nothing to remove**; it is already the right shape.

### 3.4 `bench/` — two benchmarks with no API

| Symbol | File | What it is for |
|---|---|---|
| `main()` + top-level call at :55 | [colorbench.jl:25](../../bench/colorbench.jl#L25) | Prints `isbits`/`sizeof` for four ways of representing a colour, to justify the selection-parameter design of `@document`. |
| `report(name)` + top-level `ARGS` loop at :87 | [fanout.jl:55](../../bench/fanout.jl#L55) | Walks a live example pipeline, forces every cell, and prints a cell-kind census plus the `dependents` fanout distribution attributed to `struct.field`. Backs the "immutable style cut fanout 21%" claim. |

`fanout.jl` is genuinely useful interactively — you want to run `report("json")`
then `report("workbench")` in one session and compare, which is exactly what a
script cannot do.

**Removal.** Make `bench/` a package (`ProjecturedBench`, dev-only, depending on
`ProjecturedExample`) exporting `colorbench()` and `fanout_report(name="workbench")`
(and `walk`, which is a reusable cell-tree walker worth having anyway). Delete
`main()`, the top-level call and the `ARGS` loop:

```julia
using ProjecturedBench
colorbench()
fanout_report("workbench"); fanout_report("json")
```

Cheaper interim step if a package is too much: drop the two trailing top-level
calls and rename `main` → `colorbench`. Then `include("bench/colorbench.jl");
colorbench()` works and the file stops running on load.

### 3.5 `package/adaptagrams/deps/build.jl` — **must stay a script**

[build.jl:88](../../package/adaptagrams/deps/build.jl#L88) `main()` + the
top-level call at :124. This is a `Pkg.build` hook: Pkg runs `deps/build.jl` as a
process, by convention, and there is no function-call form. Leave it. (Its
functionality *is* already reachable another way — `ProjecturedAdaptagrams.isavailable()`
is the runtime check — so nothing is hidden behind the script.)

---

## 4. omnetpp-julia

This is where nearly all the work is. Three families, and none of them is
reachable from a REPL today.

### 4.1 Simulator examples — 6 × identical `main`

`package/simulator/example/`

| File | Entry | What it models |
|---|---|---|
| [example.jl:295](../../../omnetpp-julia/package/simulator/example/example.jl#L295) | `main(; args=ARGS)` + guard :300 | Smallest end-to-end model: packet routing over a random graph, per-node hashes proving sequential and parallel runs execute in identical per-node order. |
| [routing_small.jl:126](../../../omnetpp-julia/package/simulator/example/routing_small.jl#L126) | `main(; args=ARGS)` + guard :131 | NTT backbone, 57 nodes — the OMNeT++ `routing` sample port. |
| [routing_campus.jl:192](../../../omnetpp-julia/package/simulator/example/routing_campus.jl#L192) | `main` + guard :197 | Three-tier campus: 2 core / 8 dist / 32 access / 640 hosts. |
| [routing_backbone.jl:147](../../../omnetpp-julia/package/simulator/example/routing_backbone.jl#L147) | `main` + guard :152 | 100-node Erdős–Rényi ISP backbone, 10/100 Gbps mix, 1–20 ms delays. |
| [routing_datacenter.jl:169](../../../omnetpp-julia/package/simulator/example/routing_datacenter.jl#L169) | `main` + guard :174 | k-ary fat-tree (Al-Fares); k=8 → 128 hosts / 208 nodes. |
| [routing_large.jl:127](../../../omnetpp-julia/package/simulator/example/routing_large.jl#L127) | `main` + guard :132 | 1000-node Erdős–Rényi stress case. |
| `routing.jl` | — | Shared library `include`d by the five `routing_*`; `App`/`Routing`/`L2Queue` + `build_ntt_network`. No entry point. |

Every one of the six `main`s is **byte-identical**:

```julia
function main(; args=ARGS)
    r = build_model(; args)
    run_model(r.model, r.mode; warmup_time=r.warmup_time, warmup_iters=r.warmup_iters,
              iters=r.iters, maxiter=r.maxiter)
end
```

So the real API — `build_model` / `run_model` — already exists. What the script
adds is only a hand-rolled `parse_args(args)` (a ~40-line `while` loop over a
`Dict{Symbol,Any}` of defaults, duplicated six times) and the guard.

`OmnetppSimulatorExample` ([src](../../../omnetpp-julia/package/simulator/example/src/OmnetppSimulatorExample.jl))
is already a package, but it exports only `script_path(name)` and `scripts()` —
*paths to the scripts*, not the functionality. Its own docstring concedes the
point: "Each is a standalone script rather than a registered `Example` object."

**Removal.**

1. Each `parse_args`'s defaults `Dict` becomes the keyword signature of a model
   builder — the defaults are already written down, they just live in a `Dict`
   instead of in the signature:

   ```julia
   routing_small_model(; n_nodes=57, send_ia_min=1e-4, send_ia_max=3e-4,
                         packet_length=32768, datarate_gbps=1.0, fib_n=20.0,
                         time_limit=1.0, seed=42, dest_addresses=1:50) = …
   ```

2. Each script's body moves into `OmnetppSimulatorExample` as one file per
   scenario, `include`d by the module rather than by each other.
3. `main` and the guard are deleted; the verb is the shared one:

   ```julia
   using OmnetppSimulatorExample
   run_scenario(:routing_small)                            # defaults
   run_scenario(:routing_small; mode=:par, n_nodes=200)     # was --mode par --nodes 200
   m = build_scenario(:routing_datacenter; k=16)            # inspect before running
   ```

4. `script_path`/`scripts` become a registry of scenario names —
   `scenarios()` returning `[:example, :routing_small, …]`.
5. The `--help` text in each `parse_args` becomes the function's docstring, so
   `?routing_small_model` replaces `julia routing_small.jl --help`.

Command-line use, if still wanted, is `julia --project=. -e 'using
OmnetppSimulatorExample; run_scenario(:routing_small; mode=:par)'` — or one small
generic `bin/run-scenario` dispatcher instead of six bespoke arg parsers.

### 4.2 Watch demos — 24 scripts, all guarded

`package/presentation/example/watch/`. Twelve headless self-tests and twelve SDL
demos, paired: `X.jl` builds the model + projection and self-tests it,
`X_sdl.jl` `include`s `X.jl` and opens a window.

| Script | Guard calls | What it demonstrates |
|---|---|---|
| `adaptive.jl` | `run_headless()` | `AdaptiveSearch` is opt-in — the strategy registers only once `BlackBoxOptim` is loaded. |
| `config_form_sdl.jl` | `run_form(ARGS[1] or "MM1KModel")` | The configuration form alone, no workflow chooser/catalog/scroll pane, so nothing can hide it. |
| `inspector.jl` / `inspector_sdl.jl` | `run_headless()` / `run_sdl()` | Instance + Execution inspector cards: bounded reflected shadow, one level per click. The acceptance test for bounded sync. |
| `mm1k.jl` / `mm1k_sdl.jl` | `run_headless()` / `run_sdl()` | An M/M/1/K queue on the real `SequentialSimulator`, watched live; kernel state *and* model state projected. |
| `optimization.jl` / `optimization_sdl.jl` | `run_headless()` / `run_sdl()` | `SimulationOptimization` panel: propose → evaluate → observe, stepped from the projection. |
| `parallel_sim_dashboard.jl` / `_sdl.jl` | `run_dashboard_headless()` / `run_sdl()` | Parallel-simulator dashboard: Speed/Utilization/Workers/Counters over a live parallel run, atomic pause. |
| `routing_topology.jl` / `_sdl.jl` | *(none — broken, §6.3)* / `run_sdl()` | Routing topology as a graph: one `WidgetTable` box per node, links as edges. |
| `sim_control.jl` / `sim_control_sdl.jl` | `run_headless()` / `run_sdl()` | `SequentialSimulator` control panel: progress bar / sim-time label / pause button, native sim + reactive shadow at ~10 fps. |
| `sim_dashboard.jl` / `sim_dashboard_sdl.jl` | `run_dashboard_headless()` / `run_sdl()` | Sequential statistics dashboard: status row + Speed/Utilization/Counters cards, `sample!`d periodically. |
| `sim_workbench.jl` / `sim_workbench_sdl.jl` | `run_headless()` / `run_sdl()` | `SimulationExecution` control bar; each button fires the named lifecycle operation. |
| `topology.jl` / `topology_sdl.jl` | `run_headless()` / `run_sdl()` | Topology card read from a *built instance* (`instantiate_simulation` + `model_topology`), not reconstructed. |
| `vectorplot_sdl.jl` | `run_sdl()` | Live line chart of an OMNeT++ vector result via `VectorResultToGraphics` — native primitives, no plotting library. |
| `workbench.jl` / `workbench_sdl.jl` | `run_headless()` / `run_sdl()` | The composite workbench: Type → Config → Runs → Instance → Result from one screen. |
| `workflow.jl` | `run_headless()` | Stage-dispatching projection — one dispatch entry per stage type, the replacement for the 485-line composite printer. |

**Why they can't just be moved.** These 24 files define, between them:

- `run_sdl` — **12 definitions**
- `run_headless` — **10 definitions**
- `content_projection` — **8 definitions**
- `run_dashboard_headless` — 2, `write_optimization_image` — **2 with different
  bodies** (`optimization_sdl.jl` and `workbench_sdl.jl`)

They only coexist because each runs in its own process at `Main` scope. Dropping
them all into one module as-is is a mass of method overwrites.

This looks like the biggest blocker but it is a symptom: nothing was forcing a
demo's functions to be named after the demo. Converting to `Example`s (§4.2.1)
removes it as a side effect — `Example("mm1k", make_mm1k_document,
make_mm1k_projection)` cannot be written without distinct names, which is what
projectured's `make_<name>_document_example` convention encodes. No submodules
or renaming pass needed as a separate step.

**Removal — they become `Example`s.** See §4.2.1.

### 4.2.1 Watch demos as `Example`s

Every `run_sdl` in `watch/` has the same seven-step body. Lining it up against
what the `Example` harness already provides:

| `run_sdl` step | Already provided by | Verdict |
|---|---|---|
| `sdl_display_size()` → default w/h | `run_example` core, [Gallery.jl:146](../../package/domain/example/Gallery.jl#L146) (`get_display_size(backend)`) | identical, and backend-agnostic |
| build the model document | — | ⇒ `Example.make_document` |
| `content_projection()` | — | ⇒ `Example.make_projection` |
| `WidgetScrollPane` wrap (mm1k) | `run_example(…; scrolling=true)` | identical |
| `WindowDocument` + `ScreenDocument` + window manager | `_multi_window_projection` / `shell_projection` | duplicated (see below) |
| `@async` driver task + `finally` teardown | — | **the only real gap** |
| `run_editor!` under `NullLogger` | `run_example` core | identical |

So the document/projection halves already exist as named functions in the
scripts — `content_projection()` is defined in 8 of them, and `build_run()`,
`demo_shadow()`, `ticker_instance()`, `build_parallel_demo()` are the document
makers. Converting is mostly *naming what is already there*.

**`shell_projection`/`run_shell!` are a re-implementation of `run_example`.**
[Shell.jl](../../../omnetpp-julia/package/presentation/main/src/widget/Shell.jl)'s
own header says so ("the way ProjecturEd's own `run_example` does it"), and
`OmnetppPresentation` already depends on `ProjecturedDomainExample`, so
`run_example(document, projection; name, scrolling, width, height, backend,
caching, profile, introspection, …)` — the `Example`-free core at
[Gallery.jl:107](../../package/domain/example/Gallery.jl#L107) — is importable
today. It is a superset of `run_shell!`. Eight scripts additionally define
`screen_projection(content) = shell_projection(content)`, a pure alias.

**The gap: a driver.** `run_example` has no equivalent of the `@async
drive!(native, shadow)` task, its `finally` teardown, or `run_shell!`'s
`on_frame` hook. `LiveExample` ([LiveExamples.jl:28](../../package/sdl/example/LiveExamples.jl#L28))
is the precedent for how to add one: it wraps an `Example` and pairs it with a
*timeline*, rather than growing `Example` itself. Do the same with a driver:

```julia
"""
    WatchExample(name, example, driver; on_frame=nothing, scrolling=false)

An `Example` paired with a background DRIVER — the thing that makes the document
change while the editor watches it. `driver` is a `document -> handle` thunk that
starts the work; `stop_driver!(handle)` winds it down when the window closes.
"""
struct WatchExample
    name::String
    example::Example
    driver              # document -> handle
    on_frame            # nothing, or a per-frame sync for DERIVED documents
    scrolling::Bool
end

function run_watch_example(w::WatchExample; kwargs...)
    document   = w.example.make_document()      # ALWAYS fresh — see the caution below
    projection = w.example.make_projection()
    handle = w.driver(document)
    try
        run_example(document, projection; name = w.name, scrolling = w.scrolling,
                    on_frame = w.on_frame, kwargs...)
    finally
        stop_driver!(handle)
    end
end
```

Then the REPL surface is the gallery's, verb for verb:

```julia
using OmnetppPresentationExample
watch_examples()                              # discover — impossible with scripts
run_watch_example("mm1k")                     # was: julia watch/mm1k_sdl.jl
run_watch_example("mm1k"; introspection=true) # free: a gallery flag the scripts never had
write_example_image(mm1k_example, "out.png")  # replaces 6 bespoke write_*_image helpers
print_example(topology_example)               # free
```

Static demos (`topology`, `routing_topology`, `config_form`, `workflow`) need no
driver at all — they are plain `Example`s and go straight into a registry.

**Three cautions.**

1. **`Example`'s constructor is eager.** [Harness.jl:41](../../package/kernel/example/Harness.jl#L41)
   calls `make_document()` and `make_projection()` and caches the results, so a
   module-level `const mm1k_example = Example(…)` builds a `SequentialSimulator`
   (with closures in its FES) at *precompile* time and shares that one instance
   across every session. Projectured's documents are pure data, so caching them
   is free; a simulator is stateful and re-running a cached, already-advanced one
   is wrong. `LiveExample` already sidesteps this — it never touches
   `ex.document`, calling `make_document()` fresh in both of its drivers
   ([LiveExamples.jl:92,116](../../package/sdl/example/LiveExamples.jl#L92)).
   `WatchExample` must do the same, and the registry should hold factories rather
   than constructed `Example`s for the heavy demos.
2. **This is also the fix for §6.1.** `Example("mm1k", make_mm1k_document,
   make_mm1k_projection)` forces a distinct name per factory by construction —
   which is exactly what projectured's `make_<name>_document_example` /
   `make_<name>_projection_example` convention is for. The 12 `run_sdl`s, 10
   `run_headless`es and 8 `content_projection`s collide only because nothing was
   forcing them to be named after their demo. No submodules needed.
3. **The headless siblings are tests, not examples.** The 12 `run_headless`
   bodies are `@assert` suites over the projection. In the projectured split,
   examples are *data* and tests are *functions over that data*
   (`test_printer(json_example)`). So they move to `OmnetppPresentationTest` as
   `test_watch_example(ex)` and get wired into `test_presentation()` — they
   currently never run in CI. That also removes the `X.jl` / `X_sdl.jl` file
   split, whose only purpose was keeping SDL out of the headless process.

**Which package.** No new one is needed. `OmnetppPresentationExample` is already
the `<Stem>Example` package the naming convention
([naming.md](../../package/kernel/doc/naming.md)) calls for — it just contains
`example_dir(name)`, a path helper, instead of examples. Optionally mirror
projectured's opt-in split (`ProjecturedSdlExample` hosts what needs a real
window, so the base example package precompiles with no native build): keep
documents + projections + static examples in `OmnetppPresentationExample`, and
put the driven `WatchExample`s in an `OmnetppPresentationSdlExample`. Worth doing
only if the BlackBoxOptim / Adaptagrams / SDL dependencies start hurting
precompile time — `OmnetppPresentationExample` depends on all three today.

**One small upstream change.** `run_example`'s core forwards only `mcp` to
`run_editor!` ([Gallery.jl:277](../../package/domain/example/Gallery.jl#L277));
`run_editor!` itself already accepts `on_frame`
([Editor.jl:301](../../package/kernel/main/editor/Editor.jl#L301)). Add the
`on_frame` passthrough — additive, and it is what lets the inspector/workbench
demos (whose documents are bounded reflections needing a per-frame sync) drop
`run_shell!` entirely.

**What this deletes:** 24 guards, 12 `run_sdl`s, 8 `screen_projection` aliases, 6
`write_*_image` helpers, 11 cross-file `include`s, and `Shell.jl`'s
`shell_projection` / `run_shell!` / `write_shell_image`.

### 4.3 Launcher and benchmark scripts

| File | Shape | Purpose | Removal |
|---|---|---|---|
| [package/legacy/example/run.jl](../../../omnetpp-julia/package/legacy/example/run.jl) | top-level `ARGS[1]` name, `ARGS[2]` backend, conditional `using` | Opens an `OmnetppLegacy` example (`ned`, `ini`, …) in SDL or Web. | Pure arg-plumbing over an API that already exists: `run_example(examples[idx]; backend=SdlBackend())`. Replace with an exported `run_legacy_example(name="ned"; backend=SdlBackend())` in `OmnetppLegacyExample`; delete the file. The conditional `using` becomes the caller's choice of which backend package to load — which is more honest than branching on a string. |
| [package/presentation/example/mm1k/run.jl](../../../omnetpp-julia/package/presentation/example/mm1k/run.jl) | top-level, deliberately | Loads `mm1k/root.json` via the doctype loader, composes `workbench_render_projection` + hover tracking, calls `run_shell!`. Comment says "written as a script (not a function) so the SDL event loop runs at top level". | The stated reason does not hold — `run_shell!` blocks the same way whether called from top level or from inside a function, and `run_example`/`run_file_editor` already prove it. Becomes `run_mm1k_project(; backend=SdlBackend())` on `OmnetppPresentationExample`. |
| [benchmark/benchmark.jl](../../../omnetpp-julia/benchmark/benchmark.jl) | top-level driver, `--seq-cache`/`--seq-save` | Sweeps `fib_n × n_packets`, emits CSV. **Broken** (§6.3). | `sweep_benchmark(; fib_n=…, n_packets=…, seq_cache=nothing)` returning a `DataFrame`/`Vector{NamedTuple}` — then the CSV write is the caller's, and the results are inspectable in the session instead of via a file round-trip. |
| [benchmark/compare_vec.jl:179](../../../omnetpp-julia/benchmark/compare_vec.jl#L179) | `main()` + call :208 | Compares two `.vec` files (OmnetppSimulator vs OMNeT++) with module-path and vector-name mapping + tolerance. | `compare_vec_files` already exists in `OmnetppSimulator`; this adds the C++-vs-Julia name mapping. Export `compare_reference_vec(left, right; tol=1e-9, max_diff=20)` returning the report. |
| [benchmark/lifecycle_throughput.jl:53](../../../omnetpp-julia/benchmark/lifecycle_throughput.jl#L53) | `main()` + guard :67 | Invariant-2 check for the lifecycle refactor: per-event throughput with recording off/on vs the reference `routing_large`. | `lifecycle_throughput()` returning the three measurements. Belongs next to the test suite, not in a script. |
| [benchmark/units_overhead.jl:56](../../../omnetpp-julia/benchmark/units_overhead.jl#L56) | `main()` + call :86 | Proves `SimTime`'s unit is erased before runtime — arithmetic + sort timings. | `units_overhead()`. Same treatment. |
| [benchmark/plot.jl](../../../omnetpp-julia/benchmark/plot.jl) | top-level, `ARGS[1]` CSV | Plots thread-scaling results. Depends on `Plots`/`GR`. | `plot_thread_scaling(csv=default_path)`. Note the `GR_jll` resolution problem with the SDL stack — this one wants CairoMakie if it is ever to live in the same environment as the rest. |
| [benchmark/bench_threads.sh](../../../omnetpp-julia/benchmark/bench_threads.sh) | bash | Runs `benchmark.jl` at `-t 1 2 4 6 8 10 12`, stitches the CSVs. | Cannot fully collapse — thread count is fixed at process start, so a sweep genuinely needs one process per `-t`. Keep it, but reduce it to a loop that calls `julia -t $T -e 'using OmnetppSimulatorBench; sweep_benchmark(…)'`, so the script owns *only* the thing that requires a process. |

`test/runtests.jl` is already correct: `using OmnetppUnitsTest; test_units()` etc.,
and its header documents the per-slice REPL invocations. It is the model the rest
of the repo should follow.

---

## 5. inet-julia

Almost nothing to do.

| File | Shape | Purpose | Removal |
|---|---|---|---|
| [package/linklayer/test/compare_t1s_vectors.jl](../../../inet-julia/package/linklayer/test/compare_t1s_vectors.jl) | shebang, `ARGS` length check, `exit(0/1)` | Compares two T1S `.vec` files with per-signal tolerance rules (deterministic signals `:exact`; RNG-driven `packetInterval` etc. `:count_within(2)`). Used to validate the Julia T1S port against the C++ INET run. | The rules `Dict` is the valuable part and it is currently trapped in a script. Move to `InetLinkLayerTest` as `t1s_vector_rules()` + `compare_t1s_vectors(left, right)` returning the report; the printing and `exit` become the caller's. A reference comparison already runs in `test_linklayer()` (phase 8) *without* the rules — and the rules as written never matched a real signal name (see P1). |
| [package/packet/example/packet_api_demo.jl](../../../inet-julia/package/packet/example/packet_api_demo.jl) | top-level, prints | Worked tour of the packet/chunk API — `@header Ipv4Header`, tags, `peek`, the R9 guard. | Wrap in `packet_api_demo()` exported from `InetPacketExample`; delete the top-level statements. Same registry treatment as omnetpp: `script_path`/`scripts` → `demos()` / `run_demo(:packet_api)`. |

`test/runtests.jl` is already REPL-native, with the same per-component header as
omnetpp's.

---

## 6. Cross-cutting blockers

### 6.1 Name collisions (omnetpp watch only)

Counted above: `run_sdl` ×12, `run_headless` ×10, `content_projection` ×8,
`write_optimization_image` ×2 with different bodies. Any plan that flattens these
24 files into one namespace *as they are* fails.

**Resolved by the `Example` conversion, not by a separate step.** Writing
`Example("mm1k", make_mm1k_document, make_mm1k_projection)` forces a distinct name
per factory, which is exactly what projectured's
`make_<name>_document_example` convention encodes. The collisions exist only
because nothing was forcing a demo's functions to be named after the demo. No
submodules, no standalone renaming pass (§4.2.1, caution 2).

### 6.2 `include` chains between entry points

- Each `*_sdl.jl` `include`s its headless sibling (11 pairs).
- Each `routing_*.jl` `include`s `routing.jl`.
- `benchmark/benchmark.jl` and `watch/routing_topology.jl` `include` across
  directory boundaries.

These are `include`-at-`Main` dependencies standing in for module imports. Every
one becomes a normal `using`/function call once the code lives in a package, and
that removes the load-order fragility along with the scripts.

### 6.3 Two entry points are already broken

- [watch/routing_topology.jl:23](../../../omnetpp-julia/package/presentation/example/watch/routing_topology.jl#L23) —
  `include(joinpath(@__DIR__, "..", "examples", "routing.jl"))`. No
  `package/presentation/examples/` directory exists; the routing example lives at
  `package/simulator/example/routing.jl`. The file cannot load.
- [benchmark/benchmark.jl:2](../../../omnetpp-julia/benchmark/benchmark.jl#L2) —
  `include(joinpath(@__DIR__, "..", "examples", "example.jl"))`. No top-level
  `examples/` directory either. Same failure.

Both are the 3-slice reorganisation's leftovers. A script can rot like this
silently for months; a function in a package fails at precompile the day the path
moves. That is most of the argument for this migration on its own.

### 6.4 Stale documented invocation

**22 of the 24** watch scripts document themselves as
`julia --project=watch watch/<name>.jl`. There is no `watch/Project.toml` — the
environment is `package/presentation/example`. Every one of those header comments
is wrong today. Docstrings on real functions do not have this failure mode,
because the invocation *is* the function name.

### 6.5 Argument parsing duplicated

Six hand-rolled `parse_args(args)` loops in the simulator examples, each ~40 lines
over a `Dict{Symbol,Any}` of defaults, each with its own `--help` block. All six
are keyword arguments wearing a costume. Julia's keyword defaults already provide
the defaults, the help (via docstrings) and the validation (via types).

---

## 7. Mechanical recipe

Two shapes, decided by one question: **does the script open an editor?**

### 7a. It opens an editor → it becomes an `Example`

1. **Delete the guard** and any bare top-level call.
2. **Split the body at the seam the harness already has.** The document-building
   part becomes `make_<name>_document`; the projection-building part becomes
   `make_<name>_projection` (in 8 of the 24 watch scripts this is literally the
   existing `content_projection`, renamed). Naming them after the demo is what
   dissolves the collisions (§6.1).
3. **Throw away the window/screen/editor plumbing.** `WindowDocument` +
   `ScreenDocument` + window manager + `sdl_display_size` + `NullLogger` +
   `run_editor!` are all `run_example`'s job. A `WidgetScrollPane` wrap is
   `scrolling=true`.
4. **If the document changes on its own, wrap it in a `WatchExample`** with the
   `@async` task as its `driver` and the teardown as `stop_driver!`. If it
   doesn't, it is a plain `Example`.
5. **Register it** in the package's `examples` / `watch_examples` list.
6. **Move the `@assert`s to the `*Test` package** as a function over the example.

### 7b. It computes or reports → it becomes a function

1. **Delete the guard** and any bare top-level call.
2. **Name the verb** after what it does (`colorbench`, `lifecycle_throughput`,
   `sweep_benchmark`) — not `main`.
3. **Turn `ARGS` into keywords.** Every `parse_args` default becomes a keyword
   default; every `--flag` becomes a keyword name; the `--help` text becomes the
   docstring.
4. **Return, don't just print.** Return the model / report / measurements; keep
   printing behind `verbose=true` or a `show` method. This is what makes it
   composable at the REPL rather than a prettier script.
5. **Move the file into the owning `*Example` / `*Test` / `*Bench` package** and
   `include` it from the module.
6. **Export the verb, register the name** so it is discoverable — `scenarios()`
   is the thing `ls example/` was standing in for.

### Both

**Replace path helpers with the registry.** `script_path`, `scripts` and
`example_dir` exist only because the functionality lived in files; delete them
once it doesn't.

## 8. What stays a script

- `package/adaptagrams/deps/build.jl` — Pkg's build hook is a process by contract.
- `package/executable/main/Precompile.jl` — PackageCompiler wants a file path;
  its body is already a single call.
- `julia_main` in `ProjecturedExecutable.jl` — the compiled binary's argv/exit-code
  adapter. Keep the two `julia_main` methods, drop `main()` and the guard.
- `benchmark/bench_threads.sh` — `-t N` is fixed at process start, so a
  thread-count sweep genuinely needs N processes. Reduce it to a `julia -t $T -e`
  loop.

Everything else on this list can be a function.

## 9. Steps

One commit per checked box. Ordered so the cheap, collision-free repos establish
the registry shape before the big one.

### P1 — inet-julia (2 files) · recipe 7b — **DONE** (`inet-julia@entry-point-repl-api`)

- [x] `compare_t1s_vectors.jl` → `t1s_vector_rules()` + `compare_t1s_vectors(left, right)`
      on `InetLinkLayerTest`, returning the report; printing moved to
      `print_t1s_comparison`, `exit` dropped. New file `T1sVectorComparison.jl`.
- [x] Cover the rules table in `test_linklayer()` (9 new assertions).
      **Correction to this plan:** the claim that the comparison "has never run
      in CI" was wrong — `phase8_compare_harness.jl` already diffs a `notraffic`
      run against `inet-reference/notraffic.vec`. What never ran was the *rules
      table*: it keys on bare signal names, but a recorded vector is named
      `<signal>:<mode>` (`curID:vector`), so the expansion matched nothing and
      every signal silently fell back to `:exact`. Rules now key on the base
      name via `signal_base_name`; phase 8's own assertion is untouched.
- [x] `packet_api_demo.jl` → `packet_api_demo(; io, receivers, payload_bytes)`
      returning `(; packet, copies)`. Header/tag declarations stay at module
      level — `@header` defines a struct.
- [x] Replace `script_path`/`scripts` with `DEMOS` / `demos()` / `run_demo(name)`.
      Nothing referenced the path helpers.
- [x] `broadcast` → `broadcast_packet`: shadowing `Base.broadcast` is harmless at
      `Main` scope in a script, not in a package that exports it.
- [x] Verified: linklayer 414 → 423 pass (exactly the new assertions), full
      `test/runtests.jl` 2317 pass, 0 failures.

### P2 — projectured-julia build + bench (4 files) · recipe 7b — **DONE**

- [x] `ProjecturedBuilder` promoted to a package at `package/executable/builder/`,
      added to the root environment. `using ProjecturedSdl, ProjecturedBuilder`
      is now the whole setup.
- [x] `logfile` kwarg on `build_executable` (default `nothing` — an interactive
      caller should see the output; the scripts hard-coded a redirect).
- [x] Named specs — **as functions, not constants**: `default_json_app(backend)`
      and `workbench_app(backend)`. A constant would have to name `SdlBackend`,
      making the builder depend on ProjecturedSdl and undoing the reflection
      design that keeps it backend-agnostic.
- [x] Two fixes the move forced: `exe_dir` defaulted to `@__DIR__`, now one level
      deeper → `EXECUTABLE_DIR`; and the compile's `Pkg.activate` used to strand
      the caller's REPL in the app environment → previous project restored in a
      `finally`.
- [x] Delete `Build.jl` and `regenerate.sh`; README rewritten.
- [x] `bench/` → `ProjecturedBench` with `colorbench()`, `fanout_report(name)`,
      `walk_cells` (not `walk` — ambiguous next to the kernel's `walk_document`
      once it is an export). Both now return their measurements as well as
      printing.
- [x] **Bit-rot found and fixed:** `fanout.jl` read `length(cell.dependents)`, but
      that field became `Union{Nothing,Vector{WeakRef}}` allocated on demand, so
      it threw `MethodError` on any example with an unread cell. Nothing ran it,
      so nothing caught it.
- [x] Verified: `workbench_app(SdlBackend)` generates the same `AppConfig.jl` as
      `regenerate.sh`'s spec; active project survives the call; `colorbench()`
      output unchanged; workbench max fanout still 104.

### P3 — projectured-julia executable (3 lines) · recipe 7b — **DONE**

- [x] Deleted `main()`, the `PROGRAM_FILE` guard, and `main` from the export list.
      Both `julia_main` methods kept — PackageCompiler resolves the app entry by
      that name (§8). Verified `--help`/`-v` → 0, unknown flag → 1 with usage.

### P4 — omnetpp-julia simulator examples (6 files) · recipe 7b

- [ ] Turn each `parse_args` defaults `Dict` into a keyword signature on a
      `<scenario>_model(; …)` builder; the `--help` block becomes its docstring.
- [ ] Move the six scenario bodies into `OmnetppSimulatorExample`, `include`d by
      the module rather than by each other.
- [ ] Add `scenarios()` / `build_scenario(name; …)` / `run_scenario(name; …)`;
      delete the six `main`s, guards and `script_path`/`scripts`.

### P5 — omnetpp-julia benchmarks + launchers (7 files) · recipe 7b

- [ ] `benchmark.jl` → `sweep_benchmark(; …)` returning rows; repoint its stale
      `../examples/example.jl` include (§6.3).
- [ ] `compare_vec.jl` → `compare_reference_vec(left, right; tol, max_diff)`.
- [ ] `lifecycle_throughput.jl` → `lifecycle_throughput()`; `units_overhead.jl` →
      `units_overhead()`.
- [ ] `plot.jl` → `plot_thread_scaling(csv)`; move off `Plots`/GR to CairoMakie if
      it is to share an environment with the SDL stack.
- [ ] Reduce `bench_threads.sh` to a `julia -t $T -e '…'` loop (§8).
- [ ] `legacy/example/run.jl` → `run_legacy_example(name="ned"; backend)`.

### P6 — omnetpp-julia watch demos (24 files) · recipe 7a

- [ ] **Upstream, additive:** forward `on_frame` from `run_example`'s core to
      `run_editor!`, which already accepts it (§4.2.1).
- [ ] Define `WatchExample`, `run_watch_example`, `stop_driver!` and the
      `watch_examples` registry in `OmnetppPresentationExample`.
- [ ] Convert the `mm1k` pair as the reference conversion: document maker,
      projection maker, driver; assertions to `OmnetppPresentationTest`.
- [ ] Convert the 4 static demos (`topology`, `routing_topology`, `config_form`,
      `workflow`) — plain `Example`s, no driver. Repoint `routing_topology.jl`'s
      stale include at `package/simulator/example/routing.jl` (§6.3).
- [ ] Convert the remaining 7 driven demos.
- [ ] `mm1k/run.jl` → `run_mm1k_project(; backend)`.
- [ ] Wire every converted example's assertions into `test_presentation()`.
- [ ] Delete `Shell.jl` (`shell_projection` / `run_shell!` / `write_shell_image`)
      once nothing imports them.
- [ ] Fix the 22 stale `--project=watch` header comments by deleting them — the
      docstring on the registered example replaces them (§6.4).

### Verification

- [ ] `julia --project=. test/runtests.jl` green in each repo (omnetpp needs `-t 4`).
- [ ] Every registry enumerable and every entry runnable: `run_scenario.(scenarios())`
      headless, `watch_examples()` spot-checked in a window.
- [ ] `grep -rn 'PROGRAM_FILE\|^function main\|^main()' --include=*.jl` returns only
      the four §8 survivors.
