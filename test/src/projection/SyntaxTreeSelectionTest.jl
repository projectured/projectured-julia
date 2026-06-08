# ═══════════════════════════════════════════════════════════════════════════
# test/src/projection/SyntaxTreeSelectionTest.jl
#
# Whole-element ("self") selection across the JSON → Syntax → Text chain.
#
# A whole-element selection is a reference path terminating in `SelfReference`
# (rendered `⊙`): it selects an entire node/leaf as one unit rather than a
# character cursor inside it. These tests pin the data-model + iomap plumbing:
#   * the `is_self_reference` predicate,
#   * `set_selection!`/`clear_selection!` accepting `⊙`-terminated paths,
#   * forward propagation of a whole-element selection through the printer chain
#     (JsonArray/JsonObject/SyntaxLeaf selected whole → `⊙` on the rendered text),
#   * backward recovery via `projection_read`,
#   * nested whole-child selection surviving both directions at the syntax level
#     (text-range highlighting of a nested child is deferred — it degrades to no
#     highlight rather than crashing).
# ═══════════════════════════════════════════════════════════════════════════

function test_syntax_tree_selection()
@testset "SyntaxTreeSelection" begin

# A path terminating in SelfReference == whole-element selection.
whole = ConcreteReferencePath(SelfReference())
# Walk a reference path to its terminal step.
terminal(p) = (p isa ConcreteReferencePath && p.tail isa ConcreteReferencePath) ? terminal(p.tail) : p

j2s = RecursiveProjection(JsonToSyntax())
s2t = RecursiveProjection(SyntaxToText())

@testset "is_self_reference predicate" begin
    @test is_self_reference(whole)
    @test !is_self_reference(nothing)                 # empty cursor state
    @test !is_self_reference(EmptyReferencePath())
    @test !is_self_reference(@reference value{0})     # a character cursor
    # A nested whole-child path is not itself a self-reference at the top, but
    # terminates in one.
    nested = ConcreteReferencePath(FieldReference("children"),
                 ConcreteReferencePath(ElementReference(2), whole))
    @test !is_self_reference(nested)
    @test is_self_reference(terminal(nested))
end

@testset "set/clear_selection! accept ⊙-terminated paths" begin
    leaf = SyntaxLeaf("\"", "\"", "hi")
    set_selection!(leaf, whole)
    @test is_self_reference(getfield(leaf, :selection)[])
    clear_selection!(leaf)
    @test getfield(leaf, :selection)[] === nothing

    # Nested: set_selection! routes the head step into the child and stores the
    # full ⊙-terminated path on the array.
    arr = JsonArray([JsonNumber(1), JsonNumber(2)])
    nested = ConcreteReferencePath(FieldReference("elements"),
                 ConcreteReferencePath(ElementReference(2), whole))
    set_selection!(arr, nested)
    @test is_self_reference(terminal(getfield(arr, :selection)[]))
    @test is_self_reference(getfield(arr[2], :selection)[])  # ⊙ landed on child
    clear_selection!(arr)
    @test getfield(arr, :selection)[] === nothing
    @test getfield(arr[2], :selection)[] === nothing
end

@testset "forward: JsonArray whole → SyntaxNode ⊙ → Text ⊙" begin
    arr = JsonArray([JsonNumber(1), JsonNumber(2)])
    set_selection!(arr, whole)

    node_io = projection_print(j2s, arr)
    @test is_self_reference(node_io.output.selection)

    text_io = projection_print(s2t, node_io.output)
    @test is_self_reference(text_io.output.selection)
    # The whole-element selection does not alter the rendered text.
    @test occursin("1", join(s.content for s in text_io.output))
end

@testset "forward: JsonObject whole → SyntaxNode ⊙ → Text ⊙" begin
    obj = JsonObject("a" => 1)
    set_selection!(obj, whole)

    node_io = projection_print(j2s, obj)
    @test is_self_reference(node_io.output.selection)

    text_io = projection_print(s2t, node_io.output)
    @test is_self_reference(text_io.output.selection)
end

@testset "forward: SyntaxLeaf whole → Text ⊙" begin
    leaf = SyntaxLeaf("\"", "\"", "hi")
    set_selection!(leaf, whole)
    text_io = projection_print(s2t, leaf)
    @test is_self_reference(text_io.output.selection)
end

@testset "backward: ⊙ at Text → Syntax → JSON (array)" begin
    arr = JsonArray([JsonNumber(1), JsonNumber(2)])
    set_selection!(arr, whole)
    node_io = projection_print(j2s, arr)
    text_io = projection_print(s2t, node_io.output)

    op_syntax = projection_read(s2t, text_io, ReplaceSelectionOperation(whole))
    @test op_syntax isa ReplaceSelectionOperation
    @test is_self_reference(op_syntax.path)

    op_json = projection_read(j2s, node_io, op_syntax)
    @test op_json isa ReplaceSelectionOperation
    @test is_self_reference(op_json.path)
end

@testset "nested whole-child survives Syntax level, Text degrades cleanly" begin
    arr = JsonArray([JsonNumber(1), JsonNumber(2)])
    # Select the 2nd element as a whole: .elements[2].⊙
    nested = ConcreteReferencePath(FieldReference("elements"),
                 ConcreteReferencePath(ElementReference(2), whole))
    set_selection!(arr, nested)

    # Forward: reaches the SyntaxNode as `.children[2].⊙` (terminates in ⊙ but is
    # not a top-level self-reference).
    node_io = projection_print(j2s, arr)
    nsel = node_io.output.selection
    @test nsel isa ConcreteReferencePath
    @test !is_self_reference(nsel)
    @test is_self_reference(terminal(nsel))

    # The text layer cannot yet render a nested child as a sub-range highlight
    # (deferred); it yields no selection rather than crashing.
    text_io = projection_print(s2t, node_io.output)
    @test text_io.output.selection === nothing

    # Backward: `.children[2].⊙` maps back to `.elements[2].⊙` on the JSON array.
    op_json = projection_read(j2s, node_io, ReplaceSelectionOperation(nsel))
    @test op_json isa ReplaceSelectionOperation
    @test is_self_reference(terminal(op_json.path))
end

end # @testset "SyntaxTreeSelection"
end # test_syntax_tree_selection
