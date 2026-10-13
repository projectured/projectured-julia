# Faults

> **Kind:** reference · **Status:** current · **Stands on:** [architecture.md](architecture.md)

This guide says what a fault is, how a barrier catches one, how the store keeps it, and how the drain reports it. It describes each fragment of the fault layer, `source/kernel/fault/`, and the main uses of its public names. The [fault guide of the platform](../platform/fault/fault.md) describes the views of a fault: the log, the marks and the safe mode.

The fault layer is the lowest layer of the kernel, and it imports nothing. So every layer above can catch a fault and record it. The layer names no document and no projection: it says what a fault is, and code above it says what a fault looks like.

## A fault

A fault is an exception that a catch took instead of letting it end the editor. Not every exception can be a fault. An interrupt, a stack overflow, a heap that ran out and a request to quit mean that the program is to stop. `is_fault_exception` answers which of the two an exception is. Every catch-all arm calls it first, except the arm of the code tool that runs model code:

```julia
value = try
    parse(Int, text)
catch exception
    is_fault_exception(exception) || rethrow()      # a stop goes on
    record_fault!(store, :read; origin = :Parser, exception,
                  traceback = catch_backtrace())
    0
end
```

`is_fault_exception` answers `true` for an ordinary exception and `false` for `InterruptException`, `StackOverflowError` and `OutOfMemoryError`. A layer that owns a control-flow exception adds its own method: the operation layer answers `false` for `QuitEditorException`. The law says the same for every layer: see PAR-REPORT-NEVER-THROWS in [architecture-invariants.md](../../rule/architecture-invariants.md).

## The barrier

`run_fault_barrier!` runs one stage of work, and it answers `fallback` when the stage throws a fault. Use it around a stage that the editor must survive: a frame stage, a call into a backend, the evaluation of an operation.

```julia
policy = FaultPolicy(is_sound_enabled = false)
count = run_fault_barrier!(store; policy, backend, site = :read,
                           origin = :Parser, fallback = 0) do
    parse(Int, text)
end
```

What it does, in order:

1. With `policy.is_barrier_enabled` false, it runs the body and catches nothing.
2. A body that works answers its value, and the count of faults in a row on `counter` goes back to zero.
3. An exception that is not a fault goes on at once.
4. A fault adds 1 to the count on `counter`, goes in the store, and the barrier answers `fallback`.
5. A barrier with no store has no drain behind it, so it reports the fault itself with `report_fault!`.

`site` says which kind of stage failed, for example `:print`, `:read`, `:evaluate`, `:device` or `:tool`. `counter` is `site` unless one site has two halves that fail on their own: the device seam counts its reads on `:device_read` and its writes on `:device_write`. `origin` names what failed, and `reference` says where in the document. The defaults are the origin `:editor`, no reference and the fallback `nothing`. `policy`, `backend` and `site` have no default.

Where the answer must depend on the fault and not be a fixed fallback, catch in place, as in the first example.

## The record and the store

A `FaultRecord` is one fault as a plain value. `make_fault_record` makes one; `record_fault!` makes one only for a new key.

| Field | What it holds |
| --- | --- |
| `key` | what makes two faults the same one: the site, the origin and the exception type |
| `site`, `origin`, `exception_type` | the three parts of the key, as symbols |
| `message` | the message of the first occurrence, as one line; a longer one keeps 400 characters and a `…` |
| `traceback` | the traceback of the first occurrence, or `""`; a longer one keeps 12 lines, with the message and `Stacktrace:`, and a line `  …` |
| `first_reference`, `first_time` | where and when the first occurrence was |
| `count` | how many occurrences the key has taken |

`origin` can be a symbol, a type, `nothing` or a value: the record keeps the symbol, the name of the type, `:unknown`, or the name of the type of the value.

A `FaultStore` collects the records of one editor. `record_fault!` puts one fault in it and answers the record that the fault belongs to:

```julia
store = FaultStore()                        # capacity = 64
for index in 1:3000
    record_fault!(store, :print; origin = :Printer, exception = BoundsError([1], index))
end
only(get_fault_records(store)).count        # 3000: one bug, one record
```

The key holds no reference and no message, so one bug at three thousand nodes is one record with a count, and the first place stays as an example. `get_fault_records` answers the records, oldest first.

### A store is not made of cells

A printer throws inside a computation, while the renderer reads its output, and a computation must not write a cell. A store has no dependents, so `record_fault!` is safe inside a computation. A store has no lock, so one task at a time writes it: the task that owns the cells of the editor. A task that hands the cells to another task hands the store with them.

### A full store makes room

`capacity` bounds the number of keys, and it must be at least 1. A smaller one throws an `ArgumentError`. A new key that does not fit takes the place of the oldest key that the drain already handed over. So each fault reaches the targets at least once. A key that comes back after that starts a new count.

When every key still waits for the drain, the new fault counts into one overflow record, and `record_fault!` answers `nothing`. The overflow record has the site `:store` and the origin `:FaultStore`. It does not count against the capacity, so a full store holds `capacity + 1` records. A caller that needs a record of its own fault makes one, and only then, because `make_fault_record` formats the message and the traceback:

```julia
record = record_fault!(store, :print; origin, exception, traceback)
record === nothing && (record = make_fault_record(:print; origin, exception, traceback))
```

`record_fault!` with `nothing` as the store does nothing and answers `nothing`, so code that was given no store still runs.

## The drain and the report

The drain hands the new records to the targets of the store, and reports each one at the next tier. Call it once per frame, on the task of the editor, outside every computation:

```julia
attach_fault_target!(store, log)            # log answers append_fault!
attach_fault_wake!(store, () -> wake_editor!(editor))   # Editor(…) does this for editor.faults
records = drain_faults!(store; policy, backend)
detach_fault_target!(store, log)            # when the log is gone
```

A record waits for the drain when it is new, and again when its count reaches a power of ten: 10, 100, 1000. So a fault that repeats on every frame does not write the log on every frame. The wake runs at the moment a record starts to wait, so a sleeping editor runs the frame that reports it. A store holds one wake, and `attach_fault_wake!` replaces it. The constructor of `Editor` attaches the wake of the editor, so do not attach another wake to `editor.faults`.

A target is anything that answers `append_fault!(target, record)`. Its answer says whether it showed the record: `false` says that it did not, and any other answer says that it did. `attach_fault_target!` attaches a target once, however often it is called. Code that attaches a target only for some time detaches it again. The safe mode of the editor attaches its projection when it starts, and detaches it when it ends.

```julia
struct LineLog
    lines::Vector{String}
end
FaultModule.append_fault!(log::LineLog, record::FaultRecord) =
    push!(log.lines, "$(record.site) in $(record.origin): $(record.message) ($(record.count))")
```

The tiers, in the order they are tried:

| Tier | Where | Who does it |
| --- | --- | --- |
| 1 | a mark in the output, where it failed | the barrier in a pipeline, above the kernel |
| 2 | a target of the store | `drain_faults!` and `append_fault!` |
| 3 | the console | `report_fault!`, with `@error` |
| 4 | a sound | `report_fault!`, with `play_fault_sound!` |
| 5 | nothing | `report_fault!` |

`report_fault!` answers the tier it reached: `:target`, `:console`, `:sound` or `:swallowed`. The drain passes `is_shown = true` for a record that a target took, so the console stays quiet for it. The sound plays when no target and no console showed the record. It plays also for a fault of the site `:device`, because a screen that draws nothing shows no target. A fault with a mark in the output goes to the store too, so it also reaches the targets.

```julia
tier = report_fault!(store, record; policy, backend)
```

### A report never throws

With a `FaultPolicy` as `policy`, `report_fault!` never throws an ordinary exception. A `policy` of another type throws a `TypeError` at the call. The report runs when everything else failed: a store that throws and a backend that throws, both at once, still answer a tier. A fault inside a report does not recurse: the store counts the depth, and a nested report stops after the console. The drain throws only an `ArgumentError` for a policy that is not a `FaultPolicy`. A target that throws is skipped, with a console line when the console is open. A stop exception goes on, and the records that the drain did not hand over wait for the next drain.

## The policy

A `FaultPolicy` says whether the barriers catch, and which tiers of the report are open. One editor has one.

| Field | Default | What it switches |
| --- | --- | --- |
| `is_barrier_enabled` | `true` | whether a barrier catches at all |
| `is_console_enabled` | `true` | tier 3 |
| `is_sound_enabled` | `true` | tier 4 |

`make_strict_fault_policy()` is the policy that catches nothing: every barrier re-raises, so a broken projection fails its test instead of passing quietly. It is the default of every form that makes an editor. A program that a person starts passes `FaultPolicy()`, because a loop that a person sits in front of must survive:

```julia
editor = make_editor(document, projection; backend, fault_policy = FaultPolicy())
```

## The faults in a row

A barrier counts the faults in a row on its counter, and a run that works sets the count to zero. A circuit breaker above reads the count: a seam that fails on every frame is worse to call than to leave alone.

```julia
get_consecutive_fault_count(store, :print)       # the faults in a row on :print
reset_consecutive_fault_count!(store, :print)    # set the count to zero
```

The editor layer holds the limits. `get_consecutive_fault_limit` answers one for `:print`, `:device_read` and `:device_write`, and `is_editor_degraded(editor, counter)` compares the count with it. When the printer reaches its limit, the editor enters the safe mode if a package answers `make_safe_mode_projection`. The kernel default answers `nothing`, and then the editor keeps its projection. On entry the editor sets the count of `:print` to zero, so a fault in the safe mode can raise a new count.

## The seams

The layer declares four generics in its interface file. Code above can answer them, and the default of each names nothing above the kernel. No backend answers `play_fault_sound!` now, so the sound is the BEL character.

| Seam | Default | Who answers it |
| --- | --- | --- |
| `append_fault!(target, record)` | `false`: the target did not show it | a package that owns a log, such as `FaultLog` |
| `play_fault_sound!(backend)` | the BEL character on the global `stderr` | a backend that can do better; none does now |
| `get_fault_store(target)` | `nothing` | a type that holds a store, such as the editor |
| `is_fault_exception(exception)` | `true`, `false` for the three stop exceptions of Julia | a layer that owns a control-flow exception |

`get_fault_store` serves code that holds a target only as `Any`, such as a tool that throws while it acts on its target:

```julia
record_fault!(get_fault_store(target), :tool; origin = name, exception, traceback)
```

## Layer structure

The layer is the folder [source/kernel/fault/](../../../source/kernel/fault/), and `FaultModule` is its one module.

```
fault/FaultModule.jl   (FaultModule): the module, its exports and its include order
    ├─ FaultInterface.jl : the four seams, declared with no body
    ├─ FaultDefaults.jl  : the default of each seam
    ├─ FaultRecord.jl    : FaultRecord, make_fault_record and the key
    ├─ FaultStore.jl     : FaultStore, the targets, the wake, record_fault!, the drain, the faults in a row
    ├─ FaultPolicy.jl    : FaultPolicy and make_strict_fault_policy
    ├─ FaultCascade.jl   : report_fault!, the tiers after the targets
    └─ FaultBarrier.jl   : run_fault_barrier!
```

`FaultInterface.jl` is the interface file of the layer: it declares and does not implement. The layering guard checks it.

## Where the layer is used

- The cell layer keeps the fault scope of a computation, in `CellFaultScope.jl`. So a fault in a cell goes to the barrier of the part that built the cell.
- The operation layer answers `is_fault_exception` for `QuitEditorException`.
- The editor layer puts a barrier around each stage of a frame, in `EditorLoop.jl`, `ReadEvaluatePrint.jl` and `Feeds.jl`. `FaultBarriers.jl` holds the limits, `record_paint_fault!`, and `report_frame_faults!`, which drains the store once per frame. The constructor of `Editor` attaches the wake of the editor, and `Editor` answers `get_fault_store`.
- The safe mode of the editor, in `SafeMode.jl`, declares the seam `make_safe_mode_projection`. While the safe mode lasts, the editor attaches the projection of the safe mode to the store as a target.
- The agent layer records the fault of a tool in the store that `get_fault_store` answers for the target of the tool.
- Above the kernel, `FaultCatchingProjection` in the projection algebra is the barrier inside a pipeline, and each output domain draws its own mark. The fault slice of the platform holds the log and the safe mode: see the [fault guide of the platform](../platform/fault/fault.md).

## Try it

`print_fault_example()` in `ProjecturedKernelExample` prints a REPL session with the layer: a store and a quiet policy, a barrier that answers its value and then its fallback, the count of one fault, the faults in a row, the drain, `report_fault!`, a full store that makes room and then counts into its overflow record, and a strict policy. Each line runs as it prints. Type the lines yourself after `using ProjecturedKernel.FaultModule`, and change them.

```julia
using ProjecturedKernelExample
print_fault_example()
```

## Design decisions

- **The key holds no reference and no message.** One bug is one record, whatever the size of the document. See [plan/done/the-editor-survives-a-fault.md](../../../plan/done/the-editor-survives-a-fault.md).
- **The store is outside the reactive graph.** A computation can record a fault. The cells of the log and of the marks change only on the task of the editor, outside every computation.
- **The default policy of an editor is strict.** A barrier that is on under a test turns a real bug into a passing run.
- **The console takes only what no target took.** A report goes to the first tier that works, as the law says, so a fault in the log does not also fill the console.
- **A full store forgets what the drain handed over.** Each fault reaches the targets at least once, and the capacity still bounds the memory. The overflow record counts what does not fit.
