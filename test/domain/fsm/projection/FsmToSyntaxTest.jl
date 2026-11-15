function test_fsm_to_syntax()
@testset "FsmToSyntax" begin

_render(doc) = print_document(
    ChainingProjection(RecursiveProjection(FsmToSyntax()),
                       RecursiveProjection(SyntaxToText()),
                       RecursiveProjection(TextToString())),
    doc).output

# ── the notation ─────────────────────────────────────────────────────────
@testset "notation" begin
    text = _render(make_fsm_toggle_document_example())

    # Declarations, one keyword each.
    @test occursin("component Toggle", text)
    @test occursin("variable switch_ons::Int = 0", text)
    @test occursin("timer off_timer", text)
    @test occursin("event PRESSED", text)
    @test occursin("machine Toggle initial OFF", text)
    @test occursin("state OFF", text)
    # A helper prints as Julia after the machines.
    @test occursin("const AUTO_OFF_TIME = 60.0", text)

    # Transition grammar: trigger, ending, action.
    @test occursin("on PRESSED -> ON", text)
    @test occursin("on PRESSED -> OFF / cancel_timer!(ctx, m.off_timer)", text)
    @test occursin("on timeout(off_timer) -> OFF", text)
    # An entry of two statements prints as indented lines under `entry /`.
    @test occursin(r"entry / *\n +m\.switch_ons = m\.switch_ons \+ 1\n +schedule_timer!\(", text)

    crossing = _render(make_fsm_crossing_document_example())
    # A stay has no target and keeps its action.
    @test occursin("on BUTTON stay / m.requested = true", crossing)
    # A condition-only transition has no trigger, so its line starts at `when`.
    @test occursin("when m.requested && !is_scheduled(m.min_green_timer) -> CARS_YELLOW", crossing)
    # With no guard either, the line is the target alone.
    @test occursin(r"state START\n +-> CARS_GREEN\n", crossing)
    # A one-statement entry stays on the line of `entry /`.
    @test occursin("entry / start_timer!(ctx, m, m.yellow_timer, YELLOW_TIME, expire_yellow_timer!)", crossing)

    protocol = _render(make_fsm_alternating_bit_document_example())
    # All four parts of a transition: trigger, guard, target, action.
    @test occursin("on ACK when payload == 0 -> WAIT_SEND_1 / cancel_timer!(ctx, m.retransmit_timer)", protocol)
    # An ignore has no target and no action.
    @test occursin("on ACK ignore", protocol)
    @test occursin("on timeout(retransmit_timer) stay / send_frame!(ctx, m, 0)", protocol)
    # The statements of a `;` line stay on the line of their transition.
    @test occursin("on SEND -> WAIT_ACK_0 / m.buffer = payload; send_frame!(ctx, m, 0)", protocol)
    # Each machine of the component prints its own header.
    @test occursin("machine Sender initial WAIT_SEND_0", protocol)
    @test occursin("machine Receiver initial WAIT_FRAME_0", protocol)

    # `:error` is the default policy and stays unwritten; `:ignore` is spelled.
    @test !occursin("ignoring unhandled", text)
    @test occursin("machine Light initial START ignoring unhandled", crossing)
    @test occursin("ignoring unhandled", _render(make_fsm_tcp_document_example()))
end

@testset "empty sections and ignores" begin
    # A component with nothing but a name renders exactly one line — an empty
    # section must contribute no blank line of its own.
    @test strip(_render(FsmComponent("Empty"))) == "component Empty"

    # An ignore is a stay with no action.
    s = FsmState("S")
    push!(s.transitions, FsmTransition(trigger = FsmEvent("E")))
    text = _render(s)
    @test occursin("on E ignore", text)

    # A condition-only transition opens with its guard, no trigger part.
    c = FsmState("C")
    push!(c.transitions, FsmTransition(guard = parse_julia("m.ready"), target = c))
    @test occursin("when m.ready -> C", _render(c))
end

@testset "identity references render the referent's name" begin
    a = FsmState("A")
    b = FsmState("B")
    push!(a.transitions, FsmTransition(trigger = FsmEvent("GO"), target = b))
    m = FsmMachine("M"; initial = a, states = [a, b])

    @test occursin("-> B", _render(m))
    @test occursin("initial A", _render(m))

    # Renaming the referent updates every mention: the name leaf reads through
    # the identity reference, it does not hold a copy of the name.
    b.name = "BEE"
    a.name = "AY"
    text = _render(m)
    @test occursin("-> BEE", text)
    @test occursin("initial AY", text)
    @test !occursin("-> B\n", text)

    # An unresolved reference is a legal state of a machine under construction.
    @test occursin("initial ?", _render(FsmMachine("U")))
end

# ── selection round-trip ─────────────────────────────────────────────────
@testset "selection maps through the notation" begin
    doc = make_fsm_toggle_document_example()
    # Print through the recursion so children project, but map through the rule
    # the recursion dispatched to (the graph test's idiom — the wrapper's own
    # mapper is ambiguous against the template engine's).
    iomap = print_document(RecursiveProjection(FsmToSyntax()), doc)
    projection = iomap.projection
    @test projection isa FsmComponentToSyntaxNode

    roundtrips(reference) = begin
        forward = map_reference_forward(projection, iomap, reference)
        forward === nothing && return false
        back = map_reference_backward(projection, iomap, forward)
        back !== nothing &&
            is_reference_equal(strip_reference_types(back), strip_reference_types(reference))
    end

    # A caret in a state's name. Every node of the path names its type,
    # terminal included — an under-typed `@reference` is rejected outright.
    @test roundtrips(@reference ::FsmComponent.machines::CellVector[1]::FsmMachine.states::CellVector[1]::FsmState.name::String{0}::Position)
    # A whole-element selection of the same state.
    @test roundtrips(@reference ::FsmComponent.machines::CellVector[1]::FsmMachine.states::CellVector[1]::FsmState)
    # And one reaching into an embedded Julia action, through the merged table.
    @test roundtrips(@reference ::FsmComponent.machines::CellVector[1]::FsmMachine.states::CellVector[2]::FsmState.transitions::CellVector[1]::FsmTransition)
end

# ── the julia parse this notation depends on ─────────────────────────────
# A transition action is naturally written as a semicolon-separated group on
# one line; that parses to a `:toplevel` nested inside the outer one, which is a
# `JuliaToplevel` of the statements.
@testset "semicolon statement groups parse" begin
    group = parse_julia("a!(m); b!(m)")
    @test group isa JuliaToplevel
    @test length(group.statements) == 2
end

end # @testset "FsmToSyntax"
end # test_fsm_to_syntax
