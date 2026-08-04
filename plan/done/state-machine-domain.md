# Plan: a state machine domain (`fsm` slice) with codegen into inet-julia and a live view

A new **slice of the domain package** (`package/domain/main/fsm/`) providing an extended
finite state machine as a first-class document: named states with entry actions, guarded
event- and condition-driven transitions, first-class timers, extended-state variables,
and embedded Julia code (guards/actions as real `JuliaDocument` subtrees). Two editing
projections — a **textual natural notation** (the primary edit surface, through the
standard Syntax/Text pipeline) and a **state diagram** (through the graph slice, with a
live current-state/last-transition overlay) — plus a **code generator** that projects a
machine into a complete, runnable Julia module targeting the omnetpp-julia simulator, so
a machine authored in the editor becomes live inside an inet-julia simulation.

Grounding — what was read before designing (research fan-out, 2026-08-04):

- The three target machines in INET C++: `EthernetCsmaMac.{h,cc}` + `FSMA.h` (the
  macro FSM engine), `EthernetPlca.{h,cc}` + the §148 control/data `.dot` diagrams,
  and the TCP connection machine (`TcpConnectionBase/EventProc/RcvSegment.cc`).
  Distilled into the requirements checklist of §2.
- **inet-julia already contains hand-rolled Julia ports of two of the three**:
  `package/linklayer/main/t1s/` has `Mac.jl` (6-state CSMA MAC), `PlcaControl.jl`
  (14 states, condition-driven), `PlcaData.jl` (9 states, event-driven). Golden-hash
  coverage is narrower than "tested against INET" suggests: the pinned hash is the
  model's *own*, for the `:notraffic` scenario only (PLCA control activity; INET
  `.vec` cross-comparison also covers only that scenario) — the P5 acceptance
  accounts for this. These are the codegen pilot and the behavioral oracle. No
  generic FSM helper exists in omnetpp-julia or inet-julia today.
- projectured-julia idioms: the domain-slice checklist (json as worked example), the
  graph slice (vertices/edges/layout/selection round-trip and its known gaps), the
  julia domain + formula's embedding precedent, `document_to_text`/`export_document`,
  and the live-editor rules (`sync_document!` shadow sync, `set_cell_function!`
  conditional styling, AR-REACTIVE-OUTPUT-STRUCTURE and friends).

Three repos are touched; the split is strict:

| Repo | What lands there |
| --- | --- |
| projectured-julia | the `fsm` domain slice: documents, notation, diagram, code generator (manipulates `JuliaDocument` trees only — **no dependency on omnetpp/inet**, same independence rule as chart) |
| omnetpp-julia | one small runtime support file in the simulator package (the `Fsm` struct + dispatch helpers the generated code calls) |
| inet-julia | the pilot: the t1s MAC machine re-expressed as an fsm document, its generated module replacing the hand-written FSM core, and the live watch example |

## 1. Scope: what is the domain, what is the host module's, what is deferred

| Concern | Where it lives |
| --- | --- |
| States, entry actions, transitions (trigger/guard/action/target) | **this domain** |
| Extended-state variables, timers, event declarations | **this domain** (declared on the component; codegen turns them into host-struct fields) |
| Guards/actions/entry code | **this domain**, as embedded `JuliaDocument` subtrees (§4, D2) |
| Multiple machines sharing variables in one component (PLCA control+data) | **this domain** (`FsmComponent` holds N machines over one variable set) |
| Helper functions, interface structs, constants around the machines | **this domain**, as plain `JuliaDocument` top-level items on the component (`helpers`), so the generated module is complete |
| Event classification (raw packet/segment → symbolic event) | **host code** — a plain Julia function among the helpers; the TCP research shows this must stay unconstrained code (stateful, can swallow input, can escalate events) and the FSM table stays small precisely because of it |
| Execution semantics (cascades, stays, deferred cross-machine calls, timers) | **runtime support module** in omnetpp-julia (§6) + generated dispatch functions |
| Simulation wiring (four-struct module convention, gates, model builder, catalog) | **inet-julia**, hand-written as today; the generated module is one file in the existing `include()` chain |
| Live view (current state, transitions happening) | diagram overlay fields on the presentation document (§5.2) + the established native→shadow sync pattern (§7) |
| Hierarchical/composite states, orthogonal regions, exit actions | **deferred** (§10) — none of the three target machines needs them (CSMA models rx-concurrency with per-state stays; TCP has entry-only actions) |

## 2. Requirements: what the abstraction must express

Distilled from the C++ research; every row names which target forces it. This table is
the contract — §3/§4 must cover every row, and the pilot phases prove it on real code.

| # | Capability | Needed by |
| --- | --- | --- |
| R1 | Named states with **entry actions**, run once on arrival, not per handled event | all three |
| R2 | Event transitions guarded by boolean Julia expressions over variables; several transitions on the same (state, event) disambiguated by mutually exclusive guards, evaluated in document order, first match wins | all three |
| R3 | **Condition-only transitions** (no event dimension), re-checked every time the machine is run | PLCA control (its *entire* table) |
| R4 | **Transition cascades**: one dispatch can walk several states before settling (condition transitions of the landed state fire immediately); bounded by an iteration cap | PLCA; harmless for the others |
| R5 | **Stay** (consume event, run action, no state change, no entry re-run) distinct from a true self-transition (entry re-runs) | CSMA (rx-while-transmitting stays), PLCA data |
| R6 | **Ignore** (consume silently) and a per-machine **unhandled policy**: error (CSMA, PLCA data — exhaustiveness check) vs silent ignore (TCP — unlisted pairs are legal) | all three |
| R7 | Extended-state **variables** outside the state enum, read in guards, written in actions | all three |
| R8 | **Timers first-class**: start (with a computed delay) / cancel in actions and entry; expiry is a trigger; several live timers per machine | all three |
| R9 | **Deferred actions**: calls that leave the machine (sibling FSM, PHY/MAC interface) queued and flushed after the cascade settles | CSMA, PLCA (heavily) |
| R10 | **Multiple machines in one component** sharing variables directly and injecting events into each other synchronously (via R9) | PLCA |
| R11 | **Classifier seam**: raw input → symbolic event distillation is plain host code, allowed to be stateful, to swallow input, to escalate/downgrade the event | TCP (essential), CSMA |
| R12 | Event **payload** available to guards/actions (the packet/segment behind the symbolic event) | all three |
| R13 | Entry actions can see the **previous state and firing event** | TCP (`stateEntered`) |
| R14 | Observability hook on every transition (statistics signal / trace) orthogonal to the logic | all three; also powers the live view |
| R15 | Guard-dependent **target** = two guarded transitions on the same event (no extra mechanism) | TCP |

Not required by any target and consciously out: exit actions, hierarchical states,
`FSMA_No_Event_Transition`'s re-eval-only variant (PLCA control uses the both-passes
form exclusively), reactive auto-re-evaluation of condition machines inside the
simulator (the C++ model — explicit re-run calls after relevant writes — is kept; it is
simple and the sim hot path must stay native, §6).

## 3. Execution semantics (the contract codegen and runtime implement)

One dispatch = `dispatch!(ctx, host, machine, event, payload)` (event may be `nothing`
for a pure re-evaluation run, which is how condition machines are driven):

1. Find the current state's transition list. On the **event pass**, event-triggered
   transitions matching the event AND condition-only transitions are candidates, in
   document order; first one whose guard passes wins. Stays/ignores consume the event
   without a state change.
2. A winning transition runs its action, then moves to the target and runs the target's
   entry (with `prev`/`ev` bound). Then **re-evaluation passes** run: only
   condition-only transitions of the landed state are candidates (the event is spent —
   faithful to FSMA, where an event transition can never fire on a re-eval pass).
   Repeat until no transition fires; iteration cap (default 32) throws on runaway
   cascades (FSMA's `FSM_MAXT` equivalent). A **stay** is followed by re-evaluation
   passes exactly like a winning transition (a deliberate, uniform simplification of
   FSMA's after-the-stay partial fall-through; no target machine mixes stays with
   condition-only transitions in one state, so no pilot behavior depends on the
   difference).
3. If the pass was an event pass and nothing consumed the event: apply the machine's
   unhandled policy (`:error` throws naming state+event; `:ignore` returns).
4. **Snapshot-drain the machine's own deferred queue** (closures pushed by `fsm_defer!`
   from actions — sibling `dispatch!` calls, interface call-outs): copy, clear, then
   run, as FSMA's `executeDelayedActions` does. Each machine owns its queue (a field on
   its `Fsm`); a drained closure may synchronously re-enter `dispatch!` on this or a
   sibling machine, which drains that machine's own fresh queue. A shared live queue
   would let a nested dispatch steal a sibling's pending injection (PLCA's `COMMIT_TO`)
   — verified against `EthernetPlca.cc`. **Re-entrancy rule**: `dispatch!` on a machine
   currently inside its own cascade is an error (FSMA's `busy` assert); it is legal
   again during that machine's drain.
5. Every state change bumps `transition_count`, records `last_transition`, updates
   `state`, and calls the optional `on_transition` hook (statistics emit — R14).
6. **Startup**: the initial state's entry does *not* run when the machine is
   constructed (faithful to FSMA — PLCA's `DS_IDLE` entry has side effects that would
   inject a spurious cross-machine dispatch at t=0). The host kicks the machine
   explicitly (`dispatch!(…, nothing, …)`), as `plca_start!` does today.

**Timers are usable two ways** (both occur in the targets): (a) as a **timeout
trigger** on a transition, and (b) as a **pollable guard predicate**
`is_scheduled(m.t)` — PLCA control's five timers appear in *no* trigger; its
transitions poll expiry in guards and the expiry merely re-runs the machine
event-lessly, possibly long after (the guard also needs `!CRS` etc.). Codegen's expiry
routing therefore is: for each `FsmTimer`, the generated schedule callback dispatches a
timeout event to every machine that references the timer as a trigger, **and** an
event-less re-evaluation poke to every condition-only machine of the component —
mirroring the C++ `handleSelfMessage`, which runs `handleWithControlFSM()` on every
self-message and event-dispatches only the data-FSM timers.

Code bindings available inside guards / actions / entry: `ctx` (ScheduleContext), `m`
(the host state struct — all component variables and timers are its fields), `payload`
(event payload, `nothing` for timers/conditions), and in entry additionally `prev` and
`ev`. Guards must be side-effect-free by convention (stated in the doc, not enforced)
except for the sanctioned `is_scheduled` reads.

## 4. Document model (`package/domain/main/fsm/Fsm.jl`)

`@domain Fsm` (generates `FsmDocument`, `FsmNothing`, `FsmInsertion`, insertion traits;
alias `"fsm"`). Naming decision: the short `Fsm` prefix (like `json`/`sql`/`xml`) —
"Statemachine" as a prefix would produce `StatemachineMachine`.

```julia
@document struct FsmComponent <: FsmDocument      # ⇒ one generated Julia module
    name::String
    variables::CellVector = CellVector()          # FsmVariable
    timers::CellVector = CellVector()             # FsmTimer
    events::CellVector = CellVector()             # FsmEvent
    machines::CellVector = CellVector()           # FsmMachine (≥1; PLCA has 2)
    helpers::CellVector = CellVector()            # top-level JuliaDocument items
    usings::CellVector = CellVector()             # JuliaUsing lines for the module
end

@document struct FsmVariable <: FsmDocument
    name::String
    type::Any = nothing                           # JuliaDocument type expr; nothing = Any
    default::Any = nothing                        # JuliaDocument expr
end

@document struct FsmTimer <: FsmDocument          # ⇒ a TimerHandle field + timeout trigger
    name::String
end

@document struct FsmEvent <: FsmDocument
    name::String
end

@document struct FsmMachine <: FsmDocument
    name::String
    initial::Any = nothing                        # FsmState, by identity
    states::CellVector = CellVector()             # FsmState
    on_unhandled::Symbol = :error                 # :error (CSMA/PLCA-data) | :ignore (TCP)
end

@document struct FsmState <: FsmDocument
    name::String
    entry::Any = nothing                          # JuliaDocument block/expr
    transitions::CellVector = CellVector()        # FsmTransition — OUTGOING, in priority order
end

@document struct FsmTransition <: FsmDocument
    trigger::Any = nothing    # nothing = condition-only | FsmEvent | FsmTimer (identity)
    guard::Any = nothing      # JuliaDocument boolean expr; nothing = always
    action::Any = nothing     # JuliaDocument block/expr
    target::Any = nothing     # FsmState (identity); nothing = stay (no entry re-run)
end
```

Design decisions, with rationale:

- **D1 — transitions live inside their source state**, not in a flat component table:
  the natural notation groups by state (like FSMA's `FSMA_State` blocks and every
  statechart text format), deleting a state carries its outgoing transitions, and the
  diagram projection walks states anyway. `target`/`trigger`/`initial` are held **by
  identity** (the `GraphEdge.source/target` precedent) so renaming a state or event
  never dangles a reference. A *stay* is `target = nothing` (R5); an *ignore* is a stay
  with no action (R6); a true self-transition is `target === its own state` (entry
  re-runs). First-match-wins order = `transitions` document order (R2).
- **D2 — guards/actions/entry/defaults/types are real `JuliaDocument` subtrees**, the
  formula-domain pattern (`FormulaFormula.code` mixing `JuliaDocument` nodes). They
  render/edit through `JuliaToSyntax` entries pushed onto the fsm dispatch table, get
  structural editing + insertion holes (`JuliaInsertion` scaffolds work today), and are
  **spliced verbatim into the generated tree** — codegen never stringifies code. Known
  accepted limitation: julia leaves edit at whole-element granularity (no char-level
  caret inside an identifier) until the julia flat-offset follow-up lands; the proven
  authoring floor is **hole-based typing** (JuliaTypeinTest exercises scaffolds,
  completion and commit from an empty hole); correcting an *existing* token has no
  evidenced path today and needs a structural-replace gesture wired in P1 (honest
  review finding, not assumed). No custom leaf types in v1: state/event names in code
  are unnecessary
  (state changes are the transition's `target`, never imperative code).
- **D3 — the classifier is not modeled**; it is a plain function among `helpers` (R11).
  The domain does not try to own the raw-input analysis that TCP proves must stay free
  Julia.
- **D4 — cross-slice edges**: `fsm → julia` (D2 + codegen) and `fsm → graph` (§5.2).
  Both new; the DAG stays acyclic; both get added to the edge list in
  `package/domain/doc/architecture.md` and are checked by `test_domain_layering()`.
- **D5 — component completeness**: `helpers`/`usings` make `FsmComponent` project to a
  *complete* module file (constants, downlink/upcall interface structs, classifier and
  helper functions all live in the document). This is what "working and complete Julia
  code" requires for the Mac pilot — its non-FSM code comes along as content.
- **D6 — copy/paste limitation, recorded**: `copy_document` has no alias table, so a
  clipboard copy of a machine would duplicate identity-referenced states per
  referencing field (`initial`/`target` of the copy pointing at states outside its
  `states` list — the graph slice carries the same latent defect). v1 decision: the
  fsm paste path re-resolves trigger/target/initial **by name within the pasted
  subtree** (domain-level fixup); an alias-preserving `copy_document` extension is a
  separate follow-up. `.pdoc` is safe (Serialization backrefs keep aliasing); `.fsm`
  is safe (names re-resolve on parse).
- Insertions: **every type with a required field ships an `@insertion`**
  (`insertable` probes `T()`, so all the name-bearing types — component, variable,
  timer, event, machine, state — silently drop out of completion without one);
  `FsmTransition` (all-defaulted) constructs bare. Guard/action holes are
  julia-domain placeholders, so the fsm dispatch table carries julia's
  insertion/nothing entries, and the catalog example uses the whole-tree dispatching
  projection (the self-modifying-document rule). No hand-written constructors that
  shadow Rule Y's generated positional forms (known fatal-precompile hazard); plus
  `@gestures` for append-element bindings (`,` idiom), mirroring json.

## 5. Editing projections

### 5.1 `FsmToSyntax.jl` — the textual natural notation (primary edit surface)

Standard pipeline `RecursiveProjection(FsmToSyntax()) → SyntaxToText → TextToGraphics`,
built with `@projection_template` per node type (house preference), julia subtrees
delegated to the `JuliaToSyntax` entries on the same dispatch table (formula precedent).
Sketch of the printed form (one line per transition; grouping and keywords are chrome):

```
component EthernetCsmaMac
  variable num_retries::Int = 0
  variable carrier_sense::Bool = false
  timer tx_timer
  timer ifg_timer
  event UPPER_PACKET
  event COLLISION_START
  machine Mac initial IDLE
    state IDLE
      on UPPER_PACKET / set_current_tx!(m, payload) -> TRANSMITTING
    state TRANSMITTING
      entry / start_transmission!(ctx, m)
      on COLLISION_START / abort_tx!(ctx, m) -> JAMMING
    state BACKOFF
      on LOWER_PACKET stay / process_frame!(ctx, m, payload)
      on timeout(backoff_timer) when m.num_retries < MAX_ATTEMPTS -> TRANSMITTING
    state WAIT_TO
      when m.cur_id == m.local_node_id && m.packet_pending && !m.crs -> COMMIT
```

Transition line grammar: `[on EVENT | on timeout(TIMER) | when GUARD]` `[when GUARD]`
`[/ ACTION]` `(-> TARGET | stay | ignore)`. `initial`, trigger and target render the
referenced object's *name* (reactive read through the identity ref, so a rename
propagates everywhere). Editing structure: type-to-create via the `@domain` insertion
kit; trigger/target positions offer name completion against the component's declared
events/timers/states (reader resolves typed text to the identity ref — same resolve
step `insertion_candidates` uses, scoped to the component).

Known-cost item (from the projection-template memory): template projections with
introduced/structural carets need the domain `_syntax_to_flat`
`ReplaceSelectionOperation` reader + passthrough, or text navigation runs away —
budgeted in P1, not optional.

### 5.2 `FsmToGraph.jl` — the state diagram (+ live overlay)

The pipeline mirrors the chart split exactly, so the live fields are presentation
state by construction (never document content, never serialized):

```
FsmMachine → FsmDiagram → GraphGraph → GraphLayout → GraphicsCanvas
            (stage 1,      (FsmDiagramToGraph)   (stock graph stages)
             identity-preserving)
```

Stage 1 (`FsmToFsmDiagram`, the `ChartToChartPlot` pattern) wraps the machine in a
`FsmDiagram` **built once with identity preserved across reprints** — that is what
makes the live fields survive data changes and what gives the watch driver a stable
handle (read once from the stage-1 iomap output at setup):

```julia
@document struct FsmDiagram <: FsmDocument        # stage-1 projection OUTPUT
    machine::Any                      # FsmMachine (identity)
    live_state::Int = 0               # 1-based state index; 0 = not live
    live_transition::Int = 0          # global transition index; 0 = none yet
    transition_count::Int = 0
end
```

`FsmDiagramToGraph` prints the `GraphGraph`: one `GraphVertex` per state (content is a
small label widget with the state name), one directed `GraphEdge` per transition with a
label document summarizing `trigger [guard] / action`. School A mappers peel
`machine.states[i]`/… so clicking a state selects the `FsmState` through the existing
vertex-content round-trip.

The current-state ring and last-transition re-stroke are drawn as **overlay elements
derived from the three live fields — never by touching vertex content** (a content
change would invalidate the measured sizes and re-run the whole grid layout on every
sim transition; the graph-chart research and the frozen-layout memory both flag this).
The highlight must reach the graphics stage **through the projection chain as derived
cells**, not by hand-wiring into layout internals (a fresh `GraphLayout` is built per
print; an eagerly-captured handle is silently severed on reprint):

- add `highlight_vertex::Any` / `highlight_edge::Any` to **both** `GraphGraph` and
  `GraphLayout` (small, generally useful graph-slice extension);
- `FsmDiagramToGraph` wires `graph.highlight_vertex` as a `ComputedCell` over
  `diagram.live_state` resolving to the **`GraphVertex`** (a stable identity —
  `VertexLayout` objects are rebuilt on every layout recompute and must never be
  held), and `highlight_edge` likewise from `live_transition`;
- `GraphToGraphLayout` passes both through as derived cells;
- `GraphLayoutToGraphicsCanvas` renders the ring / thick re-stroke.

A transition-count badge label is wired reactively via `set_cell_function!` (the
`WidgetBadge` idiom).

Diagram v1 limits (recorded, not hidden): transitions are **not clickable** in the
diagram (graph edges have no selection mapping yet — edit them in the notation; the
polyline hit-test is a graph-slice follow-up), and self-loop edges don't render (the
fallback engine degrades them to a point) — stays are visible inside the notation and as
node-content lines, and a `GraphicsSpline` self-loop arc is deferred (§10). Layout is
frozen per the live-editor practice.

### 5.3 Code generation — `FsmToJuliaCode.jl` (a generator function, not an editor projection)

`generate_component(c::FsmComponent)::JuliaDocument` builds the module's AST and
`export_component(c, path)` writes it via the existing `document_to_text` pipeline
(exactly what `JuliaFile.emit_text` does). This is deliberately **not** a registered
bidirectional projection: parsing hand-edited generated Julia back into the machine is
out of scope, and the bidirectionality convention applies to editor projections, not
exporters. The generated file carries a `# Generated from <name>.fsm — edit the .fsm`
header. (A read-only split-pane *preview* of the generated code inside the editor is
nearly free — the generated `JuliaDocument` through the stock julia pipeline — and is a
P4 demo item.)

Generated shape (matches the hand-written t1s idiom, so diffs against `Mac.jl` are
reviewable; plain integer state constants + a name table instead of `@enum`, keeping
codegen inside the julia domain's coverage). **State values are 0-based document
order** and the emitted statistic is the same width the hand-written enums use — the
integer values appear in recorded `.vec` output and network hashes (`PlcaData.jl`'s own
warning), so the pilot's constants must coincide with the existing
`@enum …::UInt8` values or every hash comparison is spuriously red:

```julia
module EthernetCsmaMacFsm            # JuliaModuleDef — small new julia-domain node, P4
using ..OmnetppSimulator: Fsm, fsm_goto!, fsm_defer!, drain_deferred!, ...
const MAC_IDLE = Int32(1); ...       # per machine: state consts + STATE_NAMES tuple
mutable struct MacHost               # component variables + one TimerHandle per timer
    fsm_mac::Fsm                     # + one Fsm per machine
    num_retries::Int
    ...
end
# per machine: dispatch function — straight-line if/elseif over (state, event),
# guards/actions/entry spliced verbatim, cascade loop for condition-only states,
# unhandled policy, deferred-queue drain at the end.
function mac_dispatch!(ctx, m::MacHost, event::Int32, payload) ... end
<helpers verbatim>
end
```

The one julia-domain prerequisite: a `JuliaModuleDef` document type (`module … end` is
currently unrepresentable; everything else the generated shape needs — `JuliaStruct`,
`JuliaConst`, `JuliaUsing`, `JuliaIf`/`JuliaWhile`/`JuliaFunction` — exists). Small,
generally useful, lands with parser + printer + tests in P4.

## 6. Runtime support (omnetpp-julia)

One new file in the simulator package next to `TimerModule.jl` (lowest package where it
makes sense; usable by inet-julia and anything else): `Fsm.jl`, a deliberately tiny
plain-Julia (non-reactive — this is the sim hot path) module:

```julia
mutable struct Fsm
    state::Int32
    transition_count::Int
    last_transition::Int32          # index into the machine's flattened transition list
    name::Symbol
    busy::Bool                      # the §3 re-entrancy assert
    deferred::Vector{Any}           # per-machine queue (§3 step 4 — NOT per host)
    on_transition::Any              # nothing | (fsm, from, to, tridx) -> …  (R14)
end
fsm_goto!(fsm, new_state, tridx)    # bump count, record, call hook
fsm_defer!(fsm, f) / fsm_drain!(fsm)  # R9 — snapshot drain: copy, clear, run
fsm_cascade_error(name, state)      # the R4 iteration-cap throw
```

Timers reuse the existing `TimerHandle`/`schedule_timer!`/`cancel!` API unchanged —
actions call them directly (the generated host struct owns the handles), so R8 costs the
runtime nothing. One recorded gap: omnetpp-julia's scheduler has **no scheduling
priority parameter**, so INET's priority-100 `to_timer` has no direct counterpart — the
pilot inherits the Julia port's deterministic insertion-order emulation (the `Phy.jl`
precedent); P5/P7 should not rediscover this. The dispatch logic itself is *generated*,
not interpreted from a table: straight-line branches match the existing hand idiom, run
at full speed, and are readable/debuggable — the runtime holds only what must be shared
(state cell, hooks, deferral + re-entrancy discipline, the cap). Unit tests live in
omnetpp-julia's simulator test package.

## 7. Live view — current state and transitions happening

The established pattern end-to-end (nothing new invented):

1. The generated code's `Fsm` struct is **native** and updated by `fsm_goto!` at sim
   speed — zero reactive cost on the hot path.
2. The watch example follows omnetpp-julia's `parallel_sim_dashboard.jl` pattern but
   must live in **inet-julia** (it needs the Mac model, and omnetpp-julia cannot depend
   on inet-julia); inet-julia's packages depend only on ProjecturedKernel, so the
   example gets its own `watch/` environment whose `Project.toml` adds the
   presentation/visual stack — dependency confined to that env, not the packages. It
   runs the sim in slices; once per slice (~10 fps) a monitor task copies the three
   numbers into the `FsmDiagram` fields (obtained once at setup from the stage-1 iomap
   output, §5.2) **only when changed** (the `sync_document!` minimal-write discipline;
   these are three scalar cells, so a hand-rolled
   `d.live_state == s || (d.live_state = s)` refresh is enough — no full-tree sync).
3. The diagram overlay (§5.2) re-derives: ring moves to the current state, the
   last-taken transition edge re-strokes, the counter badge updates. At sim speed many
   transitions collapse into one visible hop per slice — accepted for v1; **stepped
   execution** (pause/step drivers already exist in the watch machinery) shows every
   transition individually, which is the honest way to "watch transitions happen".
   A clock-driven fade of the highlight is a cosmetic deferral (§10).

Reactive-write confinement rule respected: the sim thread touches only native structs;
the single monitor task is the only cell writer (the parallel-dashboard precedent).

## 8. Registration, examples, docs, tests (the slice checklist)

- **Includes** in `package/domain/main/ProjecturedDomain.jl`: `fsm/Fsm.jl` with the
  document block; `fsm/FsmToSyntax.jl` after `insertion/InsertionToSyntax.jl` **and**
  after julia's projection includes (dispatch-table reuse ⇒ topological order);
  `fsm/FsmToGraph.jl` after the graph slice's projections; `fsm/FsmToJuliaCode.jl` with
  the julia-dependent files. Slice + the two DAG edges added to
  `package/domain/doc/architecture.md` (also rewrite its "only three cross-slice
  edges exist" sentence — current fact, not doctrine); `test_domain_layering()`
  green.
- **Examples** (`package/domain/example/`): `document/Fsm.jl` —
  `make_fsm_document_example()`: the **TCP connection state machine** (12 states, the
  classic RFC 793 diagram with app/segment/timer events, guards and entry actions) —
  the showcase that exercises R2/R6(:ignore)/R8/R13/R15 with zero simulator
  dependency; plus a minimal toggle machine for the atomic catalog
  (`domain_atomic_documents`). `projection/Fsm.jl` — the notation pipeline, the diagram
  pipeline, and a split-pane example (notation | diagram) as the workbench demo.
  Register in **both** registries (`domain_examples` + the umbrella `examples` vector)
  and the export lists — missing either loses a sweep tier.
- **File format**: `FsmFile.jl` registering `.fsm`. `emit_text` is the printed
  notation (via the standard `document_to_text` path). The parser (`FsmParser.jl`) is
  honestly **not** small: it is the repo's first mixed-domain natural-text round-trip
  (formula, the only other mixed-domain printer, registers no parser). The grammar
  therefore needs an explicit **block form** — multi-statement `entry`/`action`
  bodies, `helpers` and `usings` sections — specified as indented julia regions
  handed *whole* to the existing `juliaparse`, with only the fsm-structural lines
  parsed natively. Known contract limit: a document still carrying insertion holes
  has no valid natural-text form (a partially-authored machine saves as `.pdoc`, not
  `.fsm`). Acceptance: an export → import → deep-equality round-trip test on the TCP
  example. This is what lets the pilot's machine live as a committed `.fsm` source
  file in inet-julia.
- **Docs**: `package/domain/doc/fsm.md` — types, semantics contract (§3), notation
  grammar, codegen mapping, the live-view recipe; entry in `_DOMAIN_GUIDE_EXAMPLE` for
  the auto-screenshot.
- **Tests** (`package/domain/test/`): document tests; notation
  printer/reader/position-navigation/repl for the fsm examples; diagram printer +
  click-selects-state round-trip; codegen unit tests (generated text snapshots +
  re-parse via `juliaparse` to prove syntactic validity + a semantics micro-suite that
  `include`s a generated toy module and asserts cascade/stay/ignore/unhandled/deferred
  behavior directly); `test_fsm()` wired into `test_domain()`. Cross-repo: runtime
  tests in omnetpp-julia; the pilot rides inet-julia's existing
  `test_linklayer()` golden hashes. Verify live in the editor's real order
  (print → refresh → select → click → type), per house practice.

## 9. Implementation phases

Work in a dedicated worktree per repo; one commit per phase; check boxes and record
decisions here as they land. Cross-repo note: inet-julia/omnetpp-julia resolve
`[sources]` against the **live** projectured-julia checkout — coordinate landings
(the drifting-baseline rule).

- [x] **P0 — documents + semantics doc.** DONE. Slice folder, `@domain Fsm`, all
  `@document` types, insertion kit, document tests, includes + layering guard green,
  `fsm.md` carrying the §3 contract. Exit: `test_domain_layering()` 6/6,
  `test_fsm()` 56/56.

      Decisions made while implementing:
      - **Mixed positional+keyword constructors are hand-written** (`FsmState("IDLE";
        entry=…)`, likewise variable/machine/component). The macro emits
        all-positional or all-keyword, never the mix — the same constraint the chart
        plan hit with its series types. Typed `::AbstractString` first arguments keep
        them strictly more specific than the generated `::Any` forms, so no generated
        method is shadowed (the `GraphEdge` precedent).
      - A local `_fsm_cellvector` helper accepts a plain `Vector`, a `CellVector` or
        pre-wrapped `Cell`s for every collection field. `FsmComponent`'s six
        `CellVector`s get no Rule C sugar (it fires only for a *single* collection
        field), so this is the one conversion point.
      - `machine_transitions` defines the **flattened transition order** (states in
        document order, each state's transitions in order). That order is the shared
        index vocabulary for the generated `last_transition` recording and the
        diagram's live edge highlight, so it belongs to the domain, not to codegen.
      - The document layer holds embedded code as opaque `Document` values, so
        `Fsm.jl` needs **no julia import**: the `fsm → julia` edge starts at the
        notation and codegen files, which keeps the document include early in the
        topological order (right after the chart documents).
- [x] **P1 — natural notation.** DONE. `FsmToSyntax` via `@projection_template`,
  julia subtrees through the merged dispatch table, the flat-offset reader on every
  compound rule, TCP + toggle examples registered in both registries. Exit:
  `test_fsm_to_syntax()` 27/27; printer (3159 / 30501 cells), reader, repl and — for
  the toggle — position navigation all green.

      Decisions and discoveries:
      - **The transition's ending precedes its action**: `on E when G -> T / action`,
        not `… / action -> T`. An action can be several statements, and a
        multi-statement block renders as an indented run of lines; anything printed
        after it is stranded at the bottom of that block, away from its own line.
      - **Empty sections must contribute no node.** An indented node with no
        children still prints its line break, so a component that declares no
        timers used to get a blank line for the timer section. Every section (and
        the state's transition list) is conditional.
      - A `JuliaParser` gap surfaced immediately and was fixed: `a; b` written on
        ONE line parses to a `:toplevel` nested inside the outer one, which the
        parser rejected outright. Transition actions are written that way
        constantly. It means what a `:block` means.
      - **`JuliaModuleDef` was not needed here** but `hinted_text`, `bound` and the
        conditional-children thunk shape (`SyntaxConcatenation(() -> …)`, the
        `JuliaReturnToSyntaxNode` idiom) all were.
      - A caret literal ends `{0}::Position` — the strict-typing check counts the
        terminal too. And `map_reference_forward` must be called with the *rule*
        projection (`iomap.projection`), not the `RecursiveProjection` wrapper,
        whose own mapper is ambiguous against the template engine's.
      - **The TCP example is on the position-navigation skip list.** It navigates
        correctly; the exhaustive caret walk simply takes tens of minutes on a
        twelve-state machine with embedded Julia, where every other example is
        seconds. `fsm_toggle` covers the notation in that sweep. Reader and repl on
        the TCP machine are fast (13 s / 27 s) and stay in.
      - Lookup helpers filter their collections by type: a machine legally holds an
        `FsmInsertion` in `states` mid-edit, and the repl sweep found it.
- [x] **P2 — diagram.** DONE. `highlight_vertex`/`highlight_edge` on `GraphGraph`
  **and** `GraphLayout` with pass-through derived cells and ring/re-stroke
  rendering; `FsmToFsmDiagram` (identity-preserving stage 1) + `FsmDiagramToGraph`;
  `fsm_diagram` example. Exit: `test_fsm_diagram()` 25/25.

      Decisions and discoveries:
      - **The load-bearing property is asserted directly**: writing the diagram's
        three live integers adds/removes exactly the ring and the edge re-stroke,
        and every node box stays where it was. A highlight that moved the picture
        would mean it had reached the layout engine's inputs.
      - A vertex's content is the `FsmState` itself (by identity, so a click selects
        the real state), rendered by a compact `FsmStateToSyntaxLabel` — the name
        alone. Projecting a state through the full notation would inline its whole
        transition list into the node box, and for a self-loop would not terminate.
      - The highlight fields hold a `GraphVertex`/`GraphEdge`, never a
        `VertexLayout`: layouts are rebuilt on every recompute.
      - A stay contributes no edge, and a self-loop's edge routes to a zero-length
        line the fallback engine does not draw. Both are recorded limits (§10), not
        surprises.
- [x] **P3 — runtime (omnetpp-julia).** DONE. `FsmModule` beside `TimerModule`:
  the state cell and its history, the per-machine deferred queue with a
  snapshot drain, the re-entrancy guard, the cascade cap, the `on_transition`
  hook. Exit: 26/26 new tests, simulator suite unchanged.

      The sibling-drain test is the one that matters: a closure drained from one
      machine dispatches its sibling, and the sibling drains its *own* fresh queue
      without consuming what is still pending on the first — the PLCA shape.
- [x] **P4 — codegen.** DONE. `JuliaModuleDef` in the julia domain (document type,
  parser case, printer, dispatch entry — round-trips stably);
  `generate_component` / `generate_component_text` / `export_component`; a probe
  component generated, loaded and run against the §3 contract. Exit:
  `test_fsm_to_julia_code()` 35/35, `test_domain()` 174909 pass / 0 fail / 0 error,
  julia example unchanged.

      Decisions and discoveries:
      - **The cascade loop breaks on "nothing fired", not on "nothing moved".**
        That makes a stay behave exactly like a move for re-evaluation purposes,
        which is what the contract says, and it is safe: the event is spent after
        the first firing, so only condition transitions can fire again.
      - `&&` is a `JuliaBinaryOp` in this domain, not a call — generated
        `&&(a, b)` is not valid Julia at all. Same for `!`, which is a
        `JuliaUnaryOp`.
      - The generated module gets the runtime from the component's own `usings`,
        so the test's probe names a stand-in runtime module the same way a real
        component names the simulator's.
      - Julia 1.12's world-age rules apply to *reading* a binding from a
        just-evaluated module, not only to calling it; the test fetches every
        binding through `invokelatest`.

### Status: every phase landed on main

Everything through P5 is implemented, verified and merged into `main` in all
three repos (P0–P2 and P4 in projectured-julia, P3 in omnetpp-julia, P5–P7b in
inet-julia). In the shipping 10BASE-T1S model **all three state machines** — the
MAC, and PLCA's control and data machines — are generated from documents, with
every golden hash unchanged, and the machine the MAC is generated from can be
watched running. Every requirement R1–R15 is exercised by real protocol code.

**The one thing that had to happen first was landing, not design.** While the
work sat on worktree branches, inet-julia could not see the runtime at all:
its packages resolve `OmnetppSimulator` through a committed `[sources]` path
pointing at the *main* omnetpp-julia checkout, and there is no non-invasive
local override — `Manifest.toml` is gitignored, but `[sources]` lives in the
committed `Project.toml`, and a scratch environment cannot override a
path-dependency's own `[sources]` either. Since the merge,
`isdefined(OmnetppSimulator, :FsmModule)` is `true` from inet-julia's
link-layer test environment (after a `Pkg.instantiate()`, since manifests are
per-environment and gitignored). P5–P7 proceed as written.

**Done for P5 already** (and valuable on its own): the traffic
golden hash is pinned. The review's finding was correct — `:notraffic`, the
only pinned scenario, never takes a MAC out of `MAC_IDLE`, and `:bestcase`
asserted only `event_count > 0`, so a MAC swap would have passed vacuously.
`:bestcase` now runs 500 µs (where the followers contend and seven frames
really go out and come back), pins its hash, and asserts the frame counts so
the scenario cannot quietly stop covering the transmit path. Pinned against
the *unmodified* MAC, so it is usable as a before/after guard.

**Established for P5 by reading `Mac.jl` against the abstraction:** the MAC is
expressible as written, with one clarification worth recording. Requirement
R13 (pass-through handlers shared across states — `carrier_sense` must be
updated on every carrier event regardless of state) is **met by the classifier
seam, not by machine structure**: `mac_handle_carrier_sense_start!` is a helper
that updates the variable and then dispatches, exactly as the C++
`handleCarrierSenseStart()` does before calling `handleWithFsm`. No
shared-handler feature is needed, and none was built. Likewise `_start_ifg!`
becomes `target = WAIT_IFG` plus a `WAIT_IFG` **entry action** that schedules
the timer — which is what entry actions are for.
- [x] **P5 — pilot: t1s MAC (inet-julia).** DONE. The 6-state EthernetCsmaMac is
  generated from a state machine document. Exit: **both pinned golden hashes
  unchanged** — `:notraffic` `0x429fe1b7…` at 299 events, `:bestcase`
  `0x6f8ce88a…` at 480 events with 7 frames sent and received — plus
  `phase6_mac.jl` green, link layer 417/417, inet-julia 2311/2311. The generated
  machine reproduces the hand-written one bit for bit. This is the acceptance
  test for R1/R2/R5/R6/R7/R8/R9/R11/R14.

      The `:bestcase` hash was pinned first, on the unmodified MAC (the review's
      finding: `:notraffic` never takes a MAC out of `MAC_IDLE`, so it could not
      have caught a MAC change, and `:bestcase` asserted only
      `event_count > 0`).

      Decisions and discoveries:
      - **Outgoing calls had to be deferred — and that is the C++ design, not a
        workaround.** Handing a frame down reaches PLCA, which synchronously
        calls back into the MAC's own carrier handler; the generated machine
        refuses to re-enter its own cascade. That is exactly why every `phy->`
        call in `EthernetCsmaMac.cc` is wrapped in `FSMA_Delay_Action`.
        Deferring left both hashes untouched, which also proves the re-entrant
        callback's only effect while `TRANSMITTING` was setting a variable.
      - **R13 is met by the classifier seam, as predicted.** `carrier_sense` and
        `collision` are updated by the handler that receives the event, which
        then dispatches — `handleCarrierSenseStart()`'s shape. No
        shared-handler feature was needed in the abstraction.
      - The jam timer's retry increment happens in its **callback**, before the
        dispatch: the guards that follow read the new value, and a guard must
        not have side effects.
      - `on_unhandled = :ignore` matches the hand-written *port*, whose timer
        callbacks return silently when the state has moved on. The C++ is
        exhaustiveness-checked; the port is not, and the pilot reproduces the
        port.
      - **`.fsm` files were not needed and are not on the critical path.** The
        machine is a document built in `tool/generate_mac_fsm.jl`, and
        `MacFsm.jl` is generated from it. `FsmFile`/`FsmParser` remain worth
        having (they are what would make the machine editable in the editor
        rather than in Julia) but the pilot did not require them.
      - **Three julia-domain gaps surfaced**, each worked around and worth
        closing: no splat (`f(_...)`), no anonymous `function … end` (the
        lambda form works), and **no keyword arguments in a function
        *definition*** — the last is why `MacState`'s constructor stayed
        hand-written.
      - **A generated file has an ordering constraint the component cannot yet
        express**: the host struct's field types must be defined before it,
        while helpers are emitted after it because they dispatch on it. The two
        interface structs therefore live in the hand-written companion. A
        `preamble` list on `FsmComponent` would let the generator own them.
      - `generate_component(...; wrap_module = false)` was added for this: the
        t1s slice is nine files making up one module, so a generated file
        wrapped in its own module would not drop in where the hand-written one
        sat.
- [x] **P6 — live view.** DONE. `watch/mac_fsm.jl` (headless self-test) and
  `watch/mac_fsm_sdl.jl` (the editor), under a `watch/` env carrying the
  presentation-stack deps. Exit: the self-test steps a real 10BASE-T1S run until the
  MAC first moves, asserts the ring appeared and the overlay agrees, then drives to
  completion and asserts it still does — 22 transitions, 7 frames sent; inet-julia
  2311/2311.

      Decisions and discoveries:
      - **The diagram projects the same document the code was generated from**, so
        the picture cannot drift from the implementation. That is the whole point of
        the pilot arrangement and it costs nothing: the watch example includes the
        generator for the machine, and the generator was made include-safe
        (it regenerates only when run as a script).
      - The live seam really is three integers written when changed. Nothing else
        crosses from the simulation to the editor, and the layout engine never
        re-runs on a transition.
      - `live_state` is 1-based (an index into the machine's states) while the
        generated state constants are 0-based, because those had to match the enum
        they replaced. `last_transition` needs no adjustment: the generator numbers
        transitions in the machine's flattened order, which is exactly the order the
        diagram's edge highlight indexes — the two were designed against the same
        vocabulary in P0.
      - **Stepped mode is what makes transitions watchable.** At full speed a slice
        collapses many transitions into one repaint; the SDL entry point advances one
        event per frame by default.
      - The umbrella re-exports the editor/screen/projection names flatly, so the
        example needs no sub-package imports — only `ProjecturedSdl` for the backend.
      - The watch env is standalone (like omnetpp-julia's), so its self-test is run
        directly rather than from `test/runtests.jl`, whose root env has no
        Projectured.
- [x] **P7 — PLCA control (inet-julia).** DONE for the **control** machine; the data
  machine stays hand-written (see below). The 14-state condition-driven table is
  generated. Exit: both pinned hashes unchanged — `:notraffic` `0x429fe1b7…` at 299
  events (the scenario that genuinely exercises PLCA control, and the one
  cross-compared against INET) and `:bestcase` `0x6f8ce88a…` at 480 — link layer
  417/417, inet-julia 2311/2311, watch self-test unchanged. **Acceptance for R3 and
  R4**, the two requirements the MAC could not reach.

      Decisions and discoveries:
      - **This is the machine the MAC was not.** All 27 transitions are
        condition-only — no event dimension at all — and five of the nine timers are
        **polled in guards** through `is_scheduled` rather than triggering anything,
        because a timer expiring is only half a condition
        (`!is_scheduled(to_timer) && !crs`). The abstraction expressed both without
        extension.
      - **The re-entrancy guard stayed outside the machine**, in
        `handle_with_control_fsm!`, returning silently exactly as the port did. That
        is why the downlink calls could stay synchronous here, where the MAC needed
        its outgoing calls deferred: the MAC had no such guard. Two different, both
        faithful, resolutions of the same hazard.
      - `plca_start!` installs `CS_RESYNC` **directly** rather than dispatching to
        it, so no entry action runs — the machine's startup rule, and what the
        hand-written assignment did.
      - The component is named `Plca` (not `PlcaControl`) so the generated struct is
        `PlcaState`: the name `PlcaControlState` was already taken by the enum being
        replaced.
      - Two regressions were self-inflicted and worth remembering: renaming a helper
        the *other* machine calls (`_bits_to_time`), and mistyping a recorded signal
        name (`:curID`). Generated code shares a namespace with the hand-written code
        beside it; a rename is not free.

- [x] **P7b — PLCA data, and R10.** DONE. The 9-state event-driven data machine is
  generated too, and both machines are declared in **one component**. Exit: both
  hashes exact — `:notraffic` `0x429fe1b7…` / 299 events, `:bestcase`
  `0x6f8ce88a…` / 480 — link layer 430/430, inet-julia 2325/2325, watch self-test
  unchanged. **Acceptance for R9 and R10.**

      Decisions and discoveries:
      - **One component is what lets the two machines share state.** `fsm_control`
        and `fsm_data` are both fields of `PlcaState`, and so are the variables they
        pass between them. That *removed* a real hack: the hand-written data FSM
        kept its state in a module-level `IdDict` keyed by `PlcaState`, because the
        struct had nowhere to put it. The abstraction deleted a workaround rather
        than adding one.
      - **Where the deferral goes is a real design choice, and only one arrangement
        reproduces the port.** Deferring the data machine's calls back into control
        worked and was faithful to the C++ in spirit, but shifted one event and
        changed the `:bestcase` hash. Putting it where the C++ actually puts it —
        the control machine's `CS_COMMIT` entry defers its injection *into* the data
        machine, while the data machine's calls back into control stay synchronous,
        safe behind control's own `in_fsm` guard — reproduces the port exactly. The
        per-machine queues make both expressible; that is the point of them.
      - **A printer bug made generated code silently mean something else, and the
        golden hash did not catch it.** A control guard
        `… && (rx_cmd === CMD_BEACON || (!crs && …))` was printed without its
        parentheses, regrouping around the `||`. It survived because for a
        coordinator the wrong disjunct can only be true when `!crs`, and an earlier
        transition already fires there — ordering masked it. Fixed in the julia
        domain (precedence-aware parenthesization, respecting associativity so
        nothing else churned) with a round-trip regression test. **The lesson is
        about codegen generally: a hash proves the paths you exercise agree, not
        that the code says what you meant.**

## 10. Deferred / future work (recorded, deliberately out of v1)

- **TCP as a running module** — inet-julia has no TCP stack; the TCP machine ships as
  the editor example only. When a TCP port happens, the machine document is ready.
- Exit actions, hierarchical/composite states, orthogonal regions; the
  re-eval-only transition variant.
- Diagram: transition (edge) selection via polyline hit-test; self-loop arcs
  (`GraphicsSpline`); editing structure directly in the diagram (add state by click,
  drag-to-connect); transition-flash animation via the frame clock.
- Char-level caret editing inside julia leaves (the julia-domain flat-offset
  follow-up; tracked there, not here).
- A reactive in-editor *interpreter* of the machine (execute the document directly,
  no codegen) for editor-side simulation/testing of a machine without a sim.
- Importers: FSMA C++ / `.dot` → fsm document.

## 11. Risks

- **Behavioral equivalence of the generated MAC** (P5) — subtle ordering (deferred
  drain points, entry-vs-action order, timer races like PLCA's hold-vs-COMMIT_TO).
  The §3 contract was written and adversarially checked against the FSMA semantics,
  but the safety net must be built, not assumed: today's pinned hash covers only
  `:notraffic` (PLCA control — the MAC stays in `MAC_IDLE`), so P5 pins a traffic
  hash on the clean tree *before* the swap. Budget iteration time here.
- **Introduced-token selection gap** in the template notation (the known class that
  keeps graph `@test_broken` in sweeps) — mitigations known (flat-offset reader, fully
  typed references); same posture as the chart plan: printer/nav green required,
  residual gaps get explicit `@test_broken` markers with root-cause comments.
- **Trigger/target-by-identity vs text editing** — typing a target name must resolve
  to the state object (or a pending-unresolved render if absent); the reader owns
  this; new-name-then-create flows need a decision (v1: unresolved renders red,
  resolve on state creation).
- **`JuliaModuleDef`** touches the julia domain's parser/printer — small but shared;
  its own tests + a julia-example sweep before the codegen phase relies on it.
- **Three-repo coordination** — `[sources]` live-baseline drift; land
  projectured-julia phases first, keep omnetpp-julia/inet-julia phases behind them,
  re-run dependent envs' `Pkg.resolve()` when deps change.
