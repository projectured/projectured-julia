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
- Codegen: a `ProcessModel` exports to a runnable `JuliaFunction`, embedded
  code spliced verbatim (the `FsmToJuliaCode` contract: what the author sees
  is exactly what runs).
- Graph presentation: decision diamonds, labeled yes/no edges, loop
  back-edges, start/end terminators; selection round-trips (clicking a box
  selects the process node).
- Textual notation as the primary edit surface, `@projection_template`-based
  like `FsmToSyntax`.

## Where the code goes

```
package/domain/main/process/
  Process.jl                  — document types, ctors, insertions, gestures
  ProcessToSyntax.jl          — the notation (primary edit surface)
  ProcessDiagram.jl           — presentation document
  ProcessToProcessDiagram.jl  — thin identity-keeping stage
  ProcessDiagramToGraph.jl    — flowchart derivation into graph vertices/edges
  ProcessToJuliaCode.jl       — codegen exporter (one-way)
package/domain/doc/process.md — semantics contract, notation grammar, diagram rules
```

Include order in `ProjecturedDomain.jl`, mirroring fsm's two groups:
`process/Process.jl` + `process/ProcessDiagram.jl` right after
`fsm/FsmDiagram.jl` (document-model group); the four projections after fsm's
projection block (`FsmToSyntax` … `FsmToJuliaCode`), since `ProcessToSyntax`
composes with the julia dispatch table and `ProcessToJuliaCode` imports julia
node types.

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

### D7 — Two-stage presentation, identity-stable; v1 graph is view + selection

`ProcessToProcessDiagram` builds the `ProcessDiagram` once per projection
setup and keeps its identity (the `ChartToChartPlot` / `FsmToFsmDiagram`
pattern — also what keeps the adaptagrams layout from collapsing on re-read).
v1 `ProcessDiagram` carries only `model`; the live execution overlay (token
position cells, `FsmDiagram`'s three-cell pattern) is a follow-up slot.

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

### D9 — Codegen: one-way exporter, executability check

`ProcessToJuliaCode` follows `FsmToJuliaCode`: deliberately **not** a
registered bidirectional projection (the `.process` document is the source,
the `.jl` output), but document-to-document, so generated code can be shown
through the stock julia pipeline without stringifying. Block actions splice
their statements inline; parameters splice into the `JuliaFunction` header.
An **unrefined step** (action `nothing`) generates
`error("unrefined step: <description>")` — the honest executable of an
informal box. Step descriptions are otherwise dropped in generated code (the
julia domain has no comment node). The reverse importer (structured-subset
Julia → process) is mechanically feasible thanks to D3 and recorded as a
follow-up.

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
  real order (print→refresh→select→refresh→click→refresh→type); codegen test:
  generate → `document_to_text` → include in a sandbox module → call the
  function → assert the result, plus a verbatim-splice assertion. Run under
  the usual memory cap.
- **Docs**: `package/domain/doc/process.md` — document types, notation
  grammar, the execution/codegen contract (fsm.md's contract section as
  template), diagram derivation rules. Add the module inventory entry in
  `documentation/architecture.md`.

## Phases

- [ ] **P1 — Document model.** `process/Process.jl` (types, ctors,
  insertions, gestures), `@domain` wiring, includes + exports,
  `process_example` registered; construction and structural-copy test.
- [ ] **P2 — Notation.** `ProcessToSyntax.jl` template rules merged with the
  julia dispatch table; `_syntax_to_flat` readers on every compound rule;
  printer / reader / position-navigation (`check_reaches_all`) / typein /
  repl green for `process_example`.
- [ ] **P3 — Diagram.** `ProcessDiagram.jl`, `ProcessToProcessDiagram.jl`,
  `ProcessDiagramToGraph.jl` per D8; selection mapping (vertex click → ∅
  selection of the node, round-trip); pixel-pressing render test.
- [ ] **P4 — Codegen.** `ProcessToJuliaCode.jl` per D9 with the
  executability check; generated-module run test.
- [ ] **P5 — Docs.** `doc/process.md`; architecture inventory entry.

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
- Live execution overlay on `ProcessDiagram` (token position; `FsmDiagram`'s
  three-cell pattern).
- Post-test (do-until) loop; multi-clause `foreach`.
- Hybrid embedding both ways: a process body as `FsmState.entry` /
  `FsmTransition.action`; a `ProcessModel` among a Julia module's items.
