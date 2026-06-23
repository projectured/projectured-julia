# Reified gesture bindings: pattern matching/describe, the @gestures macro,
# supertype inheritance, applicability, and the document_read interpreter.
# JSON document_read *parity* with the old hand-written readers lives in
# JsonToSyntaxTest (test_json_to_syntax_reader) — exercised through the real
# projection pipeline.

# A throwaway document hierarchy to register gestures on, independent of any
# real domain. `GestureProbe` is the abstract base; the concrete leaves inherit
# its bindings.
abstract type GestureProbe <: Document end

@document struct GestureProbeLeaf <: GestureProbe
    value::Int = 0
    selection::Reference = nothing
end

@document struct GestureProbeArray <: GestureProbe
    selection::Reference = nothing
end

# Shared (base-type) bindings, with a block precondition over (doc, sel).
@gestures GestureProbe begin
    when(sel !== nothing)
    KeyPress('n')                  => "make negative" => MarkOperation(:neg)
    KeyPress('p')                  => "make positive" => MarkOperation(:pos)
    when(KeyPress(c), isdigit(c))  => "set digit"     => MarkOperation(Symbol(c))
    KeyDown(:period; ctrl)         => "toggle"        => MarkOperation(:toggle)
end

# Subtype-specific binding, no precondition.
@gestures GestureProbeArray begin
    KeyPress(',')                  => "append"        => MarkOperation(:append)
end

# A tiny operation stand-in so the binding RHS produces something identifiable.
struct MarkOperation
    tag::Symbol
end

function test_gesture_binding()
@testset "GestureBinding" begin

    @testset "matches: KeyPress ignores modifiers, honours char + guard" begin
        p = KeyPressPattern('n')
        @test matches(p, KeyPress('n'))
        @test matches(p, KeyPress('n', Modifiers(shift=true)))   # modifiers ignored
        @test !matches(p, KeyPress('x'))
        @test !matches(p, KeyDown(:n, Modifiers()))

        digit = KeyPressPattern(nothing, e -> isdigit(e.char), "0-9")
        @test matches(digit, KeyPress('5'))
        @test !matches(digit, KeyPress('z'))
    end

    @testset "matches: KeyDown honours key + exact modifiers" begin
        p = KeyDownPattern(:period, [:ctrl], nothing)
        @test matches(p, KeyDown(:period, Modifiers(ctrl=true)))
        @test !matches(p, KeyDown(:period, Modifiers()))                    # ctrl required
        @test !matches(p, KeyDown(:period, Modifiers(ctrl=true, alt=true))) # exact: alt absent
        @test !matches(p, KeyDown(:home, Modifiers(ctrl=true)))
    end

    @testset "matches: MousePress honours button, ignores position" begin
        p = MousePressPattern(:left, nothing, nothing)
        @test matches(p, MousePress(:left, 10, 20))
        @test matches(p, MousePress(:left, 99, 5))
        @test !matches(p, MousePress(:right, 10, 20))
    end

    @testset "describe renders readable gesture strings" begin
        @test describe(KeyPressPattern('n')) == "n"
        @test describe(KeyDownPattern(:period, [:ctrl], nothing)) == "Ctrl+."
        @test describe(KeyDownPattern(:tab, nothing, nothing)) == "Tab"
        @test describe(KeyDownPattern(:home, [:ctrl, :alt], nothing)) == "Ctrl+Alt+Home"
        @test describe(MousePressPattern(:left, nothing, nothing)) == "Left click"
    end

    @testset "@gestures registers an own table; descriptions captured" begin
        own = document_gestures_own(GestureProbe)
        @test length(own) == 4
        @test [b.description for b in own] ==
              ["make negative", "make positive", "set digit", "toggle"]
        @test all(b -> b.domain == "GestureProbe", own)
    end

    @testset "supertype inheritance: subtype = own + base, most-specific first" begin
        leaf = document_gestures(GestureProbeLeaf)
        @test length(leaf) == 4                       # only inherited base bindings
        arr = document_gestures(GestureProbeArray)
        @test length(arr) == 5                        # own (1) + base (4)
        @test arr[1].description == "append"          # own first
        @test arr[2].description == "make negative"   # then inherited
    end

    @testset "read_document_gesture fires the matching, applicable binding" begin
        leaf = GestureProbeLeaf()
        leaf.selection = EmptyReferencePath()
        @test read_document_gesture(leaf, KeyPress('n')) == MarkOperation(:neg)
        @test read_document_gesture(leaf, KeyPress('7')) == MarkOperation(Symbol('7'))
        @test read_document_gesture(leaf, KeyDown(:period, Modifiers(ctrl=true))) == MarkOperation(:toggle)
        # An unbound gesture yields nothing.
        @test read_document_gesture(leaf, KeyPress('z')) === nothing
    end

    @testset "applicable precondition gates firing (and greys help rows)" begin
        leaf = GestureProbeLeaf()           # selection === nothing → precondition false
        @test read_document_gesture(leaf, KeyPress('n')) === nothing
        @test isempty(applicable_gestures(leaf, document_gestures(GestureProbeLeaf)))
        leaf.selection = EmptyReferencePath()
        @test length(applicable_gestures(leaf, document_gestures(GestureProbeLeaf))) == 4
    end

    @testset "document_read interpreter routes through the reified table" begin
        arr = GestureProbeArray()
        arr.selection = EmptyReferencePath()
        @test document_read(arr, KeyPress(',')) == MarkOperation(:append)   # own
        @test document_read(arr, KeyPress('p')) == MarkOperation(:pos)      # inherited
    end

end
end

export test_gesture_binding
