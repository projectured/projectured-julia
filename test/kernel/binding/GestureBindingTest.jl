# Reified gesture bindings: the @gestures macro, supertype inheritance, the
# instance tables, applicability, the claim gate, and the read_gesture interpreter.
# The patterns and their descriptions are the event layer's, in EventModuleTest.
# The JSON tables of read_gesture are tested through the real projection pipeline
# in JsonToSyntaxTest (test_json_to_syntax_reader).

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

# A table that mixes every naming case: a named gesture rule, an unnamed one, a rule
# that reads the event, and two rules with no gesture at all.
@document struct CommandProbe
    value::Int = 0
end

@gestures CommandProbe begin
    when(sel !== nothing)
    KeyPress('x')                  => "cut it"        => MarkOperation(:cut)
    KeyPress('y')                                     => MarkOperation(:unnamed)
    when(KeyPress(c), isdigit(c))  => "set digit"     => MarkOperation(Symbol(c))
    nothing                        => "sort the keys" => MarkOperation(:sort)
    nothing                        => "reverse"       => MarkOperation(:reverse)
end

# A document whose bare name is the concrete `DC` spelling: its table sits on a
# concrete parameterization of the cell layout, not on a UnionAll.
@document [DC] struct GestureProbeValue
    value::Int = 0
end

@gestures GestureProbeValue begin
    KeyPress('v')                  => "value"         => MarkOperation(:value)
end

# A document whose bare name is the plain mutable struct: it holds its selection as a
# value, not in a cell.
@document [M, C] struct GestureProbeNative
    value::Int = 0
end

@gestures GestureProbeNative begin
    KeyPress('m')                  => "native"        => MarkOperation(:native)
end

# A document whose bare name is the immutable native struct.
@document [I, C] struct GestureProbeImmutable
    value::Int = 0
end

@gestures GestureProbeImmutable begin
    KeyPress('i')                  => "immutable"     => MarkOperation(:immutable)
end

# A plain rule and a rule that claims its key from the output layers.
@document struct ClaimProbe
    value::Int = 0
end

@gestures ClaimProbe begin
    KeyPress('<')                  => "plain"         => MarkOperation(:plain)
    override(KeyPress('>'))        => "claims"        => MarkOperation(:claims)
end

# Two rules of one key: the first makes no operation while `value` is 0.
@document struct DeclineProbe
    value::Int = 0
end

@gestures DeclineProbe begin
    KeyPress('d') => "first"  => (doc.value > 0 ? MarkOperation(:first) : nothing)
    KeyPress('d') => "second" => MarkOperation(:second)
end

# A document that carries a table of its own beside the table of its type.
@document struct InstanceProbe
    bindings::Any = GestureBinding[]
end
GestureBindingModule.get_instance_gesture_bindings(probe::InstanceProbe) =
    probe.bindings

@gestures InstanceProbe begin
    KeyPress('i')                  => "type rule"     => MarkOperation(:type)
end

# A target that is no document: its table is an instance table.
struct GestureTargetProbe
    bindings::Vector{GestureBinding}
end
GestureBindingModule.get_instance_gesture_bindings(target::GestureTargetProbe) =
    target.bindings

# One rule of `key` that makes `MarkOperation(tag)`, and stands where a selection is.
make_probe_binding(key, tag) =
    GestureBinding(KeyPressPattern(key), (doc, event) -> MarkOperation(tag);
                   applicable = (doc, sel) -> sel !== nothing,
                   description = string(tag), domain = "probe")

# A tiny operation stand-in so the binding RHS produces something identifiable.
struct MarkOperation
    tag::Symbol
end

function test_gesture_binding()
@testset "GestureBinding" begin

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

    @testset "read_bound_gesture fires the matching, applicable binding" begin
        leaf = GestureProbeLeaf()
        leaf.selection = EmptyReference()
        @test read_bound_gesture(leaf, KeyPress('n'; time = 0.0)) == MarkOperation(:neg)
        @test read_bound_gesture(leaf, KeyPress('7'; time = 0.0)) == MarkOperation(Symbol('7'))
        @test read_bound_gesture(leaf, KeyDown(:period, ModifierKeys(ctrl=true); time = 0.0)) == MarkOperation(:toggle)
        # An unbound gesture yields nothing.
        @test read_bound_gesture(leaf, KeyPress('z'; time = 0.0)) === nothing
    end

    @testset "applicable precondition gates firing (and greys help rows)" begin
        leaf = GestureProbeLeaf()           # selection === nothing → precondition false
        @test read_bound_gesture(leaf, KeyPress('n'; time = 0.0)) === nothing
        @test isempty(get_applicable_gesture_bindings(leaf, get_document_gesture_bindings(GestureProbeLeaf)))
        leaf.selection = EmptyReference()
        @test length(get_applicable_gesture_bindings(leaf, get_document_gesture_bindings(GestureProbeLeaf))) == 4
    end

    @testset "read_gesture interpreter routes through the reified table" begin
        arr = GestureProbeArray()
        arr.selection = EmptyReference()
        @test read_gesture(arr, KeyPress(','; time = 0.0)) == MarkOperation(:append)   # own
        @test read_gesture(arr, KeyPress('p'; time = 0.0)) == MarkOperation(:pos)      # inherited
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
        a = ProbeAlpha(); a.selection = EmptyReference()
        b = ProbeBeta();  b.selection = EmptyReference()
        @test read_gesture(a, KeyDown(:c, ModifierKeys(ctrl=true); time = 0.0)) == MarkOperation(:copy)
        @test read_gesture(b, KeyDown(:c, ModifierKeys(ctrl=true); time = 0.0)) == MarkOperation(:copy)
        @test read_gesture(a, KeyPress('a'; time = 0.0)) == MarkOperation(:alpha)
        @test read_gesture(b, KeyPress('b'; time = 0.0)) == MarkOperation(:beta)
        @test read_gesture(a, KeyPress('b'; time = 0.0)) === nothing   # beta's own rule isn't on alpha
    end

    @testset "a `nothing` rule is a binding with no gesture" begin
        own = get_document_gesture_bindings_own(CommandProbe)
        @test length(own) == 5
        @test [b.pattern === nothing for b in own] == [false, false, false, true, true]
        # The description of a rule with no gesture is its name, so it reads as itself
        # in a listing.
        @test own[4].description == "sort the keys"
    end

    @testset "a name is given only to a rule that can be run by one" begin
        own = get_document_gesture_bindings_own(CommandProbe)
        @test [b.name for b in own] ==
              ["cut it", nothing, nothing, "sort the keys", "reverse"]
        # own[2] wrote no description, so its description is the gesture rendering.
        @test own[2].description == "y"
        # own[3] reads the event through its bound `c`, so a name could not run it.
        @test own[3].description == "set digit"
    end

    @testset "no event fires a rule with no gesture" begin
        probe = CommandProbe()
        probe.selection = EmptyReference()
        @test read_bound_gesture(probe, KeyPress('x'; time = 0.0)) == MarkOperation(:cut)
        # An unmatched event walks the WHOLE table, past both `nothing` patterns. The
        # walk must skip them rather than ask them to match.
        @test read_bound_gesture(probe, KeyPress('z'; time = 0.0)) === nothing
        @test read_bound_gesture(probe, KeyDown(:return, ModifierKeys(); time = 0.0)) === nothing
    end

    @testset "fire_named_gesture_binding runs a binding by its name" begin
        probe = CommandProbe()
        probe.selection = EmptyReference()
        own = get_document_gesture_bindings(CommandProbe)
        sel = probe.selection
        @test fire_named_gesture_binding(own, probe, "sort the keys"; selection = sel) == MarkOperation(:sort)
        @test fire_named_gesture_binding(own, probe, "reverse"; selection = sel) == MarkOperation(:reverse)
        # A gesture rule that carries a name runs by that name too.
        @test fire_named_gesture_binding(own, probe, "cut it"; selection = sel) == MarkOperation(:cut)
        # An unknown name, and a description that is not a name, run nothing.
        @test fire_named_gesture_binding(own, probe, "no such command"; selection = sel) === nothing
        @test fire_named_gesture_binding(own, probe, "set digit"; selection = sel) === nothing
        @test fire_named_gesture_binding(own, probe, "y"; selection = sel) === nothing
    end

    @testset "the precondition gates a named run as it gates a gesture" begin
        probe = CommandProbe()                # selection === nothing → precondition false
        own = get_document_gesture_bindings(CommandProbe)
        @test fire_named_gesture_binding(own, probe, "sort the keys"; selection = probe.selection) === nothing
    end

    # Collection is the same table, asked a different question. Every row a listing
    # shows comes from here, so it cannot drift from what fires.
    @testset "CollectIntents answers with the whole table, not the first match" begin
        probe = CommandProbe()
        probe.selection = EmptyReference()
        own = get_document_gesture_bindings(CommandProbe)
        collected = fire_gesture_bindings(own, probe, CollectIntents(); selection = probe.selection)
        @test collected isa CollectedIntentsOperation
        # One intent per binding — including the ones that cannot run.
        @test length(collected.intents) == length(own)
        @test [i.description for i in collected.intents] ==
              ["cut it", "y", "set digit", "sort the keys", "reverse"]
        @test all(i -> i.domain == "CommandProbe", collected.intents)

        ops = [i.operation for i in collected.intents]
        # A rule that can run carries its built operation.
        @test ops[1] == MarkOperation(:cut)
        @test ops[4] == MarkOperation(:sort)
        @test ops[5] == MarkOperation(:reverse)
        # A rule with no description has no name, so it cannot be run from a list —
        # it still gets a row saying its key exists.
        @test ops[2] === nothing
        # A rule that reads the event has no meaning without the keystroke.
        @test ops[3] === nothing
        # The gesture is the pattern, so a listing can render the key.
        @test collected.intents[4].gesture === nothing        # the command has none
        @test collected.intents[1].gesture !== nothing
    end

    @testset "a failed precondition greys a row instead of dropping it" begin
        probe = CommandProbe()                # selection === nothing → precondition false
        own = get_document_gesture_bindings(CommandProbe)
        collected = fire_gesture_bindings(own, probe, CollectIntents(); selection = probe.selection)
        @test length(collected.intents) == length(own)
        @test all(i -> i.operation === nothing, collected.intents)
    end

    @testset "read_bound_gesture routes the payload to the same answer" begin
        probe = CommandProbe()
        probe.selection = EmptyReference()
        collected = read_bound_gesture(probe, CollectIntents())
        @test collected isa CollectedIntentsOperation
        @test length(collected.intents) == length(get_document_gesture_bindings(CommandProbe))
    end

    @testset "@gestures rejects a nameless or overriding `nothing` rule" begin
        nameless = try
            @eval @gestures CommandProbe begin
                nothing => MarkOperation(:nameless)
            end
            nothing
        catch e
            e
        end
        @test nameless !== nothing
        @test occursin("needs a description", sprint(showerror, nameless))

        overriding = try
            @eval @gestures CommandProbe begin
                override(nothing) => "claims nothing" => MarkOperation(:bad)
            end
            nothing
        catch e
            e
        end
        @test overriding !== nothing
        @test occursin("override", sprint(showerror, overriding))
    end

    @testset "a block takes one precondition" begin
        second = :(@gestures CommandProbe begin
            when(sel !== nothing)
            KeyPress('x') => "cut it" => MarkOperation(:cut)
            when(sel === nothing)
            KeyPress('y') => "other" => MarkOperation(:other)
        end)
        @test_throws "a block takes one `when(expr)`" macroexpand(@__MODULE__, second)
    end

    @testset "a table is built once" begin
        @test get_document_gesture_bindings_own(GestureProbe) ===
              get_document_gesture_bindings_own(GestureProbe)
    end

    @testset "a table on a concrete document type fires" begin
        value = GestureProbeValue()
        @test read_gesture(value, KeyPress('v'; time = 0.0)) == MarkOperation(:value)
        @test [b.description for b in get_document_gesture_bindings(value)] == ["value"]
    end

    @testset "a table on a native document reads its selection" begin
        native = GestureProbeNative()
        @test read_gesture(native, KeyPress('m'; time = 0.0)) == MarkOperation(:native)
        @test length(get_applicable_gesture_bindings(native,
                         get_document_gesture_bindings(native))) == 1
    end

    @testset "a table on an immutable native document fires" begin
        value = GestureProbeImmutable()
        @test !ismutable(value)
        @test read_gesture(value, KeyPress('i'; time = 0.0)) == MarkOperation(:immutable)
    end

    @testset "a claimed event fires only a rule that overrides" begin
        probe = ClaimProbe()
        claim = MarkOperation(:output)
        @test [b.override for b in get_document_gesture_bindings_own(ClaimProbe)] ==
              [false, true]
        @test read_gesture(probe, KeyPress('<'; time = 0.0)) == MarkOperation(:plain)
        @test read_gesture(probe, KeyPress('<'; time = 0.0); claimed = claim) === nothing
        @test read_gesture(probe, KeyPress('>'; time = 0.0); claimed = claim) ==
              MarkOperation(:claims)
        @test read_gesture(probe, KeyPress('>'; time = 0.0)) == MarkOperation(:claims)
    end

    @testset "a rule that makes no operation lets a later rule fire" begin
        @test read_gesture(DeclineProbe(), KeyPress('d'; time = 0.0)) ==
              MarkOperation(:second)
        @test read_gesture(DeclineProbe(value = 1), KeyPress('d'; time = 0.0)) ==
              MarkOperation(:first)
    end

    @testset "the table of an instance goes before the table of its type" begin
        @test isempty(get_instance_gesture_bindings(GestureProbeLeaf()))
        probe = InstanceProbe()
        probe.selection = EmptyReference()
        @test read_gesture(probe, KeyPress('i'; time = 0.0)) == MarkOperation(:type)
        probe.bindings = [make_probe_binding('i', :instance),
                          make_probe_binding('j', :extra)]
        @test read_gesture(probe, KeyPress('i'; time = 0.0)) == MarkOperation(:instance)
        @test read_gesture(probe, KeyPress('j'; time = 0.0)) == MarkOperation(:extra)
        collected = read_bound_gesture(probe, CollectIntents())
        @test [i.description for i in collected.intents] ==
              ["instance", "extra", "type rule"]
    end

    @testset "the three-argument read takes the selection that it is given" begin
        probe = CommandProbe()                # its own selection is nothing
        @test read_bound_gesture(probe, KeyPress('x'; time = 0.0)) === nothing
        @test read_bound_gesture(probe, KeyPress('x'; time = 0.0), EmptyReference()) ==
              MarkOperation(:cut)
        probe.selection = EmptyReference()
        @test read_bound_gesture(probe, KeyPress('x'; time = 0.0), nothing) === nothing

        # A target that is no document has no selection of its own.
        target = GestureTargetProbe([make_probe_binding('t', :target)])
        @test read_bound_gesture(target, KeyPress('t'; time = 0.0), EmptyReference()) ==
              MarkOperation(:target)
        @test read_bound_gesture(target, KeyPress('t'; time = 0.0), nothing) === nothing
        @test read_bound_gesture(target, KeyPress('u'; time = 0.0), EmptyReference()) ===
              nothing
    end

end
end

export test_gesture_binding
