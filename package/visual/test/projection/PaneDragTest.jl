# Drag and drop: the grab, the pointer, and what a release does.
#
# The pointer is resolved against the layout tree, so these tests state the
# window size the layout was given and then press real coordinates in it.
mutable struct _PaneDragMockEditor
    document::Any
end

function test_pane_drag()
@testset "PaneTree drag and drop" begin

_stub(t, f) = (max(1, length(t)) * 10, 24)
_tab(name) = PaneTab(name, WidgetLabel(Point2D(0, 0), name))

WIDTH = 400
HEIGHT = 300

# Print the tree into a window of a stated size, which is what the drag resolves
# the pointer against.
function _print(tree)
    proj = make_pane_projection_example(measure = _stub)
    context = PrinterContext(EmptyReference(), Cell(WIDTH), Cell(HEIGHT),
                             Dict{Symbol,Any}())
    (proj, print_document(proj, nothing, tree, context))
end

function _feed!(editor, proj, iomap, event)
    op = read_intent(proj, iomap, event)
    op === nothing || evaluate_operation(editor, op)
    op
end

# Two groups side by side: the left one holds two tabs, the right one holds one.
function _two_groups()
    left = PaneGroup(PaneTab[_tab("a"), _tab("b")])
    right = PaneGroup(PaneTab[_tab("c")])
    tree = PaneTree(PaneSplit(:vertical, [left, right]))
    (tree, left, right, _PaneDragMockEditor(tree))
end

# A point inside a group, given where in its rectangle to land (0..1 each way).
function _point(tree, group, u, v)
    r = pane_rectangle(tree, group)
    (round(Int, (r.x + u * r.w) * WIDTH), round(Int, (r.y + v * r.h) * HEIGHT))
end

# Start a drag of `index` from `group` and answer the printed pair.
function _grab!(editor, tree, group, index)
    proj, iomap = _print(tree)
    _feed!(editor, proj, iomap, DragTabOperation(_group_widget(iomap, group), index))
    (proj, iomap)
end

# The tabbed pane a group printed — read out of *this* print, because the report
# names its widget by identity.
_group_widget(chain_iomap, group) =
    _walk_widget(getfield(chain_iomap, :step_iomaps)[][1][], group)

function _walk_widget(iomap, group)
    iomap.input === group && return iomap.output
    if hasproperty(iomap, :root_iomap)
        return _walk_widget(iomap.root_iomap, group)
    elseif hasproperty(iomap, :element_iomaps)
        for child in iomap.element_iomaps
            found = _walk_widget(child, group)
            found === nothing || return found
        end
    end
    nothing
end

@testset "a grab records where the tab came from" begin
    tree, left, right, editor = _two_groups()
    proj, iomap = _print(tree)
    stranger = WidgetTabbedPane(Any[("x", WidgetLabel(Point2D(0, 0), "x"))])
    _feed!(editor, proj, iomap, DragTabOperation(stranger, 1))   # not ours
    @test tree.drag === nothing

    # The strip reports the grab; feed the report the widget would have made.
    _feed!(editor, proj, iomap, DragTabOperation(_group_widget(iomap, left), 2))
    @test tree.drag !== nothing
    @test tree.drag.group === left
    @test tree.drag.index == 2
    @test tree.drag.target === nothing
end

@testset "the pointer names the group and the zone it is over" begin
    tree, left, right, editor = _two_groups()
    proj, iomap = _grab!(editor, tree, left, 1)

    x, y = _point(tree, right, 0.5, 0.5)
    _feed!(editor, proj, iomap, MouseMove(x, y, :left, ModifierKeys()))
    @test tree.drag.target === right
    @test tree.drag.zone === :center

    x, y = _point(tree, right, 0.95, 0.5)
    _feed!(editor, proj, iomap, MouseMove(x, y, :left, ModifierKeys()))
    @test tree.drag.zone === :right

    x, y = _point(tree, right, 0.5, 0.95)
    _feed!(editor, proj, iomap, MouseMove(x, y, :left, ModifierKeys()))
    @test tree.drag.zone === :below

    # The strip runs across the top of a group, and a drop there means "into it".
    x, y = _point(tree, right, 0.5, 0.0)
    _feed!(editor, proj, iomap, MouseMove(x, y, :left, ModifierKeys()))
    @test tree.drag.zone === :strip
end

@testset "a drop in the middle moves the tab into that group" begin
    tree, left, right, editor = _two_groups()
    moved = left.tabs[1]
    proj, iomap = _grab!(editor, tree, left, 1)

    x, y = _point(tree, right, 0.5, 0.5)
    _feed!(editor, proj, iomap, MouseMove(x, y, :left, ModifierKeys()))
    _feed!(editor, proj, iomap, MouseUp(:left, x, y, ModifierKeys()))

    @test tree.drag === nothing
    @test length(left.tabs) == 1
    @test length(right.tabs) == 2
    @test right.tabs[2] === moved              # the same object moved
    @test pane_focus(tree) == (right, 2)
end

@testset "a drop on an edge band splits the landing group" begin
    tree, left, right, editor = _two_groups()
    moved = left.tabs[1]
    proj, iomap = _grab!(editor, tree, left, 1)

    x, y = _point(tree, right, 0.5, 0.95)
    _feed!(editor, proj, iomap, MouseMove(x, y, :left, ModifierKeys()))
    _feed!(editor, proj, iomap, MouseUp(:left, x, y, ModifierKeys()))

    @test tree.drag === nothing
    inner = tree.root.elements[2]
    @test inner isa PaneSplit
    @test inner.orientation === :horizontal    # dropped below
    @test inner.elements[1] === right          # the landing group is reused
    new_group = inner.elements[2]
    @test new_group.tabs[1] === moved
    @test length(left.tabs) == 1
    @test pane_focus(tree) == (new_group, 1)
end

@testset "a drop on a side band splits the other way" begin
    tree, left, right, editor = _two_groups()
    proj, iomap = _grab!(editor, tree, left, 1)
    x, y = _point(tree, right, 0.03, 0.5)
    _feed!(editor, proj, iomap, MouseMove(x, y, :left, ModifierKeys()))
    _feed!(editor, proj, iomap, MouseUp(:left, x, y, ModifierKeys()))
    inner = tree.root.elements[2]
    @test inner.orientation === :vertical
    @test inner.elements[2] === right           # dropped on the left, so it is second
end

@testset "a drop that would empty its group is declined" begin
    # The split-drop needs the source to keep a tab; the move-drop handles the
    # collapse instead. See the builder's docstring.
    tree, left, right, editor = _two_groups()
    proj, iomap = _grab!(editor, tree, right, 1)
    x, y = _point(tree, left, 0.5, 0.95)
    _feed!(editor, proj, iomap, MouseMove(x, y, :left, ModifierKeys()))
    _feed!(editor, proj, iomap, MouseUp(:left, x, y, ModifierKeys()))
    @test tree.drag === nothing                 # the drag ends either way
    @test length(right.tabs) == 1               # and nothing moved
    @test tree.root.elements[1] === left
end

@testset "a drop back on its own group does nothing" begin
    tree, left, right, editor = _two_groups()
    proj, iomap = _grab!(editor, tree, left, 1)
    x, y = _point(tree, left, 0.5, 0.5)
    _feed!(editor, proj, iomap, MouseMove(x, y, :left, ModifierKeys()))
    _feed!(editor, proj, iomap, MouseUp(:left, x, y, ModifierKeys()))
    @test tree.drag === nothing
    @test length(left.tabs) == 2
end

@testset "a release outside every pane just ends the drag" begin
    tree, left, right, editor = _two_groups()
    proj, iomap = _grab!(editor, tree, left, 1)
    _feed!(editor, proj, iomap, MouseMove(10_000, 10_000, :left, ModifierKeys()))
    @test tree.drag.target === nothing
    _feed!(editor, proj, iomap, MouseUp(:left, 10_000, 10_000, ModifierKeys()))
    @test tree.drag === nothing
    @test length(left.tabs) == 2
end

@testset "the emptied group goes away with the tab that left it" begin
    left = PaneGroup(PaneTab[_tab("only")])
    right = PaneGroup(PaneTab[_tab("c")])
    tree = PaneTree(PaneSplit(:vertical, [left, right]))
    editor = _PaneDragMockEditor(tree)
    moved = left.tabs[1]
    proj, iomap = _grab!(editor, tree, left, 1)

    x, y = _point(tree, right, 0.5, 0.5)
    _feed!(editor, proj, iomap, MouseMove(x, y, :left, ModifierKeys()))
    _feed!(editor, proj, iomap, MouseUp(:left, x, y, ModifierKeys()))

    @test tree.root === right                   # the split collapsed into it
    @test length(right.tabs) == 2
    @test right.tabs[2] === moved
end

end # testset
end # function
