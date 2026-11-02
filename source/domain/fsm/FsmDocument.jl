# Fragment of `FsmModule` — the state machine document types, the document each
# insertion starts from, and the gestures that edit them.
#
# `@domain Fsm` declares the abstract `FsmDocument` type that every type below
# subtypes, and generates `FsmNothing` and `FsmInsertion`.

@domain Fsm

# ── Declarations ─────────────────────────────────────────────────────────

"""
An extended-state variable of the component. `type` and `default` are embedded
`JuliaDocument` expressions (`nothing` = untyped / no default). Codegen turns
each variable into a field of the generated host struct; guards read them and
actions write them as `m.<name>`.
"""
@document struct FsmVariable <: FsmDocument
    name::String
    type::Any = nothing
    default::Any = nothing
end

"""
A timer of the component. Codegen turns it into a `TimerHandle` field on the
generated host struct. A timer is usable two ways (both occur in the target
protocols): as a `timeout(t)` trigger on a transition, and as a pollable
`is_scheduled(m.t)` guard predicate (PLCA control's timers appear in no
trigger — its transitions poll expiry in guards).
"""
@document struct FsmTimer <: FsmDocument
    name::String
end

"""
A symbolic event declaration. Events are produced by host classifier code
(plain Julia among the component's `helpers`) and consumed by transition
triggers; the optional payload behind an event rides the dispatch call, not
this declaration.
"""
@document struct FsmEvent <: FsmDocument
    name::String
end

# ── Structure ────────────────────────────────────────────────────────────

"""
One transition of its containing `FsmState` (the source is implicit).

- `trigger` — `nothing` for a condition-only transition (re-checked on every
  dispatch and on re-evaluation passes), or an `FsmEvent`/`FsmTimer` held by
  identity.
- `guard` — an embedded `JuliaDocument` boolean expression; `nothing` = always.
- `action` — an embedded `JuliaDocument` block/expression; `nothing` = none.
- `target` — the target `FsmState` held by identity; `nothing` = **stay**
  (consume the trigger, run the action, no state change, no entry re-run).
  A stay with no action is an *ignore*. `target === the containing state`
  is a true self-transition whose entry re-runs.

Transition order within a state is priority order: first matching transition
whose guard passes wins.
"""
@document struct FsmTransition <: FsmDocument
    trigger::Any = nothing
    guard::Any = nothing
    action::Any = nothing
    target::Any = nothing
end

"""
A named state. `entry` is an embedded `JuliaDocument` block run once when a
transition lands here (with `prev` and `ev` bound) — not on stays, and not at
machine start (startup kicks are explicit host dispatches; the contract in
`fsm.md`). `transitions` are the state's outgoing transitions in priority
order.
"""
@document struct FsmState <: FsmDocument
    name::String
    entry::Any = nothing
    transitions::CellVector = CellVector()
end

"""
One state machine: named states plus the `initial` state (held by identity).
`on_unhandled` is the machine's policy when an event pass consumes nothing:
`:error` throws naming state+event (CSMA MAC, PLCA data — the exhaustiveness
check), `:ignore` returns silently (TCP — unlisted pairs are legal).
"""
@document struct FsmMachine <: FsmDocument
    name::String
    initial::Any = nothing
    states::CellVector = CellVector()
    on_unhandled::Symbol = :error
end

"""
A component: the unit of code generation (one generated Julia module). Groups
the shared extended-state `variables`, `timers` and `events` with one or more
`machines` over them, plus `usings` (module-level `JuliaUsing` items) and
`helpers` (arbitrary top-level `JuliaDocument` items — constants, interface
structs, classifier and helper functions) so the generated module is complete.

`supertype` is what the generated `…State` struct subtypes, as source text —
empty for a struct that subtypes nothing, which is what a component says by
saying nothing. It is a STRING and this domain never reads it: a host struct
belongs to whatever system generated it, and a system that needs its state to
satisfy a bound of its own says so here rather than editing the output. The
10BASE-T1S port is the caller this exists for: an event argument must subtype
`EventArgument`, and a timer that carries the machine's state is the whole
reason its arming allocates nothing.
"""
@document struct FsmComponent <: FsmDocument
    name::String
    variables::CellVector = CellVector()
    timers::CellVector = CellVector()
    events::CellVector = CellVector()
    machines::CellVector = CellVector()
    usings::CellVector = CellVector()
    helpers::CellVector = CellVector()
    supertype::String = ""
end

# ── Mixed positional+keyword constructors ────────────────────────────────
# The macro emits all-positional or all-keyword forms, never the mix, so the
# natural authoring shape `FsmState("IDLE"; entry = …)` is hand-written. Typed
# arguments keep these strictly more specific than the generated `::Any` forms
# (the `GraphEdge` precedent) — shadowing a generated method would be a fatal
# precompile overwrite.

_fsm_cellvector(items) =
    items isa CellVector ? items :
    CellVector(Cell[x isa Cell ? x : Cell(x) for x in items])

FsmVariable(name::AbstractString; type = nothing, default = nothing) =
    FsmVariable(Cell(String(name)), Cell(type), Cell(default), Cell(nothing))

FsmState(name::AbstractString; entry = nothing, transitions = FsmTransition[]) =
    FsmState(Cell(String(name)), Cell(entry), _fsm_cellvector(transitions), Cell(nothing))

FsmMachine(name::AbstractString; initial = nothing, states = FsmState[],
           on_unhandled::Symbol = :error) =
    FsmMachine(Cell(String(name)), Cell(initial), _fsm_cellvector(states),
               Cell(on_unhandled), Cell(nothing))

FsmComponent(name::AbstractString; variables = FsmVariable[], timers = FsmTimer[],
             events = FsmEvent[], machines = FsmMachine[], usings = [], helpers = [],
             supertype::AbstractString = "") =
    FsmComponent(Cell(String(name)), _fsm_cellvector(variables), _fsm_cellvector(timers),
                 _fsm_cellvector(events), _fsm_cellvector(machines),
                 _fsm_cellvector(usings), _fsm_cellvector(helpers),
                 Cell(String(supertype)), Cell(nothing))

# ── Lookup helpers ───────────────────────────────────────────────────────
# Name-based resolution is what the notation reader and the paste fix-up use;
# identity is what the stored references hold.
#
# Every helper here filters its collection by type first. A machine being
# edited legally holds an `FsmInsertion` in its `states` (that is what typing
# a new state looks like mid-commit), and a helper that assumed otherwise would
# throw on a field the placeholder does not have.

"""
    find_state(machine::FsmMachine, name::AbstractString) -> Union{FsmState, Nothing}

The state of `machine` called `name`; `nothing` when there is none.

Use it to look up a state of a machine by its name.

# Example

    component_1 = FsmComponent("Blinker"; machines = [FsmMachine("Main"; states = [FsmState("IDLE")])])
    machine_1 = find_fsm(component_1, "Main")
    state_1 = find_state(machine_1, "IDLE")

See also `get_fsm_states` and `find_fsm`.

For the assistant.
"""
function find_state end

function find_state(machine::FsmMachine, name::AbstractString)
    for s in machine.states
        s isa FsmState && s.name == name && return s
    end
    nothing
end

"""
    find_event(component::FsmComponent, name::AbstractString) -> Union{FsmEvent, Nothing}

The event of `component` called `name`; `nothing` when there is none.

Use it to look up an event of a component by its name.

# Example

    component_1 = FsmComponent("Blinker"; machines = [FsmMachine("Main"; states = [FsmState("IDLE")])])
    event_1 = find_event(component_1, "Tick")

See also `find_timer` and `find_fsm`.

For the assistant.
"""
function find_event end

function find_event(component::FsmComponent, name::AbstractString)
    for e in component.events
        e isa FsmEvent && e.name == name && return e
    end
    nothing
end

"""
    find_timer(component::FsmComponent, name::AbstractString) -> Union{FsmTimer, Nothing}

The timer of `component` called `name`; `nothing` when there is none.

Use it to look up a timer of a component by its name.

# Example

    component_1 = FsmComponent("Blinker"; machines = [FsmMachine("Main"; states = [FsmState("IDLE")])])
    timer_1 = find_timer(component_1, "Blink")

See also `find_event` and `find_fsm`.

For the assistant.
"""
function find_timer end

function find_timer(component::FsmComponent, name::AbstractString)
    for t in component.timers
        t isa FsmTimer && t.name == name && return t
    end
    nothing
end

"""
    find_fsm(component::FsmComponent, name::AbstractString) -> Union{FsmMachine, Nothing}

The machine of `component` called `name`; `nothing` when there is none.

Use it to look up a machine of a component by its name.

# Example

    component_1 = FsmComponent("Blinker"; machines = [FsmMachine("Main"; states = [FsmState("IDLE")])])
    machine_1 = find_fsm(component_1, "Main")

See also `find_state`, `find_event` and `find_timer`.

For the assistant.
"""
function find_fsm end

function find_fsm(component::FsmComponent, name::AbstractString)
    for m in component.machines
        m isa FsmMachine && m.name == name && return m
    end
    nothing
end

"""
    get_fsm_states(machine::FsmMachine) -> Vector{FsmState}

The states of `machine` as a plain `Vector{FsmState}`, in document order.

Use it to list the states of a machine.

# Example

    component_1 = FsmComponent("Blinker"; machines = [FsmMachine("Main"; states = [FsmState("IDLE")])])
    machine_1 = find_fsm(component_1, "Main")
    states_1 = get_fsm_states(machine_1)

See also `find_state` and `get_fsm_transitions`.

For the assistant.
"""
function get_fsm_states end

get_fsm_states(machine::FsmMachine) = FsmState[s for s in machine.states if s isa FsmState]

"""
All transitions of `machine` flattened in document order (states in order,
each state's transitions in order). This global order is the transition-index
vocabulary shared by `get_fsm_transition_index`, the generated `last_transition`
recording, and the diagram's live edge highlight.

Use it to list every transition of a machine in the order that the generated code and the diagram use.

# Example

    component_1 = FsmComponent("Blinker"; machines = [FsmMachine("Main"; states = [FsmState("IDLE")])])
    machine_1 = find_fsm(component_1, "Main")
    transitions_1 = get_fsm_transitions(machine_1)

See also `get_fsm_states`.

For the assistant.
"""
function get_fsm_transitions end

function get_fsm_transitions(machine::FsmMachine)
    result = FsmTransition[]
    for s in machine.states
        s isa FsmState || continue
        for t in s.transitions
            t isa FsmTransition && push!(result, t)
        end
    end
    result
end

"The 1-based global index of `transition` in `machine`'s flattened order; 0 when absent."
function get_fsm_transition_index(machine::FsmMachine, transition::FsmTransition)
    for (i, t) in enumerate(get_fsm_transitions(machine))
        t === transition && return i
    end
    0
end

# ── Insertion factories ──────────────────────────────────────────────────
# Every type with a required field needs one, or `insertable(T)`'s `T()` probe
# silently drops it from the completion list.

@insertion FsmVariable   = @selected FsmVariable("") name{0}
@insertion FsmTimer      = @selected FsmTimer("") name{0}
@insertion FsmEvent      = @selected FsmEvent("") name{0}
@insertion FsmState      = @selected FsmState("") name{0}
@insertion FsmMachine    = @selected FsmMachine("") name{0}
@insertion FsmComponent  = @selected FsmComponent("") name{0}

# ── Structural-insert gestures ───────────────────────────────────────────

@gestures FsmMachine begin
    KeyPress(',') => "Insert a new state" => append_insertion_operation(doc, :states, FsmInsertion)
end

@gestures FsmState begin
    KeyPress(',') => "Insert a new transition" => append_insertion_operation(doc, :transitions, FsmInsertion)
end
