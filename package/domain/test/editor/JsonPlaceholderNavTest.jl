# ═══════════════════════════════════════════════════════════════════════════
# test/editor/JsonPlaceholderNavTest.jl
#
# Pins the JSON authoring-placeholder behaviour across the full graphics pipeline:
#   * Ctrl+Space toggles a text (character) cursor ⇄ a whole-element (structural)
#     selection, both ways;
#   * the empty JsonInsertion buffer is reachable by navigation (so it can be
#     typed into), and Ctrl+Space on it selects the whole insertion and back;
#   * a JsonInsertion / JsonNothing value is navigable and structurally selectable
#     in context.
#
# The position / tree completeness sweeps (umbrella) already assert reachability of
# every enumerated caret/tree selection; this file pins the specific gestures and
# the JsonNothing case (which is not present in `json_example`).
# ═══════════════════════════════════════════════════════════════════════════

_jpn_str(p) = string(strip_reference_types(p))
const _JPN_CS       = KeyDown(:space, Modifiers(ctrl=true))
const _JPN_CTRL_END = KeyDown(:end, Modifiers(ctrl=true))

function test_json_placeholder_navigation()
@testset "json placeholder nav & Ctrl+Space" begin
    proj = make_json_projection_example()

    @testset "Ctrl+Space toggles text ⇄ structural" begin
        doc = make_json_document_example()
        clear_selection!(doc); io = print_document(proj, doc)
        seed = read_intent(proj, io, _JPN_CTRL_END)
        @test seed isa ReplaceSelectionOperation                       # a text cursor
        set_selection!(doc, seed.path); io = print_document(proj, doc)
        s = read_intent(proj, io, _JPN_CS)                             # → structural
        @test s isa ReplaceSelectionOperation
        @test strip_reference_types(s.path) isa EmptyReferencePath     # ∅ (whole root)
        set_selection!(doc, s.path); io = print_document(proj, doc)
        t = read_intent(proj, io, _JPN_CS)                             # → text
        @test t isa ReplaceSelectionOperation
        @test !(strip_reference_types(t.path) isa EmptyReferencePath)  # a cursor again
    end

    @testset "empty insertion buffer: navigable + Ctrl+Space selects the whole insertion" begin
        doc = make_json_document_example()
        buf = only(filter(s -> occursin("entries[8].value.value{0}", _jpn_str(s)),
                          collect_position_selections(doc)))
        # The empty buffer caret is reachable by navigation (so it can be typed into).
        @test _jpn_str(buf) in explore_position_selections(doc, proj).visited
        # Ctrl+Space on it selects the whole JsonInsertion, and toggles back to it.
        clear_selection!(doc); set_selection!(doc, buf); io = print_document(proj, doc)
        sel = read_intent(proj, io, _JPN_CS)
        @test sel isa ReplaceSelectionOperation
        @test _jpn_str(sel.path) == ".entries[8].value"
        set_selection!(doc, sel.path); io = print_document(proj, doc)
        back = read_intent(proj, io, _JPN_CS)
        @test back isa ReplaceSelectionOperation
        @test _jpn_str(back.path) == ".entries[8].value.value{0}"
    end

    @testset "JsonInsertion is structurally (tree) selectable in context" begin
        doc = make_json_document_example()
        @test ".entries[8].value" in explore_tree_selections(doc, proj).visited
    end

    @testset "JsonNothing is navigable + structurally selectable in context" begin
        doc = JsonObject("x" => JsonNothing())
        pr = make_json_projection_example()
        # Every enumerated character position stays reachable (the placeholder does
        # not strand navigation).
        enump = Set(_jpn_str(s) for s in collect_position_selections(doc))
        @test issubset(enump, explore_position_selections(doc, pr).visited)
        # The JsonNothing value itself is a reachable whole-element (tree) selection.
        @test ".entries[1].value" in explore_tree_selections(doc, pr).visited
    end

    @testset "JsonNothing label is char-navigable via ProjectionReference steps" begin
        # A bare `empty json` placeholder: the cursor steps through its display label
        # (each position a projection-introduced caret), like every literal leaf.
        reached = explore_position_selections(JsonNothing(), make_json_projection_example()).visited
        @test length(reached) == length("empty json") + 1          # 11 caret positions
        @test all(occursin("SyntaxLeaf.value", s) for s in reached) # all on the introduced label
    end
end
end
