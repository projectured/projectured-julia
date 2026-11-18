# The keys of JSON through a view. Each test presses a key two times, with the caret
# at the same path: on a JSON content with no view, which keeps its caret, and on an
# equal content through its view. After the key the two contents are equal, the two
# carets have the same path, and the content under the view holds no caret.

# The kind of each node of a JSON document, with its plain values.
_json_keys_shape(document::JsonObject) = (:object, Any[_json_keys_shape(entry) for entry in document.entries])
_json_keys_shape(document::JsonObjectEntry) = (:entry, document.key, _json_keys_shape(document.value))
_json_keys_shape(document::JsonArray) = (:array, Any[_json_keys_shape(element) for element in document.elements])
_json_keys_shape(document) = (nameof(typeof(document)), hasproperty(document, :value) ? document.value : nothing)

# The text of a caret. A step to a text that a print made shows the type of the
# projection and the path in its output, and not the projection itself, because
# the two sides print with two projections.
function _json_keys_caret_text(caret)
    caret === nothing && return "no caret"
    steps = get_reference_steps(strip_reference_types(caret))
    isempty(steps) && return "the whole document"
    join(step isa ProjectionReferenceStep ?
             string("<", nameof(typeof(step.projection)), " ", _json_keys_caret_text(step.output_path), ">") :
             string(step)
         for step in steps)
end

# The two sides of a comparison. `make()` gives a new JSON document, and each call
# gives an equal one. The side `plain` prints the document as the editor prints a
# JSON content with no view. The side `viewed` prints an equal document through its
# view, in the stages of a view, at the one place of a layout.
function _make_json_keys_sides(make)
    measure = FixedMeasure(10, 18, 6, 0)
    plain = make()
    plain_projection = ChainingProjection(
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure = measure))
    viewed = make()
    view = make_content_view(viewed)
    root = VerticalLayout([view])
    view_projection = RecursiveProjection(TypeDispatchingProjection(Pair{Type,Any}[
        VerticalLayout => VerticalLayoutToGraphicsCanvas(),
        typeof(view)   => _make_json_view_stages(measure),
    ]))
    (; plain, plain_projection, viewed, view, root, view_projection)
end

# A path of the content of the side `viewed`, as a path from the layout.
_get_json_keys_place(sides, path) =
    concat_references(strip_reference_types(@reference(sides.root, children[1])), strip_reference_types(path))

# Put the caret at `path` on the two sides: `path(document)` gives the path in a
# JSON document.
function _set_json_keys_caret!(sides, path)
    replace_selection!(sides.plain, strip_reference_types(path(sides.plain)))
    replace_selection!(sides.root, _get_json_keys_place(sides, path(sides.viewed)))
    sides
end

# Read `event` on one side and do the operation that it gives.
function _press_json_keys_side!(projection, document, event)
    iomap = print_document(projection, document)
    operation = read_intent(projection, iomap, event)
    operation === nothing || evaluate_operation((; document), operation)
    operation
end

# Press `event` on the two sides, and test that the sides are equal after it.
# The answer is whether the key did something.
function _test_json_keys_press!(sides, event)
    before = _json_keys_shape(sides.plain), _json_keys_caret_text(get_selection(sides.plain))
    plain_operation = _press_json_keys_side!(sides.plain_projection, sides.plain, event)
    view_operation = _press_json_keys_side!(sides.view_projection, sides.root, event)
    @test (plain_operation === nothing) == (view_operation === nothing)
    @test _json_keys_shape(sides.viewed) == _json_keys_shape(sides.plain)
    @test _json_keys_caret_text(get_selection(sides.view)) == _json_keys_caret_text(get_selection(sides.plain))
    @test _json_view_holds_no_caret(sides.viewed)
    before != (_json_keys_shape(sides.plain), _json_keys_caret_text(get_selection(sides.plain)))
end

# The row with the description `description` among the rows that a palette collects
# on one side, done there. The answer is whether the row can act.
function _do_json_keys_row!(projection, document, description)
    iomap = print_document(projection, document)
    answer = read_intent(projection, nothing, Intent(CollectIntents()), iomap)
    rows = [intent for intent in answer.operation.intents if intent.description == description]
    isempty(rows) && return :absent
    operation = first(rows).operation
    operation === nothing && return :greyed
    evaluate_operation((; document), operation)
    :done
end

function _test_json_keys_row!(sides, description)
    plain_state = _do_json_keys_row!(sides.plain_projection, sides.plain, description)
    view_state = _do_json_keys_row!(sides.view_projection, sides.root, description)
    @test view_state == plain_state
    @test _json_keys_shape(sides.viewed) == _json_keys_shape(sides.plain)
    @test _json_keys_caret_text(get_selection(sides.view)) == _json_keys_caret_text(get_selection(sides.plain))
    @test _json_view_holds_no_caret(sides.viewed)
    plain_state
end

_json_keys_typed(character) = KeyPress(character, ModifierKeys(); time = 0.0)
_json_keys_down(name; modifiers...) = KeyDown(name, ModifierKeys(; modifiers...); time = 0.0)

# A tree with each kind of node: an object that holds a string, an array with a
# number, an array and a null, and an object.
_make_json_keys_tree() = JsonObject(
    "name" => JsonString("lamp"),
    "list" => JsonArray([JsonNumber(4), JsonArray([JsonBool(true), JsonNumber(8)]), JsonNull()]),
    "inner" => JsonObject("depth" => JsonNumber(2)))

function test_json_view_keys()
@testset "The keys of JSON through a view" begin

@testset "A key replaces the node that the caret names with a node of another kind" begin
    for key in ('n', 'f', 't', '"', '[', '{', ':', '7')
        sides = _make_json_keys_sides(_make_json_keys_tree)
        _set_json_keys_caret!(sides, document -> @reference(document, entries[2].value.elements[1]))
        @test _test_json_keys_press!(sides, _json_keys_typed(key))
    end
    # A node in an array in an array, and the value of an entry of an object in an object.
    for path in (document -> @reference(document, entries[2].value.elements[2].elements[1]),
                 document -> @reference(document, entries[3].value.entries[1].value))
        sides = _make_json_keys_sides(_make_json_keys_tree)
        _set_json_keys_caret!(sides, path)
        @test _test_json_keys_press!(sides, _json_keys_typed('n'))
        @test _test_json_keys_press!(sides, _json_keys_typed('['))
    end
end

@testset "A key does not replace an entry of an object" begin
    sides = _make_json_keys_sides(_make_json_keys_tree)
    _set_json_keys_caret!(sides, document -> @reference(document, entries[1]))
    @test !_test_json_keys_press!(sides, _json_keys_typed('n'))
    @test sides.viewed.entries[1] isa JsonObjectEntry
end

@testset "A comma appends to the innermost array or object around the caret" begin
    # An element of the array in the array.
    sides = _make_json_keys_sides(_make_json_keys_tree)
    _set_json_keys_caret!(sides, document -> @reference(document, entries[2].value.elements[2].elements[1]))
    @test _test_json_keys_press!(sides, _json_keys_typed(','))
    @test length(sides.viewed.entries[2].value.elements[2].elements) == 3
    @test length(sides.viewed.entries[2].value.elements) == 3
    # An entry of the object in the object.
    sides = _make_json_keys_sides(_make_json_keys_tree)
    _set_json_keys_caret!(sides, document -> @reference(document, entries[3].value.entries[1]))
    @test _test_json_keys_press!(sides, _json_keys_typed(','))
    @test length(sides.viewed.entries[3].value.entries) == 2 && length(sides.viewed.entries) == 3
    @test sides.viewed.entries[3].value.entries[2] isa JsonObjectEntry
    # An entry of the outer object.
    sides = _make_json_keys_sides(_make_json_keys_tree)
    _set_json_keys_caret!(sides, document -> @reference(document, entries[1]))
    @test _test_json_keys_press!(sides, _json_keys_typed(','))
    @test length(sides.viewed.entries) == 4
end

@testset "A comma in the text of a number goes to the array or the object around it" begin
    sides = _make_json_keys_sides(_make_json_keys_tree)
    _set_json_keys_caret!(sides, document -> @reference(document, entries[2].value.elements[1].value{1}))
    @test _test_json_keys_press!(sides, _json_keys_typed(','))
    @test length(sides.viewed.entries[2].value.elements) == 4
    @test sides.viewed.entries[2].value.elements[4] isa JsonInsertion
    @test sides.viewed.entries[2].value.elements[1].value == 4
    sides = _make_json_keys_sides(_make_json_keys_tree)
    _set_json_keys_caret!(sides, document -> @reference(document, entries[3].value.entries[1].value.value{1}))
    @test _test_json_keys_press!(sides, _json_keys_typed(','))
    @test length(sides.viewed.entries[3].value.entries) == 2 && length(sides.viewed.entries) == 3
end

@testset "A comma at a place that the print made appends to the node of that place" begin
    # From the last element of the inner array, the key Down moves the caret to the
    # line of the bracket that closes it, after the comma of the outer array.
    sides = _make_json_keys_sides(_make_json_keys_tree)
    _set_json_keys_caret!(sides, document -> @reference(document, entries[2].value.elements[2].elements[2].value{1}))
    @test _test_json_keys_press!(sides, _json_keys_down(:down))
    @test _test_json_keys_press!(sides, _json_keys_typed(','))
    @test length(sides.viewed.entries[2].value.elements) == 4
    @test length(sides.viewed.entries[2].value.elements[2].elements) == 2
    # From the entry of the inner object, the key Down moves the caret to the brace
    # that closes the outer object, before its break, which is a place of that object.
    sides = _make_json_keys_sides(_make_json_keys_tree)
    _set_json_keys_caret!(sides, document -> @reference(document, entries[3].value.entries[1].value.value{1}))
    @test _test_json_keys_press!(sides, _json_keys_down(:down))
    @test _test_json_keys_press!(sides, _json_keys_typed(','))
    @test length(sides.viewed.entries) == 4 && length(sides.viewed.entries[3].value.entries) == 1
end

@testset "A comma on the bracket that closes a node goes to the node around it" begin
    # Down puts the caret on the line of the bracket that closes the inner array, and
    # Left moves it on that line until it is on that bracket.
    sides = _make_json_keys_sides(_make_json_keys_tree)
    _set_json_keys_caret!(sides, document -> @reference(document, entries[2].value.elements[2].elements[2].value{1}))
    @test _test_json_keys_press!(sides, _json_keys_down(:down))
    inner_view = sides.view.entries[2].value.elements[2]
    is_on_bracket() = is_on_closing_delimiter(get_selection(inner_view); from = 1)
    for _ in 1:4
        is_on_bracket() && break
        _test_json_keys_press!(sides, _json_keys_down(:left))
    end
    @test is_on_bracket()
    @test _test_json_keys_press!(sides, _json_keys_typed(','))
    @test length(sides.viewed.entries[2].value.elements) == 4
    @test length(sides.viewed.entries[2].value.elements[2].elements) == 2
end

@testset "Tab moves the caret from the key of an entry to its value" begin
    sides = _make_json_keys_sides(_make_json_keys_tree)
    _set_json_keys_caret!(sides, document -> @reference(document, entries[1].key{2}))
    @test _test_json_keys_press!(sides, _json_keys_typed('\t'))
    @test _json_keys_caret_text(get_selection(sides.view)) ==
          _json_keys_caret_text(@reference(sides.viewed, entries[1].value))
    # In the key of an entry of the object in the object.
    sides = _make_json_keys_sides(_make_json_keys_tree)
    _set_json_keys_caret!(sides, document -> @reference(document, entries[3].value.entries[1].key{0}))
    @test _test_json_keys_press!(sides, _json_keys_typed('\t'))
    # In a value, Tab does not move the caret to a value.
    sides = _make_json_keys_sides(_make_json_keys_tree)
    _set_json_keys_caret!(sides, document -> @reference(document, entries[1].value.value{2}))
    _test_json_keys_press!(sides, _json_keys_typed('\t'))
end

@testset "The rows with no key: the way back to the key, and the sort of the entries" begin
    sides = _make_json_keys_sides(_make_json_keys_tree)
    _set_json_keys_caret!(sides, document -> @reference(document, entries[1].value.value{2}))
    @test _test_json_keys_row!(sides, "Move from value to key") === :done
    @test _json_keys_caret_text(get_selection(sides.view)) ==
          _json_keys_caret_text(@reference(sides.viewed, entries[1].key{0}))
    sides = _make_json_keys_sides(_make_json_keys_tree)
    _set_json_keys_caret!(sides, document -> @reference(document, entries[1].key{2}))
    @test _test_json_keys_row!(sides, "Sort the entries by key") === :done
    @test [entry.key for entry in sides.viewed.entries] == ["inner", "list", "name"]
end

@testset "A typed character and a key of the caret give the same content and caret" begin
    sides = _make_json_keys_sides(_make_json_keys_tree)
    _set_json_keys_caret!(sides, document -> @reference(document, entries[1].value.value{2}))
    for event in (_json_keys_typed('X'), _json_keys_down(:right), _json_keys_down(:left), _json_keys_down(:down),
                  _json_keys_down(:up), _json_keys_down(:end), _json_keys_down(:home), _json_keys_typed(','),
                  _json_keys_typed('n'), _json_keys_down(:backspace), _json_keys_down(:space; ctrl = true))
        _test_json_keys_press!(sides, event)
    end
end

end
end

# The place where a person types a new value, and the empty place, through their
# views: the same comparison as the keys of the other nodes.
function test_json_insertion_view()
@testset "The place for a new value through a view" begin

make_list() = JsonArray([JsonInsertion(), JsonNumber(1)])
in_text(k) = document -> @reference(document, elements[1].value{k})
type!(sides, text) = foreach(character -> _test_json_keys_press!(sides, _json_keys_typed(character)), text)

@testset "The view types of the two places take the declaration" begin
    insertion = JsonInsertion("str")
    @test make_content_view(insertion) isa JsonInsertionView && make_content_view(insertion).viewed === insertion
    @test make_content_view(JsonNothing()) isa JsonNothingView
    @test fieldnames(JsonInsertionView)[1] === :viewed && !(:value in fieldnames(JsonInsertionView))
    @test JsonArrayView(make_list()).elements[1] isa JsonInsertionView
    delimitation = SyntaxDelimitation(SyntaxLeaf(TextString("x")))
    @test make_content_view(delimitation) isa SyntaxDelimitationView
    @test fieldnames(SyntaxDelimitationView)[1] === :viewed && !(:content in fieldnames(SyntaxDelimitationView))
end

@testset "The place prints through its view as it prints with no view" begin
    sides = _make_json_keys_sides(make_list)
    content_text(document) = get_flat_string(print_document(ChainingProjection(
        RecursiveProjection(JsonToSyntax()),
        RecursiveProjection(SyntaxToText(text_folds = true))), document).output)
    iomap = print_document(sides.view_projection, sides.root)
    drawn = _json_view_collect(iomap, TextViewToGraphicsCanvasIoMap)
    @test length(drawn) == 1
    @test get_flat_string(first(drawn).input.viewed) == content_text(sides.viewed)
    @test content_text(sides.viewed) == content_text(sides.plain)
end

@testset "A typed name, Tab and Return make the document that the name names" begin
    sides = _make_json_keys_sides(make_list)
    _set_json_keys_caret!(sides, in_text(0))
    type!(sides, "str")
    @test sides.viewed.elements[1] isa JsonInsertion && sides.viewed.elements[1].value == "str"
    @test _test_json_keys_press!(sides, _json_keys_typed('\t'))
    @test sides.viewed.elements[1].value == "string"
    @test _test_json_keys_press!(sides, _json_keys_typed('\n'))
    @test sides.viewed.elements[1] isa JsonString
    type!(sides, "ab")
    @test sides.viewed.elements[1].value == "ab"
end

@testset "A typed digit makes a number at once, with the caret after the digit" begin
    sides = _make_json_keys_sides(make_list)
    _set_json_keys_caret!(sides, in_text(0))
    @test _test_json_keys_press!(sides, _json_keys_typed('7'))
    @test sides.viewed.elements[1] isa JsonNumber && sides.viewed.elements[1].value == 7
    type!(sides, "5")
    @test sides.viewed.elements[1].value == 75
    # A text that is no number yet stays the place, and the next digit makes the number.
    sides = _make_json_keys_sides(make_list)
    _set_json_keys_caret!(sides, in_text(0))
    type!(sides, "-")
    @test sides.viewed.elements[1] isa JsonInsertion
    type!(sides, "5")
    @test sides.viewed.elements[1] isa JsonNumber && sides.viewed.elements[1].value == -5
end

@testset "Escape puts the empty place back, and Insert makes the place again" begin
    sides = _make_json_keys_sides(make_list)
    _set_json_keys_caret!(sides, in_text(0))
    type!(sides, "ab")
    @test _test_json_keys_press!(sides, _json_keys_down(:escape))
    @test sides.viewed.elements[1] isa JsonNothing
    @test JsonArrayView(sides.viewed).elements[1] isa JsonNothingView
    @test _test_json_keys_press!(sides, _json_keys_down(:insert))
    @test sides.viewed.elements[1] isa JsonInsertion
    type!(sides, "nu")
    @test sides.viewed.elements[1].value == "nu"
end

@testset "A key of a kind of value on the empty place makes that value" begin
    make_empty_list() = JsonArray([JsonNothing(), JsonNumber(1)])
    # The whole empty place.
    sides = _make_json_keys_sides(make_empty_list)
    _set_json_keys_caret!(sides, document -> @reference(document, elements[1]))
    @test _test_json_keys_press!(sides, _json_keys_typed('['))
    @test sides.viewed.elements[1] isa JsonArray
    # A caret on the label of the empty place: Ctrl+Space gives it.
    sides = _make_json_keys_sides(make_empty_list)
    _set_json_keys_caret!(sides, document -> @reference(document, elements[1]))
    _test_json_keys_press!(sides, _json_keys_down(:space; ctrl = true))
    @test _test_json_keys_press!(sides, _json_keys_typed('{'))
    @test sides.viewed.elements[1] isa JsonObject
end

@testset "The whole place takes a key of a kind of value" begin
    sides = _make_json_keys_sides(make_list)
    _set_json_keys_caret!(sides, document -> @reference(document, elements[1]))
    @test _test_json_keys_press!(sides, _json_keys_typed('"'))
    @test sides.viewed.elements[1] isa JsonString
end

@testset "The place as the value of an entry of an object" begin
    make_object() = JsonObject("k" => JsonInsertion())
    sides = _make_json_keys_sides(make_object)
    _set_json_keys_caret!(sides, document -> @reference(document, entries[1].value.value{0}))
    @test _test_json_keys_press!(sides, _json_keys_typed('3'))
    @test sides.viewed.entries[1].value isa JsonNumber
    sides = _make_json_keys_sides(make_object)
    _set_json_keys_caret!(sides, document -> @reference(document, entries[1].value.value{0}))
    type!(sides, "nul")
    @test _test_json_keys_press!(sides, _json_keys_typed('\n'))
    @test sides.viewed.entries[1].value isa JsonNull
    @test JsonObjectView(sides.viewed).entries[1].value isa JsonNullView
end

@testset "A view that no view holds does not replace its content" begin
    sides = _make_json_keys_sides(() -> JsonInsertion("null"))
    insertion = sides.viewed
    replace_selection!(sides.root, _get_json_keys_place(sides, @reference(insertion, value{4})))
    for event in (_json_keys_typed('\n'), _json_keys_down(:escape))
        iomap = print_document(sides.view_projection, sides.root)
        @test read_intent(sides.view_projection, iomap, event) === nothing
    end
    @test sides.view.viewed === insertion && insertion.value == "null"
    @test sides.root.children[1] === sides.view
    # A key that changes the typed text is an edit of the text of the place.
    iomap = print_document(sides.view_projection, sides.root)
    operation = read_intent(sides.view_projection, iomap, _json_keys_typed('x'))
    @test operation isa ReplaceStringRangeOperation
    evaluate_operation((; document = sides.root), operation)
    @test insertion.value == "nullx" && get_stored_selection(insertion) === nothing
end

end
end
