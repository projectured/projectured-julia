# The view of an undo buffer. It keeps no state of its own: it is the link between
# what holds it and the view of the document that the buffer holds. The projection
# of a buffer prints it too, so an edit that comes through the views is recorded on
# the buffer, and Ctrl+Z takes it back. Two views of one buffer share the steps and
# keep two carets. The helpers are those of `JsonViewNaturalRowTest.jl`.

_ubv_make_buffer() = UndoBuffer(JsonArray([JsonString("ab"), JsonNumber(7)]))

# A layout that holds `documents`, its print through the general renderer, and a
# function that reads an event and runs the answer.
function _ubv_show(documents...; measure = FixedMeasure(10, 18, 6, 0))
    root = VerticalLayout(Any[documents...])
    projection = NaturalToGraphics(; measure)
    iomap = print_document(projection, root)
    editor = (; document = root)
    press!(event) = begin
        operation = read_intent(projection, iomap, event)
        operation === nothing || evaluate_operation(editor, operation)
        operation
    end
    (; root, projection, iomap, press!)
end

function test_json_undo_buffer_view()
@testset "UndoBufferView" begin

stored(document) = strip_reference_types(get_stored_selection(document))
typed(character) = KeyPress(character, ModifierKeys(); time = 0.0)
undo_key = KeyDown(:z, ModifierKeys(ctrl = true); time = 0.0)
redo_key = KeyDown(:y, ModifierKeys(ctrl = true); time = 0.0)

@testset "the view holds the view of the document, and no view of the steps" begin
    buffer = _ubv_make_buffer()
    view = UndoBufferView(buffer)
    @test fieldnames(UndoBufferView)[1:2] == (:viewed, :content)
    @test !(:undo_entries in fieldnames(UndoBufferView)) && !(:redo_entries in fieldnames(UndoBufferView))
    @test view.viewed === buffer
    @test view.content isa JsonArrayView && view.content.viewed === buffer.content
    @test view.content === view.content
    @test make_content_view(buffer) isa UndoBufferView
    first_view = view.content
    buffer.content = JsonNumber(1)
    @test view.content isa JsonNumberView && view.content.viewed === buffer.content
    @test view.content !== first_view
end

@testset "the buffer through its view draws what the buffer draws" begin
    plain = _ubv_show(_ubv_make_buffer())
    shown = _ubv_show(UndoBufferView(_ubv_make_buffer()))
    plain_lines = _vnr_lines(_vnr_drawn(plain.iomap.output))
    @test plain_lines == ["[", "\"ab\",", "7", "]"]
    @test _vnr_drawn(shown.iomap.output) == _vnr_drawn(plain.iomap.output)
    @test _vnr_lines(_vnr_drawn(shown.iomap.output)) == plain_lines
    @test any(step -> step.input isa JsonArrayView, _json_view_collect(shown.iomap, ViewingIoMap))
end

@testset "an edit through the view is one step of the buffer, and Ctrl+Z takes it back" begin
    buffer = _ubv_make_buffer()
    view = UndoBufferView(buffer)
    shown = _ubv_show(view)
    string = buffer.content.elements[1]
    caret(k) = strip_reference_types(@reference(shown.root, children[1].content.elements[1].value{k}))
    replace_selection!(shown.root, caret(1))
    @test shown.press!(typed('X')) isa RecordUndoOperation
    @test string.value == "aXb"
    @test length(buffer.undo_entries) == 1
    @test stored(shown.root) == caret(2)
    # The second character joins the run of the first: the caret of the view is where
    # the first character left it.
    @test shown.press!(typed('Y')) isa RecordUndoOperation
    @test string.value == "aXYb"
    @test length(buffer.undo_entries) == 1
    # No content holds a caret.
    @test get_stored_selection(buffer) === nothing
    @test get_stored_selection(buffer.content) === nothing
    @test get_stored_selection(string) === nothing
    @test shown.press!(undo_key) isa UndoOperation
    @test string.value == "ab"
    @test length(buffer.undo_entries) == 0 && length(buffer.redo_entries) == 1
    @test stored(shown.root) == caret(1)
    @test shown.press!(redo_key) isa RedoOperation
    @test string.value == "aXYb"
    @test get_stored_selection(buffer) === nothing
end

@testset "a move of the caret ends the run of typing" begin
    buffer = _ubv_make_buffer()
    shown = _ubv_show(UndoBufferView(buffer))
    caret(k) = strip_reference_types(@reference(shown.root, children[1].content.elements[1].value{k}))
    replace_selection!(shown.root, caret(1))
    shown.press!(typed('X'))
    replace_selection!(shown.root, caret(0))
    shown.press!(typed('Y'))
    @test buffer.content.elements[1].value == "YaXb"
    @test length(buffer.undo_entries) == 2
end

@testset "two views of one buffer keep two carets and share the steps" begin
    buffer = _ubv_make_buffer()
    view_a = UndoBufferView(buffer)
    view_b = UndoBufferView(buffer)
    shown = _ubv_show(view_a, view_b)
    string = buffer.content.elements[1]
    caret(place, k) = strip_reference_types(@reference(shown.root, children[place].content.elements[1].value{k}))
    in_view(k) = strip_reference_types(@reference(view_a, content.elements[1].value{k}))
    replace_selection!(shown.root, caret(2, 2))
    replace_selection!(shown.root, caret(1, 1))
    @test stored(view_a) == in_view(1) && is_live_selection(view_a)
    @test stored(view_b) == in_view(2) && !is_live_selection(view_b)
    @test shown.press!(typed('X')) isa RecordUndoOperation
    @test string.value == "aXb"
    # Each view draws the edit.
    lines = _vnr_lines(_vnr_drawn(shown.iomap.output))
    @test count(==("\"aXb\","), lines) == 2
    # Ctrl+Z in the other view takes the edit back.
    replace_selection!(shown.root, caret(2, 2))
    @test shown.press!(undo_key) isa UndoOperation
    @test string.value == "ab"
    @test length(buffer.undo_entries) == 0
end

end
end
