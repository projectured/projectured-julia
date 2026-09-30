function test_fsm_document()
@testset "FsmDocuments" begin

# ── declarations ─────────────────────────────────────────────────────────
v = FsmVariable("num_retries")
@test v.name == "num_retries"
@test v.type === nothing
@test v.default === nothing
v.name = "retries"
@test v.name == "retries"

t = FsmTimer("tx_timer")
@test t.name == "tx_timer"

e = FsmEvent("UPPER_PACKET")
@test e.name == "UPPER_PACKET"

# ── structure ────────────────────────────────────────────────────────────
idle = FsmState("IDLE")
transmitting = FsmState("TRANSMITTING")
@test idle.entry === nothing
@test length(idle.transitions) == 0

# event transition, held by identity
tr = FsmTransition(trigger = e, target = transmitting)
@test tr.trigger === e
@test tr.target === transmitting
@test tr.guard === nothing
@test tr.action === nothing
push!(idle.transitions, tr)
@test length(idle.transitions) == 1
@test idle.transitions[1] === tr

# stay: no target; ignore: stay with no action
stay = FsmTransition(trigger = e)
@test stay.target === nothing

# condition-only transition: no trigger
cond = FsmTransition(target = idle)
@test cond.trigger === nothing

# true self-transition: target is the containing state
selftr = FsmTransition(trigger = e, target = idle)
push!(idle.transitions, selftr)
@test idle.transitions[2].target === idle

machine = FsmMachine("Mac", states = [idle, transmitting], initial = idle)
@test machine.name == "Mac"
@test machine.initial === idle
@test machine.on_unhandled === :error
@test length(machine.states) == 2
machine.on_unhandled = :ignore
@test machine.on_unhandled === :ignore

comp = FsmComponent("EthernetCsmaMac")
@test comp.name == "EthernetCsmaMac"
push!(comp.variables, v)
push!(comp.timers, t)
push!(comp.events, e)
push!(comp.machines, machine)
@test length(comp.variables) == 1
@test comp.machines[1] === machine

# ── lookup helpers ───────────────────────────────────────────────────────
@test find_state(machine, "IDLE") === idle
@test find_state(machine, "NOPE") === nothing
@test find_event(comp, "UPPER_PACKET") === e
@test find_event(comp, "NOPE") === nothing
@test find_timer(comp, "tx_timer") === t
@test find_fsm(comp, "Mac") === machine
@test find_fsm(comp, "NOPE") === nothing
@test get_fsm_states(machine) == [idle, transmitting]

# flattened transition order = states in order, each state's transitions in order
push!(transmitting.transitions, FsmTransition(trigger = e, target = idle))
flat = get_fsm_transitions(machine)
@test length(flat) == 3
@test flat[1] === tr
@test flat[2] === selftr
@test get_fsm_transition_index(machine, flat[3]) == 3
@test get_fsm_transition_index(machine, FsmTransition()) == 0

# ── renaming a state never dangles identity references ──────────────────
transmitting.name = "TX"
@test tr.target === transmitting
@test tr.target.name == "TX"
@test find_state(machine, "TX") === transmitting

# ── domain kit ───────────────────────────────────────────────────────────
@test FsmNothing() isa FsmDocument
@test FsmInsertion() isa FsmDocument
@test make_insertion_document(FsmState) isa FsmState
@test make_insertion_document(FsmMachine) isa FsmMachine
@test make_insertion_document(FsmComponent) isa FsmComponent
@test make_insertion_document(FsmTransition) isa FsmTransition
for T in (FsmVariable, FsmTimer, FsmEvent, FsmState, FsmMachine, FsmComponent, FsmTransition)
    @test insertable(T)
end

# ── reactivity: a computed cell over a document field ────────────────────
base = Cell("IDLE")
named = FsmState(Cell(@computation base[] * "!"))
@test named.name == "IDLE!"
base[] = "BUSY"
@test named.name == "BUSY!"

end # @testset "FsmDocuments"
end # test_fsm_document
