# A part of a JSON document that has no view. A document of a type with no view type
# prints as content inside the views, and it keeps its caret as a content does. A
# path into it takes the step `viewed` before the step that reaches no view, such as
# `.elements.viewed[2].value{1}`. A key goes to the part by its route, so the key
# table and the printer of the part read it as they do with no view. Each test does
# the same thing two times: on a JSON content with no view, and on an equal content
# through its views. The helpers are those of `JsonViewKeysTest.jl` and of
# `JsonUndoBufferViewTest.jl`.

# A document of a type that has no view type, with one key of its own.
@document struct JsonPartProbe
    value::String
end

@gestures JsonPartProbe begin
    KeyPress('!') => "Mark the probe" => ReplaceReferencedValueOperation(doc, "value", "marked")
end

# The kind of each node of a document that holds parts with no view.
_json_part_shape(document::JsonObject) = (:object, Any[_json_part_shape(entry) for entry in document.entries])
_json_part_shape(document::JsonObjectEntry) = (:entry, document.key, _json_part_shape(document.value))
_json_part_shape(document::JsonArray) = (:array, Any[_json_part_shape(element) for element in document.elements])
_json_part_shape(document) = (nameof(typeof(document)), hasproperty(document, :value) ? document.value : nothing)

# The text of a caret with no step `viewed`: the path of the same place of a content
# with no view.
_json_part_caret_text(caret) = replace(_json_keys_caret_text(caret), ".viewed" => "")

# The two sides of a comparison. `make()` gives a document, and each call gives an
# equal one. `wrap` gives what a side shows: the document for the side `plain`, and
# its view for the side `viewed`.
function _make_json_part_sides(make; show_plain = identity, show_viewed = make_content_view)
    plain_document = make()
    viewed_document = make()
    (; plain_document, viewed_document,
       plain = _ubv_show(show_plain(plain_document)), viewed = _ubv_show(show_viewed(viewed_document)))
end

# Do `act(side)` on the two sides, and test that the sides are equal after it. The
# answer is what `act` gave on the side `plain`.
function _test_json_part_sides!(act, sides)
    plain_answer = act(sides.plain)
    view_answer = act(sides.viewed)
    @test (plain_answer === nothing) == (view_answer === nothing)
    @test _json_part_shape(sides.viewed_document) == _json_part_shape(sides.plain_document)
    @test _json_part_caret_text(get_stored_selection(sides.viewed.root)) ==
          _json_part_caret_text(get_stored_selection(sides.plain.root))
    @test _vnr_drawn(sides.viewed.iomap.output) == _vnr_drawn(sides.plain.iomap.output)
    plain_answer
end

# The place where a side draws the text `text`, with a small step into it.
function _find_json_part_spot(side, text)
    spot = first(drawn for drawn in _vnr_drawn(side.iomap.output) if drawn[1] == text)
    (spot[2] + 5, spot[3] + 5)
end

function test_json_view_part_without_view()
@testset "a part of a JSON document that has no view" begin

typed(character) = KeyPress(character, ModifierKeys(); time = 0.0)
key(name; modifiers...) = KeyDown(name, ModifierKeys(; modifiers...); time = 0.0)
click(spot) = MouseClick(:left, spot[1], spot[2]; time = 0.0)
stored(document) = strip_reference_types(get_stored_selection(document))
has_viewed_step(document) = occursin(".viewed", _json_keys_caret_text(get_stored_selection(document)))

@testset "the part prints as content, and a view has no view for it" begin
    make() = JsonArray([JsonString("ab"), PrimitiveString("xy"), JsonNumber(7)])
    sides = _make_json_part_sides(make)
    view = sides.viewed.root.children[1]
    @test view isa JsonArrayView
    @test view.elements[1] isa JsonStringView && view.elements[2] === nothing && view.elements[3] isa JsonNumberView
    @test _vnr_drawn(sides.viewed.iomap.output) == _vnr_drawn(sides.plain.iomap.output)
end

@testset "a click puts the caret into the part, and the part holds it" begin
    make() = JsonArray([JsonString("ab"), PrimitiveString("xy"), JsonNumber(7)])
    sides = _make_json_part_sides(make)
    spot = _find_json_part_spot(sides.plain, "xy")
    @test _test_json_part_sides!(side -> side.press!(click(spot)), sides) isa ReplaceSelectionOperation
    view = sides.viewed.root.children[1]
    part = sides.viewed_document.elements[2]
    # The path of the caret has the step `viewed` after the view of the list.
    @test stored(sides.viewed.root) == strip_reference_types(
        @reference(sides.viewed.root, children[1].elements.viewed[2].value{0}))
    # The part holds its caret, as with no view, and the array holds none.
    @test stored(part) == stored(sides.plain_document.elements[2])
    @test get_stored_selection(sides.viewed_document) === nothing
    @test is_live_selection(part)
    # A click in a JSON string puts the caret back into the views.
    string_spot = _find_json_part_spot(sides.plain, "ab")
    @test _test_json_part_sides!(side -> side.press!(click(string_spot)), sides) isa ReplaceSelectionOperation
    @test !has_viewed_step(sides.viewed.root)
    @test get_stored_selection(sides.viewed_document.elements[1]) === nothing
end

@testset "a typed character edits the part" begin
    make() = JsonArray([JsonString("ab"), PrimitiveString("xy"), JsonNumber(7)])
    sides = _make_json_part_sides(make)
    spot = _find_json_part_spot(sides.plain, "xy")
    _test_json_part_sides!(side -> side.press!(click(spot)), sides)
    @test _test_json_part_sides!(side -> side.press!(typed('Z')), sides) !== nothing
    @test sides.viewed_document.elements[2].value == "Zxy"
    @test has_viewed_step(sides.viewed.root)
    @test _test_json_part_sides!(side -> side.press!(typed('Q')), sides) !== nothing
    @test sides.viewed_document.elements[2].value == "ZQxy"
end

@testset "the arrow keys move the caret from a view into the part and back" begin
    make() = JsonArray([JsonString("ab"), PrimitiveString("xy"), JsonNumber(7)])
    sides = _make_json_part_sides(make)
    string_spot = _find_json_part_spot(sides.plain, "ab")
    _test_json_part_sides!(side -> side.press!(click(string_spot)), sides)
    forms = Bool[]
    for _ in 1:14
        _test_json_part_sides!(side -> side.press!(key(:right)), sides)
        push!(forms, has_viewed_step(sides.viewed.root))
    end
    # The caret goes into the part, and it comes out of it on the other side.
    @test any(forms) && !forms[1] && !forms[end]
    for _ in 1:14
        _test_json_part_sides!(side -> side.press!(key(:left)), sides)
    end
    @test !has_viewed_step(sides.viewed.root)
end

@testset "a key of the key table of the part" begin
    make() = JsonArray([JsonString("ab"), JsonPartProbe("xy"), JsonNumber(7)])
    sides = _make_json_part_sides(make)
    spot = _find_json_part_spot(sides.plain, "xy")
    _test_json_part_sides!(side -> side.press!(click(spot)), sides)
    @test _test_json_part_sides!(side -> side.press!(typed('!')), sides) isa ReplaceReferencedValueOperation
    @test sides.viewed_document.elements[2].value == "marked"
    # With the caret in a JSON string, the key is a character of the string.
    string_spot = _find_json_part_spot(sides.plain, "ab")
    _test_json_part_sides!(side -> side.press!(click(string_spot)), sides)
    _test_json_part_sides!(side -> side.press!(typed('!')), sides)
    @test occursin('!', sides.viewed_document.elements[1].value)
end

@testset "a key of the printer of the part" begin
    # The place for a new value of every domain has its keys in the table of its
    # printer. Escape puts the empty place there.
    make() = JsonArray([JsonString("ab"), DocumentInsertion("js")])
    sides = _make_json_part_sides(make)
    spot = _find_json_part_spot(sides.plain, "js")
    _test_json_part_sides!(side -> side.press!(click(spot)), sides)
    @test _test_json_part_sides!(side -> side.press!(key(:escape)), sides) !== nothing
    @test sides.viewed_document.elements[2] isa DocumentNothing
end

@testset "a write puts a part in the place of a view, and a view in the place of a part" begin
    # The caret that follows the write takes the form of the new document: with the
    # step `viewed` for a part that has no view, and with no such step for a view.
    make() = JsonArray([JsonString("ab"), JsonNumber(7)])
    array = make()
    view = JsonArrayView(array)
    shown = _ubv_show(view)
    editor = (; document = shown.root)
    place = strip_reference_types(@reference(view, elements[2]))
    part = PrimitiveString("xy")
    replace_selection!(part, strip_reference_types(@reference(part, value{1})))
    evaluate_operation(editor, reroot_operation(make_content_edit(view, make_replace_document_operation(place, part)),
                                                (FieldReferenceStep("children"), ElementReferenceStep(1))))
    @test array.elements[2] === part && view.elements[2] === nothing
    @test stored(shown.root) == strip_reference_types(@reference(shown.root, children[1].elements.viewed[2].value{1}))
    @test stored(part) == strip_reference_types(@reference(part, value{1}))
    number = JsonNumber(5)
    replace_selection!(number, strip_reference_types(@reference(number, value{1})))
    evaluate_operation(editor, reroot_operation(make_content_edit(view, make_replace_document_operation(place, number)),
                                                (FieldReferenceStep("children"), ElementReferenceStep(1))))
    @test array.elements[2] === number && view.elements[2] isa JsonNumberView
    @test stored(shown.root) == strip_reference_types(@reference(shown.root, children[1].elements[2].value{1}))
    @test get_stored_selection(number) === nothing
    # An insert of a part before an element: the caret goes into the part.
    second = PrimitiveString("pq")
    insert = make_insert_elements_operation(strip_reference_types(@reference(view, elements)), 1, Any[second];
                                            selection = strip_reference_types(@reference(view, elements[1])))
    evaluate_operation(editor, reroot_operation(make_content_edit(view, insert),
                                                (FieldReferenceStep("children"), ElementReferenceStep(1))))
    @test array.elements[1] === second && length(array.elements) == 3
    @test stored(shown.root) == strip_reference_types(@reference(shown.root, children[1].elements.viewed[1]))
end

@testset "the part as the value of an entry" begin
    make() = JsonObject("name" => PrimitiveString("xy"), "size" => JsonNumber(7))
    sides = _make_json_part_sides(make)
    spot = _find_json_part_spot(sides.plain, "xy")
    @test _test_json_part_sides!(side -> side.press!(click(spot)), sides) isa ReplaceSelectionOperation
    @test stored(sides.viewed.root) == strip_reference_types(
        @reference(sides.viewed.root, children[1].entries[1].viewed.value.value{0}))
    @test _test_json_part_sides!(side -> side.press!(typed('Z')), sides) !== nothing
    @test sides.viewed_document.entries[1].value.value == "Zxy"
    # The step `viewed` names the entry, so the entry holds the caret from itself, as
    # with no view. The object above it holds none.
    @test stored(sides.viewed_document.entries[1]) == stored(sides.plain_document.entries[1])
    @test get_stored_selection(sides.viewed_document) === nothing
    @test get_stored_selection(sides.viewed_document.entries) === nothing
end

@testset "the part as the document of an undo buffer" begin
    make() = UndoBuffer(PrimitiveString("xy"))
    sides = _make_json_part_sides(make; show_viewed = UndoBufferView)
    view = sides.viewed.root.children[1]
    @test view isa UndoBufferView && view.content === nothing
    spot = _find_json_part_spot(sides.plain, "xy")
    @test sides.plain.press!(click(spot)) isa ReplaceSelectionOperation
    @test sides.viewed.press!(click(spot)) isa ReplaceSelectionOperation
    @test stored(sides.viewed.root) == strip_reference_types(
        @reference(sides.viewed.root, children[1].viewed.content.value{0}))
    @test sides.plain.press!(typed('Z')) isa RecordUndoOperation
    @test sides.viewed.press!(typed('Z')) isa RecordUndoOperation
    @test sides.viewed_document.content.value == "Zxy" && sides.plain_document.content.value == "Zxy"
    @test length(sides.viewed_document.undo_entries) == 1
    @test sides.viewed.press!(key(:z; ctrl = true)) isa UndoOperation
    @test sides.viewed_document.content.value == "xy"
end

end
end
