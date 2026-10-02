# A printer fault costs the smallest part that it can

> **Status:** done. Written 2026-10-01, landed on `main` on 2026-10-02. The owner
> decided the direction on 2026-10-01 and 2026-10-02 (§5), and accepted the cost
> of step 6c with the landing. §11 holds what is left for later. This plan holds D3, D4 and D6
> of [a-fault-is-easy-to-see-and-stays-small.md](../pending/a-fault-is-easy-to-see-and-stays-small.md).

## 1. The request

The owner (2026-10-01): "Check how fault handling works in projectured and how
chaining and recursive and type dispatching projecrions combine other
projections. Let's design how can we make the printer fault tolerant in a way
which tries to minimize the fault blast radius."

## 2. What exists

**The barriers.**

| Barrier | Where | What it catches | Radius |
| --- | --- | --- | --- |
| `FaultCatchingProjection` | `source/platform/fault/Catching.jl` | its inner `print_document`, the cell that reads `inner.output`, its reader, its two mappers | one node, when it is at a recursion point |
| `make_fault_tolerant_projection` | `source/platform/fault/FaultLogOverlay.jl:242` | one `FaultCatchingProjection` around a whole window | the window |
| the device barrier | `source/kernel/editor/ReadEvaluatePrint.jl:185-189` | all of `write_to_devices` | the frame; after 8 in a row the window stops painting |
| the safe mode | `source/kernel/editor/FaultBarriers.jl` | 4 print faults in a row | the editor |

**Who uses them.** No pipeline of the application has a
`FaultCatchingProjection`: not `make_application_content_projections`
(`source/platform/application/Application.jl:148-185`), not the natural rows
(`source/platform/syntax/SyntaxNatural.jl:73-99`), not the pane projection
(`Application.jl:283-286`), not the shell (`source/platform/shell/WindowWrap.jl`).
Only the example gallery calls `make_fault_tolerant_projection`
(`example/projectured/Gallery.jl:300`). The renderer walk `_render_canvas!`
(`source/backend/sdl/SdlBackend.jl:1710-1808`) has no catch. The window and the
offscreen paths share it.

**How the combinators call their children.**

| Projection | When it prints its child | When no child fits |
| --- | --- | --- |
| `ChainingProjection` | each stage in a cell that reconciles on the output object of the stage before it (`Chaining.jl:72-80`, `:101-105`) | – |
| `RecursiveProjection` | passes itself as the recursion; a node printer calls `print_child` for each child inside the reconcile computation of the parent (`ProjectionTemplate.jl:500-503`, `SyntaxToText.jl:538-551`) | – |
| `TypeDispatchingProjection` | at once, transparent: it answers the IoMap of the child | throws (`TypeDispatching.jl:44`) |
| `PredicateDispatchingProjection` | at once, transparent | throws (`PredicateDispatching.jl:43`) |
| `ReferenceDispatchingProjection` | at once; output in a cell | answers its `default` |
| `SwitchingProjection` | in a cell that reconciles on the index | a bad index throws `BoundsError` |
| `NestingProjection`, `WindowInputUnwrappingProjection` | at once; output in a cell | – |

## 3. How a printer fault travels

### 3.1 The pull stack

A printer builds a graph of cells and returns. An exception comes from the
computation that runs the bad code. It moves up the stack of computations that
pull at that moment, and the first catch on that stack stops it. **The pulls
make this stack, not the nesting of the projections.** In a frame, the renderer
is at the bottom of every stack.

A fault has one of two moments:

- **Early**: in `print_document`. A node prints inside the reconcile computation
  of its parent, so the early fault is on the stack of that computation.
- **Late**: in a cell of the output document: the children, a text, the
  selection, the pointer target. A consumer pulls that cell later.

### 3.2 The node barrier misses the late fault

`FaultCatchingProjection` is on the stack at two places: around the inner
`print_document`, and in its own cell that reads `inner.output`. For a template
node, `output` is an `ImmutableCell` that holds the document
(`ProjectionTemplate.jl:192-198`), and most hand-written printers answer a plain
document too. So the second catch reads a constant and catches nothing. The
fields of the document are separate cells, and a consumer pulls them outside
every barrier. **A late fault of a real printer passes every node barrier.**

The test does not show it. The probe of `FaultCatchingTest.jl:23-29` answers a
computed output cell, which is the one case that the second catch covers.

### 3.3 Holders and aggregators

- A **holder** puts the outputs of its children into its own output and does not
  read inside them. The node of a template is a holder: its children container
  reads `im.output` only. A fault does not pass through a holder.
- An **aggregator** reads inside the outputs of its children: it splices,
  measures, joins or draws them. A fault that passes through an aggregator costs
  the whole output of the aggregator, and it moves on to the next one.

Aggregators found so far:

- `SyntaxCompoundToText`: `_splice_compound` splices the text elements of each
  child into the elements of the parent (`SyntaxToText.jl:563-565`, `:731`).
- `SyntaxLeafToText`: the span cell of a leaf reads the text of its input
  (`SyntaxToText.jl:115`), so it pulls the late faults of the stage before.
- `TextToGraphics`: `_line_groups` reads the whole block in one computation
  (`TextToGraphics.jl:483`).
- `LayoutToGraphics`: `_child_w`, `_child_h` and the sums of a list read the size
  of each child (`LayoutToGraphics.jl:466-476`, `:922-924`, `:580-582`).
- `WidgetTableParts`: the width of a part and the height of a header pane
  (`WidgetTableParts.jl:122`, `:584`, `:809`).
- `TextLineToString`, `TextBlockToString`: join the strings of the children
  (`TextToString.jl:94-101`, `:129-137`).
- The renderer: `_render_canvas!` reads every element.

### 3.4 The radius today

The natural JSON pipeline is JSON → syntax → text → word wrap → graphics. A late
fault in the text of one JSON leaf goes through the span cell of its syntax
leaf, through `_splice_compound` of each ancestor to the root text block,
through `_line_groups`, through the renderer, to the device barrier. The window
does not paint, and after 8 frames it stops. This is the end of take 7, from a
different start. An early fault (take 7: a `CellVector` where a
`JsonObjectEntry` must be) goes up the reconcile computations, and ends the same
way.

An early fault with no barrier at the recursion point has one more cost. The
reconcile computation of the parent throws before it writes its cache
(`IoMapReconcile.jl:24-42`), so each pull builds again the IoMaps of the
siblings before the bad child, and their outputs are new objects each time.

### 3.5 Two defects of the cell engine

Measured on 2026-10-01 with the script of §9.

1. **A caught fault never heals.** A cell whose computation throws stays
   invalid. The invalidation walk stops at an invalid cell
   (`ReactiveCell.jl:212-227`). So a cell above it that caught the fault and
   holds a substitute is never invalidated. In the script, `c` throws while
   `x == 1`, and `a` catches it and answers `-1`. After `x[] = 2`, `c` answers
   `20`, and `a` still answers `-1`.
2. **A fault that nothing catches runs again on each pull.** Three pulls of a
   cell that throws run its computation three times. A fault that no barrier
   catches runs on each frame.

The first defect makes a claim of `fault.md` false: "The node heals". It holds
only when the catch is in the computation that reads the input. The barrier
always reads another cell, so its mark stays until the parent prints the node
again from a new object.

### 3.6 The combinators in this light

- **Chaining** joins graphs. A barrier around a stage catches the print of that
  stage and its output cell, not a late fault in a field. The late fault of
  stage k stops at the first aggregator with a catch in stage k+1 or later, or
  at the device barrier.
- **Recursive** is the one place where each node of a stage enters again. It is
  the place for the early fault, and only there is the radius one node.
- **TypeDispatching** and **PredicateDispatching** turn "no rule fits" into an
  early fault. A barrier at the recursion point turns it into a mark at that
  node.

## 4. The problems

- **P1.** A late fault passes every node barrier (§3.2).
- **P2.** A caught fault never heals (§3.5, 1).
- **P3.** A fault that nothing catches runs on each frame (§3.5, 2).
- **P4.** An aggregator carries one fault to the root of its stage, and the next
  stage carries it to the device (§3.3, §3.4).
- **P5.** The pipelines of the application have no barrier (§2).
- **P6.** The renderer has no catch (§2). This is P2 and D4 of the other plan.
- **P7.** The test covers a case that real printers do not have, and
  `fault.md` claims a heal that does not happen.

## 5. The decisions of the owner

On 2026-10-01:

1. **Not the cell engine.** The engine does not get a third state for a cell
   that threw, and the invalidation walk does not change. The owner, on the two
   options: "I don't like any of those options. Can't we propagate the error in
   the printer in an easier way to the immediately enclosing fault handling
   projection?" So there are also no catches in the aggregators and no seam for
   their substitutes.
2. **A fault goes to the barrier that encloses the printer that built the bad
   cell** (§6). The owner: "It looks good".
3. **Two ways to try again**: A, the editor tries the cell that threw after each
   operation; C, a gesture of the person on the mark. The owner: "Options A and
   C, the latter is gesture on the fault mark by the user." The editor does not
   put the real output back after each operation, because then each edit in
   another part runs the failed part again, loses a frame and counts the fault
   again.
4. **The gestures of retry C are two**: a "Try again" item in the context menu
   of the mark, and a plain click on the mark. The owner: "Both option a and c. A
   retry is not the end of the world."
5. **The renderer catches around each element** (§6.4). The owner: "At element
   level".
6. **A barrier at every recursion point of every pipeline of the application**
   (§6.7). If the measurement of step 6 shows that it costs too much, the
   barriers go only at the widget and graphics stages, with one barrier around
   each pane. The owner: "Option a, if too costly then option b".
7. **D3, D4 and D6 of `a-fault-is-easy-to-see-and-stays-small.md` moved to this
   plan** on 2026-10-02: point 6 decides D3, point 5 decides D4, and the
   interaction test of §8 holds D6. The owner: "Agreed".
8. **The pipeline is built with its barriers before it prints** (2026-10-02). The
   owner: "I would like to build the pipeline properly before print, what needs
   to change?", and then "Agreed" to moving the barrier and the marks down. The
   barrier is a higher-order projection of the projection algebra, beside
   `ChainingProjection` and `RecursiveProjection`, and `FaultReport` moves with
   it. Each mark moves to its own domain: `FaultToSyntax` to syntax,
   `FaultToText` to text, `FaultToWidget` to widget, `FaultToGraphics` to
   graphics. Every place that builds a recursion point names the barrier and the
   mark of its output domain. The fault slice keeps the log, the overlay, the
   safe mode and the gesture bindings of a mark. The other ways were a seam that
   builds the barrier, declared low and answered by the fault slice, and a
   barrier maker passed through every factory of the natural renderer.

## 6. The design

The engine stays as it is (§3.5). The design goes around its two defects: after
the switch of §6.4 nothing pulls the cell that failed, so it does not run on each
frame, and the retry of §6.5 takes the place of the heal.

### 6.1 One barrier for each part

One `FaultCatchingProjection` object serves every node of a recursive stage: in a
JSON document it prints each array, object and leaf. So the projection can not
name a part. **The barrier of a part is the IoMap that one call of its
`print_document` makes.** That IoMap holds the input node (by identity), the
reference of the node at print time (`ctx.reference`), the inner projection, the
inner IoMap and the cell of the output. A fault names that IoMap, so it names one
node.

### 6.2 The scope

`print_document` of the barrier works in this order:

1. Make its IoMap, with no inner IoMap yet.
2. Make the IoMap the current barrier (a `ScopedValue`), and print the inner
   projection in that scope.
3. Put the inner IoMap into its IoMap.

A `Computation` that is made while a scope is active keeps that IoMap. A
`Computation` that is made inside another computation, outside every print,
keeps the IoMap of the computation that makes it. In a nested document the scope
of the inner barrier takes the place of the outer one while the child prints, and
the outer one comes back after it. A child that the reconcile computation of its
parent prints later, during a pull, gets its own scope from its own barrier.

### 6.3 The note

The innermost computation that throws notes the fault on its IoMap: the
exception, the traceback and the cell that threw. Then it throws again, as now.
A computation above it sees the same exception object and does not note it
again. An exception that `is_passthrough_exception` names is not noted.

The note also calls `record_fault!(store, :print; …)`. The record keeps its key
(site, origin, exception type), so a thousand nodes that fail by one bug stay
one record. The node is on the IoMap, not in the store: the store holds no node
by design, and `FaultStore.jl` is sealed. The noted IoMap goes into a plain list
that the printer context carries beside the store.

A computation that has no scope does not note. Its exception goes on to the next
computation up that has one. So the mark goes to the nearest barrier on the pull
path when the cell that failed was built outside every barrier.

A barrier that can not show a fault hands it to the barrier that enclosed it when
it printed: the scope that held then, which `find_fault_scope()` answers. That is
the case when its substitute could not draw the mark, and when a read from
outside its retry reaches a part that shows its mark. The fault follows the
nesting of the barriers and not the pull stack, because the cells of a part
travel by reference through the stages after it: the stack of the read that
fails can hold no other barrier at all.

### 6.4 The switch

The drain of the frame (`report_frame_faults!`) takes the list and writes the
mark into the output cell of each IoMap, outside every computation, so
`PAR-NO-WRITE-IN-THUNK` holds. From the next frame on, the parent reads the mark,
and nothing pulls the cells that failed. After the switch the reader and the two
mappers of the IoMap act as for a mark: they do not reach the inner IoMap.

**The renderer catches around each element.** The walk `_render_canvas!`
(`SdlBackend.jl:1710-1808`), which the window and the offscreen paths share,
draws each element inside a catch. An element that faults is not drawn, and the
walk goes on. So one frame notes every fault, and no frame is lost: the first
frame shows the rest of the window with a hole at each element that faulted, and
the next frame shows the marks. A fault that no barrier noted, such as a fault in
a cell outside every scope or in the renderer itself, is recorded as `:print`
with the type of the element as its origin. The step settles how the walk
reaches the store: a scope that the editor sets around `write_to_devices`, or an
argument. The walk is hot, so the catch sits in a small function of its own.

A fault outside the walk, such as in the root output that the editor reads,
still reaches the device barrier, and that frame is lost. A noted exception is
not a device fault: the body of the device barrier in `ReadEvaluatePrint.jl`
skips the paint for it and does not raise `:device_write`.

### 6.5 The retry

- **A. After each operation.** Between two frames, outside the paint, the editor
  pulls the cell that threw, inside a catch, for each open mark. If it throws,
  the mark stays: no new record, no lost frame. If it computes, the editor writes
  the real output back, and the next frame paints it. An early fault has no
  cell: the editor runs the inner print again, and on success it puts the new
  inner IoMap in place.
- **C. A gesture on the mark.** The person makes the editor do the same retry for
  that one mark at once, with one of two gestures:
  - a "Try again" item in the context menu of the mark, from a binding on
    `FaultReport` that answers the right click, beside the tooltip binding of
    `FaultDocument.jl`;
  - a plain click on the mark. Alt+press still selects the mark.
- A parent that prints the node again, from a new object or after a shift of its
  index, makes a new IoMap, and that one tries by itself.

### 6.6 What it costs

- For a node that prints: its IoMap, a small object that holds its state, and
  one reactive cell for the output. The cell computes the inner output, and
  holds the mark as a value after the switch. It must compute, because an inner
  output can be a computed cell that changes, as the output of a
  `SwitchingProjection` does. That is three cells fewer than the barrier had.
- Each computation that is made in a scope keeps one reference to the IoMap: a
  wrapper around its function, or one field in the cell. The step measures both.
- For each open mark, one pull after each operation.

Under the strict policy no barrier sets a scope, so a test sees every fault, as
now.

### 6.7 Where the barriers go

A barrier at each recursion point of every pipeline of the application, with the
substitute of the output domain of the stage:

| Stage | Substitute |
| --- | --- |
| natural rows, domain → syntax | `FaultToSyntax` |
| `SyntaxToText` | `FaultToText` |
| `WorkspaceToFileSystem` | none yet; a bare `FaultReport`, and a row for it in the next stage |
| `FileSystemToWidget`, `PaneToWidget` | `FaultToWidget` |
| `WidgetToGraphics` | `FaultToGraphics` |

The step makes the full table from the code. If it costs too much, the fallback
keeps only the rows of the widget and graphics stages and adds one barrier
around the content of each pane. A fault in a syntax or a text stage then costs
the part that the next barrier up holds, which can be the text of the whole
pane.

### 6.8 Limits

- The mark takes the place of the whole subtree of its node.
- The mark has its own size, one line of text, so the siblings can move.
- A fault in the code of a parent costs the parent.
- A cell that many nodes read, and that was built outside every barrier, such as
  a theme, gives a mark to each node that reads it.
- A stage with no recursion point, such as `TextToGraphics` or `WordWrapping`,
  is one part: a barrier around it costs that stage of the pane.
- A retry that prints a part again runs outside every computation, so the reads of
  that print do not reach the reconcile computation of the parent. The parent
  keeps the reads of the first print.
- A print that reads a cell of a child while it prints shows its own mark when
  the cell of the child fails, so the mark can stand for the parent, until the
  parent prints the part again.

### 6.9 Files

- Cell layer (⬜): `cell/CellComputation.jl` keeps the scope in a computation;
  `cell/ReactiveCell.jl` and `cell/UntrackedCell.jl` if the step picks the field.
  The cell layer can not name the fault slice, so it declares the scope and a
  generic that a noted fault calls; the fault slice gives its method for the
  IoMap of the barrier.
- Editor (⬜): `editor/ReadEvaluatePrint.jl`, `editor/FaultBarriers.jl`,
  `editor/EditorLoop.jl`.
- Platform: `fault/Catching.jl`, and the pipelines of §6.7.
- Backend: `source/backend/sdl/SdlBackend.jl`, the walk.
- No sealed file changes. The sealed seams `record_fault!` and
  `is_passthrough_exception` are called, not changed.

## 7. Questions for the owner

None are open. Each step can bring new ones.

## 8. Tests and measurements

- **The radius test.** Two faults that need no special projection: early, a node
  of a type that no rule fits, as in take 7; late, one leaf cell of the input
  made a computation that throws. For a JSON, a syntax and a widget example,
  print to the offscreen renderer, and compare the drawn text runs with a print
  where that leaf holds a plain value. Assert that the difference is that one
  leaf, and where it is.
- **The part test.** Two bad leaves of one kind in one array: after two frames,
  two marks at the two leaves, and one record with the count 2.
- **The nested test.** A bad leaf in an array in an array: the mark is at the
  leaf, and both arrays draw.
- **The switch test.** After the frame that faults, the cell that threw does not
  run again, and the device count does not grow.
- **The retry tests.** A: the input of the bad leaf is fixed, and after the next
  operation the value comes back. An operation in another part, while the fault
  stays, loses no frame and adds no record. C: the context menu item and a plain click on the mark each bring
  the value back; Alt+press on the mark still selects it.
- **The renderer test.** Two bad leaves of two kinds: the first frame draws every
  other element and notes both faults, and the second frame draws two marks.
- **The interaction test.** After the switch, a key on another node works, and
  `Ctrl+Z` works while the selection is in the mark.
- **Cost.** The count of cells for each node and the frame time on a large JSON
  file; the cost to make a computation, with the wrapper and with the field; the
  frame time of the walk with the catch around each element. A
  timing needs an idle machine and the owner's word.

## 9. Evidence

The script ran with `--project=package/ProjecturedKernel` on 2026-10-01:

```julia
using ProjecturedKernel
x = Cell(1)
runs = Ref(0)
c = Cell(@computation begin runs[] += 1; x[] == 1 ? error("bad") : x[] * 10 end)
a = Cell(@computation try c[] catch; -1 end)
a[]; a[]; x[] = 2
(a[], c[])            # (-1, 20): a does not heal

y = Cell(1)
b = Cell(@computation try (y[] == 1 ? error("bad") : y[] * 10) catch; -1 end)
b[]; y[] = 2
b[]                   # 20: a catch in the cell that reads the input heals

z = Cell(1)
runs2 = Ref(0)
d = Cell(@computation begin runs2[] += 1; z[] == 1 ? error("bad") : 0 end)
for _ in 1:3; try d[] catch end; end
runs2[]               # 3: each pull runs the computation again
```

## 10. Steps

- [x] **Step 1: the tests of §8**, with `@test_broken` where they fail today.
      Done: `test/platform/fault/FaultPartTest.jl`, `test_fault_part()`: 6 pass,
      15 broken. The pipeline of the suite is JSON → syntax → text → string,
      with a barrier at the recursion points of the syntax and text stages. The
      editor reads the string to paint, so `HeadlessBackend` reads every cell of
      the output, as a renderer does. Today a late fault in one leaf loses every
      frame, and the store counts it as a device fault of `HeadlessBackend`. An
      early fault already costs one leaf. The renderer test and the interaction
      test come with their steps (7 and 6), because they need the SDL backend
      and the application pipeline.
- [x] **Step 2: the scope and the note**: a computation keeps its scope, the
      barrier makes one IoMap for each call, the innermost computation notes.
      With the measurement of the wrapper and of the field.
- [x] **Step 3: the switch** in the drain of the frame, and the device barrier
      that skips a noted fault.

      Done together, in one commit: a barrier takes a fault only when the
      editor gave it a list, so the tests of step 1 change only with both.
      `test_fault()` 93 pass; the 15 markers of step 1 pass and are `@test`.
      What the code is:
      - `source/kernel/cell/CellFaultScope.jl`: `run_in_fault_scope`,
        `record_computation_fault!`, `RecordedFaultException`,
        `get_fault_scope`, `find_fault_scope`. `Computation` keeps the scope by wrapping its
        function in `_FaultScopedComputation`, which catches and hands the
        fault on. The wrapper and not a field of the cell, because an
        `UntrackedCell` computes with no `_recompute!`, and a field costs every
        cell, also a cell that holds a value. A computation made outside every
        scope stays a bare function, so a strict editor runs as before. The
        cost of the wrapper is measured in step 6.
      - The scope of a new computation: the barrier that prints, or the
        computation that runs when the stack is deeper than where the barrier
        set its scope. The depth is kept with the scope for that.
      - A scope that can not show the mark answers `false`, and the exception
        goes on unchanged: a barrier with no list of an editor, as in a print
        outside an editor.
      - `source/kernel/projection/ProjectionInterface.jl`: `show_barrier_mark!`,
        `retry_barrier_print!`, `get_content_iomap` (default: the IoMap
        itself). Step 6 uses the last one.
      - `source/platform/fault/Catching.jl`: the barrier keeps its state in a
        plain mutable object. Under the strict policy it still wraps the IoMap
        of its part, with no scope and no catch, so a test sees the IO maps of
        a running editor. The origin of a late fault is the projection that the
        inner IoMap names, the rule that a dispatcher chose. A
        `RecordedFaultException` in a print gives a mark with no second record.
      - Retry C is in the reader of the barrier: a plain left click with no
        modifier answers `RetryBarrierPrintOperation` in
        `ReplaceViewStateOperation`, a right click the menu with "Try again".
        A container of the widget and graphics stages routes a click by its
        point to the IoMap of the child, so a click reaches the barrier there. A
        mark of a syntax stage is reached by the selection path, not by a
        point: to check in the live editor.
      - The editor: `noted_barriers`, `marked_barriers` (weak),
        `is_retry_pending`. `print!` puts the list in the context under
        `:noted_barriers`. `report_frame_faults!` shows the marks.
        `_evaluate_operation_guarded!` sets the flag, and `run_frame!` tries
        the marks after its operations and before the paint.
        `_write_output_to_devices` skips the paint for a noted fault and counts
        no device fault. `invalidate_projection!` forgets the barriers.
      - The tests of `FaultCatchingTest.jl` that read a late fault with no
        editor now show the marks between two reads (`_read_with_marks`), as
        the frames of an editor do.
      - Retry A tries every mark after the operations of a frame. One bug in
        thousands of nodes then costs one computation and two throws per mark
        and per frame with an operation. A bound on it waits for the
        measurement.
- [x] **Step 4: retry A** after each operation.
- [x] **Step 5: retry C**, the context menu item and the plain click on the
      mark.

      Steps 4 and 5 came with steps 2 and 3, in commit 916dd6d67, with their
      tests in `FaultPartTest.jl`.

      A review of the diff before that commit found these, all fixed in it:
      - A mark whose substitute throws froze the frames with no count.
        `_show_mark!` keeps the report only after the mark is drawn;
        `show_barrier_mark!` records the fault of the substitute, and the
        barrier hands its later faults to the barrier that encloses it. The
        drain empties its list before it draws. A paint that a noted fault
        stopped counts as a device fault when no barrier is on the list.
        Test: "a mark that can not be drawn goes to the barrier above". That
        test also showed that the fallback must follow the nesting and not the
        pull stack (§6.3).
      - The wrapper stopped the retry of `_run_computation` in a newer world. A
        `MethodError` in an older world now passes the wrapper.
      - Retry A could answer a success with nothing changed: a fault of an
        untracked cell, or of the computation of the output of the barrier
        itself. The scope now gets the function of the computation that threw,
        not the cell, and the retry runs that function. A retry of a print reads
        the new output before it answers.
      - Under `run_untracked`, the depth of a scope was compared with another
        stack. The scope keeps its stack vector.
      - `set_cell_computation!` kept no scope; it does now.
      - A failed retry of an early fault recorded again; a retry records
        nothing.
      - The reader and the maps recorded a `RecordedFaultException` again; they
        do not.
- [x] **Step 6: the barriers of the application** (§6.7), with the count of cells
      and the frame time. If it costs too much, the fallback of §6.7.
  - [x] 6a. Move the barrier and `FaultReport` to the projection algebra
        (`higherorder/FaultCatching.jl`, `ProjectionDocument.jl`), and each mark
        to its domain. The projection slice gets an edge to focus, for
        `is_whole_selection_press`. The menu of a mark is a binding of
        `FaultReport` in the fault slice, because it needs the widget slice; a
        report that a barrier made carries the operation that tries its part
        again. Behaviour stays the same.
        Done: `test_fault()` 98 pass, the layering guards of the kernel and the
        platform, the slice edges, and the guards of `test/suite` for exports,
        names and the tree pass. A mark answers Alt+press and a plain click in
        the barrier, and every other gesture through `read_gesture` on its
        report, which holds the tooltip and the menu. `record_computation_fault!`
        takes `traceback` as a keyword, as `record_fault!` does, because the
        argument guard takes four positional arguments as advice.
  - [x] 6b. A barrier at each recursion point of §6.7, and
        `get_content_iomap` where a reader or a printer checks the type of the
        IoMap of a child.
        Done. Against cd427b547: `test_platform()` 84549 pass and 8 broken
        (baseline 84522 and 8; the rest are the new fault tests);
        `test_application()` 329 pass and 2 broken, as the baseline;
        `test_json()` 220, as the baseline; `test_kernel()` 4117 pass and 2
        broken. The first sweep found what a barrier around every node breaks,
        and these fixed it:
        - The IoMap of the barrier is one mutable struct whose field
          `inner_iomap` holds the IoMap of the part, as other transparent
          wrappers keep theirs, so a walk over the fields of IoMaps reaches the
          part. It forwards every property that it does not have to that IoMap
          while the part prints, so a parent that reads the grid of a pane and
          the cells of the grid reads through the barrier. `@iomap` defines a
          `getproperty` of its own, so the struct is a plain one.
        - A parent reads `.output` through the barrier, so a mark shows, and the
          projection of a child through `get_content_iomap`: `WidgetTableParts`
          reads the margins of the projection of a pane.
        - The grid functions that dispatch on `GridLayoutListIoMap` take any
          IoMap and look through it: `get_grid_list_head`,
          `get_grid_list_column_head`, `find_grid_list_row`,
          `find_grid_list_cell`.
        - The barrier maps a reference through the projection that its inner
          IoMap names, as a transparent dispatcher does; through `p.inner` the
          call was ambiguous between `TypeDispatchingProjection` and `RuleIoMap`.
        - The input of a node can be a `Cell`, which the old `@iomap`
          constructor tried to convert.
        - Two tests looked at an IoMap of a child: the helper of the cell
          editing test of `WidgetTable` looks through the barrier, and the
          helper of the application test that finds the trees of the navigator
          finds each tree once.
        What was written:
        - Barriers: the one recursion point of `NaturalToGraphics`
          (`FaultToGraphics`); the two of the syntax fabric, in
          `_fallback_rows` and `make_natural_prose_graphics`, through
          `_make_natural_syntax_stages` (`FaultToSyntax`, `FaultToText`);
          the pane stage of the application and of `make_tabs_projection`
          (`FaultToWidget`), and the renderer of the tabs (`FaultToGraphics`);
          the rows of the application for a workspace, the assistant and a
          primitive; the two conversation rows; the workspace row of the file
          system slice.
        - No barrier: `WorkspaceToFileSystem`, whose output domain has no mark,
          so its fault costs the workspace at the barrier of the renderer;
          `make_natural_projection`, which serves a text export, where a fault
          must fail loudly; the wrappers of the whole window (shell, scene,
          clipboard, history) and the small pipelines of the overlays.
        - `get_content_iomap` in `SyntaxToText` (three places),
          `ProjectionTemplate` (two), the menu items of `WidgetToGraphics`,
          `MathToGraphics`, `ConversationToWidget` and `PaneToWidget`.
          `WidgetTableParts` needs none: `_content_offset` does not dispatch on
          the projection.
        - New slice edges to graphics, for `FaultToGraphics`: pane, file system
          and application.
        - `main` moved about 30 commits on (the wrappers of `build_editor`, the
          umbrella extensions), and 13 files of this branch changed there too.
          The branch is rebased after step 6c, and the tests run again.
        Rebased on 2026-10-02 onto aa7ce9223, with conflicts only in lists of
        exports, imports and slice edges, and in the workspace row of
        `Application.jl`, whose history wrap is now `make_history_wrap(settings)`.
        On the rebased branch `test_platform()` has 84780 pass and 8 broken, and
        `test_application()` 342 pass and 2 broken. `test_kernel()` has 4129
        pass and one failure, "a gesture reaches the child its route names, and
        the child reads it" in `RoutedChangeTest.jl:199`, which fails on a clean
        copy of `main` at aa7ce9223 as well. The four export findings and the
        four argument findings of `test/suite` are in `main` as well.
  - [x] 6c. The count of cells and objects for each node, before and after.
        Done, as allocations, which do not depend on the load of the machine.
        A JSON array of `n` arrays of three values (4n + 1 nodes), printed
        through JSON → syntax → text → string and read whole, with barriers at
        the recursion points of the syntax and text stages
        (`/var/tmp/printer-fault/scripts/measure_body.jl`, 2026-10-02):

        | Pipeline | Bytes per node | Allocations per node |
        | --- | --- | --- |
        | no barrier | 46 712 | 836.6 |
        | barriers, strict policy | 48 471 (+3.8 %) | 872.7 (+4.3 %) |
        | barriers, tolerant policy | 50 216 (+7.5 %) | 921.9 (+10.2 %) |

        The output is the same in the three, and the numbers for n = 250 and
        n = 1000 agree, so the cost grows with the nodes and not faster. The
        tolerant policy adds the wrapper of each computation made in a scope and
        the scope of each print. No time was measured: a timing needs an idle
        machine and the owner's word. Whether this is too costly, and option b
        of §5 point 6 is needed, is the owner's decision.
- [x] **Step 7: the renderer catch** around each element, with the frame time.
      Done, with no frame time: a timing needs an idle machine and the owner's
      word. The editor sets a scope with itself around `write_to_devices`, and
      exports `record_paint_fault!(exception; origin)`: `true` while an editor
      with its barriers on paints, after it records a fault that no barrier took;
      `false` outside a paint, under the strict policy and for an exception that
      passes every barrier. The seam is in the editor layer because
      `BackendModule.jl` is sealed. The SDL walk `_render_canvas!`, which the
      window and the offscreen paths share, draws each element through
      `_render_element_guarded!` and reads the coordinate of the early stop
      through `_find_render_coordinate`. Test: `test_paint_fault()` in the SDL
      suite: outside a paint and under the strict policy the fault goes on;
      with the barriers on, the rows around a broken row are read and the fault
      is recorded. `test_sdl()` 832 pass, `test_fault()` 98 pass. The other
      renderers (web, console, PDF) have no catch around an element.
- [x] **Step 8: the documentation**: `fault.md` (the pull stack, the scope, the
      heal that does not happen, the test), `cell.md` (a computation keeps its
      scope), `projection-system.md`.
      Done on the rebased branch: `fault.md` (the places of the code, the
      barriers of the pipelines, how a fault reaches its barrier, the gestures of
      a mark, the repairs, the design decisions, the tests and the limits),
      `cell.md` (a computation that throws, and its fault scope),
      `projection-system.md` (a barrier around the IoMap of a child, and
      `get_content_iomap`), `higher-order-projections.md` and
      `system-anatomy.md` (the barrier among the higher-order projections). The
      guard of the documents passes. The debugging guide stays true as it is.

## 11. What is left for later

- **The cost** of barriers at every recursion point, 7.5 % more bytes and 10.2 %
  more allocations for each node of a print under the tolerant policy (step 6c),
  is accepted. The owner, asked whether it is acceptable or the fallback of §5
  point 6 is needed: "Yes, land it".
- **A timing.** No frame time and no print time is measured. A timing needs an
  idle machine and the owner's word.
- **A click on a mark of a syntax stage** reaches the barrier through the
  selection and not by its point (§6.5). It is not checked in a live window.
- **Retry A in the worst case.** One bug in thousands of nodes runs one
  computation and two throws for each mark after each frame with an operation.
  A bound waits for a measurement.
