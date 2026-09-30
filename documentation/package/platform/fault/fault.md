# Fault

> **Kind:** design · **Status:** current · **Stands on:** [editor.md](../../kernel/editor.md), [projection-system.md](../../kernel/projection-system.md), [gesturelog.md](../gesturelog/gesturelog.md)

A fault in a printer, a reader, an operation, a backend or a tool does not stop the editor, which contains, reports and repairs it. The kernel layer `fault` holds what a fault is, and `ProjecturedFault` holds what a fault looks like. This document says how the two catch, report and repair, and why a printer needs two catches.

## How it works

### Two halves

The kernel's `FaultModule` holds the record, the store, the policy, the barrier and the report. It names no document and no projection. `FaultViewModule` in this package holds the documents, the projections that catch and draw, and the safe mode, and it answers the seams of the kernel. The split is the same as the split between the kernel's `ProjectionModule` and the substrate's `ProjectionAlgebraModule`.

| Where | What |
| --- | --- |
| `source/kernel/fault/FaultRecord.jl` | `FaultRecord`, `make_fault_record` |
| `source/kernel/fault/FaultStore.jl` | `FaultStore`, `record_fault!`, `drain_faults!`, `attach_fault_target!` |
| `source/kernel/fault/FaultPolicy.jl` | `FaultPolicy`, `make_strict_fault_policy` |
| `source/kernel/fault/FaultBarrier.jl` | `run_fault_barrier!`, the catch of the editor loop |
| `source/kernel/fault/FaultCascade.jl` | `report_fault!` and its tiers |
| `source/kernel/fault/FaultInterface.jl` | the seams: `append_fault!`, `play_fault_sound!`, `get_fault_store`, `make_safe_mode_projection`, `is_passthrough_exception` |
| `source/platform/fault/FaultDocument.jl` | `FaultReport`, `FaultLog`, `FaultLogEntry` |
| `source/platform/fault/Catching.jl` | `FaultCatchingProjection`, the barrier inside a chain |
| `source/platform/fault/FaultToSyntax.jl` and its three neighbours | one mark for each output domain |
| `source/platform/fault/FaultLogOverlay.jl` | the log as a panel over a window |
| `source/platform/fault/FaultSafeMode.jl` | what the editor shows when nothing else prints |

The package has [the shared shape](../gesturelog/gesturelog.md#the-shared-shape) of the tool decorators: `FaultLog` is the document, `FaultCatchingProjection` is the decorator that catches, and `FaultLogOverlayProjection` is the panel. Unlike the gesture log panel, this panel is not there while the log is empty, so a program that works shows no extra pixel. Its default corner is the bottom left, which the gesture log panel does not use.

### Turn it on

`Editor(…)` starts with `make_strict_fault_policy()`: no barrier catches, so a broken projection fails its test. `make_editor` turns the barriers on: it gives the editor `FaultPolicy()`, because a loop that a person sits in front of must survive. `run_editor!` keeps the policy of its editor, and its keyword `fault_policy` replaces it. `print!` puts the policy of the editor in the printer context under `:fault_policy`, beside the store under `:fault_store`, so a barrier in a chain follows the same policy as the barriers of the editor. A context with no policy, such as one that a test makes by hand, counts as the strict policy.

```julia
editor = make_editor(document, projection; backend)            # barriers on
run_editor!(editor)                                             # barriers stay on
run_editor!(editor; fault_policy = make_strict_fault_policy())  # barriers off
```

A barrier inside a chain is opt-in, one for each step. Give each one a `substitute`; a section below says why.

```julia
ChainingProjection(
    RecursiveProjection(FaultCatchingProjection(inner = JsonToSyntax(), substitute = FaultToSyntax())),
    RecursiveProjection(FaultCatchingProjection(inner = SyntaxToText(), substitute = FaultToText())),
    FaultCatchingProjection(inner = TextToGraphics(measure = measure), substitute = FaultToGraphics()))
```

`make_fault_tolerant_projection(inner)` puts one barrier around a whole root projection and the panel over it, and returns the projection and its log. The barrier is inside the panel, so a fault in the chain can not take the panel with it. Attach the log to the store of the editor, and the frame fills it:

```julia
projection, log = make_fault_tolerant_projection(composed)
editor = make_editor(document, projection; backend)
attach_fault_target!(editor.faults, log)
run_editor!(editor)
```

### The report ladder

The editor reports a fault at the first tier that works. A tier that fails falls to the next.

| Tier | Where | What does it |
| --- | --- | --- |
| 1 | in the output, at the place that failed | `FaultCatchingProjection` puts a mark there |
| 2 | in the log on the screen | `FaultLogOverlayProjection` or a tab reads the `FaultLog` |
| 3 | on the console | `report_fault!` calls `@error` |
| 4 | a sound | `report_fault!` calls `play_fault_sound!` |
| 5 | nothing | `report_fault!` returns |

`report_fault!` must never throw, because it runs when everything else already failed. `PAR-REPORT-NEVER-THROWS` holds the rule. `run_fault_barrier!` and `FaultCatchingProjection` let `InterruptException`, `StackOverflowError`, `OutOfMemoryError` and the request to quit through, by `is_passthrough_exception`.

### Why a printer needs two catches

A printer does not throw when `print_document` runs. It builds a graph of computations and returns. It throws later, inside a computation, while the renderer pulls the output, one frame later or a hundred. So a `try` around `print_document` catches almost nothing.

`FaultCatchingProjection` catches in both places: around `print_document` of the inner projection, and inside the computed cell that reads the inner output. Its catch returns a value, the mark, and not an exception. The reactive engine then does three things with no more code:

- **The repeat stops.** The engine caches the mark, so the computation does not run and throw again on every frame.
- **The node heals.** The mark has the dependencies that the real value had. When the input that caused the fault changes, the computation runs again and the real output comes back.
- **The fault stays local.** The exception never leaves the cell, so no other read stops and the rest of the graph stays valid.

The reader and the two reference mappers catch too. A reader that throws returns `Intent(gesture, nothing)`, so the layer above gets its turn. A mapper that throws returns `nothing`, the normal answer for a node with no image, so no edit can address a node whose value nobody could draw.

**A mark is a thing on the screen like any other, so an Alt+press names it.** The report is no child of the node that failed, and no field or index reaches it, so the path is a drawn-object step (`OutputReferenceStep`) from that node to the report. The barrier keeps the report it printed, because a selection names an object by identity: a report made again for each press would name a different object every frame, and the selection would be lost. The barrier maps that path forward to the whole image of the node, so the container that holds the mark rings it.

**A mark says the whole fault when the pointer rests on it.** A mark draws one line, which a long message does not fit in. The tooltip binding of a `FaultReport`, "Show the fault", answers what failed, where it was caught and the whole message, as a `TextString`. `FaultToWidget` gives its alert the same text as its own `tooltip` as well, so the widget answers whether the press names the alert or the report.

### Why the store is not made of cells

`PAR-NO-WRITE-IN-THUNK` forbids a computation to write a cell: a write in the middle of a computation invalidates its consumers half way through. The log is a document made of cells. So the catch writes a `FaultStore`, a plain object outside the reactive graph. The store is safe to write from a computation: it has no dependents, and a write keyed by the fault leaves one entry for a computation that runs ten times. The editor frame then calls `report_frame_faults!` once, on its own task and outside every computation, and that call writes the log through `append_fault!`.

### Why a substitute is not optional

With no substitute the mark is a bare `FaultReport`, and the fault spreads two ways:

- **Down the chain.** The next step has no method for `FaultReport`, throws, and its own barrier fires. Four steps make four records for one cause.
- **Out to the siblings.** A parent printer often reads the output of a child: it measures a width or counts a length. A parent that gets a `FaultReport` throws in its own computation, so one mark then replaces the whole parent subtree.

A substitute prints the report as a document of the right domain: a red `SyntaxLeaf`, a red `TextBlock`, a destructive `WidgetAlert` or a `GraphicsCanvas` with one red line. The parent can measure it, so the fault stays at the one node. A step whose type dispatch ends in an `Any` entry does not throw on a `FaultReport`; it prints something wrong, with no report.

### Why the key holds no reference

A chain limits how far a fault spreads downward. Nothing limits how far it spreads sideways: one bug in one projection fails at every leaf of one kind, which in a large document is thousands of nodes. So the key of a record holds the site, the origin and the exception type, and not the reference or the message. Three thousand failures become one record with `count = 3000`, and one place kept as an example. A line of the `FaultLog` keeps the key of its record, so the log has one line for each record of the store. The document still shows one mark for each node, because each mark is a value in the cell of its node. The drain gives a record to the log once for each power of ten of its count. So a fault that repeats on every frame does not write the log on every frame.

### Repair

| After | What the editor does |
| --- | --- |
| an operation fault | applies the inverse that it took before the change |
| an operation fault | drops the projection, so the next frame prints from the start |
| an operation fault | clears a selection that no longer resolves |
| eight device faults in a row | stops calling that half of the backend |
| four print faults in a row | enters the safe mode |

The editor layer holds one limit for each counter, and `get_consecutive_fault_limit(counter)` reads it: `:print`, `:device_read` and `:device_write`. `FaultPolicy` holds only the switches that the fault layer reads. In the safe mode the editor puts its projection aside and prints `make_safe_mode_projection(store)`, which this package answers with a `FaultSafeModeProjection`. It ignores its input, draws a new log filled from the store, and returns no operation for any gesture. Escape leaves the safe mode and puts the projection back. A substitute that itself throws is not caught a second time. Its exception reaches the frame barrier of the editor, and the print-failure count climbs until the safe mode starts.

## How it fits

The kernel layer `fault` is the lowest layer of the kernel and imports nothing. `ProjecturedFault` depends on `ProjecturedCollection`, `ProjecturedDomain`, `ProjecturedGraphics`, `ProjecturedNatural`, `ProjecturedProjection`, `ProjecturedSerialization`, `ProjecturedStyle`, `ProjecturedSyntax`, `ProjecturedText`, `ProjecturedWidget` and the kernel. It needs the four output domains for the four marks.

`ProjecturedShell` attaches `get_session_fault_log()` to the store of the editor when a window starts, and its toolbar has a Fault log button; see [shell.md](../shell/shell.md). The gallery wraps each window with `make_fault_tolerant_projection` unless `fault_tolerant = false`. A built binary takes `--strict-fault-policy`.

The package registers the natural row `:fault` for `FaultLog`, the title `Faults` and the insertion alias `faults`. `make_insertion_document` returns the session log, because a new log would never fill: only the drain of a store fills a log. `pred_arguments` of a `FaultLog` holds only `capacity`, and the package registers no `.pred` type for it.

## Design decisions

- **The name is fault, not error.** `Error` and `Exception` are words of Julia itself, and `Fault` composes into `FaultRecord` and `FaultStore` with no collision. See [plan/done/the-editor-survives-a-fault.md](../../../../plan/done/the-editor-survives-a-fault.md).
- **The kernel records and the package shows.** The kernel names no document or projection, so the view of a fault must live above it.
- **The catch returns a value.** The reactive engine then caches, heals and contains the fault; a catch that only logs would throw again on every frame.
- **The store is outside the reactive graph.** A computation may write it, and the frame drains it into the log.
- **The key holds no reference.** One bug is one record, whatever the size of the document.
- **A barrier in a chain is opt-in.** A pipeline without one behaves as before. The strict policy keeps every barrier off under test, the barriers in a chain too.
- **The fault log is not saved.** The faults of one session say nothing about the next one.

## Usage

```julia
run_example(fault_print_example)     # one mark; the siblings draw; one line in the panel
run_example(fault_read_example)      # F8: the reader throws, the editor lives
run_example(fault_evaluate_example)  # F9: the operation throws, the editor repairs
run_example(fault_map_example)       # select the broken value: the mappers return nothing
run_fault_device_example()           # the backend breaks while it runs; the editor stops calling it
run_fault_tool_example()             # a tool throws; the same panel reports it
```

- Examples: `example/platform/fault/FaultExamples.jl`. The four `Example` constants are not in the example registry, because each one throws on purpose and a sweep over every example would stop there.
- Test: `test_fault()` in `ProjecturedFaultTest` runs the layering guard, the store, the report ladder, the barrier in a chain, the safe mode against a real editor, and `make_fault_tolerant_projection`. The most important test raises the fault inside the output cell and not in `print_document`, because a real printer fails there.

## Limits

- A `CompoundOperation` is not atomic and gets no rollback. Only `evaluate_invertible_operation!` builds its way back member by member.
- A parse error is not a fault. A parser that returns a partial document is a separate concern.
