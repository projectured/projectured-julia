# The editor survives a fault

> **Kind:** plan · **Status:** pending · **Written:** 2026-09-18
> **Stands on:** [architecture-invariants.md](../../documentation/rule/architecture-invariants.md),
> [projection-system.md](../../documentation/package/kernel/projection-system.md),
> [editor.md](../../documentation/package/kernel/editor.md),
> [devices-and-backends.md](../../documentation/package/kernel/devices-and-backends.md)

Make ProjecturEd error tolerant. A fault in a printer, in a reader, in an
operation, in a backend or in a tool must not stop the editor. The fault must
appear where a person can see it, and the editor must continue.

## 1. What the editor does today

The whole read-evaluate-print loop runs with one barrier, and that barrier
recognises one exception:

```julia
# source/kernel/editor/EditorModule.jl:365-383
try
    while true
        with_performance_counters() do
            set_clock_time!(editor.clock, Base.time() - t_start)
            drain_operations!(editor)
            run_frame!(editor)
            perf!(editor)
        end
        sleep(0.01)
    end
catch e
    e isa QuitEditorException || rethrow()
```

Every other exception ends the loop and the process. `run_frame!`
(`EditorModule.jl:318-328`) calls `read!`, `evaluate!` and `print!` with no
barrier of its own. `print!` (`EditorModule.jl:254-261`) hands
`editor.iomap.output` to `write_to_devices`, and a backend method that throws
throws through the loop. The backend seam has no catch-all method by design, so
a backend that lacks a method raises a bare `MethodError`
(`source/kernel/backend/BackendInterface.jl:39-41`).

Three barriers exist above the loop, and all three are in the assistant path:
the agent turn task (`source/assistant/AssistantTurn.jl:228-244`), one per tool
call (`source/kernel/agent/AgentLoop.jl:69-80`), and `execute_julia_code`
(`source/kernel/tool/CodeExecution.jl:199-201`). Each turns an exception into
text. None of them protects the document, and none of them writes to a place a
person reads while an editor runs without an assistant.

Elsewhere the code catches 138 times in 65 files. The dominant form is a bare
`catch` that answers a default value. There is no common exception supertype,
no fault record, no fault log, no sound and no policy. `WorkbenchConsole`
(`source/workbench/WorkbenchDocument.jl:77-96`) and `WidgetStatusBar` exist as
chrome, and nothing writes to either.

## 2. The rule this plan follows

A fault is reported at the first tier that works. Each tier can fail, and a
failure falls to the next tier.

| tier | where | who reports it |
| --- | --- | --- |
| 1 | in the output document, at the place that failed | `FaultCatchingProjection` substitutes a mark |
| 2 | in the message log on the screen | `FaultLogOverlayProjection` reads the `FaultLog` |
| 3 | on the console | `report_fault!` calls `@error` |
| 4 | a sound | `report_fault!` calls `play_fault_sound!(backend)` |
| 5 | nothing | `report_fault!` returns |

Tier 5 can not fail. `report_fault!` is the one function in the system that
must never throw, and a test asserts it.

## 3. The design

### 3.1 Five barriers, each with one job

| barrier | where it sits | what it does when it catches |
| --- | --- | --- |
| frame | `run_editor!`, around each stage of `run_frame!` | records the fault, skips the stage, keeps the loop |
| device | each `Backend` seam call | records the fault, counts it, degrades the backend after a limit |
| projection | `FaultCatchingProjection`, inside the pipeline | substitutes a mark for the node that failed |
| operation | `evaluate!` and `drain_operations!` | records the fault, repairs the editor state |
| tool | the MCP wire handler and the agent loop | answers the caller an error text, records the fault |

The frame barrier, the device barrier and the operation barrier live in the
kernel and are always compiled in. The projection barrier is opt-in: an author
adds it to a pipeline, exactly as `GestureLogRecordingProjection` is added
today. The tool barrier is a small local change in `source/mcp/Mcp.jl`.

### 3.2 The purity problem, and the two-stage store

This is the point that decides the whole design.

A printer does not throw when `print_document` runs. It throws later, when the
renderer reads the reactive output cell — `print!` calls `print_document` once
and reads `editor.iomap.output` every frame. So the barrier must sit inside the
thunk that derives the output, not only around the one-time call.

A thunk must not write a cell (`PAR-NO-WRITE-IN-THUNK`) and must be pure
(`PAR-PURE-THUNK`). A fault log is a document made of cells. So the thunk can
not write the log.

The answer is two stages:

1. **The thunk writes a `FaultStore`.** The store is a plain object outside the
   reactive graph. It has no dependents, so a write to it can not invalidate
   anything in the middle of a computation, which is exactly what
   `PAR-NO-WRITE-IN-THUNK` protects. The write is keyed by fault identity and
   is idempotent, so a thunk that runs ten times leaves one record. The cached
   result of the thunk does not depend on the store, so the cache stays correct.
2. **The editor loop drains the store once per frame**, before `read!`. The
   drain calls `append_fault!(target, record)` for each target the store holds.
   That call runs on the editor task, outside any thunk, so it can write the
   log document.

The drain writes only records that it did not drain before. When no new fault
appears, no cell changes, nothing is invalidated and nothing repaints. This is
what stops a fault that repeats every frame from turning into a busy loop.

This carve-out needs a paragraph in `PAR-PURE-THUNK` and in
`PAR-NO-WRITE-IN-THUNK`. `PAR-PER-EDITOR-STATE` already carries a carve-out
paragraph of the same shape, so the form exists.

### 3.3 The substitute is what stops the cascade

`FaultCatchingProjection` takes a `substitute` projection. Give it one at every
stage. It is not a decoration, and the two reasons it exists are the two ways a
fault otherwise spreads.

```julia
FaultCatchingProjection(inner = JsonToSyntax(), substitute = FaultToSyntax())
```

The barrier prints the `FaultReport` through the substitute, so its output is an
ordinary document of the output domain — `FaultToSyntax` answers a `SyntaxLeaf`.
No domain type dispatcher changes, and no domain package learns a new type.

**Without a substitute the fault spreads down the chain.** The output is a bare
`FaultReport`, the next stage does not know that type, throws, and its own
barrier fires. Four stages make four records for one root cause. That is bounded
and it is survivable, but it is the degraded path, not the design.

**Without a substitute the fault also spreads out to the siblings, which is
worse.** A parent printer often reads its child's output: it measures a width,
it counts a length. A parent handed a `FaultReport` throws in its *own* thunk,
its barrier fires, and one mark then replaces the whole parent subtree. The
substitute keeps the child's output a real document that the parent can measure,
so containment stays at the one node that failed.

**Do not depend on the throw downstream.** A stage whose type dispatcher ends in
an `Any` entry does not throw on a `FaultReport`. It prints something wrong, and
it does so quietly. Which stages carry an `Any` entry is a thing to check in
Phase 5, not a thing to assume.

So the scale of the report stays small, and it stays small in both directions:

| what happened | records |
| --- | --- |
| one node fails, substitute given | 1 |
| one node fails, no substitute, four stages | 4 |
| one bug fails at 3000 nodes, substitute given | 1, count 3000 |
| one bug fails at 3000 nodes, no substitute | 4, each count 3000 |

The second column is records, not marks. The document still carries one mark per
node that failed, because each mark is a value in that node's own cell. Only the
log groups, and section 4.1 says what the key must hold for the grouping to
work.

The mark keeps its slot in the parent. The barrier wraps the recursion entry,
so its output is what the parent puts in its child vector, and the parent's
layout still places it. One node fails; the rest of the tree draws.

**When the mark itself fails, the barrier re-raises.** If the substitute throws,
the re-entrancy guard stops the recursion, but the thunk must still answer a
value and there is none it can trust. So the barrier gives up on that node and
lets the exception reach the frame barrier, which skips the print for that frame
and reports on the console. The screen keeps the frame before it. That repeats
every frame, so the print-failure counter reaches its limit and the safe mode of
section 3.4 takes over. The loop terminates on machinery this plan already has.

A node that failed is inert: its `map_reference_forward` and
`map_reference_backward` answer `nothing`, and its `read_intent` declines. A
person can not edit a mark, and the selection does not walk into it.

### 3.4 What the editor does to heal itself

A barrier that only swallows leaves a broken editor running. Four repairs cost
little and fix the common cases. The first one is new since the plan was
written, and section 9 says why.

0. **After an operation fault, take the operation back.** Call
   `make_inverse_operation(editor.document, operation)` **before**
   `evaluate_operation`, and apply the answer when the evaluation throws. An
   inverse reads the state the change starts from, so it must be taken first.
   `nothing` is a truthful answer and not an error: the barrier then falls to
   repair 1 and records that the document can be inconsistent.
1. **After an operation fault, re-print from scratch.** Call
   `invalidate_projection!(editor)`. A half-applied operation often leaves the
   reactive graph inconsistent, and a fresh `print_document` rebuilds it.
2. **After an operation fault, repair the selection.** When
   `is_valid_reference(editor.document, get_selection(editor.document))` is
   false, clear the selection to the root. A selection that points at a deleted
   node is the most common cause of a printer fault that then repeats every
   frame.
3. **After the print barrier fires N times in a row, enter the safe mode.**
   Swap `editor.projection` for a `ConstantProjection` that shows the fault log
   alone. The editor then always shows something, and at worst it shows the
   list of faults with a line that says how to leave the safe mode.

**A `CompoundOperation` still gets no rollback.** Its way back is built member
by member, because the inverse of the second member depends on what the first
member did, and only `evaluate_invertible_operation!` does that interleave
(`source/kernel/operation/Inversion.jl`). The barrier sits outside `evaluate!`
and does not take an operation apart, so `make_inverse_operation` answers
`nothing` for a compound and the barrier falls to repair 1. Every other
operation type rolls back. A barrier that interleaves is the follow-on, and it
belongs with the undo slice rather than here.

### 3.5 The device barrier is a circuit breaker

A backend that throws in `write_to_devices` throws again on the next frame, 100
times a second. So the device barrier counts consecutive failures per seam
function. At the limit it marks that seam degraded and stops calling it.
`read_from_devices` keeps running so the person can still quit, and the sound
plays once when a seam degrades, not once per frame.

## 4. The new code

### 4.1 Kernel layer `fault`

**The fault layer is layer 1, and it comes before `cell`.** The kernel then has
eighteen layers. The layer hard-references nothing above `Base`: `FaultRecord`
holds an `Exception`, a `String` and a `Float64`, its `reference` field is
`Any`, and the store is deliberately not a cell. So the lowest position is open,
and the lowest position is the right one — every layer above can report,
including `cell`, `device`, `gesture` and `backend`, none of which can report
today.

The one thing that looked like it forced the layer upward was the sound, which
seemed to need the `Backend` type. It does not. `play_fault_sound!` is a
bodiless generic with a default method on `Any`, so the fault layer names no
backend and a backend package adds its own method later.

| file | what it declares |
| --- | --- |
| `source/kernel/fault/FaultLayer.jl` | the ordered includes |
| `source/kernel/fault/FaultModule.jl` | the module head and its exports |
| `source/kernel/fault/FaultInterface.jl` | the two seams: `play_fault_sound!`, `append_fault!` |
| `source/kernel/fault/FaultDefaults.jl` | the `Any` default of each seam |
| `source/kernel/fault/FaultRecord.jl` | `FaultRecord`, `make_fault_record`, `compute_fault_key` |
| `source/kernel/fault/FaultStore.jl` | `FaultStore`, `record_fault!`, `drain_faults!`, `attach_fault_target!`, `get_consecutive_fault_count` |
| `source/kernel/fault/FaultPolicy.jl` | `FaultPolicy` |
| `source/kernel/fault/FaultBarrier.jl` | `run_fault_barrier` |
| `source/kernel/fault/FaultCascade.jl` | `report_fault!` and the five tiers |

The file split follows the backend layer, which is the kernel's model for a
seam: `BackendInterface.jl` declares and `BackendDefaults.jl` answers, because
`PAR-INTERFACE-DECLARES-ONLY` says an interface file never implements.

`FaultRecord` is a plain immutable struct and not a `Document`, so the kernel
keeps its rule of zero concrete documents.

```julia
struct FaultRecord
    key::UInt64            # site, projection type, exception type, message — NOT the reference
    site::Symbol           # :print, :read, :evaluate, :map, :device, :tool
    projection_type::Symbol
    exception_type::Symbol
    message::String        # formatted once, when the key is new
    traceback::String      # the first N frames, truncated
    first_reference::Any   # the first place it happened, as an example
    first_time::Float64
    count::Int             # how many places, or how many times
end
```

**Found while it was written:** the bucket rule must compare against the count
that was last **queued**, not the one that was last drained. Comparing against
the drained count re-queues the key on every occurrence above the first bucket,
so three thousand failures queue 2,991 log writes instead of four. The store
keeps `queued_counts` for exactly this.

**The key must not hold the reference, and that decision carries the design.**
The chain bounds how far a fault spreads downward — four stages at most. Nothing
bounds how far it spreads sideways. One bug in one stage fails at every leaf of
one kind, which in a large document is thousands of nodes. With the reference in
the key those are thousands of distinct keys, the store fills at its cap of 64,
and the log shows 64 near-identical lines and a count of what it dropped. That
report is useless.

Without the reference in the key they collapse into one record with `count =
3000` and one reference kept as an example. The log then reads `SyntaxToText:
BoundsError, 3000 places, first at obj.items[4].value`, which is the line a
person can act on.

Nothing is lost by the grouping, because the two surfaces answer two questions.
The document shows **where**: one mark per node, because each mark is a value in
that node's own cell. The log shows **what** and **how many**.

The count grows per thunk run, not per frame. A thunk caches the mark it
answers, so the three thousand catches happen once and not a hundred times a
second.

`FaultStore` is bounded. It keeps at most `capacity` distinct keys, counts what
it drops, and holds the targets the drain feeds:

```julia
mutable struct FaultStore
    records::Dict{UInt64, FaultRecord}
    order::Vector{UInt64}
    undrained::Vector{UInt64}
    targets::Vector{Any}
    capacity::Int          # 64 by default
    dropped::Int
end
```

The two seams keep the kernel ignorant of everything above it.
`append_fault!(target, record)` answers nothing by default, and
`ProjecturedFault` answers it for `FaultLog`, so the kernel never names the log.
`play_fault_sound!(backend)` writes the BEL character to the stream the logger
captured at start, and a backend package can answer it with real audio.

`FaultPolicy` is per editor, and the field that matters most is the first:

```julia
struct FaultPolicy
    is_barrier_enabled::Bool          # false under test — a throw must fail a test
    is_console_enabled::Bool
    is_sound_enabled::Bool
    device_failure_limit::Int      # 8
    print_failure_limit::Int       # 4, then the safe mode
end
```

`run_fault_barrier` re-raises the exceptions that must never be caught:
`QuitEditorException`, `InterruptException`, `StackOverflowError` and
`OutOfMemoryError`. It also holds the re-entrancy guard: a fault raised while a
fault is reported goes straight to tier 3, so the machinery can not recurse.

### 4.2 Substrate package `ProjecturedFault`

The shape copies `ProjecturedGestureLog` one to one, and that package is
proven. Its dependency set is the same: Kernel, Collection, Graphics,
Projection, Style, Syntax, Text.

The module is `FaultViewModule`, not `FaultModule`. Both slices are named
`fault`, so both would otherwise declare the same module name. The kernel's
`ProjectionModule` against the substrate's `ProjectionAlgebraModule` settles the
form: the kernel takes the plain name, and the substrate takes a qualifier. The
qualifier is honest here — the kernel records a fault, and this package shows
one.

| file | what it declares |
| --- | --- |
| `source/fault/FaultViewModule.jl` | the module head |
| `source/fault/FaultDocument.jl` | `FaultReport`, `FaultLog`, `FaultLogEntry`, `append_fault!`, `clear_fault_log!` |
| `source/fault/Catching.jl` | `FaultCatchingProjection`, `FaultCatchingIoMap` |
| `source/fault/FaultToSyntax.jl` | one `FaultReport` as a red syntax leaf |
| `source/fault/FaultToWidget.jl` | one `FaultReport` as a small alert widget |
| `source/fault/FaultToText.jl` | one `FaultReport` as a text row |
| `source/fault/FaultToGraphics.jl` | one `FaultReport` as a red box, the last resort of the chain |
| `source/fault/FaultLogOverlay.jl` | `FaultLogOverlayProjection`, the panel |
| `source/fault/FaultLogToSyntax.jl` | the log as a document a person can open |

The printer of the barrier, which is the part that carries the design:

```julia
function print_document(p::FaultCatchingProjection, recursion, input, ctx)
    store = get_property(ctx, :fault_store, nothing)
    reference = ctx.reference
    inner = nothing
    early = nothing                    # a fault raised while the child built its IoMap
    try
        inner = print_document(p.inner, recursion, input, ctx)
    catch exception
        early = make_fault_record(:print, p.inner, reference, exception, catch_backtrace())
        record_fault!(store, early)
    end
    guarded = ComputedCell() do
        early === nothing || return (output = _print_fault_mark(p, early, ctx), fault = early)
        try
            (output = inner.output, fault = nothing)
        catch exception
            late = make_fault_record(:print, p.inner, reference, exception, catch_backtrace())
            record_fault!(store, late)  # the carve-out of section 3.2
            (output = _print_fault_mark(p, late, ctx), fault = late)
        end
    end
    FaultCatchingIoMap(p, input,
                       ComputedCell(() -> guarded[].output),
                       inner, store,
                       ComputedCell(() -> guarded[].fault))
end
```

`_print_fault_mark` calls `print_document(p.substitute, p.substitute, record,
ctx)` inside the thunk. `SqlSubqueryFromItemToSyntaxNode`
(`source/sql/SqlToSyntax.jl:106-109`) already builds a child IoMap inside a
thunk, so the pattern is accepted.

**Both calls to `_print_fault_mark` sit outside the `try`, and that is
deliberate.** A throw from the mark itself is not caught again. It leaves the
thunk and reaches the frame barrier, which is the re-raise of section 3.3. Do
not wrap these two calls in a second `try` while the code is written: a barrier
that can not fail is a barrier that can lie.

The reader declines instead of throwing:

```julia
function read_intent(p::FaultCatchingProjection, recursion, change::Intent,
                     iomap::FaultCatchingIoMap)
    iomap.inner_iomap === nothing && return Intent(change.gesture, nothing)
    try
        read_intent(p.inner, recursion, change, iomap.inner_iomap)
    catch exception
        record_fault!(iomap.store,
                      make_fault_record(:read, p.inner, nothing, exception, catch_backtrace()))
        Intent(change.gesture, nothing)
    end
end
```

Both mappers answer `nothing` when they catch, which is the existing contract
for "there is no image".

### 4.3 How an author turns it on

One line per recursion point and one line per chain step:

```julia
function make_json_projection_example(; measure = measure_truetype_text)
    ChainingProjection(
        RecursiveProjection(FaultCatchingProjection(inner = JsonToSyntax(),
                                                    substitute = FaultToSyntax())),
        RecursiveProjection(FaultCatchingProjection(inner = SyntaxToText(),
                                                    substitute = FaultToText())),
        FaultCatchingProjection(inner = TextToGraphics(measure = measure),
                                substitute = FaultToGraphics()),
    )
end
```

Every stage carries a `substitute`, and the last one carries it too. The last
stage answers the backend, so a bare `FaultReport` there reaches no barrier at
all. `FaultToGraphics` is therefore a fourth renderer, beside `FaultToSyntax`,
`FaultToText` and `FaultToWidget`, and Phase 5 writes all four.

And one line at the root for the panel, beside the gesture log panel that is
already there:

```julia
FaultLogOverlayProjection(inner = root, log = fault_log)
```

## 5. The phases

### Phase 1 — Add the `fault` layer to the kernel ✅ DONE

1. Write the nine files of section 4.1.
2. Add the include line as the **first** of the list in
   `package/ProjecturedKernel/src/ProjecturedKernel.jl`, renumber the comment
   of every layer below it, and change the count in its header comment from
   seventeen to eighteen. This file is sealed; the user gave permission on
   2026-09-18.
3. Add the layer to the static guard and to the inventory in `SEALING.md`.
   `test_kernel_layering()` is green: 10 pass, 0 fail.
4. Update the layer list in
   [system-anatomy.md](../../documentation/design/system-anatomy.md).
5. Run `test_kernel_layering()`.

### Phase 2 — Put barriers in the editor loop ✅ DONE

1. Add `faults::FaultStore` and `fault_policy::FaultPolicy` to `Editor`
   (`EditorModule.jl`, not sealed). Both per editor, so `PAR-PER-EDITOR-STATE`
   holds.

   **Settled while it was built: an `Editor` starts strict and `run_editor!`
   turns the barriers on.** Every test in the tree builds an `Editor`
   directly and none of them calls `run_editor!`, so this keeps every existing
   test at today's behaviour with no edit to any of them, and leaves no way for
   a barrier to turn a real bug into a passing run. `run_editor!` takes a
   `fault_policy` keyword for a caller that wants it the other way.
2. Wrap `drain_operations!`, `read!`, `evaluate!` and `print!` in
   `run_fault_barrier`.
3. Pass the store to the printer: `with_property(ctx, :fault_store,
   editor.faults)` in `print!`. `PrinterContext` does not change.
4. Call `report_frame_faults!(editor)` once per frame, before `read!`. It
   drains and reports. **The drain is the one console reporter**, because it is
   the one place that knows which records are new and it is where the
   projection barrier's records arrive as well. `run_fault_barrier` reports for
   itself only when it was given no store, since nothing will drain that.
5. Add the four repairs of section 3.4 to the operation barrier. Take the
   inverse BEFORE `evaluate_operation`, not after.
6. `is_passthrough_exception(::QuitEditorException) = true` in the operation
   layer, so a request to quit still stops the loop.

**Result.** `test_kernel()` answers 1964 pass, 3 fail, 3 error. The three
failures and three errors are the Rule C group in `DocumentMacroTest.jl` and
`MEvalBranch` in `ReferenceEvalTest.jl`, which are the known baseline and sit in
files this branch does not touch. `test_kernel_layering()` is 10 of 10.

### Phase 3 — Guard the backend seam and add the sound ✅ DONE

1. Add `call_backend` or an equivalent wrapper in the editor layer that counts
   consecutive failures per seam function.
2. Declare `play_fault_sound!` in `FaultInterface.jl` and answer it on `Any` in
   `FaultDefaults.jl`. The default writes the BEL character to the stream the
   logger captured at start. Do not use a raw `println`: `execute_julia_code`
   redirects the global streams (`EditorModule.jl:238-242`).
3. Add the degraded-backend state and the one sound per degrade.

**Found while it was built: the two halves of the device seam must count
apart.** `write_to_devices` and `read_from_devices` are called from different
places and fail on their own. With one consecutive counter between them, a read
that works resets the count a write that failed just raised, and the breaker
never trips — a broken screen throws a hundred times a second for ever.
`run_fault_barrier` therefore takes a `counter` keyword that defaults to the
site, and the editor passes `:device_write` and `:device_read` while both still
record under the one site `:device`. With it, a broken `write_to_devices` stops
being called after eight frames and the editor runs on.

### Phase 4 — Add the `ProjecturedFault` package ⬜

1. Create `package/ProjecturedFault/` and `source/fault/`, copying the shape of
   `ProjecturedGestureLog`.
2. Write `FaultReport`, `FaultLog`, `FaultLogEntry`, `append_fault!` and
   `clear_fault_log!`.
3. Write `FaultCatchingProjection` and its IoMap, all four functions. Keep the
   two calls to `_print_fault_mark` outside the `try`, so a mark that can not be
   printed re-raises.
4. Create `package/ProjecturedFaultTest/` and `package/ProjecturedFaultExample/`.
5. Write test 9 of section 8 before the package is wired to anything. A store
   that groups by reference passes every other test and fails only this one.

### Phase 5 — Make the fault visible ⬜

1. Write all four renderers: `FaultToSyntax`, `FaultToText`, `FaultToWidget`
   and `FaultToGraphics`.
2. Write `FaultLogOverlayProjection`, copying `GestureLogOverlay.jl`.
3. Write `FaultLogToSyntax` so a person can open the log as a document.
4. Add the barrier to the gallery pipelines, **with a `substitute` on every
   stage**. A stage with no substitute is the degraded path of section 3.3.
5. Find which stages end their type dispatcher in an `Any` entry. Such a stage
   prints a `FaultReport` as something wrong rather than throwing, so the
   substitute of the stage before it is the only thing that protects it. Record
   what you find in this plan.

### Phase 6 — Guard the tools, the agent and the MCP server ✅ DONE

1. Add a local barrier to the MCP wire handler
   (`source/mcp/Mcp.jl:118-123`), so the server does not depend on the external
   library for its only barrier.
2. Route the three existing assistant barriers through `report_fault!`, so a
   tool failure reaches the same log as a printer failure. Keep the text they
   already answer to the model.
3. Add a fault record to `start_mcp!`, which only warns today
   (`source/mcp/Mcp.jl:72-77`).

**Needed while it was built: a seam for the store.** The kernel's agent layer
drives a tool against a target it knows only as `Any`, and it may not name
`Editor`, which sits above it. So the fault layer declares `get_fault_store` and
`get_fault_policy`, each answering nothing of its own by default, and the editor
layer answers both for `Editor`. The MCP package names the editor directly and
needs neither.

The three barriers that existed keep the text they answer the model: a tool that
throws is not a broken turn, and the model is told what went wrong so it can try
something else. They now record the fault as well, so one log carries every
failure.

### Phase 7 — Add the safe mode ⬜

1. Count consecutive print faults on the editor.
2. At the limit, swap `editor.projection` for a `ConstantProjection`
   (`source/projection/generic/Constant.jl`) that shows the log.
3. Add the gesture that leaves the safe mode and restores the projection.

### Phase 8 — Write the guide and the invariants ⬜

1. Write `documentation/package/fault/fault.md`.
2. Add the carve-out paragraph to `PAR-PURE-THUNK` and to
   `PAR-NO-WRITE-IN-THUNK` (section 3.2).
3. Add a new invariant, `PAR-REPORT-NEVER-THROWS`.
4. Update `documentation/design/system-anatomy.md` and
   `documentation/rule/package-rules.md`.

## 6. The footprint on the code that exists

| file | change | sealed |
| --- | --- | --- |
| `package/ProjecturedKernel/src/ProjecturedKernel.jl` | one include line, the layer comments | yes — unsealed on 2026-09-18 |
| `source/kernel/editor/EditorModule.jl` | two fields, four barriers, one property, one drain | no |
| `source/mcp/Mcp.jl` | one local barrier, one fault record | no |
| `source/kernel/agent/AgentLoop.jl` | one call to `report_fault!` | no |
| `source/assistant/AssistantTurn.jl` | one call to `report_fault!` | no |
| `test/kernel/layering/` | the layer list | no |
| `SEALING.md` | the inventory of the new layer | no |
| `example/**/…ProjectionExample.jl` | one wrap per stage, opt-in | no |

No document type changes. No domain package changes. No projection outside the
new package changes. No type dispatcher gains an entry.

`package/ProjecturedKernel/src/ProjecturedKernel.jl` is the only sealed file
this plan needs, and it needs one include line plus the renumbered layer
comments. There is no way to add a kernel layer without it. The user gave
permission for that file on 2026-09-18. Touch nothing else in it, and flip
nothing in `SEALING.md` except the entry of the new layer.

## 7. The hazards, and what stops each

| hazard | what stops it |
| --- | --- |
| a barrier hides a real bug from the test suite | `is_barrier_enabled` is false under test; a guard test asserts the default |
| a repeated fault repaints every frame | the drain writes only new keys |
| the store grows without a bound | the store keeps 64 keys and counts what it drops |
| one bug at 3000 nodes fills the store and hides every other fault | the key holds no reference, so the 3000 become one record with a count |
| one fault becomes four, one per stage of the chain | give every stage a `substitute`; the chain bounds the rest at four |
| one fault takes the whole parent subtree with it | the `substitute` keeps the child's output measurable by the parent |
| the fault machinery faults, and recurses | the re-entrancy guard falls to tier 3 at once |
| the mark itself can not be printed | the barrier re-raises to the frame barrier, and the safe mode bounds the repeat |
| a broken backend throws 100 times a second | the circuit breaker degrades the seam after 8 failures |
| a half-applied operation leaves a broken document | the barrier applies the inverse it took first; a compound falls back to a re-print |
| the try blocks cost run time | measure with `with_performance_counters` before and after |
| a person does not notice a swallowed fault | every new key reaches tier 3, whatever the higher tiers do |

## 8. The tests

The suite is `ProjecturedFaultTest`, and it drives behaviour rather than reads
code (`PAR-DRIVE-THE-BEHAVIOUR`).

1. A projection that throws on one node. The other nodes still draw, and the
   mark stands in the slot of the node that failed.
2. The same, when the throw comes from the output cell and not from
   `print_document`. This is the case section 3.2 exists for.
3. A reader that throws. The gesture is declined, and the editor keeps running.
4. A mapper that throws. The answer is `nothing` and the selection does not
   move.
5. An operation that throws. The editor re-prints and the selection is valid
   after it.
6. A backend that throws in `write_to_devices`. The seam degrades after the
   limit, and `read_from_devices` still runs.
7. `report_fault!` never throws: give it a store that throws, a target that
   throws and a backend that throws, all at once.
8. The same fault, raised in 1000 thunk runs, makes one record and one log
   entry.
9. One bug that fails at 3000 different nodes makes one record with `count =
   3000` and one `first_reference`. The store does not reach its cap, and no
   other fault is pushed out of it.
10. A stage with a `substitute` makes exactly one record for one root cause.
    The same stage without one makes at most four, and the count does not grow
    with the size of the document.
11. A parent that measures its child still lays out when the child failed. Its
    siblings draw, and only the node that failed carries a mark.
12. A `substitute` that throws re-raises. The frame barrier reports it, the
    screen keeps the frame before it, and the safe mode starts at the limit.
13. No new fault means no cell write in the drain, so nothing repaints.
14. `is_barrier_enabled` is false in a test editor by default.
15. The safe mode starts after the limit, and the gesture leaves it.
16. The test double that throws lives in the test package, never in a main
    package (`PAR-NO-TEST-DOUBLES-IN-MAIN`).

## 9. What this plan does not do

> **Changed on 2026-09-19, before Phase 1 started.** When the plan was written
> there was no undo and no inverse. Both landed since: `source/undo/` holds
> `UndoBuffer` and its projection, and `source/kernel/operation/Inversion.jl`
> holds `make_inverse_operation`, `evaluate_invertible_operation!` and the
> inverses of the operations the kernel owns. So the operation barrier does not
> have to swallow a broken change any more. Repair 0 of section 3.4 takes the
> operation back, and the first item below shrank to the compound case alone.

- **It does not make a `CompoundOperation` atomic.** A compound that throws half
  way leaves its first members applied, because its way back is built member by
  member and the barrier does not take an operation apart. Every other operation
  type rolls back. See section 3.4.
- **It does not fix the race between a tool and the frame.** The assistant
  task and the MCP task write `editor.document` directly rather than through
  `post_operation!` (`source/assistant/AssistantTurn.jl`,
  `source/mcp/Mcp.jl:120-123`), and the inbox exists to stop exactly that
  (`EditorModule.jl:83-90`). A race corrupts state and then raises a fault that
  looks random, so this matters for robustness — but it is a separate change,
  and it belongs in its own plan.
- **It does not add a common exception supertype.** The seven `*Exception`
  types keep their shape. `FaultRecord` records any `Exception`.
- **It does not change how a parse error is reported.** A parser that answers a
  partial document is a different concern from a projection that throws.

## 10. The decisions the plan takes, and the ones it leaves open

**Taken.**

- The word is **fault**, not error. `Error` and `Exception` are Julia's
  vocabulary and the naming law reserves `Exception` for a thrown type. `Fault`
  is free and it composes: `FaultRecord`, `FaultStore`, `FaultReport`,
  `FaultLog`, `record_fault!`, `report_fault!`, `FaultToSyntax`. A document
  named `DocumentError` would break the law twice: a document is a noun phrase
  whose slice comes first, and `Error` names a thrown thing.
- The sound seam is **`play_fault_sound!(backend)`**, not `beep!`. `beep` fails
  the naming law three ways: it is a noun used as a verb, it names how the
  output sounds rather than the work, and it names no unit that flows. The seam
  family it joins is verb plus the unit — `write_to_devices`, `record_video`,
  `measure_text` — so the verb comes first, the kind produced comes last
  (`sound`), the owner comes from dispatch, and the `!` marks the external side
  effect, exactly as it does on `write_os_clipboard!`. The runner-up was
  `play_alert_sound!`, dropped because `WidgetAlert` already owns the word
  alert. `fault` ties the seam to the rest of this vocabulary and keeps the name
  guessable in both directions.
- The collector is **`FaultStore`**, not `FaultSink`. A sink is a metaphor, and
  the writing rules ban one. A store is a plain noun, and `record_fault!(store,
  record)` reads as English.
- The barrier helper is **`run_fault_barrier`**, not `with_fault_barrier`. The
  naming law reserves `with_<stem>` for a derived copy — `with_property`,
  `with_selection` — and this function runs a body and returns nothing of the
  kind. The word barrier is the one word this plan uses for the concept, so the
  function keeps it and takes a verb in front.
- The kernel file that holds the cascade is **`FaultCascade.jl`**, because
  `FaultReport` is the document type in the substrate package and one name must
  not mean two things.
- The barrier projection is **opt-in per pipeline**, like
  `GestureLogRecordingProjection`. An automatic wrap would change
  `editor.projection` under every existing test.
- The kernel gets **a new layer at position 1**, not a fragment of the cell
  layer and not a fragment of the editor layer. One layer holds one concept.
  The cell layer's concept is the reactive engine, and the store takes faults
  from a reader, from an operation, from a backend seam call and from a tool —
  none of which is a cell. The store exists because of a cell-layer rule, which
  is not the same as belonging to it. Position 1 is open because the layer
  hard-references only `Base`, and position 1 is what lets `cell`, `clock`,
  `event`, `device`, `gesture` and `backend` report. None of them can today.
- The **reactive engine does not catch**, and `FaultCatchingProjection` does.
  The engine knows nothing about documents, references or domains, so the most
  it could store is an opaque poison value. Every consumer of every cell would
  then have to understand poison, or the poison throws on the next read and
  nothing is gained. The projection catches at a place that knows the reference,
  the input document and which substitute fits the output domain, so it can put
  a real mark in the right slot. That knowledge does not exist at layer 1.

**Open.**

- Where the panel sits on the screen, and whether it opens by itself on the
  first fault or only on a gesture.
- Whether the safe mode is worth Phase 7, or whether tiers 1 to 4 are enough.
- The exact limits: 64 keys, 8 device failures, 4 print faults.
