function test_fsm_to_julia_code()
@testset "FsmToJuliaCode" begin

# ── shape ────────────────────────────────────────────────────────────────
@testset "the generated module is complete and parses" begin
    text = generate_component_text(make_fsm_toggle_document_example())

    @test occursin("module ToggleFsm", text)
    @test occursin("end # module ToggleFsm", text)
    # State constants are 0-based document order — the values are recorded as
    # statistics and compared against a reference implementation, so the
    # numbering is part of the contract.
    @test occursin("const TOGGLE_S_OFF = Int32(0)", text)
    @test occursin("const TOGGLE_S_ON = Int32(1)", text)
    @test occursin("const TOGGLE_STATE_NAMES = (\"OFF\", \"ON\")", text)
    # Events are 1-based; 0 means "no event", the pure re-evaluation dispatch.
    @test occursin("const E_PRESSED = Int32(1)", text)
    # A timer's event is numbered after the declared events, so a timeout and
    # an event never collide.
    @test occursin("const T_BLINK_TIMER = Int32(2)", text)
    @test occursin("mutable struct ToggleState", text)
    @test occursin("fsm_toggle::Fsm", text)
    @test occursin("blink_timer::TimerHandle", text)
    @test occursin("blinks::Int", text)
    @test occursin("function toggle_dispatch!", text)
    @test occursin("function expire_blink_timer!", text)
    # The author's code is spliced verbatim, never stringified and rewritten.
    @test occursin("m.blinks = m.blinks + 1", text)

    # It is real Julia.
    @test (Meta.parseall(text); true)

    # `wrap_module = false` emits the same statements without the module, for
    # a host package whose file is `include`d into an existing module.
    bare = generate_component_text(make_fsm_toggle_document_example(); wrap_module = false)
    @test !occursin("module ToggleFsm", bare)
    @test occursin("mutable struct ToggleState", bare)
    @test occursin("function toggle_dispatch!", bare)
    @test (Meta.parseall(bare); true)
end

@testset "helpers and usings come along" begin
    text = generate_component_text(make_fsm_tcp_document_example())
    @test occursin("const MSL = 120.0", text)
    @test occursin("function analyse_segment", text)
    @test occursin("ack_acceptable(m, seg)", text)
    # The `:ignore` policy writes no unhandled check at all: an unlisted
    # (state, event) pair is legal, which is what TCP means by an empty
    # `default:` arm.
    @test !occursin("fsm_unhandled_error", text)
    @test (Meta.parseall(text); true)
end

# ── semantics ────────────────────────────────────────────────────────────
# The generated code is loaded and run, against the contract in fsm.md. This
# is the part that a snapshot test cannot check.
@testset "generated code runs to the contract" begin
    component = _fsm_semantics_component()
    mod = _load_generated(component, :FsmSemanticsProbe)
    state = Base.invokelatest(_binding(mod, :ProbeState))
    dispatch(event, payload = nothing) =
        Base.invokelatest(_binding(mod, :probe_dispatch!), nothing, state, event, payload)
    # Read the state off the Fsm directly: the runtime names the generated
    # module `using`s are not reachable through `getfield` on it.
    current() = Int(state.fsm_probe.state)

    S_IDLE  = Int(_binding(mod, :PROBE_S_IDLE))
    S_BUSY  = Int(_binding(mod, :PROBE_S_BUSY))
    E_GO    = _binding(mod, :E_GO)
    E_PING  = _binding(mod, :E_PING)
    E_STOP  = _binding(mod, :E_STOP)

    @test current() == S_IDLE

    # An event transition moves, and the target's entry runs.
    dispatch(E_GO)
    @test current() == S_BUSY
    @test state.entries == 1
    @test state.count == 0

    # A stay runs its action with the event's payload, does not move, and does
    # not re-run entry.
    dispatch(E_PING, 1)
    @test current() == S_BUSY
    @test state.count == 1
    @test state.entries == 1

    # An ignore consumes the event and does nothing at all.
    dispatch(E_STOP)
    @test current() == S_BUSY
    @test state.count == 1

    # The payload really is the event's, not a constant.
    dispatch(E_PING, 41)
    @test state.count == 42

    # A cascade: this event moves to DONE, whose condition-only transition
    # fires in the same dispatch and carries on to IDLE.
    state.ready = true
    dispatch(E_GO)
    @test current() == S_IDLE
    @test state.entries == 3      # BUSY, DONE, IDLE — one entry each

    # An unhandled event is an error under the default policy.
    @test_throws ErrorException dispatch(E_STOP)
end

@testset "deferred actions run after the cascade settles" begin
    component = _fsm_semantics_component()
    mod = _load_generated(component, :FsmDeferProbe)
    state = Base.invokelatest(_binding(mod, :ProbeState))
    # The DONE entry defers a call; it must not run until the machine has
    # settled and left its own cascade.
    state.ready = true
    dispatch(event) = Base.invokelatest(_binding(mod, :probe_dispatch!), nothing, state, event, nothing)
    dispatch(_binding(mod, :E_GO))    # IDLE → BUSY
    dispatch(_binding(mod, :E_GO))    # BUSY → DONE, which defers, then cascades to IDLE
    @test state.deferred_at_entry == 0     # not yet run while cascading
    @test state.deferred_runs == 1         # ran once, in the drain
end

end # @testset "FsmToJuliaCode"
end # test_fsm_to_julia_code

# ── the probe machine ────────────────────────────────────────────────────────
#
# Built here rather than registered as an example: it exists to exercise the
# execution contract (stay, ignore, entry, cascade, deferral, unhandled), not
# to be looked at.

function _fsm_semantics_component()
    go   = FsmEvent("GO")
    ping = FsmEvent("PING")
    stop = FsmEvent("STOP")

    idle = FsmState("IDLE"; entry = parse_julia("m.entries = m.entries + 1"))
    busy = FsmState("BUSY"; entry = parse_julia("m.entries = m.entries + 1"))
    done = FsmState("DONE"; entry = parse_julia("""
        m.entries = m.entries + 1
        fsm_defer!(m.fsm_probe, () -> begin
            m.deferred_runs = m.deferred_runs + 1
        end)
        """))

    # IDLE: GO → BUSY.
    push!(idle.transitions, FsmTransition(trigger = go, target = busy))
    # BUSY: PING stays and counts (with the payload when there is one); STOP is
    # ignored; GO moves on to DONE.
    push!(busy.transitions, FsmTransition(trigger = ping,
        action = parse_julia("m.count = m.count + payload")))
    push!(busy.transitions, FsmTransition(trigger = stop))
    push!(busy.transitions, FsmTransition(trigger = go, target = done))
    # DONE: a condition-only transition, which fires in the same dispatch that
    # landed here — the cascade.
    push!(done.transitions, FsmTransition(guard = parse_julia("m.ready"),
        action = parse_julia("m.deferred_at_entry = m.deferred_runs"),
        target = idle))

    machine = FsmMachine("Probe"; initial = idle, states = [idle, busy, done])

    FsmComponent("Probe";
        # Where the generated module gets `Fsm`, `fsm_goto!` and the rest —
        # the component says so itself, exactly as a real one names the
        # simulator's runtime module.
        usings = [JuliaUsing(:using, "..ProbeRuntime")],
        variables = [FsmVariable("count"; type = parse_julia("Int"), default = parse_julia("0")),
                     FsmVariable("entries"; type = parse_julia("Int"), default = parse_julia("0")),
                     FsmVariable("ready"; type = parse_julia("Bool"), default = parse_julia("false")),
                     FsmVariable("deferred_runs"; type = parse_julia("Int"), default = parse_julia("0")),
                     FsmVariable("deferred_at_entry"; type = parse_julia("Int"), default = parse_julia("0"))],
        events = [go, ping, stop],
        machines = [machine])
end

# Reading a binding that a just-evaluated module defined is itself a world-age
# access, not only calling it — hence the `invokelatest` here rather than a bare
# `getfield`.
_binding(mod::Module, name::Symbol) = Base.invokelatest(getfield, mod, name)

# Load a generated component as a real module. The runtime it calls
# (`Fsm`, `fsm_goto!`, …) lives in an embedder, which this package does not
# depend on — so the probe module is given a local stand-in with the same
# contract. That the generated code compiles and runs against *an*
# implementation of the contract is what is being checked here; the real
# runtime is exercised by its own tests and by the inet-julia pilot.
function _load_generated(component, name::Symbol)
    text = generate_component_text(component)
    mod = Module(name)
    # A `module` expression is only legal at top level, so both the stand-in
    # runtime and the generated module are loaded as source, not as a quoted
    # expression.
    Base.include_string(mod, _PROBE_RUNTIME_SOURCE)
    # The generated module's own `using ..ProbeRuntime` is what binds the
    # runtime names it calls.
    Base.include_string(mod, text)
    _binding(mod, Symbol(component.name * "Fsm"))
end

const _PROBE_RUNTIME_SOURCE = """
module ProbeRuntime
export Fsm, TimerHandle, FSM_CASCADE_LIMIT, fsm_state, fsm_enter!, fsm_leave!,
       fsm_goto!, fsm_defer!, fsm_drain!, fsm_cascade_error, fsm_unhandled_error
mutable struct Fsm
    name::Symbol
    state::Int32
    transition_count::Int
    last_transition::Int32
    busy::Bool
    deferred::Vector{Any}
    on_transition::Any
end
Fsm(name::Symbol, initial::Integer) = Fsm(name, Int32(initial), 0, Int32(0), false, Any[], nothing)
mutable struct TimerHandle
    gen::Int
    active::Bool
end
TimerHandle() = TimerHandle(0, false)
const FSM_CASCADE_LIMIT = 32
fsm_state(f) = f.state
function fsm_enter!(f)
    f.busy && error("fsm \$(f.name): re-entrant dispatch")
    f.busy = true
    nothing
end
fsm_leave!(f) = (f.busy = false; nothing)
function fsm_goto!(f, s, i)
    f.state = Int32(s); f.transition_count += 1; f.last_transition = Int32(i); nothing
end
fsm_defer!(f, g) = (push!(f.deferred, g); nothing)
function fsm_drain!(f)
    while !isempty(f.deferred)
        pending = copy(f.deferred); empty!(f.deferred)
        for g in pending; g(); end
    end
    nothing
end
fsm_cascade_error(f) = error("fsm \$(f.name): cascade did not settle")
fsm_unhandled_error(f, e) = error("fsm \$(f.name): unhandled event \$e in state \$(f.state)")
end # module ProbeRuntime
"""
