# A press that selects a document to show: the pane names the document by
# identity, selects it, and scrolls the least that brings it into view. A part to
# reveal: the pane scrolls the least that shows it and selects nothing. A pane that
# shows the selection of its content when it starts.

using ProjecturedKernel.EventModule: MouseScroll
using ProjecturedPlatform.LayoutModule: RevealPartOperation

_scroll_show_projection() = RecursiveProjection(TypeDispatchingProjection(
    WidgetToGraphics(; measure = FixedMeasure(10, 18, 6, 0)).dispatch))

# Every operation of type `T` that `operation` holds, inside compounds and wrappers.
function _find_shown_members(operation, T)
    operation isa T && return Any[operation]
    operation isa CompoundOperation &&
        return reduce(vcat, (_find_shown_members(member, T) for member in operation.operations); init = Any[])
    operation isa WrappingOperation && return _find_shown_members(get_wrapped_operation(operation), T)
    Any[]
end

function test_scroll_pane_show()
@testset "a selection to show" begin
    projection = _scroll_show_projection()
    rows = Any[WidgetLabel("row $index") for index in 1:40]
    link(document) = GestureBinding[GestureBinding(MouseClickPattern(:left),
                                                   (_, _, _) -> SelectDocumentOperation(document);
                                                   description = "Go to the row", domain = "test")]
    far = WidgetLabel("Go to row 30"; gestures = link(rows[30]))
    near = WidgetLabel("Go to row 2"; gestures = link(rows[2]))
    pane = WidgetScrollPane(VerticalLayout(Any[far, near, rows...]); size = Point2D(300, 240))
    iomap = print_document(projection, pane)
    press(y) = read_intent(projection, nothing, Intent(MouseClick(:left, 5, y; time = 0.0)), iomap).operation

    @testset "a press selects the row it names, and the pane scrolls it into view" begin
        answer = press(5)
        shown = only(_find_shown_members(answer, ShowSelectionOperation))
        path = strip_reference_types(shown.operation.path)
        @test evaluate_reference(pane, path) === rows[30]
        scroll = only(write for write in _find_shown_members(answer, ReplaceReferencedValueOperation)
                      if write.document === pane)
        @test scroll.value.y[] > 0
        # Drawn at the new place, the row lies in the view of the pane.
        getfield(pane, :scroll_position)[] = scroll.value
        scrolled = print_document(projection, pane)
        image = map_reference_forward(projection, scrolled, path)
        @test find_reference_box(scrolled.output, image; visible = true) !== nothing
        getfield(pane, :scroll_position)[] = Point2D(0, 0)
    end

    @testset "a row that shows is selected and the pane stays" begin
        names_near(answer) = any(shown -> evaluate_reference(pane, strip_reference_types(shown.operation.path)) === rows[2],
                                 _find_shown_members(answer, ShowSelectionOperation))
        answer = first(answer for answer in (press(y) for y in 0:2:80) if names_near(answer))
        @test isempty([write for write in _find_shown_members(answer, ReplaceReferencedValueOperation)
                       if write.document === pane])
    end

    @testset "an editor selects a document that no reader named, and the history keeps no step" begin
        root = VerticalLayout(Any[rows[1], rows[2]])
        editor = (; document = root)
        evaluate_operation(editor, SelectDocumentOperation(rows[1]))
        # Its way back puts the selection where it was, so an add that takes the
        # caret has a way back.
        inverse = evaluate_invertible_operation!(editor, SelectDocumentOperation(rows[2]))
        @test evaluate_reference(root, strip_reference_types(get_selection(root))) === rows[2]
        evaluate_operation(editor, inverse)
        @test evaluate_reference(root, strip_reference_types(get_selection(root))) === rows[1]
        evaluate_operation(editor, SelectDocumentOperation(rows[2]))
        @test evaluate_reference(root, strip_reference_types(get_selection(root))) === rows[2]
        @test find_document_path(root, WidgetLabel("elsewhere")) === nothing
        @test !is_undo_step(nothing, ShowSelectionOperation(ReplaceSelectionOperation(EmptyReference())))
        @test !is_undo_step(nothing, SelectDocumentOperation(rows[1]))
    end

    # The answer of the pane to `operation`, an answer of its content.
    answer_of_content(map, operation) =
        ProjecturedPlatform.WidgetModule._show_pane_selection(get_iomap_projection(map), map, operation)
    # The writes of the scroll position of the pane `shown` that `answer` holds.
    pane_writes(answer, shown) = [write for write in _find_shown_members(answer, ReplaceReferencedValueOperation)
                                  if write.document === shown &&
                                     write.reference.head == FieldReferenceStep("scroll_position")]
    # The path of `row` in the pane `shown` and in its content.
    pane_path(shown, row) = annotate_reference_types(shown, find_document_path(shown, row))
    content_path(shown, row) = annotate_reference_types(shown.content, find_document_path(shown.content, row))
    # The box of `row` in the view of the pane of `map`, or `nothing` when it does not show.
    shown_box(map, row) = find_reference_box(map.output, map_reference_forward(projection, map, pane_path(map.input, row));
                                             visible = true)

    @testset "a reveal scrolls the least that shows the part and selects nothing" begin
        answer = answer_of_content(iomap, RevealPartOperation(content_path(pane, rows[30])))
        reveal = only(_find_shown_members(answer, RevealPartOperation))
        @test evaluate_reference(pane, strip_reference_types(reveal.reference)) === rows[30]
        @test isempty(_find_shown_members(answer, ReplacePathOperation))
        @test !is_undo_step(nothing, answer)
        scroll = only(pane_writes(answer, pane))
        getfield(pane, :scroll_position)[] = scroll.value
        scrolled = print_document(projection, pane)
        box = shown_box(scrolled, rows[30])
        @test box !== nothing
        # The least move puts the row at the bottom edge: nothing of the row below it shows.
        below = shown_box(scrolled, rows[31])
        @test below === nothing || below.height == 0
        # A reveal of a row that shows moves nothing, and goes up as it is.
        again = answer_of_content(scrolled, RevealPartOperation(content_path(pane, rows[29])))
        @test isempty(pane_writes(again, pane))
        @test length(_find_shown_members(again, RevealPartOperation)) == 1
        getfield(pane, :scroll_position)[] = Point2D(0, 0)
    end

    @testset "a pane shows the selection of its content when it starts" begin
        content = VerticalLayout(Any[WidgetLabel("row $index") for index in 1:40])
        named = content.children[30]
        replace_selection!(content, annotate_reference_types(content, find_document_path(content, named)))
        plain = print_document(projection, WidgetScrollPane(content; size = Point2D(300, 240)))
        @test shown_box(plain, named) === nothing
        shown = WidgetScrollPane(content; size = Point2D(300, 240), is_selection_revealed = true)
        shown_iomap = print_document(projection, shown)
        box = shown_box(shown_iomap, named)
        @test box !== nothing
        # In the middle of the view, within the height of a row.
        middle = Int(shown_iomap.output.y) + Int(shown_iomap.output.h) ÷ 2
        @test abs(box.y + box.height / 2 - middle) <= box.height
        start = shown_iomap.revealed_scroll
        @test start[2] > 0
        # The selection moves, and the view stays.
        replace_selection!(content, annotate_reference_types(content, find_document_path(content, content.children[1])))
        @test shown_iomap.revealed_scroll == start
        @test shown_box(shown_iomap, named) !== nothing
        # The first turn of the wheel scrolls from the shown offset, and the pane
        # then stays where the turn puts it.
        down = read_intent(projection, nothing, Intent(MouseScroll(0, -1, 100, 100; time = 0.0)), shown_iomap).operation
        written = only(pane_writes(down, shown)).value
        @test Int(written.y[]) > start[2]
        evaluate_operation(nothing, down)
        @test Int(_scroll_pane_viewport(shown_iomap).content.y) == -Int(written.y[])
    end
end
end
