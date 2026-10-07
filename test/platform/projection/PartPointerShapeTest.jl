# The parts that a press acts on draw a region of the pointer shape, and the
# region and the reader of a part keep one rule: each test sweeps the points of a
# part, and at each point the pointer shows the shape of the part exactly where a
# press reaches it.

const _POINTER_PART_MODIFIERS = ModifierKeys()
const _POINTER_PART_MEASURE = FixedMeasure(10, 18, 6, 0)

# Whether `operation` holds an operation of type `type`, in a compound operation or
# inside a view state mark.
_holds_pointer_part_operation(operation, type::Type) =
    operation isa type ||
    (operation isa CompoundOperation &&
     any(member -> _holds_pointer_part_operation(member, type), operation.operations)) ||
    (operation isa WrappingOperation &&
     _holds_pointer_part_operation(get_wrapped_operation(operation), type))

# The answer of a projection to a gesture, as an operation.
function _read_pointer_part(projection, iomap, gesture)
    change = read_intent(projection, nothing, Intent(gesture, nothing), iomap)
    change isa Intent ? change.operation : change
end

# The absolute place of the text `label` that `node` draws, through canvases,
# viewports and lists.
function _find_pointer_part_text(node, label, x = 0, y = 0)
    if node isa GraphicsText
        return string(node.text) == label ? (x + Int(node.x), y + Int(node.y)) : nothing
    elseif node isa GraphicsViewport
        content = node.content
        return _find_pointer_part_text(content, label, x + Int(node.x), y + Int(node.y))
    elseif node isa GraphicsCanvas
        x, y = x + Int(node.x), y + Int(node.y)
        elements = node.elements
        values = elements isa ListNode ? (n.value for n in _walk_pointer_part_list(elements)) : elements
        for element in values
            found = _find_pointer_part_text(element, label, x, y)
            found === nothing || return found
        end
    end
    nothing
end

# The nodes of a list from its head, at most 50.
function _walk_pointer_part_list(head::ListNode)
    nodes = ListNode[]
    node = head
    while node !== nothing && length(nodes) < 50
        push!(nodes, node)
        node = node.next
    end
    nodes
end

# A list of the values `values` from its head.
function _make_pointer_part_list(values)
    head = ListNode(first(values))
    foreach(value -> push!(head, value), values[2:end])
    head
end

# A tab click: a selection of a tab of the pane, and of nothing in it.
_is_pointer_part_tab_click(operation) =
    operation isa ReplaceSelectionOperation && (path = operation.path;
        path isa ConcreteReference && path.head == FieldReferenceStep("selector_element_pairs") &&
        path.tail isa ConcreteReference && path.tail.tail isa EmptyReference)

function test_part_pointer_shape()
@testset "the pointer shows what a press on a part does" begin

    widgets = make_widget_projection_example(measure = _POINTER_PART_MEASURE)
    down(x, y) = MouseDown(:left, x, y, _POINTER_PART_MODIFIERS; time = 0.0)
    click(x, y) = MouseClick(:left, x, y, _POINTER_PART_MODIFIERS; time = 0.0)

    @testset "the divider of a split pane is a double arrow where a press grabs it" begin
        document = make_widget_split_pane_document_example()
        iomap = print_document(widgets, document)
        xs = 280:320
        shapes = [find_pointer_shape(iomap.output, x, 50) for x in xs]
        grabs = [_holds_pointer_part_operation(read_intent(widgets, iomap, down(x, 50)),
                                               StartDragOperation) for x in xs]
        @test count(grabs) > 0
        @test (shapes .=== :double_arrow_horizontal) == grabs
    end

    @testset "the edge of a column is a double arrow where a press starts its drag" begin
        tables = RecursiveProjection(TypeDispatchingProjection(vcat(
            LayoutToGraphics().dispatch,
            WidgetToGraphics(StyleFont("Ubuntu", 20); measure = FixedMeasure(8, 12, 4, 0)).dispatch)))
        context = with_exact_size(PrinterContext(); width = Cell(Int32(600)), height = Cell(Int32(300)))
        rows = _make_pointer_part_list([make_widget_table_row(Any["row $(i)", string(i)]) for i in 1:5])
        vector_columns = WidgetTable(; column_headers = Any["name", "value"], cells = rows,
                                       columns = Any[WidgetTableColumn(; policy = Fixed(120)),
                                                     WidgetTableColumn(; policy = Fixed(80))])
        headers = _make_pointer_part_list(Any[WidgetLabel("h$(c)") for c in 1:5])
        cells = _make_pointer_part_list(Any[_make_pointer_part_list(Any[WidgetLabel("r$(i) c$(c)")
                                                                       for c in 1:5]) for i in 1:3])
        listed_columns = WidgetTable(; column_headers = headers, cells,
                                       column_policy = Fixed(60), row_policy = Fixed(16))
        for (table, label, edges) in ((vector_columns, "name", 2), (listed_columns, "h1", 5))
            iomap = print_document(tables, nothing, table, context)
            _, y = _find_pointer_part_text(iomap.output, label)
            xs = 0:500
            shapes = [find_pointer_shape(iomap.output, x, y + 2) for x in xs]
            grabs = [_holds_pointer_part_operation(_read_pointer_part(tables, iomap, down(x, y + 2)),
                                                   StartDragOperation) for x in xs]
            @test count(grabs) == 7 * edges
            @test (shapes .=== :double_arrow_horizontal) == grabs
            # The cells under the header are no edge.
            @test !any(x -> find_pointer_shape(iomap.output, x, y + 60) === :double_arrow_horizontal, xs)
        end
    end

    @testset "a text field and a text area are an I-beam where a press puts the caret" begin
        for (enabled, field) in ((true, WidgetText("hello"; width = 100)),
                                 (false, WidgetText("hello"; width = 100, enabled = false)),
                                 (true, WidgetTextarea("hello"; width = 100)),
                                 (false, WidgetTextarea("hello"; width = 100, enabled = false)))
            iomap = print_document(widgets, field)
            points = [(x, y) for x in -4:4:140 for y in -4:4:120]
            shapes = [find_pointer_shape(iomap.output, x, y) for (x, y) in points]
            carets = [_read_pointer_part(widgets, iomap, click(x, y)) isa ReplaceSelectionOperation
                      for (x, y) in points]
            @test (count(carets) > 0) == enabled
            @test (shapes .=== :ibeam) == carets
        end
    end

    @testset "a text is an I-beam over its box, where a click puts the caret" begin
        # A text answers a click at any point with the nearest caret; the
        # container that holds it gives it only the clicks in its box.
        text = TextBlock(TextString("hello world", StyleFont("Ubuntu Mono", 20), color_black))
        projection = TextToGraphics(measure = _POINTER_PART_MEASURE)
        iomap = print_document(projection, text)
        width, height = Int(iomap.output.w), Int(iomap.output.h)
        @test width > 0 && height > 0
        points = [(x, y) for x in -5:5:150 for y in -5:5:40]
        inside = [0 <= x < width && 0 <= y < height for (x, y) in points]
        shapes = [find_pointer_shape(iomap.output, x, y) for (x, y) in points]
        @test (shapes .=== :ibeam) == inside
        @test all(read_intent(projection, iomap, click(x, y)) isa ReplaceSelectionOperation
                  for (x, y) in points[inside])
    end

    @testset "a span that names a pointer shape has it over its text, and the I-beam elsewhere" begin
        font = StyleFont("Ubuntu Mono", 20)
        text = TextBlock(TextString("see ", font, color_black),
                         TextString("link", StyleText(font, color_black), :pointing_hand),
                         TextString(" here", font, color_black))
        iomap = print_document(TextToGraphics(measure = _POINTER_PART_MEASURE), text)
        segment = only(s for s in iomap.char_to_coord if s.text == "link")
        @test find_pointer_shape(iomap.output, segment.x + 1, segment.y + 1) === :pointing_hand
        @test find_pointer_shape(iomap.output, segment.x + segment.width - 1, segment.y + 1) === :pointing_hand
        @test find_pointer_shape(iomap.output, segment.x - 2, segment.y + 1) === :ibeam
        @test find_pointer_shape(iomap.output, segment.x + segment.width + 2, segment.y + 1) === :ibeam
    end

    @testset "a button is a pointing hand where a click runs its action" begin
        for (enabled, button) in ((true, WidgetButton("Go"; size = Point2D(120, 40), action = _ -> nothing)),
                                  (false, WidgetButton("Go"; size = Point2D(120, 40), action = _ -> nothing,
                                                       enabled = false)))
            iomap = print_document(widgets, button)
            points = [(x, y) for x in -4:4:140 for y in -4:4:60]
            shapes = [find_pointer_shape(iomap.output, x, y) for (x, y) in points]
            actions = [_read_pointer_part(widgets, iomap, click(x, y)) isa InvokeActionOperation
                       for (x, y) in points]
            @test (count(actions) > 0) == enabled
            @test (shapes .=== :pointing_hand) == actions
        end
    end

    @testset "a tab is a pointing hand, and an open hand where a press grabs it" begin
        for draggable in (false, true)
            pane = WidgetTabbedPane(Any[("one", WidgetLabel("1")), ("two", WidgetLabel("2"))];
                                    closable = true, new_tab = true, draggable)
            iomap = print_document(widgets, pane)
            points = [(x, y) for x in 0:2:300 for y in 0:2:40]
            shapes = [find_pointer_shape(iomap.output, x, y) for (x, y) in points]
            clicks = [_read_pointer_part(widgets, iomap, click(x, y)) for (x, y) in points]
            downs = [_read_pointer_part(widgets, iomap, down(x, y)) for (x, y) in points]
            buttons = [operation isa Union{CloseTabOperation, OpenTabOperation, DuplicateTabOperation}
                       for operation in clicks]
            tabs = _is_pointer_part_tab_click.(clicks) .& .!buttons
            @test count(buttons) > 0 && count(tabs) > 0
            if draggable
                @test (shapes .=== :open_hand) == [operation isa DragTabOperation for operation in downs]
                @test (shapes .=== :pointing_hand) == buttons
            else
                @test (shapes .=== :pointing_hand) == (tabs .| buttons)
            end
        end
    end
end
end
