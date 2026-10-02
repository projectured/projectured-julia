# The acceptance test of the pane layout: start from one empty tab group and
# build a whole user interface with nothing but real gestures.
#
# One projection and **one iomap** serve the entire sequence, as a live editor
# would keep them: every structural edit has to reach the screen through the
# iomaps that are already standing, not through a fresh print. That is what makes
# this test catch what a direct read and a re-print both miss.
mutable struct _PaneConstructMockEditor
    document::Any
end

function test_pane_construct()
@testset "PaneTree built from empty" begin

_stub = FixedMeasure(10, 18, 6, 0)
WIDTH = 400
HEIGHT = 300

tree = PaneTree(PaneGroup(PaneTab[]))
editor = _PaneConstructMockEditor(tree)
projection = make_pane_projection_example(measure = _stub)
iomap = print_document(projection, nothing, tree,
                       PrinterContext(EmptyReference(), Cell(WIDTH), Cell(HEIGHT),
                                      Dict{Symbol,Any}()))

# One gesture, read through the standing iomap and applied.
function press!(event)
    operation = read_intent(projection, iomap, event)
    operation === nothing || evaluate_operation(editor, operation)
    operation
end

ctrl(key) = KeyDown(key, ModifierKeys(ctrl = true); time = 0.0)
ctrl_shift(key) = KeyDown(key, ModifierKeys(ctrl = true, shift = true); time = 0.0)
ctrl_alt(key) = KeyDown(key, ModifierKeys(ctrl = true, alt = true); time = 0.0)

# Rename whatever tab has the focus: into the name, clear it, type the new one.
function rename!(name)
    press!(KeyDown(:f2, ModifierKeys(); time = 0.0))
    focus = get_pane_focus_title(tree)
    focus === nothing && return false
    for _ in 1:length(get_pane_tab_title_string(focus[1].tabs[focus[2]]))
        press!(KeyDown(:backspace, ModifierKeys(); time = 0.0))
    end
    for c in name
        press!(KeyPress(c, ModifierKeys(); time = 0.0))
    end
    press!(KeyDown(:escape, ModifierKeys(); time = 0.0))
    true
end

# The shape of a rendered canvas, as a string. Two prints of the same tree must
# give the same shape — which is the whole point of a standing iomap.
function shape(node, depth = 0)
    depth > 8 && return "…"
    if node isa GraphicsCanvas
        return "C[" * join([shape(e, depth + 1) for e in node.elements], ",") * "]"
    elseif node isa GraphicsViewport
        return "V(" * shape(node.content, depth + 1) * ")"
    end
    string(nameof(typeof(node)))
end

# **The standing render must equal a fresh one.** A structural edit that only the
# document sees is the failure this catches: `WidgetSplitPane` fixes its slot
# count when it is printed, so a split has to re-print the pane widgets, and a
# test that asserts on the tree alone would never notice that it did not.
function assert_rendered!()
    fresh = print_document(make_pane_projection_example(measure = _stub), nothing, tree,
                           PrinterContext(EmptyReference(), Cell(WIDTH), Cell(HEIGHT),
                                          Dict{Symbol,Any}()))
    @test shape(iomap.output) == shape(fresh.output)
end

# A point inside a group, as a fraction of its own rectangle.
function point(group, u, v)
    r = get_pane_rectangle(tree, group)
    (round(Int, (r.x + u * r.w) * WIDTH), round(Int, (r.y + v * r.h) * HEIGHT))
end

# The tabbed pane a group printed, out of the standing iomap.
function widget_of(group)
    stage = getfield(iomap, :step_iomaps)[][1][]
    _walk(im) = begin
        im.input === group && return im.output
        hasproperty(im, :root_iomap) && return _walk(im.root_iomap)
        if hasproperty(im, :element_iomaps)
            for child in im.element_iomaps
                found = _walk(child)
                found === nothing || return found
            end
        end
        nothing
    end
    _walk(stage)
end

@testset "the empty start state" begin
    @test tree.root isa PaneGroup
    @test isempty(tree.root.tabs)
    @test get_pane_focus(tree) === nothing        # nothing is selected yet
end

@testset "the first focus comes from a gesture" begin
    press!(ctrl(:tab))
    @test get_pane_focus(tree) == (tree.root, 0)  # the empty group itself
end

first_group = tree.root

@testset "open the first tab and name it" begin
    press!(ctrl(:t))
    @test length(first_group.tabs) == 1
    @test rename!("a")
    @test get_pane_tab_title_string(first_group.tabs[1]) == "a"
end

@testset "split to the right and name that one" begin
    press!(ctrl(:backslash))
    @test tree.root isa PaneSplit
    @test tree.root.orientation === :vertical
    @test tree.root.elements[1] === first_group
    @test rename!("b")
    assert_rendered!()
end

second_group = tree.root.elements[2]

@testset "split the right pane downward" begin
    press!(ctrl_shift(:backslash))
    right = tree.root.elements[2]
    @test right isa PaneSplit
    @test right.orientation === :horizontal
    @test right.elements[1] === second_group
    @test rename!("d")
    assert_rendered!()
end

@testset "move back to the left pane and split it too" begin
    press!(ctrl_alt(:left))
    @test get_pane_focus(tree)[1] === first_group
    press!(ctrl_shift(:backslash))
    @test rename!("c")
    assert_rendered!()
end

@testset "four panes, four names, two by two" begin
    groups = get_pane_groups(tree)
    @test length(groups) == 4
    names = [get_pane_tab_title_string(g.tabs[1]) for g in groups]
    @test sort(names) == ["a", "b", "c", "d"]
    # The left column holds a over c, the right one b over d.
    left, right = tree.root.elements[1], tree.root.elements[2]
    @test left isa PaneSplit && left.orientation === :horizontal
    @test right isa PaneSplit && right.orientation === :horizontal
    @test get_pane_tab_title_string(left.elements[1].tabs[1]) == "a"
    @test get_pane_tab_title_string(left.elements[2].tabs[1]) == "c"
end

@testset "drag a tab from one group into another" begin
    left = tree.root.elements[1]
    source = left.elements[2]            # the group holding "c"
    target = tree.root.elements[2].elements[1]   # the one holding "b"
    moved = source.tabs[1]

    press!(DragTabOperation(widget_of(source), 1))
    @test tree.drag !== nothing
    x, y = point(target, 0.5, 0.5)
    # A grab that code makes starts at the first move with the button held; the
    # release comes as `DragEnd`, which the drag wrapper sends the tree, and then
    # as the release by position.
    press!(MouseMove(x, y, MouseButtons(:left), ModifierKeys(); time = 0.0))
    @test tree.drag.target === target
    press!(DragEnd(x, y; time = 0.0))
    press!(MouseUp(:left, x, y, ModifierKeys(); time = 0.0))

    @test tree.drag === nothing
    @test length(target.tabs) == 2
    @test target.tabs[2] === moved       # the same tab, moved
    # Its group had nothing else in it, so the group went away with it.
    @test tree.root.elements[1] === first_group
    @test length(get_pane_groups(tree)) == 3
    assert_rendered!()
end

@testset "close a group away" begin
    right = tree.root.elements[2]
    d_group = right.elements[2]
    @test get_pane_tab_title_string(d_group.tabs[1]) == "d"

    # Focus it by clicking inside it, then close the tab. The click lands in the
    # middle of the pane: the tree's rectangles are proportional and ignore the
    # few pixels a border and a splitter take, so an edge is not a place to aim.
    x, y = point(d_group, 0.5, 0.5)
    press!(MouseClick(:left, x, y, ModifierKeys(); time = 0.0))
    @test get_pane_focus(tree)[1] === d_group
    press!(ctrl(:w))

    @test length(get_pane_groups(tree)) == 2
    @test tree.root isa PaneSplit
    @test tree.root.elements[1] === first_group
    names = [get_pane_tab_title_string(t) for g in get_pane_groups(tree) for t in g.tabs]
    @test sort(names) == ["a", "b", "c"]
    assert_rendered!()
end

@testset "and it still renders" begin
    @test iomap.output isa GraphicsCanvas
    assert_rendered!()
    # The layout is two panes side by side, so a press in each half must land in
    # a different group.
    left_group, right_group = get_pane_groups(tree)
    lx, ly = point(left_group, 0.5, 0.5)
    press!(MouseClick(:left, lx, ly, ModifierKeys(); time = 0.0))
    @test get_pane_focus(tree)[1] === left_group
    rx, ry = point(right_group, 0.5, 0.5)
    press!(MouseClick(:left, rx, ry, ModifierKeys(); time = 0.0))
    @test get_pane_focus(tree)[1] === right_group
end

@testset "duplicate a tab with a press on its +" begin
    group = get_pane_groups(tree)[2]
    count = length(group.tabs)
    shown = get_pane_tab_title_string(group.tabs[1])
    # The first press in the group's strip that answers a duplicate: an insert
    # of one tab whose title carries a number.
    writes(op) = op isa CompoundOperation ? reduce(vcat, map(writes, op.operations); init = Any[]) :
                 op isa ReplaceReferencedValueOperation ? Any[op] : Any[]
    is_duplicate(op) = any(w -> w.value isa AbstractVector && length(w.value) == 1 &&
                                w.value[1] isa PaneTab &&
                                endswith(get_pane_tab_title_string(w.value[1]), " (2)"),
                           writes(op))
    r = get_pane_rectangle(tree, group)
    x0, y0 = round(Int, r.x * WIDTH), round(Int, r.y * HEIGHT)
    target = nothing
    for y in y0:2:(y0 + 40), x in x0:2:(x0 + 200)
        if is_duplicate(read_intent(projection, iomap, MouseClick(:left, x, y, ModifierKeys(); time = 0.0)))
            target = (x, y)
            break
        end
    end
    @test target !== nothing
    press!(MouseClick(:left, target[1], target[2], ModifierKeys(); time = 0.0))
    @test length(group.tabs) == count + 1
    @test get_pane_tab_title_string(group.tabs[2]) == shown * " (2)"
    @test get_pane_focus(tree) == (group, 2)
    assert_rendered!()
end

end # testset
end # function
