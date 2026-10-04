# Fault

> **Kind:** design · **Status:** current · **Stands on:** [editor.md](../../kernel/editor.md), [projection-system.md](../../kernel/projection-system.md), [gesturelog.md](../gesturelog/gesturelog.md)

A fault in a printer, a reader, an operation, a backend or a tool does not stop the editor, which contains, reports and repairs it. The kernel layer `fault` holds what a fault is, the projection algebra holds the barrier that a pipeline puts at each recursion point, and the fault slice of `ProjecturedPlatform` holds the log and the safe mode. This document says how they catch, report and repair, and how a fault in a printer reaches the barrier of the part that built the cell that failed.

## How it works

### Two halves

The kernel's `FaultModule` holds the record, the store, the policy, the barrier of the editor loop and the report. It names no document and no projection. The kernel's cell layer holds the fault scope of a computation, and its projection layer the seams of a barrier. The platform's `ProjectionAlgebraModule` holds the barrier inside a pipeline and the report that it leaves, and each output domain holds the mark that draws the report. `FaultViewModule` in this package holds the log, the panel, the safe mode and the gestures of a mark, and it answers the seams of the kernel.

| Where | What |
| --- | --- |
| `source/kernel/fault/FaultRecord.jl` | `FaultRecord`, `make_fault_record` |
| `source/kernel/fault/FaultStore.jl` | `FaultStore`, `record_fault!`, `drain_faults!`, `attach_fault_target!` |
| `source/kernel/fault/FaultPolicy.jl` | `FaultPolicy`, `make_strict_fault_policy` |
| `source/kernel/fault/FaultBarrier.jl` | `run_fault_barrier!`, the catch of the editor loop |
| `source/kernel/fault/FaultCascade.jl` | `report_fault!` and its tiers |
| `source/kernel/fault/FaultInterface.jl` | the seams: `append_fault!`, `play_fault_sound!`, `get_fault_store`, `make_safe_mode_projection`, `is_passthrough_exception` |
| `source/kernel/cell/CellFaultScope.jl` | `run_in_fault_scope`, `record_computation_fault!`, `RecordedFaultException`, `find_fault_scope` |
| `source/kernel/projection/ProjectionInterface.jl` | the seams of a barrier: `show_barrier_mark!`, `retry_barrier_print!`, `get_content_iomap` |
| `source/kernel/editor/FaultBarriers.jl` | the barriers of the editor, the drain that draws the marks, the retry after an operation, and `record_paint_fault!` for a renderer |
| `source/platform/projection/higherorder/FaultCatching.jl` | `FaultCatchingProjection`, the barrier inside a pipeline, and `RetryBarrierPrintOperation` |
| `source/platform/projection/ProjectionDocument.jl` | `FaultReport`, the report that a barrier leaves |
| `source/platform/syntax/FaultToSyntax.jl`, `text/FaultToText.jl`, `widget/FaultToWidget.jl`, `graphics/FaultToGraphics.jl` | one mark for each output domain |
| `source/platform/fault/FaultDocument.jl` | `FaultLog`, `FaultLogEntry`, and the gestures of a `FaultReport` |
| `source/platform/fault/FaultLogOverlay.jl` | the log as a panel over a window |
| `source/platform/fault/FaultSafeMode.jl` | what the editor shows when nothing else prints |

The package has [the shared shape](../gesturelog/gesturelog.md#the-shared-shape) of the tool decorators: `FaultLog` is the document, `FaultCatchingProjection` of the projection algebra is the decorator that catches, and `FaultLogOverlayProjection` is the panel. Unlike the gesture log panel, this panel is not there while the log is empty, so a program that works shows no extra pixel. Its default corner is the bottom left, which the gesture log panel does not use.

### Turn it on

Every form that makes an editor starts with `make_strict_fault_policy()`: no barrier catches, so a broken projection fails its test. A program that a person starts turns the barriers on: it passes `fault_policy = FaultPolicy()` to `make_editor` or `build_editor`, because a loop that a person sits in front of must survive. `run_editor!` keeps the policy of its editor, and its keyword `fault_policy` replaces it. `run_print_stage!` puts the policy of the editor in the printer context under `:fault_policy`, the store under `:fault_store` and the list of the barriers that took a fault under `:noted_barriers`, so a barrier in a pipeline follows the same policy as the barriers of the editor. A context with no policy, such as one that a test makes by hand, counts as the strict policy. Under the strict policy a barrier sets no scope and catches nothing, and it still wraps the IoMap of its part, so a test sees the IO maps of a running editor.

```julia
editor = make_editor(document, projection; backend,
                     fault_policy = FaultPolicy())              # barriers on
run_editor!(editor)                                             # barriers stay on
run_editor!(editor; fault_policy = make_strict_fault_policy())  # barriers off
```

Each recursion point of a pipeline that a person sees has a barrier, with the mark of its output domain as the `substitute`: the natural renderer (`NaturalToGraphics`), the two recursive stages of the syntax fabric, the pane stage, the renderer of the tabs that `build_editor` adds, and the rows of the application and of the conversation. A pipeline of your own puts its barriers the same way when it builds itself. Give each one a `substitute`; a section below says why.

```julia
ChainingProjection(
    RecursiveProjection(FaultCatchingProjection(inner = JsonToSyntax(), substitute = FaultToSyntax())),
    RecursiveProjection(FaultCatchingProjection(inner = SyntaxToText(), substitute = FaultToText())),
    FaultCatchingProjection(inner = TextToGraphics(measure = measure), substitute = FaultToGraphics()))
```

`make_fault_tolerant_projection(inner)` puts one barrier around a whole root projection and the panel over it, and returns the projection and its log. The barrier is inside the panel, so a fault in the chain can not take the panel with it. Attach the log to the store of the editor, and the frame fills it:

```julia
projection, log = make_fault_tolerant_projection(composed)
editor = make_editor(document, projection; backend, fault_policy = FaultPolicy())
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

### How a fault in a printer reaches its barrier

A printer does not throw when `print_document` runs. It builds a graph of computations and returns. It throws later, inside a computation, while the renderer pulls the output, one frame later or a hundred. By then the barrier has returned as well, so it is not on the stack of the read that fails, and a `try` around `print_document` catches only a fault in the print itself. The cells of a part travel by reference through the stages after it, so the stack of the read that fails can hold no other barrier at all.

So the relation is kept from the moment a cell is built:

1. Each call of `print_document` of a barrier makes the IoMap of one part, and prints the part inside `run_in_fault_scope`, with that IoMap as the scope.
2. A `Computation` made in the scope keeps it, and so does a computation that `set_cell_computation!` gives a cell. A computation made inside another computation takes the scope of that computation.
3. The innermost computation in a scope that throws calls `record_computation_fault!` with its scope. The barrier records the fault in the store and puts itself on the list of the editor. The computation then throws a `RecordedFaultException`, which no barrier above records again. A `MethodError` in an older world passes, so the cell runs the computation again in the newest world.
4. The SDL renderer reads each element of the output inside a catch, and calls `record_paint_fault!` when the read throws. While an editor with its barriers on paints, the call records a fault that no barrier took, and the renderer skips that element and draws the rest. So the first frame shows the window with a hole where the part failed. A read outside an element, such as the read of the root output, loses the frame: the device barrier skips the paint for a `RecordedFaultException` and counts no device fault, so the screen keeps the frame before it.
5. Between two frames, `report_frame_faults!` calls `show_barrier_mark!` for each barrier on the list. The barrier writes its output cell with the mark, outside every computation, so the parent reads the mark and nothing reads the cells that failed.

A barrier that can not draw its mark, because its substitute throws, records that fault, and its later faults go to the barrier that held the scope when it printed: `find_fault_scope()` answers that one. So the fault follows the nesting of the barriers, and the mark stands in a larger place.

The mark stays until the part is tried again, in three ways. After the operations of a frame, the editor calls `retry_barrier_print!` for each barrier that draws a mark. A plain click on the mark tries its part at once, and so does "Try again" in the menu of the mark. A retry runs the function of the computation that failed again, or prints the part again when the print failed; a retry that fails records nothing and keeps the mark. A parent that prints the part again, from a new object, makes a new barrier, which tries by itself.

While its part prints, a barrier adds nothing to it. `get_content_iomap(child)` answers the IoMap of the part, for a reader that checks the type of a child. A property that the IoMap of the barrier does not have is read from the IoMap of the part, and its field `inner_iomap` holds that IoMap, as other transparent wrappers keep theirs. A parent reads `.output` through the barrier, so the mark shows.

The reader and the two reference mappers catch too. A reader that throws returns `Intent(gesture, nothing)`, so the layer above gets its turn. A mapper that throws returns `nothing`, the normal answer for a node with no image, so no edit can address a node whose value nobody could draw.

**A mark is a thing on the screen like any other, so an Alt+press names it, and a plain click tries its part again.** The report is no child of the node that failed, and no field or index reaches it, so the path is a drawn-object step (`OutputReferenceStep`) from that node to the report. The barrier keeps the report it printed, because a selection names an object by identity: a report made again for each press would name a different object every frame, and the selection would be lost. The barrier maps that path forward to the whole image of the node, so the container that holds the mark rings it.

**A mark says the whole fault when the pointer rests on it, and a right click opens its menu.** A mark draws one line, which a long message does not fit in. The tooltip binding of a `FaultReport`, "Show the fault", answers what failed, where it was caught and the whole message, as a `TextString`. `FaultToWidget` gives its alert the same text as its own `tooltip` as well, so the widget answers whether the press names the alert or the report. The menu binding has one item, "Try again", which evaluates the operation that the barrier put in the field `retry` of its report. The reader of the barrier passes every gesture on a mark other than an Alt+press and a plain click to `read_gesture` on the report. A click reaches the reader of the barrier where a container routes a click by its point, as the containers of the widget and graphics stages do. A mark of a syntax stage is reached through the selection.

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
| a fault in a cell of a part | draws the mark of that part between two frames |
| an operation | tries each part that draws a mark again |
| a click on a mark, or "Try again" | tries that part again |
| eight device faults in a row | stops calling that half of the backend |
| four print faults in a row | enters the safe mode |

The editor layer holds one limit for each counter, and `get_consecutive_fault_limit(counter)` reads it: `:print`, `:device_read` and `:device_write`. `FaultPolicy` holds only the switches that the fault layer reads. In the safe mode the editor puts its projection aside and prints `make_safe_mode_projection(store)`, which this package answers with a `FaultSafeModeProjection`. It ignores its input, draws a new log filled from the store, and returns no operation for any gesture. Escape leaves the safe mode and puts the projection back. A substitute that throws while a print fails goes on up as the fault of that print. A substitute that throws when the editor draws a mark is recorded, and the barrier around it draws the mark in its place.

### The `fault_log` wrapper of `build_editor`

`fault_log = true` is the wrapper of `build_editor` that attaches the fault log of the session (`get_session_fault_log()`) to the fault store of the editor in a start step, so the log holds every fault that the editor catches. It is off by default. It acts in the layer `:screen` with the number 30, which acts once, on the root, rather than nesting around the content.

### The theme

`FaultTheme` holds the text of the count, the site, the origin and the message of a line of the fault log, and of an empty log. Each value has the default that the slice draws with no
appearance. `FaultLogToSyntax` holds its styles and no theme. `make_fault_log_projection(; theme)`
fills them with `get_fault_style`, from a `FaultTheme` scaled or not, or the default values for
`nothing`. The registration of the fault log gives the scaled theme of the `Appearance`. The overlay of the fault log and the substitutes of a fault barrier keep their own styles, built the same way through `make_fault_log_panel_syntax_projection`, because no builder of them has an `Appearance`.

## How it fits

The kernel layer `fault` is the lowest layer of the kernel and imports nothing. The cell layer uses it for `is_passthrough_exception`. The barrier is in the projection algebra and each mark in its own domain, so every slice that builds a recursion point names its barrier when it builds the pipeline. The fault slice depends on the kernel and on the collection, domain, focus, graphics, natural, projection, serialization, settings, style, syntax, text, tooltip and widget slices.

The `fault_log` wrapper attaches the session's fault log when a window starts, and the shell slice's toolbar has a Fault log button that opens it only when the wrapper is on; see [shell.md](../shell/shell.md). The gallery wraps each window with `make_fault_tolerant_projection` unless `fault_tolerant = false`. A built binary takes `--strict-fault-policy`.

The fault slice registers the natural row `:fault` for `FaultLog`, the title `Faults` and the insertion alias `faults`. `make_insertion_document` returns the session log, because a new log would never fill: only the drain of a store fills a log. `pred_arguments` of a `FaultLog` holds only `capacity`, so a loaded log starts empty.

## Design decisions

- **The name is fault, not error.** `Error` and `Exception` are words of Julia itself, and `Fault` composes into `FaultRecord` and `FaultStore` with no collision. See [plan/done/the-editor-survives-a-fault.md](../../../../plan/done/the-editor-survives-a-fault.md).
- **The kernel records and the package shows.** The kernel names no document or projection, so the view of a fault must live above it.
- **A fault goes to the barrier of the part that built the cell that failed.** A computation keeps its scope from the moment it is made, so the pull stack does not decide which barrier draws the mark. The reactive engine does not change.
- **The editor draws a mark between two frames.** A computation must not write a cell, so the barrier only records the fault and puts itself on a list.
- **A mark tries again after an operation and on a click, not by itself.** The cell that failed is not read again until then, so a fault does not run on each frame.
- **A barrier is a projection of the algebra, and each domain draws its own mark.** A pipeline is built with its barriers before it prints.
- **The store is outside the reactive graph.** A computation may write it, and the frame drains it into the log.
- **The key holds no reference.** One bug is one record, whatever the size of the document.
- **The strict policy keeps every barrier off under test.** A barrier still wraps the IoMap of its part there, so a test sees the same IO maps as a running editor.
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
- Test: `test_fault()` in `ProjecturedPlatformTest` runs the barrier in a pipeline, the safe mode against a real editor, `test_fault_part()` and `make_fault_tolerant_projection`. `test_fault_part()` drives a real editor over a JSON pipeline whose last stage joins the text into one string, so a paint reads every cell. Its faults happen in a cell of the output, while a paint reads it, because a real printer fails there. `test_cell_fault_scope()` in `ProjecturedKernelTest` tests the scope.

## Limits

- The first frame of a fault draws the rest of the window, with a hole where an element failed, only with the SDL renderer, which catches around each element. Another renderer, and a fault outside an element, lose that frame, and there one frame finds one fault, because the read stops at the first.
- The mark takes the place of the whole part, and it has its own size, so the siblings can move.
- A stage with no recursion point, such as `TextToGraphics`, is one part. A barrier around it costs that stage of the pane.
- A parent that reads the inner fields of a child, as a table reads the grid of its pane, fails with the child, so its own barrier draws the mark.
- `WorkspaceToFileSystem` has no mark of its own, so a fault in it costs the workspace.
- A `CompoundOperation` is not atomic and gets no rollback. Only `evaluate_invertible_operation!` builds its way back member by member.
- A parse error is not a fault. A parser that returns a partial document is a separate concern.
