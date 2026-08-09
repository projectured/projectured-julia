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
    @test occursin("variable blinks::Int = 0", text)
    @test occursin("timer blink_timer", text)
    @test occursin("event PRESSED", text)
    @test occursin("machine Toggle initial OFF", text)
    @test occursin("state OFF", text)

    # Transition grammar: trigger, guard, ending, action.
    @test occursin("on PRESSED -> ON", text)
    @test occursin("on timeout(blink_timer) when m.blinks > 3 -> OFF", text)
    # A stay has no target and keeps its action.
    @test occursin("on PRESSED stay / m.blinks = m.blinks + 1", text)
    # An entry action is its own indented line under the state.
    @test occursin("entry / m.blinks = m.blinks + 1", text)

    # `:error` is the default policy and stays unwritten; `:ignore` is spelled.
    @test !occursin("ignoring unhandled", text)
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
    push!(c.transitions, FsmTransition(guard = juliaparse("m.ready"), target = c))
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

# ── the julia parser gap this notation depends on ────────────────────────
# A transition action is naturally written as a semicolon-separated group on
# one line; that parses to a `:toplevel` nested inside the outer one, which the
# parser used to reject outright.
@testset "semicolon statement groups parse" begin
    block = juliaparse("a!(m); b!(m)")
    @test block isa JuliaBlock
    @test length(block.statements) == 2
end

end # @testset "FsmToSyntax"
end # test_fsm_to_syntax
