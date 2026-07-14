# Reified gesture bindings: pattern matching/describe, the @gestures macro,
# supertype inheritance, applicability, and the read_gesture interpreter.
# JSON read_gesture *parity* with the old hand-written readers lives in
# JsonToSyntaxTest (test_json_to_syntax_reader) — exercised through the real
# projection pipeline.

# A throwaway document hierarchy to register gestures on, independent of any
# real domain. `GestureProbe` is the abstract base; the concrete leaves inherit
# its bindings.
abstract type GestureProbe <: Document end

@document struct GestureProbeLeaf <: GestureProbe
    value::Int = 0
end

@document struct GestureProbeArray <: GestureProbe
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

# A reusable gesture set spliced into two UNRELATED document types (no common
# supertype below Document) — the cross-type sharing single inheritance can't
# express. The set carries its own precondition and domain tag.
@gesture_set probe_clipboard begin
    KeyDown(:c; ctrl)              => "Copy"          => MarkOperation(:copy)
    KeyDown(:v; ctrl)              => "Paste"         => MarkOperation(:paste)
end

@document struct ProbeAlpha
end
@document struct ProbeBeta
end

@gestures ProbeAlpha begin
    splice(probe_clipboard)
    KeyPress('a')                  => "alpha only"    => MarkOperation(:alpha)
end

@gestures ProbeBeta begin
    splice(probe_clipboard)
    KeyPress('b')                  => "beta only"     => MarkOperation(:beta)
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
        own = get_document_gesture_bindings_own(GestureProbe)
        @test length(own) == 4
        @test [b.description for b in own] ==
              ["make negative", "make positive", "set digit", "toggle"]
        @test all(b -> b.domain == "GestureProbe", own)
    end

    @testset "supertype inheritance: subtype = own + base, most-specific first" begin
        leaf = get_document_gesture_bindings(GestureProbeLeaf)
        @test length(leaf) == 4                       # only inherited base bindings
        arr = get_document_gesture_bindings(GestureProbeArray)
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
        @test isempty(get_applicable_gesture_bindings(leaf, get_document_gesture_bindings(GestureProbeLeaf)))
        leaf.selection = EmptyReferencePath()
        @test length(get_applicable_gesture_bindings(leaf, get_document_gesture_bindings(GestureProbeLeaf))) == 4
    end

    @testset "read_gesture interpreter routes through the reified table" begin
        arr = GestureProbeArray()
        arr.selection = EmptyReferencePath()
        @test read_gesture(arr, KeyPress(',')) == MarkOperation(:append)   # own
        @test read_gesture(arr, KeyPress('p')) == MarkOperation(:pos)      # inherited
    end

    @testset "@gesture_set + splice shares a set across unrelated types" begin
        # The set is a plain Vector{GestureBinding}, tagged by its own name.
        @test probe_clipboard isa Vector{GestureBinding}
        @test [b.description for b in probe_clipboard] == ["Copy", "Paste"]
        @test all(b -> b.domain == "probe_clipboard", probe_clipboard)

        alpha = get_document_gesture_bindings(ProbeAlpha)
        beta = get_document_gesture_bindings(ProbeBeta)
        # Each type = spliced set (in position) + its own rule.
        @test [b.description for b in alpha] == ["Copy", "Paste", "alpha only"]
        @test [b.description for b in beta] == ["Copy", "Paste", "beta only"]
        # The spliced bindings are the *same objects*, not copies — shared, not duplicated.
        @test alpha[1] === probe_clipboard[1]
        @test beta[1] === probe_clipboard[1]

        # Both unrelated types fire the shared gestures; each keeps its own.
        a = ProbeAlpha(); a.selection = EmptyReferencePath()
        b = ProbeBeta();  b.selection = EmptyReferencePath()
        @test read_gesture(a, KeyDown(:c, Modifiers(ctrl=true))) == MarkOperation(:copy)
        @test read_gesture(b, KeyDown(:c, Modifiers(ctrl=true))) == MarkOperation(:copy)
        @test read_gesture(a, KeyPress('a')) == MarkOperation(:alpha)
        @test read_gesture(b, KeyPress('b')) == MarkOperation(:beta)
        @test read_gesture(a, KeyPress('b')) === nothing   # beta's own rule isn't on alpha
    end

end
end

export test_gesture_binding
