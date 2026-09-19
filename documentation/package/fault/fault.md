# Fault slice

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md), [projection-system.md](../kernel/projection-system.md), [editor.md](../kernel/editor.md)

How ProjecturEd survives a failure. A fault in a printer, in a reader, in an
operation, in a backend or in a tool does not stop the editor: it is contained
where it happened, reported where a person can read it, and repaired where it
can be.

The work is split in two. The **kernel's `fault` layer** holds what a fault *is*
— the record, the store, the barrier and the report — and names no document and
no projection. The **`ProjecturedFault` package** holds what a fault *looks
like*. That is the same split the projection layer already uses between the
kernel's `ProjectionModule` and the substrate's `ProjectionAlgebraModule`.

## What it is made of

| Where | What |
| --- | --- |
| [`source/kernel/fault/FaultRecord.jl`](../../../source/kernel/fault/FaultRecord.jl) | `FaultRecord`, `make_fault_record`, `compute_fault_key` |
| [`source/kernel/fault/FaultStore.jl`](../../../source/kernel/fault/FaultStore.jl) | `FaultStore`, `record_fault!`, `drain_faults!`, `attach_fault_target!` |
| [`source/kernel/fault/FaultPolicy.jl`](../../../source/kernel/fault/FaultPolicy.jl) | `FaultPolicy`, `make_strict_fault_policy` |
| [`source/kernel/fault/FaultBarrier.jl`](../../../source/kernel/fault/FaultBarrier.jl) | `run_fault_barrier`, the one catch |
| [`source/kernel/fault/FaultCascade.jl`](../../../source/kernel/fault/FaultCascade.jl) | `report_fault!` and the five tiers |
| [`source/kernel/fault/FaultInterface.jl`](../../../source/kernel/fault/FaultInterface.jl) | the seams: `append_fault!`, `play_fault_sound!`, `get_fault_store`, `make_safe_mode_projection`, `is_passthrough_exception` |
| [`source/fault/FaultDocument.jl`](../../../source/fault/FaultDocument.jl) | `FaultReport`, `FaultLog`, `FaultLogEntry` |
| [`source/fault/Catching.jl`](../../../source/fault/Catching.jl) | `FaultCatchingProjection`, the barrier inside a pipeline |
| [`source/fault/FaultToSyntax.jl`](../../../source/fault/FaultToSyntax.jl) and its three neighbours | one renderer per output domain |
| [`source/fault/FaultLogOverlay.jl`](../../../source/fault/FaultLogOverlay.jl) | the log as a panel over a window |
| [`source/fault/FaultSafeMode.jl`](../../../source/fault/FaultSafeMode.jl) | what the editor shows when nothing else can be shown |

## Turn it on

An `Editor` starts **strict**: no barrier catches anything, so a broken
projection fails its test exactly as it did before this slice existed.
`run_editor!` is what turns the barriers on, because a loop a person is sitting
in front of is the thing that must survive.

```julia
run_editor!(editor)                                        # barriers on
run_editor!(editor; fault_policy = make_strict_fault_policy())   # barriers off
```

The barriers inside a pipeline are opt-in, one line per step. Give every one of
them a `substitute`; the next section says why.

```julia
ChainingProjection(
    RecursiveProjection(FaultCatchingProjection(inner = JsonToSyntax(),
                                                substitute = FaultToSyntax())),
    RecursiveProjection(FaultCatchingProjection(inner = SyntaxToText(),
                                                substitute = FaultToText())),
    FaultCatchingProjection(inner = TextToGraphics(measure = measure),
                            substitute = FaultToGraphics()))
```

Two more lines put the message log on the screen:

```julia
log = FaultLog()
attach_fault_target!(editor.faults, log)
projection = FaultLogOverlayProjection(inner = root, log = log)
```

## The report ladder

A fault is reported at the first tier that works, and a tier that fails falls to
the next.

| tier | where | who does it |
| --- | --- | --- |
| 1 | in the output, at the place that failed | `FaultCatchingProjection` substitutes a mark |
| 2 | in the message log on the screen | `FaultLogOverlayProjection` reads the `FaultLog` |
| 3 | on the console | `report_fault!` calls `@error` |
| 4 | a sound | `report_fault!` calls `play_fault_sound!` |
| 5 | nothing | `report_fault!` returns |

`report_fault!` never throws. It is the one function in the system with that
contract, because it runs when everything else has already failed — see
`PAR-REPORT-NEVER-THROWS`.

## Why a printer needs two catches

**This is the point the whole design turns on.**

A printer does not throw when `print_document` runs. It builds a graph of thunks
and returns. It throws later, inside one of those thunks, while the renderer
pulls the output — one frame later, or a hundred. A `try` around the call to
`print_document` therefore catches almost nothing.

So `FaultCatchingProjection` catches in both places, and what its catch *answers*
is a value rather than an exception. That single move makes three things fall
out of the reactive engine for nothing:

- **The spin stops.** The engine caches the mark, so the thunk does not run
  again and does not throw again. Without this the read repeats every frame and
  the editor faults a hundred times a second.
- **It heals by itself.** The mark is cached under the same dependencies the
  real value had, so when the input that caused the fault changes, the thunk
  runs again and the real output comes back. Nobody writes code for that.
- **It stays local.** The exception never escapes the cell, so no other read is
  aborted and the rest of the cached graph is untouched.

## Why the store is not made of cells

A thunk may not write a cell (`PAR-NO-WRITE-IN-THUNK`): a write in the middle of
a computation invalidates consumers half way through. But the message log is a
document made of cells.

So the catch writes a `FaultStore` instead — a plain object outside the reactive
graph, with no dependents to invalidate. The editor's frame then calls
`report_frame_faults!` once, on its own task, outside every thunk, and *that*
call writes the log. Two properties make the store safe to write from a thunk,
and both invariants carry the carve-out:

- it is **outside the graph**, so nothing can be invalidated half way;
- its write is **idempotent**, keyed by identity, so a thunk that runs ten times
  for one logical fault leaves one entry.

## Why a substitute is not optional

Without one, a fault spreads two ways.

*Down the chain.* The output is a bare `FaultReport`, the next step does not
know that type, throws, and its own barrier fires. Four steps make four records
for one cause.

*Out to the siblings, which is worse.* A parent printer often reads its child's
output — it measures a width, it counts a length. A parent handed a
`FaultReport` throws in its **own** thunk, so one mark then replaces the whole
parent subtree. A substitute keeps the child's output a real document of the
right domain, so containment stays at the one node that failed.

Do not lean on the throw downstream either: a step whose type dispatcher ends in
an `Any` entry will not throw on a `FaultReport`. It prints something wrong, and
quietly.

## Why the key holds no reference

A chain bounds how far a fault spreads downward — four steps at most. Nothing
bounds how far it spreads sideways: one bug in one projection fails at every
leaf of one kind, which in a large document is thousands of nodes.

So `compute_fault_key` holds the site, the origin and the exception type, and
holds neither the reference nor the message. Three thousand failures become one
record with `count = 3000` and one place kept as an example. The document still
shows one mark per node, because each mark is a value in that node's own cell.
The document says **where**; the log says **what** and **how many**.

The drain hands a record over once per power of ten, so a fault that repeats
every frame does not rewrite the log every frame.

## What the editor does to repair itself

| after | what happens |
| --- | --- |
| an operation fault | the inverse taken **before** the change is applied is applied back |
| an operation fault | the projection is dropped, so the next frame prints from scratch |
| an operation fault | a selection that no longer resolves is cleared |
| eight device faults in a row | that half of the backend seam is left alone |
| four print faults in a row | the safe mode shows the fault list; Escape leaves it |

A `CompoundOperation` gets no rollback: its way back is built member by member,
and only `evaluate_invertible_operation!` does that interleave.

## What it does not do

- It does not make a `CompoundOperation` atomic.
- It does not fix the race between a tool task and the frame. The assistant and
  the MCP server write `editor.document` directly rather than through
  `post_operation!`, and the inbox exists to stop exactly that.
- It does not change how a parse error is reported. A parser that answers a
  partial document is a different concern from a projection that throws.

## Test it

`test_fault()` in `ProjecturedFaultTest`. The three suites are the store, the
report cascade and the barrier, plus the safe mode driven against a real editor.
The test that matters most raises the failure from inside the output cell rather
than from `print_document`, because that is where a real printer fails.
