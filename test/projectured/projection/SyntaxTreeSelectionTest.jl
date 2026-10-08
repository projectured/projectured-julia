# ═══════════════════════════════════════════════════════════════════════════
# test/projection/SyntaxTreeSelectionTest.jl
#
# Whole-element ("tree") selection across the JSON → Syntax → Text chain.
#
# A whole-element selection is *not* a distinct reference step: it is simply a
# path that terminates AT the element, i.e. an `EmptyReference` (`∅`). Each
# node stores only its remaining path, so the one node whose `selection` cell
# holds `∅` is the wholly-selected one; its ancestors hold a non-empty path
# routing down to it, and its descendants hold `nothing`. These tests pin:
#   * `set_selection!`/`clear_selection!` placing `∅` at the right node,
#   * forward propagation (JsonArray/JsonObject/SyntaxLeaf selected whole → `∅`
#     on the rendered text),
#   * backward recovery via `read_intent`,
#   * a nested whole-child selection surviving both directions at the syntax
#     level as `.children[i]` (terminating `∅`); the text layer can't yet render
#     a nested child as a sub-range, so it degrades to no highlight, not a crash.
# ═══════════════════════════════════════════════════════════════════════════

function test_syntax_tree_selection()
@testset "SyntaxTreeSelection" begin

# Whole-element selection == a path that ends at the element.
whole = EmptyReference()
selof(x) = getfield(x, :selection)[]

j2s = RecursiveProjection(JsonToSyntax())
s2t = RecursiveProjection(SyntaxToText())

@testset "empty path is the whole-element marker" begin
    # An empty path evaluates to the element itself.
    arr = JsonArray([JsonNumber(1), JsonNumber(2)])
    @test evaluate_reference(arr, whole) === arr
    # A character cursor (`.value{0}`) is a non-empty path — clearly distinct.
    @test !isempty(@reference(JsonNumber(42), value{0}))
    @test isempty(whole)
end

@testset "set/clear_selection! place ∅ at the target node" begin
    leaf = SyntaxLeaf("hi"; open="\"", close="\"")
    set_selection!(leaf, whole)
    @test strip_reference_types(selof(leaf)) isa EmptyReference
    clear_selection!(leaf)
    @test selof(leaf) === nothing

    # Nested: the array holds `.elements[2]` (non-empty), the child holds ∅, and
    # everything else is untouched — the tree-position invariant.
    arr = JsonArray([JsonNumber(1), JsonNumber(2)])
    nested = ConcreteReference(FieldReferenceStep("elements"),
                 ConcreteReference(ElementReferenceStep(2), whole))
    set_selection!(arr, nested)
    @test selof(arr) isa ConcreteReference          # ancestor: non-empty path
    @test !isempty(selof(arr))
    @test strip_reference_types(selof(arr[2])) isa EmptyReference   # target: ∅
    @test selof(arr[1]) === nothing                     # sibling: nothing
    clear_selection!(arr)
    @test selof(arr) === nothing
    @test selof(arr[2]) === nothing
end

@testset "forward: JsonArray whole → SyntaxNode ∅ → Text ∅" begin
    arr = JsonArray([JsonNumber(1), JsonNumber(2)])
    set_selection!(arr, whole)

    node_io = print_document(j2s, arr)
    @test strip_reference_types(node_io.output.selection) isa EmptyReference

    text_io = print_document(s2t, node_io.output)
    @test text_io.output.selection isa EmptyReference
    # The whole-element selection does not alter the rendered text.
    @test occursin("1", get_flat_string(text_io.output))
end

@testset "forward: JsonObject whole → SyntaxNode ∅ → Text ∅" begin
    obj = JsonObject("a" => JsonNumber(1))
    set_selection!(obj, whole)

    node_io = print_document(j2s, obj)
    @test strip_reference_types(node_io.output.selection) isa EmptyReference

    text_io = print_document(s2t, node_io.output)
    @test text_io.output.selection isa EmptyReference
end

@testset "forward: SyntaxLeaf whole → Text ∅" begin
    leaf = SyntaxLeaf("hi"; open="\"", close="\"")
    set_selection!(leaf, whole)
    text_io = print_document(s2t, leaf)
    @test text_io.output.selection isa EmptyReference
end

@testset "backward: ∅ at Text → Syntax → JSON (array)" begin
    arr = JsonArray([JsonNumber(1), JsonNumber(2)])
    set_selection!(arr, whole)
    node_io = print_document(j2s, arr)
    text_io = print_document(s2t, node_io.output)

    op_syntax = read_intent(s2t, text_io, ReplaceSelectionOperation(whole))
    @test op_syntax isa ReplaceSelectionOperation
    @test op_syntax.path isa EmptyReference

    op_json = read_intent(j2s, node_io, op_syntax)
    @test op_json isa ReplaceSelectionOperation
    @test strip_reference_types(op_json.path) isa EmptyReference
end

@testset "nested whole-child emits TextSpanReferenceStep at Text level" begin
    arr = JsonArray([JsonNumber(1), JsonNumber(2)])
    # Select the 2nd element as a whole: .elements[2] (terminating ∅).
    nested = ConcreteReference(FieldReferenceStep("elements"),
                 ConcreteReference(ElementReferenceStep(2), whole))
    set_selection!(arr, nested)

    # Forward: reaches the SyntaxNode as `.children[2]` (a complete path ending
    # at the child — i.e. the child wholly selected).
    node_io = print_document(j2s, arr)
    expected_child = ConcreteReference(FieldReferenceStep("children"),
                         ConcreteReference(ElementReferenceStep(2), EmptyReference()))
    @test is_reference_equal(strip_reference_types(node_io.output.selection), expected_child)

    # The text layer now emits a TextSpanReferenceStep carrying the child's
    # flat character range for the highlight box.
    text_io = print_document(s2t, node_io.output)
    text_sel = text_io.output.selection
    @test text_sel isa ConcreteReference
    @test text_sel.head isa TextSpanReferenceStep
    @test text_sel.tail isa EmptyReference
    # The range must be non-empty and cover the child's extent.
    tr = text_sel.head::TextSpanReferenceStep
    @test tr.start >= 0
    @test tr.stop > tr.start

    # Backward: `.children[2]` maps back to `.elements[2]` on the JSON array.
    op_json = read_intent(j2s, node_io, ReplaceSelectionOperation(node_io.output.selection))
    @test op_json isa ReplaceSelectionOperation
    @test is_reference_equal(strip_reference_types(op_json.path), nested)
end

end # @testset "SyntaxTreeSelection"
end # test_syntax_tree_selection
