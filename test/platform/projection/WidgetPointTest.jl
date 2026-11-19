# A point of a widget maps back to the part drawn at it: a container to its
# child, with the hit test of a pointer event, and a widget with parts to the part
# that a click there selects. The points are read through the whole widget
# projection, a chain.
function test_widget_point()
@testset "a point of a widget maps back to the part drawn at it" begin

_projection() = make_widget_projection_example(measure = FixedMeasure(10, 18, 6, 0))
_path(steps...) = extend_reference(EmptyReference(), steps...)
_at(i) = RangeReferenceStep(i - 1, i)

function _map(document, x, y)
    projection = _projection()
    iomap = print_document(projection, document)
    answer = map_reference_backward(projection, iomap, PointReferenceStep(x, y))
    answer === nothing ? nothing : strip_reference_types(answer)
end

@testset "a composite maps to the element under the point" begin
    composite = WidgetComposite(Any[WidgetButton("One"),
                                    WidgetButton("Two"; position = Point2D(0, 40))])
    @test _map(composite, 5, 5) == _path(FieldReferenceStep("elements"), _at(1))
    @test _map(composite, 5, 45) == _path(FieldReferenceStep("elements"), _at(2))
    @test _map(composite, 500, 500) === nothing
end

@testset "a menu maps to the item under the point" begin
    menu = WidgetMenu(Any[WidgetMenuItem("Alpha"), WidgetMenuItem("Beta"),
                          WidgetMenuItem("Gamma")]; orientation = :vertical)
    # The rows start 5 down, and each is 32 high: a line of 24 and the padding
    # of a command, 4 above and 4 below.
    @test _map(menu, 5, 50) == _path(FieldReferenceStep("elements"), _at(2))
    @test _map(menu, 5, 80) == _path(FieldReferenceStep("elements"), _at(3))
end

@testset "a list maps to the item of the row under the point" begin
    list = WidgetList(Any["a", "b", "c", "d"])
    @test _map(list, 5, 5) == _path(FieldReferenceStep("items"), _at(1))
    @test _map(list, 5, 45) == _path(FieldReferenceStep("items"), _at(2))
    @test _map(list, 5, 300) === nothing
end

@testset "a split pane maps into the pane under the point" begin
    split = WidgetSplitPane(:horizontal, Any[WidgetLabel("left"),
                                             WidgetComposite(Any[WidgetButton("Go")])];
                            sizes = [300, 300])
    # Each slot gives its slot padding, so what it holds stands that far inside
    # it, past the divider of the width of a border.
    theme = get_theme_defaults(WidgetTheme)
    left, top = Int(theme.slot_padding.left[]), Int(theme.slot_padding.top[])
    # The left pane is a label, so the point is on its text: the caret there.
    @test _map(split, left + 5, top + 5) ==
          _path(FieldReferenceStep("elements"), _at(1), FieldReferenceStep("content"), RangeReferenceStep(0, 0))
    @test _map(split, 300 + theme.border_width + left + 5, top + 5) ==
          _path(FieldReferenceStep("elements"), _at(2), FieldReferenceStep("elements"), _at(1))
end

@testset "a scroll pane maps into its content" begin
    scroll = WidgetScrollPane(WidgetComposite(Any[WidgetLabel("Item $i"; position = Point2D(4, (i - 1) * 44))
                                                  for i in 1:8]))
    # The point is on the text of the second label: the caret there.
    @test _map(scroll, 10, 50) ==
          _path(FieldReferenceStep("content"), FieldReferenceStep("elements"), _at(2),
                FieldReferenceStep("content"), RangeReferenceStep(1, 1))
end

@testset "a table maps to a column header or a cell" begin
    table = WidgetTable(["Invoice", "Status"], [["INV001", "Paid"], ["INV002", "Pending"]])
    @test _map(table, 100, 30) == _path(FieldReferenceStep("column_headers"), _at(2))
    @test _map(table, 5, 55) == _path(FieldReferenceStep("cells"), _at(1), _at(1))
end

@testset "a tree maps to the node of the row under the point" begin
    tree = WidgetTree(Any[WidgetTreeNode(:folder, "src", Any[WidgetTreeNode(:file, "app.jl")]),
                          WidgetTreeNode(:file, "README.md")]; expanded = Set([[1]]))
    @test _map(tree, 30, 5) == _path(FieldReferenceStep("roots"), _at(1))
    @test _map(tree, 30, 55) ==
          _path(FieldReferenceStep("roots"), _at(1), FieldReferenceStep("children"), _at(1))
end

@testset "a text maps to its content, at the point, as a path a layout can type" begin
    # A layout passes its child the point as a bare step; the text answers a
    # path that ends in the point, so the layout can put the node types on it.
    answer = _map(VerticalLayout(Any[WidgetText("hello")]), 3, 3)
    steps = collect(get_reference_steps(answer))
    @test steps[1:3] == [FieldReferenceStep("children"), _at(1), FieldReferenceStep("content")]
    @test last(steps) isa PointReferenceStep
end

@testset "an accordion maps a header to its item" begin
    accordion = WidgetAccordion([("First?", "Yes, first."), ("Second?", "No.")])
    @test _map(accordion, 10, 5) == _path(FieldReferenceStep("items"), _at(1))
    @test _map(accordion, 10, 90) == _path(FieldReferenceStep("items"), _at(2))
end

# The titles and the open body of an accordion are texts that it draws. An Alt+click
# on a title puts the caret there, and a plain click on it opens or closes its item,
# because the header is a control. A point on the open body is the caret there, and
# the caret maps forward to its line.
@testset "the texts of an accordion take the caret, and a header keeps its click" begin
    accordion = WidgetAccordion([("First?", "Yes, first."), ("Second?", "No.")])
    projection = _projection()
    iomap = print_document(projection, accordion)
    texts = _collect_task_view_texts(get_iomap_output(iomap))
    title = only(t for t in texts if t[3] == "First?")
    body = only(t for t in texts if t[3] == "Yes, first.")
    item(field) = [FieldReferenceStep("items"), _at(1), FieldReferenceStep(field)]
    steps(path) = collect(get_reference_steps(strip_reference_types(path)))
    click(t, modifiers) =
        read_intent(projection, iomap, MouseClick(:left, t[1] + 2, t[2] + 2, 1, modifiers; time = 0.0))
    alt = click(title, ModifierKeys(alt = true))
    @test alt isa ReplaceSelectionOperation && steps(alt.path)[1:3] == item("title")
    @test !(click(title, ModifierKeys()) isa ReplaceSelectionOperation)
    caret = _map(accordion, body[1] + 2, body[2] + 2)
    @test steps(caret)[1:3] == item("body") && last(steps(caret)) isa RangeReferenceStep
    @test map_reference_forward(projection, iomap, annotate_reference_types(accordion, caret)) !== nothing
    # The title selected as a whole has a band behind it, at the place of the title
    # in its header.
    function rects(node, x = 0, y = 0, found = Tuple{Int,Int,Int,Int}[])
        node = unwrap_cell(node)
        if node isa GraphicsCanvas
            for element in node.elements
                rects(element, x + Int(node.x), y + Int(node.y), found)
            end
        elseif node isa GraphicsViewport
            rects(node.content, x + Int(node.x), y + Int(node.y), found)
        elseif node isa GraphicsRect
            push!(found, (x + Int(node.x), y + Int(node.y), Int(node.w), Int(node.h)))
        end
        found
    end
    before = rects(get_iomap_output(iomap))
    replace_selection!(accordion, annotate_reference_types(accordion, extend_reference(EmptyReference(), item("title")...)))
    added = setdiff(rects(get_iomap_output(iomap)), before)
    @test any(r -> r[1] <= title[1] + 2 < r[1] + r[3] && r[2] <= title[2] + 2 < r[2] + r[4], added)
    replace_selection!(accordion, nothing)
end

# A move names the part under the pointer (`compute_part_at_point`). A separator
# draws no part of its own, so a point on its rule names the separator as a whole,
# and no point in its drawing.
@testset "a move on the rule of a separator names the separator" begin
    projection = _projection()
    iomap = print_document(projection, WidgetSeparator(; length = 260))
    rule = last([e for e in get_iomap_output(iomap).elements if e isa GraphicsRect])
    part = compute_part_at_point(iomap, Int(rule.x) + 100, Int(rule.y))
    @test strip_reference_types(part) == EmptyReference()
end

# A canvas passes a point through: its backward map answers the point step
# itself. A tabbed pane whose open page is a canvas maps a point in the page to
# that point in the page, and a layout maps a point in a canvas child the same.
@testset "a point in a canvas page or child maps to the point in the canvas" begin
    canvas() = GraphicsCanvas(Any[GraphicsRect(0, 0, 120, 40), GraphicsRect(0, 60, 120, 40)]; w = 120, h = 100)
    ends_in_point(answer, head) = answer !== nothing && last(collect(get_reference_steps(answer))) isa PointReferenceStep &&
                                  first(collect(get_reference_steps(answer))) == head
    # The natural renderer draws a canvas, as the editor does; the widget
    # projection of `_map` has no row for it.
    natural = NaturalToGraphics(; measure = FixedMeasure(10, 18, 6, 0))
    function map_natural(document, x, y)
        iomap = print_document(natural, document)
        answer = map_reference_backward(natural, iomap, PointReferenceStep(x, y))
        answer === nothing ? nothing : strip_reference_types(answer)
    end
    answers = [map_natural(WidgetTabbedPane(Any[("One", canvas())]), 30, y) for y in 0:5:160]
    @test any(answer -> ends_in_point(answer, FieldReferenceStep("selector_element_pairs")), answers)
    layout = VerticalLayout(Any[WidgetLabel("above"), canvas()])
    answers = [map_natural(layout, 30, y) for y in 0:5:160]
    @test any(answer -> ends_in_point(answer, FieldReferenceStep("children")), answers)
end

end # @testset
end # test_widget_point
