# A press that selects a document to show: the pane names the document by
# identity, selects it, and scrolls the least that brings it into view.

_scroll_show_projection() = RecursiveProjection(TypeDispatchingProjection(
    WidgetToGraphics(StyleFont("Ubuntu Mono", 20); measure = FixedMeasure(10, 18, 6, 0)).dispatch))

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
                                                   (_, _) -> SelectDocumentOperation(document);
                                                   description = "Go to the row", domain = "test")]
    far = WidgetLabel("Go to row 30"; gestures = link(rows[30]))
    near = WidgetLabel("Go to row 2"; gestures = link(rows[2]))
    pane = WidgetScrollPane(VerticalLayout(Any[far, near, rows...]); size = Point2D(300, 240))
    iomap = print_document(projection, pane)
    press(y) = read_intent(projection, iomap, MouseClick(:left, 5, y; time = 0.0))

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
end
end
