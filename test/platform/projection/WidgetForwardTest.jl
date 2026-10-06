# A part of a widget maps forward to the node that draws it, and back again: the
# output reference reaches a printed node, and a point inside the box of that
# node maps back to the part, or to a part inside it. The references are read
# through the whole widget projection, a chain.
function test_widget_forward()
@testset "a part of a widget maps forward to the node that draws it" begin

_projection() = make_widget_projection_example(measure = FixedMeasure(10, 18, 6, 0))
_path(steps...) = extend_reference(EmptyReference(), steps...)
_at(i) = RangeReferenceStep(i - 1, i)
_value(v) = v isa Cell ? _value(v[]) : v

# The box of the node that `part` of `document` maps forward to, or `nothing`.
function _box(document, part)
    projection = _projection()
    iomap = print_document(projection, document)
    image = map_reference_forward(projection, iomap, annotate_reference_types(document, part))
    image === nothing && return nothing
    find_reference_box(_value(get_iomap_output(iomap)), image)
end

# Whether the point at the middle of the box of `part` maps back to `part` or to a
# part inside it.
function _returns(document, part)
    box = _box(document, part)
    box === nothing && return false
    projection = _projection()
    iomap = print_document(projection, document)
    point = PointReferenceStep(box.x + box.width ÷ 2, box.y + box.height ÷ 2)
    answer = map_reference_backward(projection, iomap, point)
    answer === nothing && return false
    answer = strip_reference_types(answer)
    answer == part || is_reference_prefix(part, answer)
end

@testset "a widget maps itself to the canvas it draws" begin
    button = WidgetButton("Go"; size = Point2D(80, 24))
    box = _box(button, EmptyReference())
    @test box !== nothing
    @test (box.width, box.height) == (80, 24)
end

@testset "a composite maps an element to the canvas of the element" begin
    composite = WidgetComposite(Any[WidgetButton("One"),
                                    WidgetButton("Two"; position = Point2D(0, 40))])
    @test _returns(composite, _path(FieldReferenceStep("elements"), _at(1)))
    @test _returns(composite, _path(FieldReferenceStep("elements"), _at(2)))
    @test _box(composite, _path(FieldReferenceStep("elements"), _at(2))).y == 40
end

@testset "a menu maps an item to its row" begin
    menu = WidgetMenu(Any[WidgetMenuItem("Alpha"), WidgetMenuItem("Beta"),
                          WidgetMenuItem("Gamma")]; orientation = :vertical)
    @test _returns(menu, _path(FieldReferenceStep("elements"), _at(2)))
    @test _returns(menu, _path(FieldReferenceStep("elements"), _at(3)))
end

@testset "a list maps an item to its row" begin
    list = WidgetList(Any["a", "b", "c", "d"])
    @test _returns(list, _path(FieldReferenceStep("items"), _at(1)))
    @test _returns(list, _path(FieldReferenceStep("items"), _at(2)))
end

@testset "a split pane maps into each pane" begin
    split = WidgetSplitPane(:horizontal, Any[WidgetLabel("left"),
                                             WidgetComposite(Any[WidgetButton("Go")])];
                            sizes = [300, 300])
    @test _returns(split, _path(FieldReferenceStep("elements"), _at(1)))
    @test _returns(split, _path(FieldReferenceStep("elements"), _at(2),
                                FieldReferenceStep("elements"), _at(1)))
end

@testset "a scroll pane maps into its content, also a part out of view" begin
    scroll = WidgetScrollPane(WidgetComposite(Any[WidgetLabel("Item $i"; position = Point2D(4, (i - 1) * 44))
                                                  for i in 1:40]))
    @test _returns(scroll, _path(FieldReferenceStep("content"), FieldReferenceStep("elements"), _at(2)))
    # A part below the view has an image too; its box is outside the view.
    far = _path(FieldReferenceStep("content"), FieldReferenceStep("elements"), _at(40))
    @test _box(scroll, far) !== nothing
end

@testset "a table maps a column header and a cell" begin
    table = WidgetTable(["Invoice", "Status"], [["INV001", "Paid"], ["INV002", "Pending"]])
    @test _returns(table, _path(FieldReferenceStep("column_headers"), _at(2)))
    @test _returns(table, _path(FieldReferenceStep("cells"), _at(1), _at(1)))
end

@testset "a tree maps a node to its row" begin
    tree = WidgetTree(Any[WidgetTreeNode(:folder, "src", Any[WidgetTreeNode(:file, "app.jl")]),
                          WidgetTreeNode(:file, "README.md")]; expanded = Set([[1]]))
    @test _returns(tree, _path(FieldReferenceStep("roots"), _at(1)))
    @test _returns(tree, _path(FieldReferenceStep("roots"), _at(1),
                               FieldReferenceStep("children"), _at(1)))
    # A node under a closed one has no row, and so no image.
    closed = WidgetTree(Any[WidgetTreeNode(:folder, "src", Any[WidgetTreeNode(:file, "app.jl")])])
    @test _box(closed, _path(FieldReferenceStep("roots"), _at(1),
                             FieldReferenceStep("children"), _at(1))) === nothing
end

@testset "an accordion maps an item to its header" begin
    accordion = WidgetAccordion([("First?", "Yes, first."), ("Second?", "No.")])
    @test _returns(accordion, _path(FieldReferenceStep("items"), _at(1)))
    @test _returns(accordion, _path(FieldReferenceStep("items"), _at(2)))
end

@testset "a tab that is not displayed has no image" begin
    # The first tab is open, because the pane selects no other.
    tabs = WidgetTabbedPane(Any[("One", WidgetButton("A")), ("Two", WidgetButton("B"))])
    page(i) = _path(FieldReferenceStep("selector_element_pairs"), _at(i), FieldReferenceStep("element"))
    @test _returns(tabs, page(1))
    projection = _projection()
    iomap = print_document(projection, tabs)
    closed = page(2)
    @test map_reference_forward(projection, iomap, annotate_reference_types(tabs, closed)) === nothing
end

end # @testset
end # test_widget_forward
