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
    @test _map(menu, 5, 30) == _path(FieldReferenceStep("elements"), _at(2))
    @test _map(menu, 5, 60) == _path(FieldReferenceStep("elements"), _at(3))
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
    @test _map(split, 5, 5) == _path(FieldReferenceStep("elements"), _at(1))
    @test _map(split, 305, 5) ==
          _path(FieldReferenceStep("elements"), _at(2), FieldReferenceStep("elements"), _at(1))
end

@testset "a scroll pane maps into its content" begin
    scroll = WidgetScrollPane(WidgetComposite(Any[WidgetLabel("Item $i"; position = Point2D(4, (i - 1) * 44))
                                                  for i in 1:8]))
    @test _map(scroll, 10, 50) ==
          _path(FieldReferenceStep("content"), FieldReferenceStep("elements"), _at(2))
end

@testset "a table maps to a column header or a cell" begin
    table = WidgetTable(["Invoice", "Status"], [["INV001", "Paid"], ["INV002", "Pending"]])
    @test _map(table, 100, 30) == _path(FieldReferenceStep("column_headers"), _at(2))
    @test _map(table, 5, 55) == _path(FieldReferenceStep("rows"), _at(1), _at(1))
end

@testset "a tree maps to the node of the row under the point" begin
    tree = WidgetTree(Any[WidgetTreeNode(:folder, "src", Any[WidgetTreeNode(:file, "app.jl")]),
                          WidgetTreeNode(:file, "README.md")]; expanded = Set([[1]]))
    @test _map(tree, 30, 5) == _path(FieldReferenceStep("roots"), _at(1))
    @test _map(tree, 30, 55) ==
          _path(FieldReferenceStep("roots"), _at(1), FieldReferenceStep("children"), _at(1))
end

@testset "an accordion maps a header to its item" begin
    accordion = WidgetAccordion([("First?", "Yes, first."), ("Second?", "No.")])
    @test _map(accordion, 10, 5) == _path(FieldReferenceStep("items"), _at(1))
    @test _map(accordion, 10, 90) == _path(FieldReferenceStep("items"), _at(2))
end

end # @testset
end # test_widget_point
