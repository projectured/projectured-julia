# One JSON object with a string, an array and an object, in two views at three
# places. Each entry has a view, and the value of an entry has the view of its
# kind. The key of an entry is a text of the entry, so a caret in a key is on the
# view of the entry.

# Each document of a JSON content, with the lists that hold them.
function _json_view_content_documents(document, found = Any[])
    push!(found, document)
    if document isa JsonObject
        push!(found, document.entries)
        foreach(entry -> _json_view_content_documents(entry, found), document.entries)
    elseif document isa JsonArray
        push!(found, document.elements)
        foreach(element -> _json_view_content_documents(element, found), document.elements)
    elseif document isa JsonObjectEntry
        _json_view_content_documents(document.value, found)
    end
    found
end

# Whether no document of a JSON content holds a caret.
_json_view_holds_no_caret(document) =
    all(part -> get_stored_selection(part) === nothing, _json_view_content_documents(document))

function test_json_object_view()
@testset "JsonObjectView" begin

measure = FixedMeasure(10, 18, 6, 0)
inner = JsonObject("depth" => JsonNumber(2))
tags = JsonArray([JsonString("x")])
object = JsonObject("name" => JsonString("lamp"), "tags" => tags, "inner" => inner)
view_a = JsonObjectView(object)
view_b = JsonObjectView(object)
root = VerticalLayout([view_a, view_b, view_a])
projection = RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
    VerticalLayout => VerticalLayoutToGraphicsCanvas(),
    JsonObjectView => _make_json_view_stages(measure),
]))
iomap = print_document(projection, root)
editor = (; document = root)
press!(event) = begin
    operation = read_intent(projection, nothing, Intent(event), iomap).operation
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
# The text of the object with no view, through the same two stages.
content_text() = get_flat_string(print_document(ChainingProjection(
    RecursiveProjection(JsonToSyntax()),
    RecursiveProjection(SyntaxToText(text_folds = true))), object).output)
steps = _json_view_collect(iomap, ViewingIoMap)

@testset "Each entry has a view, and each value has the view of its kind" begin
    @test fieldnames(JsonObjectView)[1:3] == (:viewed, :entries, :collapsed)
    @test fieldnames(JsonObjectEntryView)[1:2] == (:viewed, :value)
    @test !(:key in fieldnames(JsonObjectEntryView))
    @test make_content_view(object) isa JsonObjectView
    @test make_content_view(object.entries[1]) isa JsonObjectEntryView
    @test view_a.entries isa CellVectorView && length(view_a.entries) == 3
    @test all(i -> view_a.entries[i] isa JsonObjectEntryView && view_a.entries[i].viewed === object.entries[i], 1:3)
    @test view_a.entries[1].value isa JsonStringView && view_a.entries[2].value isa JsonArrayView
    @test view_a.entries[3].value isa JsonObjectView
    @test all(i -> view_a.entries[i].value.viewed === object.entries[i].value, 1:3)
    @test view_a.entries[3].value.entries[1].value isa JsonNumberView
    @test all(i -> view_a.entries[i] !== view_b.entries[i], 1:3)
    @test all(i -> view_a.entries[i].value !== view_b.entries[i].value, 1:3)
    @test view_a.collapsed == false
end

@testset "An object in an array has its view, with the views of its entries" begin
    list = JsonArray([JsonObject("k" => JsonString("v"))])
    list_view = JsonArrayView(list)
    @test list_view.elements[1] isa JsonObjectView
    @test list_view.elements[1].entries[1] isa JsonObjectEntryView
    @test list_view.elements[1].entries[1].value isa JsonStringView
end

@testset "The object through its view prints the text of the object with no view" begin
    expected = content_text()
    @test occursin("\"name\": \"lamp\"", expected) && occursin("\"depth\": 2", expected)
    @test texts() == [expected, expected, expected]
end

@testset "The print of an entry keeps one child print, and its node has two children" begin
    whole = first(filter(m -> m.input === view_a, steps))
    entry_print = get_content_iomap(get_child_iomaps(whole.content)[2])
    @test entry_print.input === object.entries[2]
    @test length(entry_print.output.children) == 2
    @test length(get_child_iomaps(entry_print)) == 1
end

@testset "The step of an entry puts the view of the value at the place of the value" begin
    whole = first(filter(m -> m.input === view_a, steps))
    @test whole.output isa SyntaxNodeView && length(whole.output.children) == 3
    @test all(i -> whole.output.children[i] isa SyntaxNodeView, 1:3)
    @test all(i -> whole.output.children[i].viewed === whole.output.viewed.children[i], 1:3)
    # The view of the node of the second entry. The rule of the entry makes the leaf
    # of the key itself, with no step, so that leaf has no view.
    entry_node = whole.output.children[2]
    @test length(entry_node.children) == 2
    @test entry_node.children[1] === nothing
    @test entry_node.children[2] isa SyntaxNodeView
    @test entry_node.children[2].viewed === entry_node.viewed.children[2]
end

@testset "The carets are on the views, and no content holds one" begin
    replace_selection!(root, at(2, @reference(view_b, entries[3].value.entries[1].key{1})))
    replace_selection!(root, at(1, @reference(view_a, entries[1].value.value{2})))
    @test stored(view_a.entries[1].value) == plain(@reference(view_a.entries[1].value, value{2}))
    @test stored(view_a.entries[1]) == plain(@reference(view_a.entries[1], value.value{2}))
    @test stored(view_b.entries[3].value.entries[1]) == plain(@reference(view_b.entries[3].value.entries[1], key{1}))
    @test is_live_selection(view_a) && !is_live_selection(view_b)
    @test _json_view_holds_no_caret(object)
end

@testset "A typed character changes a value and a key, through the views" begin
    @test press!(typed('X')) isa ReplaceStringRangeOperation
    @test object.entries[1].value.value == "laXmp"
    @test stored(view_a) == plain(@reference(view_a, entries[1].value.value{3}))
    replace_selection!(root, at(1, @reference(view_a, entries[1].key{4})))
    @test stored(view_a.entries[1]) == plain(@reference(view_a.entries[1], key{4}))
    @test press!(typed('s')) isa ReplaceStringRangeOperation
    @test object.entries[1].key == "names"
    @test stored(view_a) == plain(@reference(view_a, entries[1].key{5}))
    # The second view keeps its own caret.
    @test stored(view_b) == plain(@reference(view_b, entries[3].value.entries[1].key{1}))
    @test all(text -> occursin("\"names\": \"laXmp\"", text), texts())
    @test texts() == fill(content_text(), 3)
    @test _json_view_holds_no_caret(object)
end

@testset "The fold of an object is the fold of a view" begin
    folded(text) = !occursin("\"depth\"", text)
    evaluate_operation(editor, ToggleFoldOperation(at(1, @reference(view_a, entries[3].value))))
    @test view_a.entries[3].value.collapsed && !view_b.entries[3].value.collapsed
    @test folded.(texts()) == [true, false, true]
    # Ctrl+. folds the innermost fold around the caret of the view of the place.
    replace_selection!(root, at(2, @reference(view_b, entries[3].value.entries[1].key{1})))
    @test press!(KeyDown(:period, ModifierKeys(ctrl = true); time = 0.0)) isa ToggleFoldOperation
    @test view_b.entries[3].value.collapsed
    @test folded.(texts()) == [true, true, true]
    # The whole object folds at the view of the place, and the other view stays open.
    evaluate_operation(editor, ToggleFoldOperation(places[2]))
    @test view_b.collapsed && !view_a.collapsed
    @test !occursin("\"names\"", texts()[2]) && occursin("\"names\"", texts()[1])
end

end
end
