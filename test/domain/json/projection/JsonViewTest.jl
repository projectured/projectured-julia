# One JSON string in two views at three places of a vertical layout, printed by one
# recursion over the views at each stage: JSON to syntax, syntax to text, and text
# to graphics. Each view keeps a caret of its own, the places of one view share its
# caret, and no content holds a caret. The helpers are those of the platform tests.

const _json_view_collect = ProjecturedPlatformTest._text_view_collect
const _json_view_caret_x = ProjecturedPlatformTest._text_view_caret_x
const _json_view_is_caret_live = ProjecturedPlatformTest._text_view_is_caret_live

function test_json_string_view()
@testset "JsonStringView" begin

measure = FixedMeasure(10, 18, 6, 0)
json_string = JsonString("abcd")
view_a = JsonStringView(json_string)
view_b = JsonStringView(json_string)
root = VerticalLayout([view_a, view_b, view_a])
stages = ChainingProjection(
    RecursiveProjection(ViewingProjection(JsonToSyntax())),
    RecursiveProjection(ViewingProjection(SyntaxToText())),
    RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        TextView  => TextViewToGraphicsCanvas(),
        TextBlock => TextBlockToGraphicsCanvas(; measure),
    ])))
projection = RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
    VerticalLayout => VerticalLayoutToGraphicsCanvas(),
    JsonStringView => stages,
]))
iomap = print_document(projection, root)
editor = (; document = root)
press!(event) = begin
    operation = read_intent(projection, iomap, event)
    operation === nothing || evaluate_operation(editor, operation)
    operation
end

places = [@reference(root, children[1]), @reference(root, children[2]), @reference(root, children[3])]
value_caret(k) = strip_reference_types(@reference(view_a, value{k}))
caret_at(place, k) = concat_references(places[place], value_caret(k))
stored(document) = strip_reference_types(get_stored_selection(document))

steps = _json_view_collect(iomap, ViewingIoMap)
json_steps = filter(m -> m.input isa JsonStringView, steps)
drawn = _json_view_collect(iomap, TextViewToGraphicsCanvasIoMap)

@testset "Each place prints its view through the three stages" begin
    @test all(map(===, [m.input for m in json_steps], [view_a, view_b, view_a]))
    # JSON to syntax: the view of the leaf that the string printed to.
    @test all(m -> m.output isa SyntaxLeafView && m.output.viewed === m.content.output, json_steps)
    # Syntax to text: the view of the text of that leaf.
    leaf_steps = filter(m -> m.input isa SyntaxLeafView, steps)
    @test all(map(===, [m.input for m in leaf_steps], [m.output for m in json_steps]))
    @test all(m -> m.output isa TextView && get_flat_string(m.output.viewed) == "\"abcd\"", leaf_steps)
    @test length(drawn) == 3
end

@testset "Two views keep two carets, and no content holds one" begin
    replace_selection!(root, caret_at(2, 3))
    replace_selection!(root, caret_at(1, 1))
    @test stored(view_a) == value_caret(1) && is_live_selection(view_a)
    @test stored(view_b) == value_caret(3) && !is_live_selection(view_b)
    @test get_stored_selection(json_string) === nothing
    @test all(m -> get_stored_selection(m.content.output) === nothing, json_steps)
    # The open quote is one character: `.value{1}` is drawn at 20 and `.value{3}` at 40.
    @test _json_view_caret_x.(drawn) == [20, 40, 20]
end

@testset "Only the place on the path from the root draws a live caret" begin
    # The path goes through the first place. The view of each stage is live there
    # and dormant at the third place, which shows the same view.
    @test _json_view_is_caret_live.(drawn) == [true, false, false]
    @test is_live_selection.([m.output for m in json_steps]) == [true, false, false]
    replace_selection!(root, caret_at(3, 1))
    @test _json_view_is_caret_live.(drawn) == [false, false, true]
    @test is_live_selection.([m.output for m in json_steps]) == [false, false, true]
    @test _json_view_caret_x.(drawn) == [20, 40, 20]
    replace_selection!(root, caret_at(1, 1))
end

@testset "A key moves the caret of the view" begin
    @test press!(KeyDown(:right, ModifierKeys(); time = 0.0)) isa ReplaceSelectionOperation
    @test stored(view_a) == value_caret(2)
    @test stored(view_b) == value_caret(3)
    @test _json_view_caret_x.(drawn) == [30, 40, 30]
end

@testset "A typed character edits the string and moves the caret of the view" begin
    @test press!(KeyPress('X', ModifierKeys(); time = 0.0)) isa ReplaceStringRangeOperation
    @test json_string.value == "abXcd"
    @test stored(view_a) == value_caret(3)
    @test stored(view_b) == value_caret(3)
    @test get_stored_selection(json_string) === nothing
    @test all(m -> get_flat_string(m.content.output) == "\"abXcd\"",
              filter(m -> m.input isa SyntaxLeafView, _json_view_collect(iomap, ViewingIoMap)))
end

@testset "A click puts the caret of the view that it hits" begin
    place_y = Int(iomap.output.elements[1].elements[2].y)
    # x = 25 is between the caret 2 and the caret 3 of `"abXcd"`: `.value{1}`.
    @test press!(MouseClick(:left, 25, place_y + 5; time = 0.0)) isa ReplaceSelectionOperation
    @test stored(view_b) == value_caret(1) && is_live_selection(view_b)
    @test stored(view_a) == value_caret(3) && !is_live_selection(view_a)
end

@testset "A string with no view prints as content" begin
    output = print_document(RecursiveProjection(ViewingProjection(JsonToSyntax())), json_string).output
    @test output isa SyntaxLeaf
end

@testset "The view types of JSON take the declaration" begin
    leaves = [(JsonNullView, JsonNull()), (JsonBoolView, JsonBool(true)), (JsonNumberView, JsonNumber(1)),
              (JsonStringView, JsonString("a"))]
    for (view_type, content) in leaves
        @test fieldnames(view_type)[1] === :viewed && !(:value in fieldnames(view_type))
        @test make_content_view(content) isa view_type && make_content_view(content).viewed === content
    end
    array = JsonArray([JsonString("a")])
    array_view = JsonArrayView(array)
    @test fieldnames(JsonArrayView)[1:3] == (:viewed, :elements, :collapsed)
    @test array_view.elements isa CellVectorView && array_view.elements.viewed === array.elements
    @test make_content_view(array) isa JsonArrayView
    given = CellVector(Any[nothing])
    @test make_content_view(array, given).elements.given === given
    @test array_view.collapsed == false
end

end
end

# One JSON array with a string, a number and an array, in two views at three
# places. The step of an array gives the view of its node over the views that the
# steps of its elements give; a key table of a view edits the content through the
# view; a fold of an array is a fold of a view.
function test_json_array_view()
@testset "JsonArrayView" begin

measure = FixedMeasure(10, 18, 6, 0)
nested = JsonArray([JsonString("x")])
array = JsonArray([JsonString("ab"), JsonNumber(42), nested])
view_a = JsonArrayView(array)
view_b = JsonArrayView(array)
root = VerticalLayout([view_a, view_b, view_a])
stages = ChainingProjection(
    RecursiveProjection(ViewingProjection(JsonToSyntax())),
    RecursiveProjection(ViewingProjection(SyntaxToText(text_folds = true))),
    TextFolding(),
    RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        TextView  => TextViewToGraphicsCanvas(),
        TextBlock => TextBlockToGraphicsCanvas(; measure),
    ])))
projection = RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
    VerticalLayout => VerticalLayoutToGraphicsCanvas(),
    JsonArrayView  => stages,
]))
iomap = print_document(projection, root)
editor = (; document = root)
press!(event) = begin
    operation = read_intent(projection, iomap, event)
    operation === nothing || evaluate_operation(editor, operation)
    operation
end
typed(character) = KeyPress(character, ModifierKeys(); time = 0.0)

places = [@reference(root, children[1]), @reference(root, children[2]), @reference(root, children[3])]
at(place, path) = concat_references(places[place], strip_reference_types(path))
stored(document) = strip_reference_types(get_stored_selection(document))
plain(path) = strip_reference_types(path)
# The text that each place draws.
texts() = [get_flat_string(m.input.viewed) for m in _json_view_collect(iomap, TextViewToGraphicsCanvasIoMap)]
open_text = "[\n  \"ab\",\n  42,\n  [\n    \"x\"\n  ]\n]"

@testset "Each element has a view of its kind" begin
    @test view_a.elements[1] isa JsonStringView && view_a.elements[2] isa JsonNumberView
    @test view_a.elements[3] isa JsonArrayView && view_a.elements[3].elements[1] isa JsonStringView
    @test all(i -> view_a.elements[i].viewed === array.elements[i], 1:3)
    @test all(i -> view_a.elements[i] !== view_b.elements[i], 1:3)
    @test texts() == [open_text, open_text, open_text]
end

@testset "The step of an array gives the view of its node over the views of its elements" begin
    steps = _json_view_collect(iomap, ViewingIoMap)
    step = first(filter(m -> m.input === view_a, steps))
    @test step.output isa SyntaxNodeView && step.output.viewed === step.content.output
    children = collect(step.output.children)
    @test children[1] isa SyntaxLeafView && children[2] isa SyntaxLeafView && children[3] isa SyntaxNodeView
    @test all(i -> children[i].viewed === step.output.viewed.children[i], 1:3)
    # The view of the node of the nested array is the output of the step of the view
    # of that array, not a new view: it takes the fold of that view.
    view_a.elements[3].collapsed = true
    @test children[3].collapsed
    view_a.elements[3].collapsed = false
    @test !children[3].collapsed
end

@testset "The carets live on the views of the elements, and no content holds one" begin
    replace_selection!(root, at(2, @reference(view_b, elements[3].elements[1].value{0})))
    replace_selection!(root, at(1, @reference(view_a, elements[1].value{1})))
    @test stored(view_a.elements[1]) == plain(@reference(view_a.elements[1], value{1}))
    @test stored(view_b.elements[3]) == plain(@reference(view_b.elements[3], elements[1].value{0}))
    @test !is_live_selection(view_b)
    @test all(d -> get_stored_selection(d) === nothing, (array, nested, array.elements[1], nested.elements[1]))
end

@testset "A typed character edits the element through its view" begin
    @test press!(typed('X')) isa ReplaceStringRangeOperation
    @test array.elements[1].value == "aXb"
    @test stored(view_a) == plain(@reference(view_a, elements[1].value{2}))
    @test all(t -> occursin("\"aXb\"", t), texts())
end

@testset "A comma appends an element to the innermost array, through the view" begin
    replace_selection!(root, at(1, @reference(view_a, elements[3].elements[1])))
    @test press!(typed(',')) isa CompoundOperation
    @test length(nested.elements) == 2 && nested.elements[2] isa JsonInsertion
    @test length(array.elements) == 3
    @test stored(view_a) == plain(@reference(view_a, elements[3].elements[2]))
    @test get_stored_selection(nested.elements[2]) === nothing
    @test get_stored_selection(nested) === nothing
end

@testset "A key replaces an element with one of another kind, through the view" begin
    replace_selection!(root, at(1, @reference(view_a, elements[2])))
    @test press!(typed('n')) isa CompoundOperation
    @test array.elements[2] isa JsonNull
    @test view_a.elements[2] isa JsonNullView && view_b.elements[2] isa JsonNullView
    @test get_stored_selection(array.elements[2]) === nothing
    @test all(t -> occursin("\n  null,\n", t), texts())
end

@testset "A fold of an array is a fold of a view" begin
    folded_text(t) = !occursin("\"x\"", t)
    evaluate_operation(editor, ToggleFoldOperation(at(1, @reference(view_a, elements[3]))))
    @test view_a.elements[3].collapsed && !view_b.elements[3].collapsed
    @test folded_text.(texts()) == [true, false, true]
    # Ctrl+. folds the innermost fold around the caret of the view of the place.
    replace_selection!(root, at(2, @reference(view_b, elements[3].elements[1].value{0})))
    @test press!(KeyDown(:period, ModifierKeys(ctrl = true); time = 0.0)) isa ToggleFoldOperation
    @test view_b.elements[3].collapsed
    @test folded_text.(texts()) == [true, true, true]
end

end
end

# The four stages that print a view of a JSON array at a place, as the editor
# chains them.
_make_json_view_stages(measure) = ChainingProjection(
    RecursiveProjection(ViewingProjection(JsonToSyntax())),
    RecursiveProjection(ViewingProjection(SyntaxToText(text_folds = true))),
    TextFolding(),
    RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        TextView  => TextViewToGraphicsCanvas(),
        TextBlock => TextBlockToGraphicsCanvas(; measure),
    ])))

# One JSON array in two views at four places: each view is at a place of the whole
# view and at a place of the view of its nested array. No type stands for a place:
# the layout holds the view, or the view of the part. The places of one view share
# its folds and its caret, and only the place on the path from the root draws the
# caret as a live one.
function test_json_view_places()
@testset "The places of JSON views" begin

measure = FixedMeasure(10, 18, 6, 0)
nested = JsonArray([JsonString("x"), JsonString("y")])
array = JsonArray([JsonString("ab"), JsonNumber(42), nested])
view_a = JsonArrayView(array)
view_b = JsonArrayView(array)
part_a = view_a.elements[3]
part_b = view_b.elements[3]
root = VerticalLayout([view_a, part_a, view_b, part_b])
projection = RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
    VerticalLayout => VerticalLayoutToGraphicsCanvas(),
    JsonArrayView  => _make_json_view_stages(measure),
]))
iomap = print_document(projection, root)
editor = (; document = root)
press!(event) = begin
    operation = read_intent(projection, iomap, event)
    operation === nothing || evaluate_operation(editor, operation)
    operation
end

place(i) = @reference(root, children[i])
at(i, path) = concat_references(place(i), strip_reference_types(path))
stored(document) = strip_reference_types(get_stored_selection(document))
plain(path) = strip_reference_types(path)
drawn() = _json_view_collect(iomap, TextViewToGraphicsCanvasIoMap)
texts() = [get_flat_string(m.input.viewed) for m in drawn()]
whole_text = "[\n  \"ab\",\n  42,\n  [\n    \"x\",\n    \"y\"\n  ]\n]"
part_text = "[\n  \"x\",\n  \"y\"\n]"

@testset "A place of a part prints the view of the part" begin
    @test part_a isa JsonArrayView && part_a.viewed === nested
    @test part_a !== part_b && part_b.viewed === nested
    @test texts() == [whole_text, part_text, whole_text, part_text]
    # The step of each place prints the view that the place holds.
    steps = filter(m -> m.input isa JsonArrayView, _json_view_collect(iomap, ViewingIoMap))
    @test all(map(===, [m.input for m in steps], [view_a, part_a, view_b, part_b]))
end

@testset "A fold of a part is the fold that the whole view shows" begin
    folded(text) = !occursin("\"x\"", text)
    evaluate_operation(editor, ToggleFoldOperation(place(2)))
    @test part_a.collapsed && !part_b.collapsed
    @test folded.(texts()) == [true, true, false, false]
    evaluate_operation(editor, ToggleFoldOperation(at(1, @reference(view_a, elements[3]))))
    @test !part_a.collapsed
    @test texts() == [whole_text, part_text, whole_text, part_text]
end

@testset "A caret through the whole view is dormant at the place of the part" begin
    replace_selection!(root, at(1, @reference(view_a, elements[3].elements[2].value{1})))
    @test stored(part_a) == plain(@reference(part_a, elements[2].value{1}))
    @test _json_view_is_caret_live.(drawn())[1:2] == [true, false]
    # The two places draw the same place of the text of `"y"`: the whole view has
    # two more spaces before it than the part has.
    xs = _json_view_caret_x.(drawn())
    @test xs[1] == xs[2] + 20
    @test xs[3] === nothing && xs[4] === nothing
end

@testset "A caret through the place of the part leaves the whole view its own caret" begin
    replace_selection!(root, at(2, @reference(part_a, elements[1].value{0})))
    @test stored(part_a) == plain(@reference(part_a, elements[1].value{0}))
    @test stored(view_a) == plain(@reference(view_a, elements[3].elements[2].value{1}))
    @test !is_live_selection(view_a)
    @test _json_view_is_caret_live.(drawn())[1:2] == [false, true]
end

@testset "A key at the place of the part edits the content of every place" begin
    @test press!(KeyPress('Z', ModifierKeys(); time = 0.0)) isa ReplaceStringRangeOperation
    @test nested.elements[1].value == "Zx"
    @test stored(part_a) == plain(@reference(part_a, elements[1].value{1}))
    @test all(text -> occursin("\"Zx\"", text), texts())
    @test get_stored_selection(nested) === nothing
end

@testset "A second view keeps a caret of its own at its places" begin
    replace_selection!(root, at(4, @reference(part_b, elements[2].value{0})))
    @test stored(part_b) == plain(@reference(part_b, elements[2].value{0}))
    @test stored(part_a) == plain(@reference(part_a, elements[1].value{1}))
    @test _json_view_is_caret_live.(drawn()) == [false, false, false, true]
    # The whole view B holds no caret: the path from the root did not go through it.
    @test get_stored_selection(view_b) === nothing
end

end
end

# The three pastes of a view, with the keys of the clipboard. A copy and a paste
# give a copy of the content with a new view. A note and a paste give a second
# view of the same content. A note and "Paste the same view" give the same view at
# a second place.
function test_json_view_pastes()
@testset "The pastes of a JSON view" begin

measure = FixedMeasure(10, 18, 6, 0)
style = StyleText(StyleFont("Ubuntu Mono", 20), color_white)
nested = JsonArray([JsonString("x"), JsonString("y")])
array = JsonArray([JsonString("ab"), JsonNumber(42), nested])
view_a = JsonArrayView(array)
layout = VerticalLayout(Any[view_a, [make_text_block("empty", style) for _ in 1:5]...])
root = make_clipboard_document(layout)
projection = make_clipboard_projection(RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
    VerticalLayout => VerticalLayoutToGraphicsCanvas(),
    JsonArrayView  => _make_json_view_stages(measure),
    TextBlock      => TextBlockToGraphicsCanvas(; measure),
])))
iomap = print_document(projection, root)
editor = (; document = root)
press!(event) = begin
    operation = read_intent(projection, iomap, event)
    operation === nothing || evaluate_operation(editor, operation)
    operation
end
ctrl(name; modifiers...) = KeyDown(name, ModifierKeys(; ctrl = true, modifiers...); time = 0.0)

place(i) = @reference(root, content.children[i])
at(i, view, path) = concat_references(place(i), strip_reference_types(path))
select!(path) = replace_selection!(root, path)
# A path to a place wakes the dormant caret of the view at the place. A second
# write of the path, to the view that is then live, selects the view as a whole.
select_whole!(i) = (select!(place(i)); select!(place(i)))
stored(document) = strip_reference_types(get_stored_selection(document))
plain(path) = strip_reference_types(path)
held(i) = layout.children[i]
drawn() = _json_view_collect(iomap, TextViewToGraphicsCanvasIoMap)
texts() = [get_flat_string(m.input.viewed) for m in drawn()]

# View A folds its nested array and has its caret in its first element.
view_a.elements[3].collapsed = true

@testset "A note and a paste give a second view of the same content" begin
    select_whole!(1)
    @test press!(ctrl(:n)) isa CompoundOperation
    @test root.slice === view_a
    select!(at(1, view_a, @reference(view_a, elements[1].value{1})))
    select!(place(2))
    @test press!(ctrl(:v)) isa CompoundOperation
    view_b = held(2)
    @test view_b isa JsonArrayView && view_b !== view_a && view_b.viewed === array
    @test held(1) === view_a
    # The new view starts with the fold of view A. A paste selects what it puts in
    # as a whole, so the new view is the live selection, and its copy of the caret
    # of view A waits in it as a dormant one.
    @test view_b.elements[3].collapsed && view_b.elements[3] !== view_a.elements[3]
    @test get_selection(view_b) isa EmptyReference
    @test is_live_selection(view_b) && !is_live_selection(view_a)
    leaf_b = view_b.elements[1]
    @test stored(leaf_b) == plain(@reference(leaf_b, value{1})) && !is_live_selection(leaf_b)
    @test length(texts()) == 2 && texts()[1] == texts()[2]

    # Then each view keeps its own caret and its own fold, over one content.
    select!(at(2, view_b, @reference(view_b, elements[1].value{1})))
    @test press!(KeyDown(:right, ModifierKeys(); time = 0.0)) isa ReplaceSelectionOperation
    @test stored(view_b) == plain(@reference(view_b, elements[1].value{2}))
    @test stored(view_a) == plain(@reference(view_a, elements[1].value{1}))
    view_b.elements[3].collapsed = false
    @test view_a.elements[3].collapsed
    @test occursin("\"x\"", texts()[2]) && !occursin("\"x\"", texts()[1])
    @test press!(KeyPress('Q', ModifierKeys(); time = 0.0)) isa ReplaceStringRangeOperation
    @test array.elements[1].value == "abQ"
    @test all(text -> occursin("\"abQ\"", text), texts())
end

@testset "A second paste gives a third view" begin
    select!(place(3))
    @test press!(ctrl(:v)) isa CompoundOperation
    @test held(3) isa JsonArrayView && held(3) !== view_a && held(3) !== held(2)
    @test held(3).viewed === array
end

@testset "A note and Paste the same view give the same view at a second place" begin
    select!(at(1, view_a, @reference(view_a, elements[1].value{1})))
    select!(place(4))
    @test press!(ctrl(:v; alt = true)) isa CompoundOperation
    @test held(4) === view_a
    # A paste selects what it puts in as a whole: view A is the live selection,
    # through its new place.
    @test get_selection(view_a) isa EmptyReference && is_live_selection(view_a)
    # A caret through the new place is the one caret of view A: live there, and
    # dormant at its first place.
    select!(at(4, view_a, @reference(view_a, elements[1].value{1})))
    @test stored(view_a) == plain(@reference(view_a, elements[1].value{1}))
    views = [m for m in drawn()]
    @test length(views) == 4
    @test _json_view_is_caret_live.(views[[1, 4]]) == [false, true]
    @test _json_view_caret_x(views[1]) == _json_view_caret_x(views[4])
end

@testset "A note of a part and Paste the same view give a place of the part" begin
    select!(at(1, view_a, @reference(view_a, elements[3])))
    @test press!(ctrl(:n)) isa CompoundOperation
    @test root.slice === view_a.elements[3]
    select!(place(5))
    @test press!(ctrl(:v; alt = true)) isa CompoundOperation
    @test held(5) === view_a.elements[3]
    @test held(5).viewed === nested
end

@testset "A copy and a paste give a copy of the content with a new view" begin
    select_whole!(1)
    @test press!(ctrl(:c)) isa CompoundOperation
    copy = root.slice
    @test copy isa JsonArrayView && copy !== view_a && copy.viewed !== array
    @test copy.viewed.elements[1].value == "abQ" && copy.elements[3].collapsed
    @test !(get_stored_selection(copy) isa ConcreteReference)
    select!(place(6))
    @test press!(ctrl(:v)) isa CompoundOperation
    view_c = held(6)
    @test view_c isa JsonArrayView && view_c !== copy && view_c.viewed === copy.viewed
    @test view_c.elements[3].collapsed
    # An edit of the copy does not change the content of view A.
    select!(at(6, view_c, @reference(view_c, elements[1].value{0})))
    @test press!(KeyPress('W', ModifierKeys(); time = 0.0)) isa ReplaceStringRangeOperation
    @test view_c.viewed.elements[1].value == "WabQ"
    @test array.elements[1].value == "abQ"
    # "Paste copy" gives a new copy of the content each time.
    select_whole!(6)
    @test press!(ctrl(:v; shift = true)) isa CompoundOperation
    @test held(6) isa JsonArrayView && held(6) !== view_c
    @test held(6).viewed !== copy.viewed && held(6).viewed !== array
    @test held(6).viewed.elements[1].value == "WabQ"
end

@testset "A paste does not write into a view" begin
    select_whole!(1)
    @test press!(ctrl(:n)) isa CompoundOperation
    select!(at(2, held(2), @reference(held(2), elements[2])))
    @test !(press!(ctrl(:v)) isa CompoundOperation)
    @test !(press!(ctrl(:v; alt = true)) isa CompoundOperation)
    @test !(press!(ctrl(:x)) isa CompoundOperation)
    @test array.elements[2] isa JsonNumber && length(array.elements) == 3
    @test held(2).elements[2] isa JsonNumberView
end

@testset "A paste replaces a view at its place" begin
    select_whole!(2)
    earlier = held(2)
    @test press!(ctrl(:v)) isa CompoundOperation
    @test held(2) isa JsonArrayView && held(2) !== earlier && held(2) !== view_a
    @test held(2).viewed === array
    # The new view is the selected one, as a whole.
    @test get_selection(held(2)) isa EmptyReference && is_live_selection(held(2))
    # The same view over a view of the same kind: it is live at the new place.
    select_whole!(6)
    @test press!(ctrl(:v; alt = true)) isa CompoundOperation
    @test held(6) === view_a
    @test get_selection(view_a) isa EmptyReference && is_live_selection(view_a)
end

@testset "The duplicate of a view is a second view of the same content" begin
    duplicate = make_document_duplicate(view_a)
    @test duplicate isa JsonArrayView && duplicate !== view_a && duplicate.viewed === array
    @test duplicate.elements[3].collapsed
    @test copy_document(view_a).viewed !== array
end

@testset "A cut takes a view from its place" begin
    select_whole!(3)
    taken = held(3)
    count = length(layout.children)
    @test press!(ctrl(:x)) isa CompoundOperation
    # The place is an element of the list of the layout, so the element goes.
    @test root.slice === taken && length(layout.children) == count - 1
    @test !any(child -> child === taken, layout.children)
end

end
end
