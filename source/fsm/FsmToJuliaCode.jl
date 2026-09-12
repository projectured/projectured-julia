"""
    FsmToJuliaCodeModule

Code generation: an `FsmComponent` → a complete, runnable Julia module, built
as a `JuliaDocument` tree and written out through the ordinary
`print_natural_text` path.

This is deliberately **not** a registered bidirectional projection. Reading a
hand-edited generated file back into a machine is not a goal — the `.fsm`
document is the source, the `.jl` file is output — and the bidirectionality
convention applies to editor projections, not to exporters. What it *is* is a
document-to-document function, so the generated code can also be shown in the
editor (through the stock Julia pipeline) without generating a string first.

The embedded code is **spliced verbatim**: a guard, an action, an entry block,
a helper function is already a `JuliaDocument`, so it is placed into the
generated tree as-is. Nothing is stringified and re-parsed, and nothing is
rewritten — what the author sees in the notation is exactly what runs.

## What is generated

For a component named `Foo` with machines `A`, `B`:

```julia
module FooFsm
using ...                     # the component's own `usings`
const A_S_IDLE = Int32(0)     # one constant per state, per machine
const A_STATE_NAMES = ("IDLE", …)
mutable struct FooState       # the host: variables, timers, one Fsm per machine
    fsm_a::Fsm
    tx_timer::TimerHandle
    num_retries::Int
    …
end
FooState(; …) = …             # keyword constructor with the declared defaults
function a_dispatch!(ctx, m::FooState, event::Int32, payload = nothing)
    …                         # the transition logic
end
function a_expire_tx_timer!(ctx, m::FooState)  # one per (machine, timer) pair
    …
end
<helpers verbatim>
end # module FooFsm
```

**State values are 0-based document order.** They appear in recorded statistics
and are compared against a reference implementation's, so the numbering is part
of the contract, not an implementation detail.

The dispatch function is straight-line branching, not a table walk: it reads
like the hand-written protocol code it replaces, and runs at the same speed.
The runtime module an embedder supplies (`FsmModule`) gives
only what a local branch cannot express — the state cell, the deferred queue,
the re-entrancy guard, the cascade cap.
"""
module FsmToJuliaCodeModule

import ..FsmModule: FsmComponent, FsmMachine, FsmState, FsmTransition,
                    FsmVariable, FsmTimer, FsmEvent,
                    machine_states, machine_transitions
import ..JuliaModule: JuliaDocument, JuliaIdentifier, JuliaInteger, JuliaBool,
                      JuliaString, JuliaNothing, JuliaCall, JuliaBinaryOperation,
                      JuliaAssignment, JuliaBlock, JuliaIf, JuliaWhile,
                      JuliaReturn, JuliaBreak, JuliaConst, JuliaUsing,
                      JuliaStruct, JuliaSubtype, JuliaFunction, JuliaTuple,
                      JuliaTypeAnnotation, JuliaFieldAccess, JuliaModuleDefinition,
                      JuliaUnaryOperation
import ..NaturalNotationModule: print_natural_text

export generate_component, generate_component_text, export_component,
       state_constant_name, machine_field_name, dispatch_function_name,
       event_constant_name

# ── Naming ───────────────────────────────────────────────────────────────────
#
# Every generated name is derived here, in one place, so the dispatch function,
# the host struct and the timer callbacks cannot disagree about what a thing is
# called.

_upper(name) = uppercase(replace(name, r"[^A-Za-z0-9_]" => "_"))
_lower(name) = lowercase(replace(name, r"[^A-Za-z0-9_]" => "_"))

"The generated module's name: the component's name with an `Fsm` suffix."
module_name(component::FsmComponent) = component.name * "Fsm"

"The generated host struct's name."
host_type_name(component::FsmComponent) = component.name * "State"

"The constant naming one state of one machine, e.g. `MAC_S_IDLE`."
state_constant_name(machine::FsmMachine, state::FsmState) =
    _upper(machine.name) * "_S_" * _upper(state.name)

"The constant naming one event of the component, e.g. `E_UPPER_PACKET`."
event_constant_name(event::FsmEvent) = "E_" * _upper(event.name)

"The host struct's field holding one machine's `Fsm`."
machine_field_name(machine::FsmMachine) = "fsm_" * _lower(machine.name)

"The machine's dispatch function, e.g. `mac_dispatch!`."
dispatch_function_name(machine::FsmMachine) = _lower(machine.name) * "_dispatch!"

"The callback a timer's expiry schedules for one machine."
expiry_function_name(machine::FsmMachine, timer::FsmTimer) =
    _lower(machine.name) * "_expire_" * _lower(timer.name) * "!"

"The component-wide callback a timer's expiry schedules."
timer_expiry_name(timer::FsmTimer) = "expire_" * _lower(timer.name) * "!"

# ── Small AST helpers ────────────────────────────────────────────────────────

_id(name::AbstractString) = JuliaIdentifier(String(name))
_call(callee::AbstractString, args...) = JuliaCall(_id(callee), JuliaDocument[args...])
_field(object::AbstractString, name::AbstractString) = JuliaFieldAccess(_id(object), _id(name))
_int32(value::Integer) = _call("Int32", JuliaInteger(Int(value)))

# A body that is already a block stays one; anything else is wrapped, so every
# generated `if` branch has a block to hold statements.
_block(doc) = doc isa JuliaBlock ? doc : JuliaBlock(JuliaDocument[doc])
_block(docs::Vector) = JuliaBlock(JuliaDocument[docs...])

# ── Declarations ─────────────────────────────────────────────────────────────

"""
    state_constants(component) -> Vector{JuliaDocument}

One `const` per state of every machine, plus a name tuple per machine (which is
what a trace or an error message prints). Values are **0-based document
order**: they are recorded as statistics and compared against a reference
implementation, so the numbering is part of the contract.
"""
function state_constants(component::FsmComponent)
    result = JuliaDocument[]
    for machine in component.machines
        machine isa FsmMachine || continue
        states = machine_states(machine)
        for (index, state) in enumerate(states)
            push!(result, JuliaConst(JuliaAssignment(
                _id(state_constant_name(machine, state)), _int32(index - 1))))
        end
        push!(result, JuliaConst(JuliaAssignment(
            _id(_upper(machine.name) * "_STATE_NAMES"),
            JuliaTuple(JuliaDocument[JuliaString(s.name) for s in states]))))
    end
    result
end

"""
    event_constants(component) -> Vector{JuliaDocument}

One `const` per declared event, 1-based (0 is reserved for "no event", which is
how a condition-only re-evaluation is dispatched).
"""
function event_constants(component::FsmComponent)
    result = JuliaDocument[]
    for (index, event) in enumerate(component.events)
        event isa FsmEvent || continue
        push!(result, JuliaConst(JuliaAssignment(
            _id(event_constant_name(event)), _int32(index))))
    end
    result
end

"""
    host_struct(component) -> JuliaDocument

The mutable struct every generated function takes as `m`: one `Fsm` per
machine, one `TimerHandle` per timer, one field per variable. Plain and
mutable — this is hot-path state, not a document.
"""
function host_struct(component::FsmComponent)
    fields = JuliaDocument[]
    for machine in component.machines
        machine isa FsmMachine || continue
        push!(fields, JuliaTypeAnnotation(_id(machine_field_name(machine)), _id("Fsm")))
    end
    for timer in component.timers
        timer isa FsmTimer || continue
        push!(fields, JuliaTypeAnnotation(_id(timer.name), _id("TimerHandle")))
    end
    for variable in component.variables
        variable isa FsmVariable || continue
        type = variable.type
        push!(fields, type === nothing ? _id(variable.name) :
                      JuliaTypeAnnotation(_id(variable.name), type))
    end
    # `Foo <: Bar` when the component names a supertype, and the bare name when
    # it does not — an empty `supertype` generates exactly what it always did.
    head = isempty(component.supertype) ?
           _id(host_type_name(component)) :
           JuliaSubtype(_id(host_type_name(component)), _id(component.supertype))
    JuliaStruct(true, head, JuliaBlock(fields))
end

"""
    host_constructor(component) -> JuliaDocument

A keyword constructor filling in the declared defaults: the machines start in
their initial states, the timers are fresh handles, and each variable takes its
declared default (or `nothing` when it declares none).
"""
function host_constructor(component::FsmComponent)
    arguments = JuliaDocument[]
    for machine in component.machines
        machine isa FsmMachine || continue
        initial = machine.initial
        states = machine_states(machine)
        initial_state = initial isa FsmState ? initial :
                        (isempty(states) ? nothing : states[1])
        initial_value = initial_state === nothing ? _int32(0) :
                        _id(state_constant_name(machine, initial_state))
        push!(arguments, _call("Fsm", JuliaCall(_id("Symbol"), JuliaDocument[JuliaString(machine.name)]),
                               initial_value))
    end
    for timer in component.timers
        timer isa FsmTimer || continue
        push!(arguments, _call("TimerHandle"))
    end
    for variable in component.variables
        variable isa FsmVariable || continue
        default = variable.default
        push!(arguments, default === nothing ? JuliaNothing() : default)
    end
    JuliaAssignment(_call(host_type_name(component)),
                    _call(host_type_name(component), arguments...))
end

# ── Dispatch ─────────────────────────────────────────────────────────────────

# The guard of one transition, as the condition of the `if` that fires it:
# the trigger test and the author's guard, `&&`-joined. A condition-only
# transition contributes only the guard; an always-true event transition only
# the trigger test.
function _transition_condition(machine::FsmMachine, transition::FsmTransition,
                               component::FsmComponent)
    trigger = transition.trigger
    guard = transition.guard
    trigger_test = if trigger isa FsmEvent
        JuliaBinaryOperation(:(==), _id("event"), _id(event_constant_name(trigger)))
    elseif trigger isa FsmTimer
        JuliaBinaryOperation(:(==), _id("event"), _id("T_" * _upper(trigger.name)))
    else
        nothing
    end
    trigger_test === nothing && guard === nothing && return JuliaBool(true)
    trigger_test === nothing && return guard
    guard === nothing && return trigger_test
    JuliaBinaryOperation(:&&, trigger_test, guard)
end

# What one transition does when it fires. Order is the contract: the action
# runs, then the machine moves and the target's entry runs. A stay moves
# nothing and runs no entry.
function _transition_body(machine::FsmMachine, state::FsmState,
                          transition::FsmTransition, index::Integer)
    statements = JuliaDocument[]
    action = transition.action
    action === nothing || append!(statements, _statements(action))
    target = transition.target
    if target isa FsmState
        push!(statements, _call("fsm_goto!", _field("m", machine_field_name(machine)),
                                _id(state_constant_name(machine, target)), JuliaInteger(Int(index))))
        entry = target.entry
        if entry !== nothing
            # `prev` and `ev` are bound for the entry, which is the one place
            # the contract says can see the transition edge it arrived on.
            push!(statements, JuliaAssignment(_id("prev"), _id("_from")))
            push!(statements, JuliaAssignment(_id("ev"), _id("event")))
            append!(statements, _statements(entry))
        end
    end
    push!(statements, JuliaAssignment(_id("_fired"), JuliaBool(true)))
    JuliaBlock(statements)
end

_statements(doc) = doc isa JuliaBlock ? JuliaDocument[s for s in doc.statements] : JuliaDocument[doc]

# The per-state branch: try each transition in document order, first match
# wins. On a re-evaluation pass only the condition-only transitions are
# candidates — the event is spent.
function _state_branch(component::FsmComponent, machine::FsmMachine, state::FsmState,
                       flat_index::Dict{FsmTransition,Int})
    branch = nothing
    transitions = [t for t in state.transitions if t isa FsmTransition]
    for transition in reverse(transitions)
        condition = _transition_condition(machine, transition, component)
        # An event transition cannot fire on a re-evaluation pass.
        if transition.trigger !== nothing
            condition = JuliaBinaryOperation(:&&, _id("_is_event"), condition)
        end
        body = _transition_body(machine, state, transition, get(flat_index, transition, 0))
        branch = JuliaIf(condition, body, branch === nothing ? JuliaBlock(JuliaDocument[]) : _block(branch))
    end
    branch === nothing ? JuliaBlock(JuliaDocument[]) : branch
end

"""
    dispatch_function(component, machine) -> JuliaDocument

The machine's dispatch: one pass per cascade step, the current state's
transitions tried in order, the deferred queue drained once it settles.

`event` is the symbolic event, or 0 for a pure re-evaluation (how a
condition-driven machine is run). `payload` is whatever the classifier attached
to it.
"""
function dispatch_function(component::FsmComponent, machine::FsmMachine)
    flat = machine_transitions(machine)
    flat_index = Dict{FsmTransition,Int}(t => i for (i, t) in enumerate(flat))
    fsm = _field("m", machine_field_name(machine))

    # The state dispatch inside the cascade loop.
    state_branch = nothing
    for state in reverse(machine_states(machine))
        condition = JuliaBinaryOperation(:(==), _call("fsm_state", fsm),
                                  _id(state_constant_name(machine, state)))
        body = _state_branch(component, machine, state, flat_index)
        state_branch = JuliaIf(condition, _block(body),
                               state_branch === nothing ? JuliaBlock(JuliaDocument[]) : _block(state_branch))
    end

    loop_body = JuliaBlock(JuliaDocument[
        JuliaAssignment(_id("_fired"), JuliaBool(false)),
        JuliaAssignment(_id("_from"), _call("fsm_state", fsm)),
        state_branch === nothing ? JuliaBlock(JuliaDocument[]) : state_branch,
        # Nothing fired: the machine has settled.
        JuliaIf(JuliaUnaryOperation(:!, _id("_fired")),
                JuliaBlock(JuliaDocument[JuliaBreak()]), JuliaBlock(JuliaDocument[])),
        # Something fired, so the event (if any) is now spent: from here on
        # only condition transitions are candidates, and they go round again —
        # a move can enable one on the landed state, and a stay's action can
        # enable one on this state.
        JuliaAssignment(_id("_consumed"), JuliaBool(true)),
        JuliaAssignment(_id("_is_event"), JuliaBool(false)),
        JuliaAssignment(_id("_steps"), JuliaBinaryOperation(:+, _id("_steps"), JuliaInteger(1))),
        JuliaIf(JuliaBinaryOperation(:(>), _id("_steps"), _id("FSM_CASCADE_LIMIT")),
                JuliaBlock(JuliaDocument[_call("fsm_cascade_error", fsm)]),
                JuliaBlock(JuliaDocument[])),
    ])

    statements = JuliaDocument[
        _call("fsm_enter!", fsm),
        JuliaAssignment(_id("_is_event"), JuliaBinaryOperation(:(!=), _id("event"), _int32(0))),
        JuliaAssignment(_id("_consumed"), JuliaUnaryOperation(:!, _id("_is_event"))),
        JuliaAssignment(_id("_steps"), JuliaInteger(0)),
        JuliaWhile(JuliaBool(true), loop_body),
        _call("fsm_leave!", fsm),
    ]
    # The unhandled policy. `:ignore` writes nothing at all — an unlisted
    # (state, event) pair is legal, which is what TCP's empty `default:` means.
    if machine.on_unhandled !== :ignore
        push!(statements, JuliaIf(JuliaCall(_id("!"), JuliaDocument[_id("_consumed")]),
            JuliaBlock(JuliaDocument[_call("fsm_unhandled_error", fsm, _id("event"))]),
            JuliaBlock(JuliaDocument[])))
    end
    push!(statements, _call("fsm_drain!", fsm))
    push!(statements, JuliaReturn(JuliaNothing()))

    JuliaFunction(_id(dispatch_function_name(machine)),
                  JuliaDocument[_id("ctx"),
                                JuliaTypeAnnotation(_id("m"), _id(host_type_name(component))),
                                JuliaTypeAnnotation(_id("event"), _id("Int32")),
                                _id("payload")],
                  JuliaBlock(statements))
end

"""
    timer_expiry_functions(component) -> Vector{JuliaDocument}

One callback per timer, routing its expiry the way the reference
implementation's `handleSelfMessage` does: a **timeout event** to every machine
that names the timer as a trigger, and an **event-less re-evaluation** to every
machine that has condition-only transitions (whose guards may poll
`is_scheduled`, and so change meaning the moment the timer fires).
"""
function timer_expiry_functions(component::FsmComponent)
    result = JuliaDocument[]
    for timer in component.timers
        timer isa FsmTimer || continue
        statements = JuliaDocument[]
        for machine in component.machines
            machine isa FsmMachine || continue
            triggered = any(t -> t.trigger === timer, machine_transitions(machine))
            conditional = any(t -> t.trigger === nothing, machine_transitions(machine))
            if triggered
                push!(statements, _call(dispatch_function_name(machine), _id("ctx"), _id("m"),
                                        _id("T_" * _upper(timer.name)), JuliaNothing()))
            elseif conditional
                push!(statements, _call(dispatch_function_name(machine), _id("ctx"), _id("m"),
                                        _int32(0), JuliaNothing()))
            end
        end
        push!(statements, JuliaReturn(JuliaNothing()))
        push!(result, JuliaFunction(_id(timer_expiry_name(timer)),
                                    JuliaDocument[_id("ctx"),
                                                  JuliaTypeAnnotation(_id("m"), _id(host_type_name(component)))],
                                    JuliaBlock(statements)))
    end
    result
end

"""
    timer_event_constants(component) -> Vector{JuliaDocument}

One event constant per timer, numbered after the declared events so a timeout
and an event never collide.
"""
function timer_event_constants(component::FsmComponent)
    base = count(e -> e isa FsmEvent, component.events)
    result = JuliaDocument[]
    for (index, timer) in enumerate(component.timers)
        timer isa FsmTimer || continue
        push!(result, JuliaConst(JuliaAssignment(
            _id("T_" * _upper(timer.name)), _int32(base + index))))
    end
    result
end

# ── The whole module ─────────────────────────────────────────────────────────

"""
    generate_component(component::FsmComponent; wrap_module = true) -> JuliaDocument

The complete generated code, as a Julia document. Everything the component
declares is present: its `usings`, the state and event constants, the host
struct and its constructor, one dispatch function per machine, the timer
expiry callbacks, and the author's own helpers spliced verbatim at the end.

`wrap_module = false` returns the bare `JuliaBlock` of top-level statements
instead of a module. That is what a host package needs when the generated file
is `include`d into an existing module rather than standing alone as a file —
the 10BASE-T1S slice, where nine files make up one module, is the case that
asked for it.
"""
function generate_component(component::FsmComponent; wrap_module::Bool = true)
    statements = JuliaDocument[]
    for using_item in component.usings
        push!(statements, using_item)
    end
    append!(statements, state_constants(component))
    append!(statements, event_constants(component))
    append!(statements, timer_event_constants(component))
    push!(statements, host_struct(component))
    push!(statements, host_constructor(component))
    for machine in component.machines
        machine isa FsmMachine || continue
        push!(statements, dispatch_function(component, machine))
    end
    append!(statements, timer_expiry_functions(component))
    for helper in component.helpers
        push!(statements, helper)
    end
    body = JuliaBlock(statements)
    wrap_module ? JuliaModuleDefinition(module_name(component), body) : body
end

"""
    generate_component_text(component::FsmComponent; wrap_module = true) -> String

The generated code as Julia source, through the ordinary `print_natural_text`
path, with a header naming the machine it came from.
"""
generate_component_text(component::FsmComponent; wrap_module::Bool = true) =
    "# Generated from the state machine `" * component.name *
    "` — edit the machine, not this file.\n\n" *
    print_natural_text(generate_component(component; wrap_module = wrap_module)) * "\n"

"""
    export_component(component::FsmComponent, path::AbstractString; wrap_module = true)

Write the generated code to `path`.
"""
function export_component(component::FsmComponent, path::AbstractString;
                          wrap_module::Bool = true)
    write(path, generate_component_text(component; wrap_module = wrap_module))
    path
end

end # module
