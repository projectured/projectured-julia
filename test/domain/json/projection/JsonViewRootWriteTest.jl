# The write of the node of a view that a view holds. The document of an undo buffer
# is the node of the view at the top of the JSON views, and its place is the field
# `content` of the buffer. The printer of the view of the buffer holds that place:
# it writes the node there, and it records the write. Each test presses a key two
# times, at the same caret: on a buffer with no view, and on an equal buffer
# through its view. After the key the two documents are equal, and the two carets
# have the same path. The helpers are those of `JsonViewKeysTest.jl` and of
# `JsonUndoBufferViewTest.jl`.

# The two sides of a comparison: `make()` gives the document of a buffer. The side
# `plain` shows the buffer, and the side `viewed` shows an equal buffer through its
# view. Each side is the one child of a layout, printed by the general renderer.
function _make_root_write_sides(make)
    plain_buffer = UndoBuffer(make())
    viewed_buffer = UndoBuffer(make())
    view = UndoBufferView(viewed_buffer)
    (; plain_buffer, viewed_buffer, view, plain = _ubv_show(plain_buffer), viewed = _ubv_show(view))
end

_root_write_place(side, path) =
    concat_references(strip_reference_types(@reference(side.root, children[1].content)), strip_reference_types(path))

# Put the caret at `path` of the document of the buffer on the two sides:
# `path(document)` gives the path in the document.
function _set_root_write_caret!(sides, path)
    replace_selection!(sides.plain.root, _root_write_place(sides.plain, path(sides.plain_buffer.content)))
    replace_selection!(sides.viewed.root, _root_write_place(sides.viewed, path(sides.viewed_buffer.content)))
    sides
end

# Press `event` on the two sides, and test that the sides are equal after it. The
# answer is whether the key gave an operation.
function _test_root_write_press!(sides, event)
    plain_operation = sides.plain.press!(event)
    view_operation = sides.viewed.press!(event)
    @test (plain_operation === nothing) == (view_operation === nothing)
    @test _json_keys_shape(sides.viewed_buffer.content) == _json_keys_shape(sides.plain_buffer.content)
    @test _json_keys_caret_text(get_stored_selection(sides.viewed.root)) ==
          _json_keys_caret_text(get_stored_selection(sides.plain.root))
    @test length(sides.viewed_buffer.undo_entries) == length(sides.plain_buffer.undo_entries)
    @test _json_view_holds_no_caret(sides.viewed_buffer.content)
    @test get_stored_selection(sides.viewed_buffer) === nothing
    @test sides.view.content !== nothing && sides.view.content.viewed === sides.viewed_buffer.content
    plain_operation !== nothing
end

function test_json_view_root_write()
@testset "the write of the node of a view that a view holds" begin

typed(character) = KeyPress(character, ModifierKeys(); time = 0.0)
key(name; modifiers...) = KeyDown(name, ModifierKeys(; modifiers...); time = 0.0)
undo_key = key(:z; ctrl = true)
whole(document) = EmptyReference()
in_value(k) = document -> @reference(document, value{k})

@testset "a typed digit in the place for a new value makes the number" begin
    sides = _set_root_write_caret!(_make_root_write_sides(JsonInsertion), in_value(0))
    @test _test_root_write_press!(sides, typed('7'))
    @test sides.viewed_buffer.content isa JsonNumber && sides.viewed_buffer.content.value == 7
    @test sides.view.content isa JsonNumberView
    @test length(sides.viewed_buffer.undo_entries) == 1
    # Ctrl+Z puts the place for a new value back, with its view and its caret.
    @test _test_root_write_press!(sides, undo_key)
    @test sides.viewed_buffer.content isa JsonInsertion
    @test sides.view.content isa JsonInsertionView
end

@testset "a typed name and Return make the document of the name" begin
    sides = _set_root_write_caret!(_make_root_write_sides(JsonInsertion), in_value(0))
    for character in "null"
        @test _test_root_write_press!(sides, typed(character))
    end
    @test sides.viewed_buffer.content isa JsonInsertion && sides.viewed_buffer.content.value == "null"
    @test _test_root_write_press!(sides, typed('\n'))
    @test sides.viewed_buffer.content isa JsonNull
    @test sides.view.content isa JsonNullView
    @test _test_root_write_press!(sides, undo_key)
    @test sides.viewed_buffer.content isa JsonInsertion
end

@testset "Escape puts the empty place back" begin
    sides = _set_root_write_caret!(_make_root_write_sides(JsonInsertion), in_value(0))
    @test _test_root_write_press!(sides, typed('x'))
    @test _test_root_write_press!(sides, key(:escape))
    @test sides.viewed_buffer.content isa JsonNothing
    @test sides.view.content isa JsonNothingView
    @test _test_root_write_press!(sides, undo_key)
    @test sides.viewed_buffer.content isa JsonInsertion
end

@testset "a key of a kind replaces the document of the buffer" begin
    sides = _set_root_write_caret!(_make_root_write_sides(JsonNull), whole)
    @test _test_root_write_press!(sides, typed('['))
    @test sides.viewed_buffer.content isa JsonArray
    @test sides.view.content isa JsonArrayView
    @test _test_root_write_press!(sides, undo_key)
    @test sides.viewed_buffer.content isa JsonNull
    sides = _set_root_write_caret!(_make_root_write_sides(() -> JsonNumber(4)), in_value(1))
    @test _test_root_write_press!(sides, typed('t'))
    @test sides.viewed_buffer.content isa JsonBool
end

@testset "a view that no view holds gives no operation" begin
    # The view of the place for a new value in a layout: no view above it holds its
    # node, so a typed digit has no place to write the number.
    insertion = JsonInsertion()
    shown = _ubv_show(JsonInsertionView(insertion))
    replace_selection!(shown.root, strip_reference_types(@reference(shown.root, children[1].value{0})))
    @test shown.press!(typed('7')) === nothing
    @test shown.root.children[1] isa JsonInsertionView && shown.root.children[1].viewed === insertion
end

end
end
