# A point of a layout maps back to the child drawn at it. The hit test is the one
# a pointer event takes (`_find_child_point`), so a point maps to the child that a
# click there reaches, and a chain carries the point back through its stages.
function test_layout_point()
@testset "a point of a layout maps back to the child drawn at it" begin

_projection() = make_widget_projection_example()
_path(steps...) = extend_reference(EmptyReference(), steps...)
_children(i) = (FieldReferenceStep("children"), RangeReferenceStep(i - 1, i))

# The point `(dx, dy)` inside the child of entry `i` of the layout's IO map, in the
# frame of the layout's canvas.
function _point_in_child(layout_iomap, i, dx, dy)
    (ox, oy, child) = getfield(layout_iomap, :child_iomaps)[][i]
    PointReferenceStep(Int(ox[]) + Int(child.output.x) + dx, Int(oy[]) + Int(child.output.y) + dy)
end

# The IO map of `layout` in the IO map tree of a print.
function _find_layout_iomap(iomap, layout, depth = 0)
    depth > 8 && return nothing
    get_iomap_input(iomap) === layout && iomap isa ChildrenIoMap && return iomap
    for field in fieldnames(typeof(iomap))
        value = getfield(iomap, field)
        value = value isa CellModule.Cell ? value[] : value
        for candidate in (value isa AbstractVector ? value : (value,))
            candidate = candidate isa CellModule.Cell ? candidate[] : candidate
            candidate isa IoMap || continue
            found = _find_layout_iomap(candidate, layout, depth + 1)
            found === nothing || return found
        end
    end
    nothing
end

@testset "a vertical layout maps a point to the child under it, through the chain" begin
    layout = VerticalLayout(Any[WidgetLabel("one"), WidgetLabel("two"), WidgetLabel("three")];
                            gap = 10)
    projection = _projection()
    iomap = print_document(projection, layout)
    inner = _find_layout_iomap(iomap, layout)
    point = _point_in_child(inner, 2, 3, 3)
    # The layout itself, and the whole chain above it, answer the same child.
    @test strip_reference_types(map_reference_backward(inner.projection, inner, point)) ==
          _path(_children(2)...)
    @test strip_reference_types(map_reference_backward(projection, iomap, point)) ==
          _path(_children(2)...)
    # A point where nothing is drawn maps to nothing.
    @test map_reference_backward(projection, iomap, PointReferenceStep(900, 900)) === nothing
end

@testset "a stack maps a point to its topmost child" begin
    stack = StackLayout(Any[WidgetLabel("P1"), WidgetLabel("P2")])   # both drawn at the origin
    projection = _projection()
    iomap = print_document(projection, stack)
    @test strip_reference_types(map_reference_backward(projection, iomap, PointReferenceStep(3, 3))) ==
          _path(_children(2)...)
end

end # @testset
end # test_layout_point
