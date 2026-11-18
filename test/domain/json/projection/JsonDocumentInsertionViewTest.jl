# The place of every domain through a view: the place where a person types the name
# of a kind of document, and the empty place. Each test does the same thing two
# times: in a JSON array with no view, and in an equal array through its views. After
# it the two arrays are equal, and the two carets name the same place. The helpers
# are those of `JsonViewPartTest.jl`.

function test_json_document_insertion_view()
@testset "the place of every domain through a view" begin

typed(character) = KeyPress(character, ModifierKeys(); time = 0.0)
key(name; modifiers...) = KeyDown(name, ModifierKeys(; modifiers...); time = 0.0)
click(spot) = MouseClick(:left, spot[1], spot[2]; time = 0.0)
has_viewed_step(document) = occursin(".viewed", _json_keys_caret_text(get_stored_selection(document)))
press!(sides, event) = _test_json_part_sides!(side -> side.press!(event), sides)
get_view(sides) = sides.viewed.root.children[1]

# The two sides with the caret in the text `text` that the second element draws.
function make_sides(make, text)
    sides = _make_json_part_sides(make)
    spot = _find_json_part_spot(sides.plain, text)
    @test press!(sides, click(spot)) isa ReplaceSelectionOperation
    sides
end

@testset "the two places have view types" begin
    insertion = DocumentInsertion("js")
    @test make_content_view(insertion) isa DocumentInsertionView && make_content_view(insertion).viewed === insertion
    @test make_content_view(DocumentNothing()) isa DocumentNothingView
    @test fieldnames(DocumentInsertionView)[1] === :viewed && !(:value in fieldnames(DocumentInsertionView))
    view = JsonArrayView(JsonArray([JsonString("ab"), DocumentInsertion("js"), DocumentNothing()]))
    @test view.elements[2] isa DocumentInsertionView && view.elements[3] isa DocumentNothingView
end

@testset "the caret of the place is on its view" begin
    sides = make_sides(() -> JsonArray([JsonString("ab"), DocumentInsertion("js")]), "js")
    view = get_view(sides)
    @test !has_viewed_step(sides.viewed.root)
    @test get_stored_selection(view.elements[2]) !== nothing
    @test get_stored_selection(sides.viewed_document.elements[2]) === nothing
    # A typed character goes into the text of the place.
    @test press!(sides, typed('o')) !== nothing
    @test occursin('o', sides.viewed_document.elements[2].value)
    @test get_stored_selection(sides.viewed_document.elements[2]) === nothing
end

@testset "Tab takes the completion of the typed name" begin
    sides = make_sides(() -> JsonArray([JsonString("ab"), DocumentInsertion("js")]), "js")
    @test press!(sides, typed('\t')) !== nothing
    @test sides.viewed_document.elements[2].value == sides.plain_document.elements[2].value
    @test startswith(sides.viewed_document.elements[2].value, "js") && length(sides.viewed_document.elements[2].value) > 2
end

@testset "Return makes the document that the typed name names" begin
    for name in ("json", "text")
        default_factory(name) === nothing && continue
        sides = make_sides(() -> JsonArray([JsonString("ab"), DocumentInsertion(name)]), name)
        @test press!(sides, typed('\n')) !== nothing
        made = sides.viewed_document.elements[2]
        @test !(made isa DocumentInsertion)
        @test typeof(made) === typeof(sides.plain_document.elements[2])
        # The new document has a view when its type has one, and it is a part with no
        # view otherwise. The caret takes the form of the document.
        view = get_view(sides)
        @test (view.elements[2] === nothing) == (make_content_view(made) === nothing)
        @test has_viewed_step(sides.viewed.root) == (view.elements[2] === nothing)
    end
end

@testset "Escape puts the empty place back, and Insert makes the place of it again" begin
    sides = make_sides(() -> JsonArray([JsonString("ab"), DocumentInsertion("js")]), "js")
    @test press!(sides, key(:escape)) !== nothing
    @test sides.viewed_document.elements[2] isa DocumentNothing
    @test get_view(sides).elements[2] isa DocumentNothingView
    @test !has_viewed_step(sides.viewed.root)
    @test press!(sides, key(:insert)) !== nothing
    @test sides.viewed_document.elements[2] isa DocumentInsertion
    @test get_view(sides).elements[2] isa DocumentInsertionView
    @test get_stored_selection(sides.viewed_document.elements[2]) === nothing
end

@testset "Insert makes the place of JSON the place of every domain" begin
    sides = make_sides(() -> JsonArray([JsonString("ab"), JsonInsertion("str")]), "str")
    @test get_view(sides).elements[2] isa JsonInsertionView
    @test press!(sides, key(:insert)) !== nothing
    made = sides.viewed_document.elements[2]
    @test made isa DocumentInsertion && made.value == "str"
    @test get_view(sides).elements[2] isa DocumentInsertionView
    @test !has_viewed_step(sides.viewed.root) && get_stored_selection(made) === nothing
    # The place of every domain takes the name of a kind of any domain.
    @test press!(sides, key(:escape)) !== nothing
    @test sides.viewed_document.elements[2] isa DocumentNothing
end

@testset "the place of every domain as the document of an undo buffer" begin
    # The printer of the view of the buffer holds the place, so Return writes the new
    # document into the buffer.
    sides = _make_root_write_sides(() -> DocumentInsertion("json"))
    @test sides.view.content isa DocumentInsertionView
    _set_root_write_caret!(sides, document -> @reference(document, value{4}))
    plain_operation = sides.plain.press!(typed('\n'))
    view_operation = sides.viewed.press!(typed('\n'))
    @test plain_operation !== nothing && view_operation !== nothing
    @test typeof(sides.viewed_buffer.content) === typeof(sides.plain_buffer.content)
    @test !(sides.viewed_buffer.content isa DocumentInsertion)
    @test sides.view.content !== nothing && sides.view.content.viewed === sides.viewed_buffer.content
    @test length(sides.viewed_buffer.undo_entries) == 1
end

end
end
