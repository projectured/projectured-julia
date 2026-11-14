# One syntax node with two leaves, in two views at three places of a vertical
# layout. The viewing step of a node view prints the node with `SyntaxToText`, and
# gives the content projection the recursion of the view, which prints the view of
# each child, found by the step of the child. The carets live on the child views,
# and no content holds one. The helpers are those of `TextViewTest.jl`.

# A projection that records each document that it prints, and is `inner` in all
# else: it shows which documents a stage prints.
struct _ViewPrintRecorder <: Projection
    inner::Any
    printed::Vector{Any}
end
function ProjectionModule.print_document(p::_ViewPrintRecorder, recursion, input, ctx)
    push!(p.printed, input)
    print_document(p.inner, recursion, input, ctx)
end
ProjectionModule.read_intent(p::_ViewPrintRecorder, recursion, change::Intent, iomap) =
    read_intent(p.inner, recursion, change, iomap)
ProjectionModule.read_intent(p::_ViewPrintRecorder, iomap, payload) = read_intent(p.inner, iomap, payload)
ProjectionModule.map_reference_forward(p::_ViewPrintRecorder, iomap, reference) =
    map_reference_forward(p.inner, iomap, reference)
ProjectionModule.map_reference_backward(p::_ViewPrintRecorder, iomap, reference) =
    map_reference_backward(p.inner, iomap, reference)

function test_syntax_node_view()
@testset "SyntaxNodeView" begin

measure = FixedMeasure(10, 18, 6, 0)
font = StyleFont("Ubuntu Mono", 20)
text(s) = TextString(s, font, color_white)
first_leaf = SyntaxLeaf(text("ab"))
second_leaf = SyntaxLeaf(text("cde"))
node = SyntaxNode([first_leaf, second_leaf]; open = text("["), close = text("]"), sep = text(", "))
view_a = SyntaxNodeView(node)
view_b = SyntaxNodeView(node)
root = VerticalLayout([view_a, view_b, view_a])
printed = Any[]
stages = ChainingProjection(
    RecursiveProjection(_ViewPrintRecorder(ViewingProjection(SyntaxToText(text_folds = true)), printed)),
    RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        TextView  => TextViewToGraphicsCanvas(),
        TextBlock => TextBlockToGraphicsCanvas(; measure),
    ])))
projection = RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
    VerticalLayout => VerticalLayoutToGraphicsCanvas(),
    SyntaxNodeView => stages,
]))
iomap = print_document(projection, root)
editor = (; document = root)
press!(event) = begin
    operation = read_intent(projection, iomap, event)
    operation === nothing || evaluate_operation(editor, operation)
    operation
end
key(name; modifiers...) = KeyDown(name, ModifierKeys(; modifiers...); time = 0.0)

places = [@reference(root, children[1]), @reference(root, children[2]), @reference(root, children[3])]
in_child(i, k) = strip_reference_types(@reference(view_a, children[i].value{k}))
caret_at(place, i, k) = concat_references(places[place], in_child(i, k))
stored(document) = strip_reference_types(get_stored_selection(document))
leaf_caret(k) = strip_reference_types(@reference(view_a.children[1], value{k}))

node_steps = filter(m -> m.input isa SyntaxNodeView, _text_view_collect(iomap, ViewingIoMap))

@testset "The recursion of a view prints the view of each child" begin
    @test all(map(===, [m.input for m in node_steps], [view_a, view_b, view_a]))
    @test view_a.children[1].viewed === first_leaf && view_a.children[2].viewed === second_leaf
    @test view_a.children[1] !== view_b.children[1]
    # The stage prints the three views of the places and the views of their
    # children, and no content on its own: R gives each child print to a view.
    @test all(d -> d isa ContentView, printed)
    child_views = filter(d -> d isa SyntaxLeafView, printed)
    @test length(child_views) == 6
    @test Set(objectid.(child_views)) ==
          Set(objectid.([view_a.children[1], view_a.children[2], view_b.children[1], view_b.children[2]]))
    # The content print of each place is the print of the node with its leaves.
    @test all(m -> m.content.input === node && get_flat_string(m.output.viewed) == "[ab, cde]", node_steps)
end

@testset "The carets live on the child views, and no content holds one" begin
    replace_selection!(root, caret_at(2, 1, 0))
    replace_selection!(root, caret_at(1, 2, 1))
    @test stored(view_a) == in_child(2, 1)
    @test stored(view_a.children[2]) == leaf_caret(1)
    @test stored(view_b) == in_child(1, 0) && !is_live_selection(view_b)
    @test stored(view_b.children[1]) == leaf_caret(0)
    @test all(d -> get_stored_selection(d) === nothing, (node, first_leaf, second_leaf))
    # `[ab, ` is 5 characters, so `.children[2].value{1}` is the caret 6 of the text.
    @test [stored(m.output) for m in node_steps] ==
          [make_flat_caret_reference(6), make_flat_caret_reference(1), make_flat_caret_reference(6)]
end

@testset "A key moves the caret of the view" begin
    @test press!(key(:right)) isa ReplaceSelectionOperation
    @test stored(view_a) == in_child(2, 2)
    @test stored(view_b) == in_child(1, 0)
end

@testset "A typed character edits the leaf and moves the caret of the view" begin
    @test press!(KeyPress('X', ModifierKeys(); time = 0.0)) isa ReplaceStringRangeOperation
    @test second_leaf.value.content == "cdXe"
    @test stored(view_a) == in_child(2, 3)
    @test all(d -> get_stored_selection(d) === nothing, (node, first_leaf, second_leaf))
    @test all(m -> get_flat_string(m.output.viewed) == "[ab, cdXe]", node_steps)
end

@testset "The keys of the tree act on the caret of the view" begin
    @test press!(key(:space; ctrl = true)) isa ReplaceSelectionOperation
    @test stored(view_a) == strip_reference_types(@reference(view_a, children[2]))
    @test press!(key(:up; alt = true)) isa ReplaceSelectionOperation
    @test stored(view_a) == EmptyReference()
    @test stored(view_b) == in_child(1, 0)
end

@testset "A click puts the caret of the view that it hits" begin
    place_y = Int(iomap.output.elements[2].y)
    # x = 25 is between the caret 2 and the caret 3 of `[ab, cdXe]`: `.children[1].value{1}`.
    @test press!(MouseClick(:left, 25, place_y + 5; time = 0.0)) isa ReplaceSelectionOperation
    @test stored(view_b) == in_child(1, 1) && is_live_selection(view_b)
end

@testset "A child keeps its view when a child is added before it" begin
    first_view = view_a.children[1]
    insert!(node.children, 1, SyntaxLeaf(text("z")))
    @test view_a.children[2] === first_view
    @test view_a.children[1].viewed.value.content == "z"
    @test all(m -> get_flat_string(m.output.viewed) == "[z, ab, cdXe]",
              filter(m -> m.input isa SyntaxNodeView, _text_view_collect(iomap, ViewingIoMap)))
end

@testset "A fold is state of a view" begin
    folded_leaf = SyntaxLeaf(text("ab"))
    tree = SyntaxNode([folded_leaf, SyntaxLeaf(text("cde"))];
                      open = "[\n", close = "\n]", sep = ",\n", indentation = 1)
    fold_a = SyntaxNodeView(tree)
    fold_b = SyntaxNodeView(tree)
    layout = VerticalLayout([fold_a, fold_b, fold_a])
    folding = RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        VerticalLayout => VerticalLayoutToGraphicsCanvas(),
        SyntaxNodeView => ChainingProjection(
            RecursiveProjection(ViewingProjection(SyntaxToText(text_folds = true))),
            TextFolding(),
            RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
                TextView  => TextViewToGraphicsCanvas(),
                TextBlock => TextBlockToGraphicsCanvas(; measure),
            ]))),
    ]))
    folded_iomap = print_document(folding, layout)
    folded_editor = (; document = layout)
    read!(event) = begin
        operation = read_intent(folding, folded_iomap, event)
        operation === nothing || evaluate_operation(folded_editor, operation)
        operation
    end
    drawn() = [_text_view_texts(m.output) for m in _text_view_collect(folded_iomap, TextViewToGraphicsCanvasIoMap)]
    open_text = ["[", "ab", ",", "cde", "]"]
    closed_text = ["[", "…", "]"]
    fold_places = [@reference(layout, children[1]), @reference(layout, children[2]), @reference(layout, children[3])]

    @test drawn() == [open_text, open_text, open_text]
    evaluate_operation(folded_editor, ToggleFoldOperation(concat_references(fold_places[1], EmptyReference())))
    @test fold_a.collapsed && !fold_b.collapsed && !tree.collapsed
    @test drawn() == [closed_text, open_text, closed_text]

    # Ctrl+. folds the innermost fold around the caret of the view of the place.
    replace_selection!(layout, concat_references(fold_places[2],
                                                 strip_reference_types(@reference(fold_b, children[1].value{1}))))
    @test read!(key(:period; ctrl = true)) isa ToggleFoldOperation
    @test fold_a.collapsed && fold_b.collapsed && !tree.collapsed
    @test drawn() == [closed_text, closed_text, closed_text]

    # A click on the placeholder of a closed fold opens the fold of that view. The
    # fixed measure puts `…` from x = 10 to x = 20, and the vertical layout hits it
    # with the width of the font, about 7 pixels, so x = 16 is on it and nearest the
    # boundary after it.
    @test read!(MouseClick(:left, 16, Int(folded_iomap.output.elements[1].y) + 5; time = 0.0)) isa ToggleFoldOperation
    @test !fold_a.collapsed && fold_b.collapsed && !tree.collapsed
    @test drawn() == [open_text, closed_text, open_text]
end

@testset "A caret move recomputes only the places of its view" begin
    replace_selection!(root, caret_at(1, 3, 1))
    drawn = _text_view_collect(iomap, TextViewToGraphicsCanvasIoMap)
    cells = [_text_view_cells(m.output) for m in drawn]
    replace_selection!(root, caret_at(1, 3, 2))
    stale = _text_view_stale_counts(cells)
    @test stale[1] > 0 && stale[2] == 0 && stale[3] == stale[1]
end

end
end
