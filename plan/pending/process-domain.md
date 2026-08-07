# Process domain — structured flowcharts beside fsm

A new domain layer for process modeling: algorithms drawn as flowcharts. A
process is what a spec draws as boxes and diamonds — do this, decide that,
loop until — and what a program writes as structured control flow. The domain
sits beside `fsm` as its run-to-completion complement: an fsm state is where
control *rests* waiting for events, a process step is work control *passes
through*. The two goals that drive every decision below:

1. **Mix naturally with the julia domain.** Conditions and actions are
   embedded `JuliaDocument` subtrees, and the document shapes align
   field-for-field with julia's structured control-flow nodes, so code
   generation is a mechanical 1:1 walk — unlike `FsmToJuliaCode`, which has to
   *synthesize* a dispatcher.
2. **Print and edit as a graph.** The flowchart picture is a projection
   through the existing diagram pipeline (`FsmDiagram` → graph → adaptagrams →
   graphics precedent), not the document shape.

## Requirements

- Steps, binary decisions, pre-test and foreach loops, jumps
  (break/continue/return), sequences; single-token run-to-completion
  semantics. No events, no waiting, no parallelism — that is fsm's territory,
  and keeping it there is what makes the two domains complementary rather
  than overlapping.
- A step can be **informal**: a prose description with no code yet ("wait for
  carrier", the way IEEE spec flowcharts read). Refinement = adding the code.
  This is the reason the domain exists at all rather than being a flowchart
  projection over the julia domain (D2).
- **Realization**: a `ProcessModel` projects to a runnable `JuliaFunction`,
  embedded code spliced verbatim (the `FsmToJuliaCode` contract: what the
  author sees is exactly what runs). "Realize" = document → runnable Julia,
  the term used throughout this plan.
- **Debugging the realization in the editor**: while a realized process runs,
  *where it is* is reflected live in the UI — in the diagram (the executing
  box ringed, the arrow just taken re-stroked) and in the notation (the
  executing line highlighted), from one shared position vocabulary. The UI
  also drives execution: breakpoints, step, continue, pause. Realized code
  must stay runnable **outside** the editor, so nothing in it may depend on
  the document or projection layers.
- Graph presentation: decision diamonds, labeled yes/no edges, loop
  back-edges, start/end terminators; selection round-trips (clicking a box
  selects the process node).
- Textual notation as the primary edit surface, `@projection_template`-based
  like `FsmToSyntax`.

## Where the code goes

```
package/domain/main/process/
  Process.jl                  — document types, ctors, insertions, gestures
  ProcessRuntime.jl           — plain-Julia probe runtime (no ProjecturEd deps)
  ProcessToSyntax.jl          — the notation (primary edit surface)
  ProcessDiagram.jl           — presentation document
  ProcessDebugSession.jl      — live position + debug control, shared by both views
  ProcessToProcessDiagram.jl  — thin identity-keeping stage
  ProcessDiagramToGraph.jl    — flowchart derivation into graph vertices/edges
  ProcessToJuliaCode.jl       — realization (one-way), plain and instrumented
package/domain/doc/process.md — semantics contract, notation grammar, diagram
                                rules, the probe protocol
```

Include order in `ProjecturedDomain.jl`, mirroring fsm's two groups:
`process/Process.jl`, `process/ProcessRuntime.jl`, `process/ProcessDiagram.jl`
and `process/ProcessDebugSession.jl` right after `fsm/FsmDiagram.jl`
(document-model group); the four projections after fsm's projection block
(`FsmToSyntax` … `FsmToJuliaCode`), since `ProcessToSyntax` composes with the
julia dispatch table and `ProcessToJuliaCode` imports julia node types.

## Design decisions

### D1 — A structured tree, not a node/edge list

The document is recursive — sequences, decisions and loops *nest* — not a flat
vertex list with identity-referenced edges (the `FsmMachine` shape). This is
the load-bearing decision:

- **Julia mixing becomes trivial.** A process tree is isomorphic to the
  structured subset of the julia domain (D3). The edge-list alternative makes
  codegen a CFG-structuring problem (recognizing which diamond+back-edge is a
  `while`; irreducible graphs need node duplication) — decompilation, not
  projection.
- **The graph stays easy.** Deriving vertices and edges from a tree is a
  plain printer (D8). Böhm–Jacopini guarantees no expressiveness is lost by
  going structured.
- **No identity references in v1 at all.** fsm needs them (any state targets
  any state) and pays for them — `Fsm.jl` records the `copy_document`
  alias-table limitation. A process subtree copies structurally, no fix-up.
- **Graph editing stays meaningful.** Every edit the graph surface will ever
  offer maps to a structured operation (insert into sequence, wrap in loop);
  free edge drawing that produces meaningless control flow is unrepresentable.

fsm is a graph domain because state machines *are* graphs. Processes only
look like graphs; they are trees wearing a graph projection.

### D2 — A domain of its own, not a flowchart projection over julia

The cheaper alternative was considered: if every step is executable Julia,
a `JuliaToFlowchartDiagram` projection over the existing julia domain would
give maximal mixing with zero new types. Rejected because a process node
carries what a Julia AST cannot: a **prose description before there is code**
(`ProcessStep.description`), the informal→formal refinement workflow, and
flowchart-legal structure enforcement. Same reason fsm is a domain and not a
projection over a hand-written dispatch function. The price is small because
D3 keeps the mapping mechanical.

### D3 — Shapes aligned field-for-field with julia; embedded code held opaque

| process | julia | codegen |
|---|---|---|
| `ProcessSequence.steps` | `JuliaBlock.statements` | 1:1 |
| `ProcessDecision(condition, then_branch, else_branch)` | `JuliaIf` | 1:1 |
| `ProcessWhile(condition, body)` | `JuliaWhile` | 1:1 |
| `ProcessForeach(variable, iterable, body)` | `JuliaFor` (single clause) | 1:1 |
| `ProcessBreak` / `ProcessContinue` / `ProcessReturn(value)` | `JuliaBreak` / `JuliaContinue` / `JuliaReturn` | 1:1 |
| `ProcessModel(name, parameters, body)` | `JuliaFunction` | 1:1 |
| `ProcessStep(description, action)` | its `action` statement(s) | splice |

Embedded code (a decision's condition, a step's action, a foreach's
variable/iterable, the model's parameters) are `JuliaDocument` subtrees held
as opaque `::Any` fields — **the slice has no julia edge at the document
level**, exactly the `Fsm.jl` precedent. Only `ProcessToSyntax` (shared
recursion) and `ProcessToJuliaCode` (verbatim splice) know what is inside.

### D4 — Run-to-completion; fsm complementarity preserved

Semantics contract (goes in `doc/process.md`, the `fsm.md` "contract" section
as template): execution is structural traversal — a sequence runs its steps in
order; a decision evaluates its condition and takes one branch; `while`
pre-tests; `foreach` iterates; jumps behave as in Julia. One token, no
waiting. A model is **executable** iff every step has an action and every
decision/loop has a condition; codegen checks and reports (D9).

Composition points this leaves open (follow-ups, not v1): a process body
embedded as an `FsmState.entry` / `FsmTransition.action` — the flowchart
describing what happens *within* one reactive step — and a `ProcessModel` as
an item among a Julia module's definitions.

### D5 — Naming: `process` layer, `Process*` types, root `ProcessModel`

The domain is named for the semantics, the picture for the projection —
domain `fsm`, picture `FsmDiagram`; domain `process`, picture
`ProcessDiagram`. Rejected: `flowchart` as domain name (names the picture),
`Flow*` (ambiguous with dataflow). The root cannot be bare `Process` —
`Base.Process` is exported — hence `ProcessModel` (also the process-mining
term of art). Notation keywords reuse `if/else/while/for/break/continue/
return` with their exact Julia meanings (reuse with identical meaning is not
overloading) plus two minted ones: `process`, `step`.

### D6 — Bodies are always `ProcessSequence`; `else` is optional

`ProcessModel.body`, both decision branches when present, and loop bodies are
always a `ProcessSequence` (possibly empty) — uniform recursion, and an empty
sequence is the natural insert point for the reader. `else_branch = nothing`
means *no else branch* (renders nothing, codegen omits it), distinct from an
empty one. `@domain Process` provides `ProcessDocument`, `ProcessNothing`,
`ProcessInsertion`; placeholders must be typed, navigable and selectable
(the json-domain lesson).

**Implemented in P1, with one relaxation.** A body field defaults to
`nothing` rather than to an empty sequence, and `body_steps(body)` normalizes:
`nothing` is an empty body, a `ProcessSequence` is its steps, anything else is
a one-node body. A constructor cannot fill the default instead — a
hand-written ctor whose only positional parameter is `::Any` has the *same*
signature as the macro's generated positional form, and redefining it is a
fatal precompile overwrite. `else_branch === nothing` keeps its distinct
meaning (*no else branch*, as opposed to an empty one), the one place the
distinction is load-bearing.

Field requiredness follows from Rule Y (positional ctors need `req ≥ 1`):
`ProcessModel.name` and `ProcessStep.description` are required, every other
node is fully defaulted so `T()` works and the macro emits the keyword form.
Only those two need an `@insertion` factory — the rest are already zero-arg
constructible, which is what `insertable`'s probe asks for.

### D7 — Two-stage presentation, identity-stable; v1 graph is view + selection

`ProcessToProcessDiagram` builds the `ProcessDiagram` once per projection
setup and keeps its identity (the `ChartToChartPlot` / `FsmToFsmDiagram`
pattern — also what keeps the adaptagrams layout from collapsing on re-read).
`ProcessDiagram` carries the `model` and the `session` (D12) whose cells the
live overlay reads — a driver takes the diagram's handle at setup and writes
the same cells for the rest of the run, which is why the identity has to hold.

v1 scope on the graph surface: **view, navigation, selection** — clicking a
vertex yields the whole-element (∅) selection of the corresponding process
node, round-tripped through the pipeline (School A: each stage peels only the
step it owns, `FsmToFsmDiagram` precedent). Structural editing *from the
graph* (insert-after, wrap-in-loop as vertex context operations) is a
follow-up; v1 editing happens in the notation.

### D8 — Diagram derivation rules

`ProcessDiagramToGraph` prints the tree into `GraphVertex`/`GraphEdge`:

- Every step, decision, loop header and jump → one vertex. Vertex content is
  a document (the graph domain renders any content): a step shows its
  description if nonempty, else its action code; a decision/loop shows its
  condition (rendered through the stock julia pipeline).
- **Start/end terminators are synthesized vertices** — picture-only, no
  document nodes behind them (the ANSI terminator is drawing, not semantics).
- Sequence → chain of edges. Decision → `yes`/`no`-labeled out-edges to the
  branch heads; **no merge vertex** — both branch tails route directly to the
  successor vertex. Fallback if adaptagrams routing degrades on shared
  targets: synthesize small UML-style merge diamonds.
- While → condition vertex with `yes` → body head, body tail → back-edge to
  the condition, `no` → successor. Foreach → header vertex ("more items?")
  with the same two exits.
- `break` → edge to the enclosing loop's successor; `continue` → edge to the
  loop header; `return` → edge to the end terminator.
- Vertex identity is stable across reprints (layout stability).
- The live overlay is two `ComputedCell`s over the session (D12), the
  `FsmDiagramToGraph` shape: `highlight_vertex` resolves `session.node` to a
  vertex; `highlight_edge` resolves the `(session.previous, session.node)`
  pair to the edge between them. Deriving the stroked arrow from the node
  *pair* is what keeps edges picture-only — the document has no edge to
  index, and the runtime never learns a picture vocabulary. Both cells read
  nothing else, so a step arriving mid-run repaints the overlay without
  invalidating anything the layout engine depends on.

### D9 — Realization: one-way, document-to-document, executability check

`ProcessToJuliaCode` follows `FsmToJuliaCode`: deliberately **not** a
registered bidirectional projection (the `.process` document is the source,
the `.jl` output), but document-to-document, so realized code can be shown
through the stock julia pipeline without stringifying. Block actions splice
their statements inline; parameters splice into the `JuliaFunction` header.
An **unrefined step** (action `nothing`) generates
`error("unrefined step: <description>")` — the honest executable of an
informal box. Step descriptions are otherwise dropped in realized code (the
julia domain has no comment node). The reverse importer (structured-subset
Julia → process) is mechanically feasible thanks to D3 and recorded as a
follow-up.

### D10 — One position vocabulary: the node index

Everything about debugging hangs off a single shared vocabulary, the
`machine_transitions` / `transition_index` precedent: `process_nodes(model)`
flattens the tree in document order into a `Vector`, and `node_index(model,
node)` is a node's 1-based position in it (0 when absent). Realization
numbers nodes by the **same walk**, so a bare `Int` is all the realized code
ever reports, and both views resolve that `Int` back to a node by identity.

**Landed in `Process.jl` (P1), not P4** — the walk is document-level
vocabulary, next to the types it walks, exactly as `machine_transitions` sits
in `Fsm.jl`. It indexes **every** node, sequences and placeholders included,
so the mapping is total and no consumer needs a second numbering; the nodes
that never appear in a trace simply never come up. `process_children(node)`
is the walk's one extension point and is what keeps embedded Julia opaque.

This is what lets the runtime stay ignorant of ProjecturEd (D11) and the
notation and the diagram share one live position without either knowing about
the other (D13). It is also the fragile part: the index vocabulary is only
valid for the tree the code was realized from, hence the staleness guard in
D12.

### D11 — Realization is instrumented at a chosen level; the probe protocol

Debugging needs the realized code itself to say where it is — nothing else
can know. So `ProcessToJuliaCode(; instrumentation = :position)` takes a
level, and the *same* tree walk emits the same code plus, per level, one
extra statement per node:

| level | emitted per node | use |
|---|---|---|
| `:none` | nothing | export / ship; zero overhead |
| `:position` | `process_at!(trace, i)` | in-editor debugging (default) |
| `:locals` | `process_at!(trace, i, (; x, y, …))` | position + variable watch |

`:locals` splices a `NamedTuple` of the variables in scope at that node —
statically known, since they are the model's parameters plus the assignment
targets and loop variables of enclosing nodes. It allocates per step, which
is why it is a level rather than the default.

Probes are strictly **additive** — one statement, always in statement
position, never rewriting the surrounding code — so an instrumented and a
plain realization cannot diverge in behaviour by construction; a test asserts
the two return equal results (D-risk: Heisenbug).

`trace` is threaded as the realized function's first parameter, defaulted:
`f(args…; trace = nothing)`, and `process_at!(::Nothing, …)` is a no-op, so
even an instrumented realization runs standalone with no debug machinery
attached.

**The runtime is plain Julia.** `ProcessRuntime.jl` defines a `mutable struct
ProcessTrace` and the `process_at!` protocol with **no ProjecturEd
dependency** — no `@document`, no cells — exactly as omnetpp-julia's `Fsm`
runtime does for `FsmToJuliaCode`. Realized code says `using ProcessRuntime`
and depends on nothing else; the module ships in the domain package for the
editor's own use, and an embedder (a simulation host) may substitute its own
implementation of the same protocol. The protocol, not the file, is the
contract, and `doc/process.md` states it.

### D12 — `ProcessDebugSession`: the document side, bridged on the refresh hook

The session is a document (never serialized — live view state, the
`FsmDiagram` rule that a running machine's position is not part of the
machine) holding cells: `node`, `previous`, `step_count`, `status`
(`:detached | :running | :paused | :finished | :stale`), `breakpoints`
(node indices), `locals`, `node_count` (the staleness stamp).

**Two objects, one bridge.** The `ProcessTrace` is written by the running
code; the session is what projections read. `sync_process_debug!(session,
trace)` runs **from the editor's refresh hook, never from a cell** (the
`refresh_lifecycle!` rule — it writes), and goes both ways in one call: it
pulls position/locals up into the session's cells with `set_cell_value!`, and
pushes UI intent down into the trace (breakpoint set, run mode, resume). One
function, one direction of control flow, no cell ever written from the
process's task.

**Threading.** A realized process runs on its own `Task` so a breakpoint
cannot block the editor loop; the trace is written by that task and read by
the refresh hook. Only `Int`s and an immutable `NamedTuple` cross, and the
process is *stopped* whenever the interesting reads happen, so no lock is
needed — but the rule that document cells are only ever written by the
refresh hook is what actually keeps this safe, and it is absolute.

**Blocking is the runtime's job.** `process_at!` records, then blocks on a
`Channel` when node `i` is in `breakpoints` or the mode is `:step`. Continue
/ step / pause / stop are gestures → operations that write session fields;
the next bridge call turns them into runtime writes. Pause latency is one
refresh, which is imperceptible and buys a threading model with no traps.

**Staleness.** Node indices belong to the tree the code was realized from, so
the session stamps `node_count = length(process_nodes(model))` at
realization; when it stops matching, the bridge sets `status = :stale` and
the views drop the highlight instead of ringing the wrong box. Cheap, and it
catches exactly the edits that shift indices (structural ones — editing
embedded Julia does not).

### D13 — Both views reflect it; breakpoints are session state

The session is deliberately **not** a field of `ProcessDiagram` alone: "where
the process is" belongs in the notation as much as in the flowchart, and the
notation is the primary edit surface. So `ProcessDebugSession` is its own
document, `ProcessDiagram` holds one, and `ProcessToSyntax(; session =
nothing)` optionally takes the same one — printers read its cells *inside*
cells, so the highlight repaints reactively without a reprint (the rule that
a printer reading a cell outside a cell freezes the render).

Breakpoints live on the session, not on `ProcessStep` — they are debug state,
not process content, and keeping them off the document is what lets
`Process.jl` stay pure content. A breakpoint gesture on a step (either view)
toggles the node's index in `session.breakpoints`.

## Document model (sketch)

```julia
@domain Process   # generates ProcessDocument, ProcessNothing, ProcessInsertion

@document struct ProcessModel <: ProcessDocument
    name::String                       # required — keeps the positional ctor (Rule Y)
    parameters::CellVector = CellVector()  # embedded Julia items (identifier / ::type)
    body::Any = nothing                # a ProcessSequence
end

@document struct ProcessSequence <: ProcessDocument
    steps::CellVector = CellVector()
end

@document struct ProcessStep <: ProcessDocument
    description::String = ""           # the prose face; "" = code-only step
    action::Any = nothing              # embedded JuliaDocument; nothing = unrefined
end

@document struct ProcessDecision <: ProcessDocument
    condition::Any = nothing           # embedded JuliaDocument boolean
    then_branch::Any = nothing         # ProcessSequence
    else_branch::Any = nothing         # ProcessSequence, or nothing = no else
end

@document struct ProcessWhile <: ProcessDocument
    condition::Any = nothing
    body::Any = nothing
end

@document struct ProcessForeach <: ProcessDocument
    variable::Any = nothing            # embedded Julia identifier
    iterable::Any = nothing            # embedded Julia expression
    body::Any = nothing
end

@document struct ProcessBreak    <: ProcessDocument end
@document struct ProcessContinue <: ProcessDocument end
@document struct ProcessReturn   <: ProcessDocument
    value::Any = nothing
end
```

The live side (D11–D13). The session is a document; the trace is not:

```julia
# ProcessDiagram.jl — presentation document, projection output, never content
@document struct ProcessDiagram <: ProcessDocument
    model::Any
    session::Any = nothing             # a ProcessDebugSession
end

# ProcessDebugSession.jl — live position and debug control; never serialized
@document struct ProcessDebugSession <: ProcessDocument
    status::Symbol = :detached         # :detached|:running|:paused|:finished|:stale
    node::Int = 0                      # current node index; 0 = nowhere
    previous::Int = 0                  # the node stepped from — the picture's edge
    step_count::Int = 0
    breakpoints::CellVector = CellVector()   # node indices
    locals::Any = nothing              # NamedTuple at the last probe, or nothing
    node_count::Int = 0                # staleness stamp taken at realization
end

# ProcessRuntime.jl — PLAIN Julia. No @document, no cells, no ProjecturEd.
mutable struct ProcessTrace
    node::Int
    previous::Int
    step_count::Int
    locals::Any
    mode::Symbol                       # :run | :step | :pause | :stop
    breakpoints::Set{Int}
    resume::Channel{Symbol}
    on_step::Any                       # nothing | (trace, i) -> nothing
end

process_at!(::Nothing, i, locals = nothing) = nothing   # runs standalone
function process_at!(trace::ProcessTrace, i, locals = nothing)
    trace.previous, trace.node = trace.node, i
    trace.step_count += 1
    trace.locals = locals
    hook = trace.on_step; hook === nothing || hook(trace, i)
    (trace.mode === :step || i in trace.breakpoints) && take!(trace.resume)
    trace.mode === :stop && throw(ProcessStopped())
    nothing
end
```

The `on_step` hook mirrors `Fsm.on_transition`: an embedder that wants
statistics or tracing hangs them off it instead of tangling recording into
the protocol.

Constructors follow fsm's "mixed positional+keyword" section verbatim: the
natural authoring shapes (`ProcessStep("prepare"; action = …)`,
`ProcessModel("transmit"; parameters = […], body = …)`) are hand-written with
typed arguments so they stay strictly more specific than the macro's `::Any`
forms — shadowing a generated method is a fatal precompile overwrite.
`@insertion` factories for every type (caret at the natural first hole:
`name{0}`, `description{0}`, `condition{0}`), since `insertable(T)`'s `T()`
probe silently drops types with required fields. Structural-insert gestures as
in fsm: `KeyPress(',')` appends a `ProcessInsertion` into the enclosing
sequence.

## Notation (sketch)

```
process csma_transmit(frame)
  step "prepare" / x = encode(frame)
  while attempts < max_attempts
    if carrier_free()
      step / start_tx!(ctx, x)
      return :sent
    step "binary exponential backoff"
    step / attempts += 1
  return :failed
```

Line grammar (parts optional where bracketed; indentation-scoped bodies, no
`end`, the fsm precedent):

```
process NAME(PARAM, …)
step ["DESCRIPTION"] [/ ACTION]     — at least one part present
if CONDITION   /  else
while CONDITION
for VAR in ITERABLE
break  |  continue  |  return [VALUE]
```

The `/ ACTION` separator and action-last placement are fsm's, for fsm's
reason: an action can be a block, rendering as an indented run of lines, and
anything printed after it would be stranded. Rules are `@projection_template`
builders composed with the julia type-dispatch table into one
`TypeDispatchingProjection` (the `FsmToSyntax` / `FormulaToSyntax` pattern);
every compound rule collapses unmapped carets to a bounded `_syntax_to_flat`
offset — projection-introduced chrome (every keyword) is pervasive here, and
without that reader text navigation runs away.

## Examples, tests, registration, docs

- **Example**: `process_example = Example("process", …)` in
  `package/domain/example/Examples.jl` + the catalog list. Content: the
  CSMA-flavored transmit procedure above — exercises every node type,
  includes one informal step, a decision inside a loop, `break`-free but
  `return`-from-loop control (add one `break`/`continue` pair in a second
  small model if one example can't cover all jumps naturally).
- **Tests**: `test_example(process_example)` (printer, reader, position
  navigation with `check_reaches_all = true`), `test_typein`, `test_repl`;
  the chained stacks explicitly (process→syntax→text and
  process→diagram→graph→graphics — single-stage tests miss chain rules); a
  render test that forces the tree and presses real pixels, in the editor's
  real order (print→refresh→select→refresh→click→refresh→type); realization
  test: realize → `document_to_text` → include in a sandbox module → call the
  function → assert the result, plus a verbatim-splice assertion (the
  `FsmToJuliaCodeTest` sandbox pattern, with `ProcessRuntime` included as
  source into the sandbox exactly as `_PROBE_RUNTIME_SOURCE` is). Run under
  the usual memory cap.
- **Debug tests** (P5): realize at `:position`, run to completion with a
  trace attached, assert the visited node-index sequence is exactly the
  expected path (including the loop's repeats and the branch not taken);
  assert `:none` and `:position` realizations return equal results (the
  Heisenbug guard); breakpoint test — run on a task, assert it blocks at the
  marked node, that the session reports `:paused` at that node after one
  bridge call, and that continue resumes; step-mode test walks the path one
  node at a time; staleness test appends a step to the model and asserts the
  next bridge marks `:stale` and both views drop the highlight; and a render
  assertion that the *stroked* vertex and edge are the right ones (force the
  tree and check the highlight cells resolve to the expected objects, not
  merely that the function returned).
- **Docs**: `package/domain/doc/process.md` — document types, notation
  grammar, the execution/realization contract (fsm.md's contract section as
  template), the `process_at!` probe protocol and instrumentation levels as a
  contract an embedder can reimplement, diagram derivation rules. Add the
  module inventory entry in `documentation/architecture.md`.

## Phases

- [x] **P1 — Document model.** *Done.* `process/Process.jl` (types, ctors,
  insertions, gestures), `@domain` wiring, the include in
  `ProjecturedDomain.jl`, and the tree walk (`process_children`,
  `process_nodes`, `node_index`, `node_at`, `body_steps`, `unrefined_nodes`,
  `is_executable`). `test_process()` in `document/ProcessTest.jl` covers
  construction, document order, index round-trip, opaque embedded Julia,
  placeholders as nodes, and the insertion kit — 66 passing.
  `process_example` moves to P2, where there is a projection to render it.
- [x] **P2 — Notation.** *Done.* `ProcessToSyntax.jl` template rules merged
  with the julia dispatch table; `_syntax_to_flat` readers on every compound
  rule; `process_example` / `process_drain_example` registered with their
  document and projection factories. Green: printer 3139, reader 225, position
  navigation 365, repl 225 (each example), notation assertions 107.
  `test_typein(process_example)` inherits the julia domain's name-leaf caret
  gap (`test_typein(julia_example)` is 0 of 84 on a clean tree), so the
  notation's own typein is guarded by a julia-free document instead — 75 of
  75, and that assertion lives in `ProcessToSyntaxTest`.
- [x] **P3 — Diagram.** *Done.* `ProcessDiagram.jl`,
  `ProcessToProcessDiagram.jl`, `ProcessDiagramToGraph.jl` per D8, plus
  `process_diagram_example`. 36 passing: the flowchart's arrows (spine, both
  loop exits, the back edge, labelled decision exits with no merge vertex,
  `continue` to the header, `break` to the loop exit, `return` to stop), the
  overlay repainting reactively without moving the layout, and the selection
  round-trip.

  Three things the implementation settled. **`ProcessDebugSession.jl` landed
  here, not in P5** — the overlay has to read something, and the document is
  independent of the runtime that fills it. **`ProcessTerminal` and
  `ProcessEdgeLabel`** are presentation documents in `ProcessDiagram.jl` with
  label rules of their own: a terminal oval and an arrow caption have no
  document node behind them, and inventing one to carry a string would have
  been faking content. **A hand-built `@reference` must type its last node
  too** — `…vertices[i]::GraphVertex.content::nt` with
  `nt = get_reference_node_type(node)`; `FsmDiagramToGraph` gets away without
  it only because its trailing `^(rest)` splice carries the type.
- [ ] **P4 — Realization.** `ProcessToJuliaCode.jl` per D9 at
  `instrumentation = :none`, with the executability check;
  `process_nodes` / `node_index` (D10) landed here since realization is their
  first user; realized-module run test.
- [ ] **P5 — Debugging.** `ProcessRuntime.jl` and the probe protocol (D11);
  the `:position` and `:locals` levels; `ProcessDebugSession.jl` and
  `sync_process_debug!` (D12); live overlay in the diagram (D8 last bullet)
  and the notation highlight (D13); run/step/continue/pause/breakpoint
  gestures and operations; the debug test set above. Land the position
  reflection first and get it green before the control commands — reflection
  is the requirement, control is what makes it usable.
- [ ] **P6 — Docs.** `doc/process.md` including the probe protocol;
  architecture inventory entry.

## Risks

- **Pervasive introduced tokens.** Every keyword is projection chrome; carets
  on introduced tokens historically needed handling in three places (forward
  map, backward map, tree-navigate unwrap). The template + flat-offset
  readers are the mitigation; `check_reaches_all` navigation is the verifier.
- **Ctor arity traps.** Keep `name`/`description` requirements as sketched;
  do not widen Rule Y; hand-written ctors must stay strictly more specific
  than generated `::Any` forms.
- **Layout stability.** The diagram must be built once and reconciled, or
  the reactive `GraphToGraphLayout` collapses on re-read; live tests call
  `initialize_backend!` before measuring.
- **Merge-free routing** (D8) may render badly on adaptagrams for deeply
  nested decisions — the merge-diamond fallback is the recorded plan B.
- **Placeholder type-swap.** `ProcessInsertion` swapping into a concrete type
  on a gesture needs the whole-tree dispatching projection in catalog
  registration (the self-modifying-document rule).
- **Hand-built references** in tests/readers must carry type checkpoints
  (`reference_node_type`, `::CellVector` before index steps).
- **Index staleness** (D12) is the sharp edge of the whole debug design:
  edit the process while it runs and every index means something else. The
  `node_count` stamp is the guard; the test that appends a step mid-run is
  what proves it, and `:stale` must be visibly *no* highlight, never a
  plausible wrong one.
- **A blocking probe inside a host.** Breakpoints block the calling task by
  design. Fine for a process the editor started on its own task; **not** fine
  for a process realized into a simulation, where blocking stops the whole
  simulation. Embedded realizations run at `:none`, or with an empty
  breakpoint set and `mode = :run`, and `doc/process.md` says so.
- **Cells written off the refresh hook.** The one threading rule (D12); a
  probe that writes a document cell from the process's task would race the
  editor. `ProcessRuntime` having no ProjecturEd dependency is what makes
  that mistake unrepresentable — keep it that way.
- **Instrumentation divergence.** Mitigated structurally (additive probes,
  one walk) plus the equal-results test; if a probe ever needs to be anything
  other than one statement in statement position, that is a design change,
  not an implementation detail.

## Out of scope (follow-ups)

- Multiway decision node — `elseif` chains nest in `else_branch` for now; a
  dedicated N-way node (and its cascade rendering) later.
- `ProcessCall` — invoking another process (the ANSI "predefined process"
  box). Deferred *because* it reintroduces identity references and fsm's
  copy/paste alias-table concern; v1 calls are plain steps whose action is a
  Julia call.
- Parallel fork/join; any event/wait node — the latter permanently: waiting
  is fsm's job (by design, not deferral).
- Julia → process importer over the structured subset (D3 makes it
  mechanical).
- Graph-side structural editing operations (insert-after, wrap-in-loop from
  the diagram).
- Debugger comforts beyond P5: conditional breakpoints (a `JuliaDocument`
  predicate evaluated in the probe), a step history / time-travel scrub over
  recorded traces, editing a variable while paused, step-over vs step-into
  (meaningless until `ProcessCall` exists), and debugging several concurrent
  realizations of one model (the session assumes one).
- Attaching the debugger to a realization running in another process or a
  simulation host — the protocol allows it (the trace is plain data, the
  bridge is one function), but the transport is not designed here.
- Post-test (do-until) loop; multi-clause `foreach`.
- Hybrid embedding both ways: a process body as `FsmState.entry` /
  `FsmTransition.action`; a `ProcessModel` among a Julia module's items.
