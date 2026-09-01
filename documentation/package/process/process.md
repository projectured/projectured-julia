# The `process` domain — structured flowcharts

> **Kind:** reference · **Status:** current · **Stands on:** [system-anatomy.md](../../design/system-anatomy.md), [domain-inventory.md](../../design/domain-inventory.md)

An algorithm as a first-class document: steps, decisions, loops and jumps that
nest, run to completion, and project both to a notation and to a flowchart. The
slice exists so a procedure can be drawn the way a specification draws it — and
still be real, runnable code, debuggable in the editor while it runs.

Slice: `package/process/main/`. Design plan: `plan/done/process-domain.md`.

## Process or state machine?

The two domains are complements, and the difference is one line:

| | `fsm` | `process` |
| --- | --- | --- |
| a node is | a **state** — where control rests, waiting | a **step** — work control passes through |
| an edge is | a transition: `trigger [guard] / action` | plain "next", labelled only out of a decision |
| what advances it | an external event or timeout | the completion of the step before it |
| where the Julia is | on edges (guard/action) and state entry | inside nodes (action, condition) |
| lifetime | long-lived, reactive | starts, runs, ends |
| shape | a graph — any state may target any state | a tree — the graph is derived from the nesting |

If it waits, it is a state machine. A process that needs to wait belongs inside
one: an `FsmState.entry` or an `FsmTransition.action` is where a process body
fits, which is the composition this domain is shaped for.

## Document types

| Type | Holds |
| --- | --- |
| `ProcessModel` | the unit of realization: `name`, `parameters`, `body` |
| `ProcessSequence` | `steps` — the domain's block; every body is one |
| `ProcessStep` | `description` (prose) and `action` (code); either may be absent, never both |
| `ProcessDecision` | `condition`, `then_branch`, `else_branch` |
| `ProcessWhile` | `condition`, `body` — a pre-test loop |
| `ProcessForeach` | `variable`, `iterable`, `body` |
| `ProcessBreak` / `ProcessContinue` / `ProcessReturn` | the three jumps |

Embedded code (an action, a condition, a `for`'s variable and iterable, the
model's parameters) is a `JuliaDocument` subtree — real structured Julia, edited
natively and spliced verbatim into realized code. Nothing is stored as an opaque
source string, and nothing in this domain walks into one: `process_children`
descends structural children only.

Every shape has a Julia counterpart with the same fields (`ProcessDecision` ↔
`JuliaIf`, `ProcessWhile` ↔ `JuliaWhile`, `ProcessForeach` ↔ `JuliaFor`,
`ProcessSequence` ↔ `JuliaBlock`), which is what makes realization a 1:1 walk
instead of a translation.

**Nothing is held by identity.** A process is a tree; the flowchart's edges are
derived from the nesting rather than stored, so a subtree copies structurally
with no alias fix-up — the limitation `fsm` records for machines does not arise.

A body field may be `nothing`, which means an empty body; `body_steps` is what
normalizes it. Only `ProcessDecision.else_branch` distinguishes *absent* (no
else branch at all) from *empty*.

## Refinement

A step with a `description` and no `action` is **unrefined**: a specification
box that says what happens without yet saying how. That is the reason this is a
domain and not a flowchart projection over Julia function bodies.

- `unrefined_nodes(model)` — the nodes still waiting for code: a step with no
  action, a decision or `while` with no condition, a `foreach` with no variable
  or iterable.
- `is_executable(model)` — whether that list is empty.

Realizing an unrefined node emits `error("unrefined …")` rather than nothing.
A process that silently skipped its unwritten steps would lie about what it
does.

## The position vocabulary

`process_nodes(model)` flattens the tree in document order — a node before its
children, children left to right — and a node's 1-based index in that vector is
the **one position vocabulary** the whole domain shares: realized code reports
it, a breakpoint names one, and both views resolve it back with
`node_at` / `node_index`.

Every node is indexed, sequences and placeholders included, so the mapping is
total. A placeholder counts because a document being edited is a legal
document, and skipping it would shift every index after the caret.

Indices belong to the tree they were taken from. A structural edit renumbers
everything after it — see *staleness* below.

## Notation

The primary edit surface (`ProcessToSyntax`). Indentation-scoped, with no
`end`: a body is an indented run of lines, which is what makes the text read
like the picture.

```
process transmit(medium, payload, max_attempts)
  step "prepare" / frame = encode(payload)
  step / attempts = 0
  while true
    if carrier_free(medium)
      step / transmit!(medium, frame)
      return :sent
    if attempts >= max_attempts
      break
    step "wait a binary exponential backoff"
    step / attempts = attempts + 1
  return :failed
```

| Line | Renders |
| --- | --- |
| `process NAME(PARAM, …)` | the model header; parameters are embedded Julia |
| `step "DESCRIPTION" / ACTION` | both parts optional — a code-only step drops the quotes, an informal one has no `/` |
| `if CONDITION` … `else` | a decision; `else` appears only when there is an else branch |
| `while CONDITION` | a pre-test loop |
| `for VAR in ITERABLE` | an iteration loop |
| `break` / `continue` / `return [VALUE]` | the jumps |

`if`, `else`, `while`, `for`, `in`, `break`, `continue` and `return` carry their
exact Julia meanings and their Julia colour; only `process` and `step` are
minted. An unrefined hole renders a muted `<condition>` / `<variable>` /
`<iterable>` marker — chrome, so there is something to see and somewhere to put
a caret.

## Flowchart

`ProcessToProcessDiagram` → `ProcessDiagramToGraph` → the stock graph, layout
and graphics stages. The diagram document is built once per projection setup and
keeps its identity, so a driver can take its handle and keep writing it.

Every step, decision, loop header and jump gets a box whose content is the
document node **itself**, so clicking one selects the real node. Sequences get
none — they are structure, and the picture draws structure as edges. The start
and stop ovals (`ProcessTerminal`) and the arrow captions (`ProcessEdgeLabel`)
are presentation documents with no node behind them.

Arrows come from the standard structured-control-flow construction:

| Node | Arrows |
| --- | --- |
| sequence | each node to the next; the last to the sequence's own successor |
| decision | `yes` to the then-branch entry, `no` to the else-branch entry — or straight to the successor when that branch is empty or absent. **No merge vertex**: both tails already point at the successor |
| `while` | `yes` to the body entry, `no` to the successor; the body's successor is the header — that back edge is the loop |
| `foreach` | the same two exits, labelled `next` and `done` |
| `break` / `continue` / `return` | to the loop's exit / the loop's header / the stop terminal |

### Which engine draws it

The flowchart asks for `deferred_layout_engine(orthogonal = true)` rather than
naming an engine. Two things follow.

It gets **right-angled routes** where the engine can provide them, because a
flowchart's arrows are read as flow, and a diagonal between two boxes reads as
a relation instead of a direction.

And it gets the **best engine in the session**, resolved when the layout runs
rather than when the projection is built — `ProjecturedAdaptagrams` registers
itself from its `__init__`, so:

```julia
using ProjecturedAdaptagrams          # native placement + obstacle-avoiding routing
run_example("process_diagram")
```

Without it, the pure-Julia `GridEmbedding` places boxes on a grid and
draws straight lines between them — legible for a handful of boxes, crossed and
unreadable for a real procedure. The resolution is late on purpose: an
`Example` builds its projection in its constructor, at module load, which is
long before an optional native package can be loaded, so an engine captured
then would be the fallback forever.

Neither engine is a *flowchart* layout: both place by general graph criteria,
so the picture is not guaranteed to read top-to-bottom. A layout derived from
the process tree — where a sequence is a column, a decision opens two, and a
loop's back edge runs up a margin lane — would give that by construction, and
is the natural next step.

Known v1 limits: a selection maps only when it names a node exactly (a caret
*inside* a step's action does not light its box), and edges are not clickable.

## Realization

`realize_process(model)` turns a model into a `JuliaFunction`;
`realize_process_text` renders it as source and `export_process` writes it out.
Like `FsmToJuliaCode` this is deliberately **not** a registered bidirectional
projection — the process document is the source, the `.jl` file is output — but
it is document-to-document, so realized code can be shown through the stock
Julia pipeline without stringifying it.

### Instrumentation levels

`realize_process(model; instrumentation = …)` chooses how much the realized code
reports as it runs:

| Level | Emits per node | For |
| --- | --- | --- |
| `:none` | nothing | the artifact to ship; zero overhead |
| `:position` | `process_at!(trace, i)` | debugging in the editor |
| `:locals` | `process_at!(trace, i, (; x, y))` | position plus the variables in scope |

A probe is **one statement, always in statement position**, added in front of
what the node does — never a rewrite of it. That is what makes an instrumented
realization behave identically to a plain one, and there is a test that runs
both and compares.

Either instrumented level appends a `trace = nothing` parameter, so the realized
function is still callable with the process's own arguments alone.

`:locals` reports the model's parameters plus the variables assigned before that
point, minus anything a loop introduced once the loop has ended — Julia gives a
loop its own scope, and reporting its variable afterwards would name something
that no longer exists.

A loop is probed twice: before it, and as the first statement of its body. The
header is therefore marked on entry and at the top of every iteration, including
one a `continue` jumps to. The failing final test — the one that ends the loop —
is not marked; it is the one position a realized loop does not report.

## The probe protocol (the contract)

Realized code depends on **nothing but these names**, which is what keeps it
runnable outside the editor. `ProcessRuntime` is the implementation shipped
here; an embedder may substitute its own, exactly as the state machine
domain lets an embedder substitute its own `Fsm` runtime.

1. `process_at!(trace, index)` and `process_at!(trace, index, locals)` — record
   that execution reached node `index`.
2. `process_at!(::Nothing, …)` is a **no-op**. An instrumented realization must
   run at full speed with nothing attached.
3. A probe, in order: records the position (`previous` ← the old `node`),
   increments `step_count`, stores `locals`, calls the `on_step` hook if there
   is one, and then blocks if — and only if — the mode is `:step`/`:pause` or
   the node is in the breakpoint set.
4. Blocking blocks the **calling task**. A process being debugged runs on its
   own task (`start_process`); a process realized into a simulation must run at
   `:none`, or with mode `:run` and no breakpoints, or it stops the simulation
   with it.
5. Mode `:stop` unwinds by throwing `ProcessStopped`. The runner catches it;
   nothing else should.

## Debugging in the editor

Three parts, deliberately separable — an embedder that realizes into its own
host and drives its own trace uses only the first.

- **`ProcessTrace`** (`ProcessRuntime`) — plain mutable Julia. No cells, no
  documents. Written by the process's own task.
- **`ProcessDebugSession`** — a document. Live view state, never content and
  never serialized: `status`, `node`/`previous` (indices), `current` /
  `previous_document` (the same positions as documents, for views that have a
  node in hand but no root), `step_count`, `breakpoints` (nodes, held by
  identity), `locals`, `node_count`, `command`.
- **`sync_process_debug!(session, trace, model)`** — the bridge, and the only
  place the two meet. One call, both directions: breakpoints and the pending
  `command` down into the runtime, position and status back up.

**Call the bridge from the editor's refresh hook, never from a cell.** It
writes document cells, and the rule that only the editor's own task writes them
is what makes the threading model safe with no locks. The cost is that a
command takes effect within one refresh, which is not perceptible.

Both views reflect the session. The diagram rings the current box and re-strokes
the arrow just taken, derived from the `(previous, current)` pair — which is why
the runtime never needs a vocabulary for edges. The notation renders the current
node's keyword in the live colour and a breakpoint's in another; it is a **style
swap on a keyword that is printed anyway**, so a live position never shifts a
caret offset out from under whoever is typing.

### Staleness

Node indices belong to the tree they were realized from, so a session records
`node_count` at realization. When it stops matching, the bridge sets `status =
:stale` and clears the position, and both views draw **no** highlight. A
plausible wrong box would be worse than none. Editing an embedded Julia
expression does not renumber anything, which is why the node count is the stamp.

## What is not modeled

- **Waiting of any kind** — no event nodes, no timeouts. That is `fsm`, by
  design and not by omission.
- **Parallelism** — no fork/join. One token, run to completion.
- **Calling another process** — a call is a step whose action is a Julia call.
  A first-class `ProcessCall` would reintroduce identity references and the
  copy/paste concern this domain currently avoids.
- **Multiway decisions** — `elseif` chains nest in `else_branch`.
- **Post-test (do-until) loops** and multi-clause `foreach`.
- **Conditional breakpoints, step-over, time-travel** over a recorded trace,
  and debugging several concurrent realizations of one model (a session assumes
  one).
