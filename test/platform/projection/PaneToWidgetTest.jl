# PaneTree → widgets: the shape the printer builds, the orientation translation,
# the weights, and the reference mapping in both directions.
mutable struct _PaneWidgetMockEditor
    document::Any
end

function test_pane_to_widget()
@testset "PaneToWidget" begin

_stub = FixedMeasure(10, 18, 6, 0)
_tab(name) = PaneTab(name, WidgetLabel(name))
_pane_stage() = RecursiveProjection(PaneToWidget())
# The pane tree prints as an overlay composite: the layout in slot 1, the drop
# indicator in slot 2. Slot 1 is what these tests are about.
_layout(iomap) = iomap.output.elements[1]
_indicator(iomap) = iomap.output.elements[2]
# The whole chain: pane nodes become widgets, then widgets become graphics. A
# tab's content passes through the first stage untouched, which is what lets a
# tab hold a document of any domain.
_chain() = ChainingProjection(_pane_stage(), make_widget_projection_example(measure = _stub))

function _apply!(editor, op)
    op === nothing && return nothing
    evaluate_operation(editor, op)
    op
end

@testset "a group prints a tabbed pane that offers the whole vocabulary" begin
    group = PaneGroup(PaneTab[_tab("a"), _tab("b")])
    tree = PaneTree(group)
    iomap = print_document(_pane_stage(), tree)
    pane = _layout(iomap)
    @test pane isa WidgetTabbedPane
    @test length(pane.selector_element_pairs) == 2
    @test [string(p.selector.text) for p in pane.selector_element_pairs] == ["a", "b"]
    @test pane.closable === true
    @test pane.new_tab === true
    @test pane.draggable === true
end

@testset "an empty group prints an empty strip" begin
    tree = PaneTree(PaneGroup(PaneTab[]))
    iomap = print_document(_pane_stage(), tree)
    @test _layout(iomap) isa WidgetTabbedPane
    @test isempty(_layout(iomap).selector_element_pairs)
    # The strip still offers its new-tab button, which is the only way out of
    # the empty start state.
    @test _layout(iomap).new_tab === true
end

@testset "the two orientation vocabularies are translated" begin
    left, right = PaneGroup(PaneTab[_tab("l")]), PaneGroup(PaneTab[_tab("r")])
    # A vertical split has a vertical divider, so its children sit side by side —
    # which the widget calls a horizontal layout.
    vertical = PaneTree(PaneSplit(:vertical, [left, right]))
    @test _layout(print_document(_pane_stage(), vertical)).orientation === :horizontal

    top, bottom = PaneGroup(PaneTab[_tab("t")]), PaneGroup(PaneTab[_tab("b")])
    horizontal = PaneTree(PaneSplit(:horizontal, [top, bottom]))
    @test _layout(print_document(_pane_stage(), horizontal)).orientation === :vertical
end

@testset "weights become the slots' layout weights" begin
    left, right = PaneGroup(PaneTab[_tab("l")]), PaneGroup(PaneTab[_tab("r")])
    tree = PaneTree(PaneSplit(:vertical, [left, right]; weights = [0.25, 0.75]))
    pane = _layout(print_document(_pane_stage(), tree))
    @test length(pane.elements) == 2
    @test all(e -> e isa LayoutConstraint, [pane.elements[i] for i in 1:2])
    @test [pane.elements[i].weight_width for i in 1:2] == [0.25, 0.75]
    # The children keep their own widgets under the constraint wrapper.
    @test pane.elements[1].child isa WidgetTabbedPane

    # A stacked split carries its weights on the other axis.
    stacked = PaneTree(PaneSplit(:horizontal, [PaneGroup(PaneTab[_tab("t")]),
                                               PaneGroup(PaneTab[_tab("b")])]))
    stacked_pane = _layout(print_document(_pane_stage(), stacked))
    @test [stacked_pane.elements[i].weight_height for i in 1:2] == [0.5, 0.5]
    @test stacked_pane.elements[1].weight_width === nothing
end

@testset "the selection is forwarded onto the widgets" begin
    group = PaneGroup(PaneTab[_tab("a"), _tab("b")])
    tree = PaneTree(group)
    editor = _PaneWidgetMockEditor(tree)
    iomap = print_document(_pane_stage(), tree)
    pane = _layout(iomap)
    @test get_selection(pane) === nothing

    _apply!(editor, make_pane_focus_operation(tree, group, 2))
    forwarded = get_selection(pane)
    @test forwarded !== nothing
    # The tabbed pane reads the index alone, so that is all that is forwarded.
    @test forwarded.head isa FieldReferenceStep
    @test forwarded.head.name == "selector_element_pairs"
    @test forwarded.tail.head.start == 1        # 0-based: the second tab
end

@testset "a split forwards which slot holds the focus" begin
    left = PaneGroup(PaneTab[_tab("l")])
    right = PaneGroup(PaneTab[_tab("r")])
    tree = PaneTree(PaneSplit(:vertical, [left, right]))
    editor = _PaneWidgetMockEditor(tree)
    iomap = print_document(_pane_stage(), tree)
    split_pane = _layout(iomap)

    _apply!(editor, make_pane_focus_operation(tree, right, 1))
    forwarded = get_selection(split_pane)
    @test forwarded.head.name == "elements"
    @test forwarded.tail.head.start == 1        # the second slot
end

@testset "a reference maps forward and back again" begin
    left = PaneGroup(PaneTab[_tab("l1"), _tab("l2")])
    right = PaneGroup(PaneTab[_tab("r")])
    tree = PaneTree(PaneSplit(:vertical, [left, right]))
    iomap = print_document(_pane_stage(), tree)

    for (group, index) in ((left, 1), (left, 2), (right, 1))
        reference = get_pane_tab_reference(tree, group, index)
        image = map_reference_forward(iomap.projection, iomap, reference)
        @test image !== nothing
        @test map_reference_backward(iomap.projection, iomap, image) == reference
    end
end

@testset "a bare tab-strip reference names the tab" begin
    group = PaneGroup(PaneTab[_tab("a"), _tab("b")])
    tree = PaneTree(group)
    iomap = print_document(_pane_stage(), tree)
    # What a tab click produces at the widget layer: the pair index and nothing
    # more. It must name the tab, not fail for want of a suffix.
    click = @reference ::WidgetComposite.elements::CellVector[1]::WidgetTabbedPane.selector_element_pairs::CellVector[2]::WidgetDocument
    @test map_reference_backward(iomap.projection, iomap, click) ==
          get_pane_tab_reference(tree, group, 2)
end

@testset "a reference inside a tab's content maps into the content" begin
    # The tab holds a document of another domain, and a caret in it is a path
    # through `tabs[i].content`. An answer truncated to the tab is what leaves a
    # form field in a pane with no caret and the next key with nowhere to go.
    group = PaneGroup(PaneTab[PaneTab("a", PrimitiveString("hello"))])
    tree = PaneTree(group)
    iomap = print_document(_pane_stage(), tree)
    caret = @reference ::PaneTree.root::PaneGroup.tabs::CellVector[1]::PaneTab.content::PrimitiveString.value::String{2}::Position
    image = map_reference_forward(iomap.projection, iomap, caret)
    @test image !== nothing
    @test map_reference_backward(iomap.projection, iomap, image) == caret
end

@testset "the layout carries a drop indicator, invisible until a drag" begin
    tree = PaneTree(PaneGroup(PaneTab[_tab("a")]))
    iomap = print_document(_pane_stage(), tree)
    @test iomap.output isa WidgetComposite
    @test length(iomap.output.elements) == 2
    # It is always in the tree — only its `visible` moves — so the widget tree
    # keeps its shape whether a tab is held or not.
    @test _indicator(iomap).visible === false
end

@testset "the whole chain renders to a canvas" begin
    left = PaneGroup(PaneTab[_tab("l")])
    right = PaneGroup(PaneTab[_tab("r")])
    tree = PaneTree(PaneSplit(:vertical, [left, right]))
    iomap = print_document(_chain(), tree)
    @test iomap.output isa GraphicsCanvas
    @test get_graphics_size(iomap.output)[1] > 0
end

# Every rectangle of a render, in the coordinates of the whole canvas. A viewport
# and a canvas each carry an offset, so both are added on the way down.
function _global_rects(node, ox = 0, oy = 0, acc = Tuple{Int,Int,Int,Int}[])
    if node isa GraphicsRect
        push!(acc, (ox + Int(node.x[]), oy + Int(node.y[]),
                    Int(node.w[]), Int(node.h[])))
    elseif node isa GraphicsCanvas
        for e in node.elements
            _global_rects(e, ox + Int(node.x[]), oy + Int(node.y[]), acc)
        end
    elseif node isa GraphicsViewport
        _global_rects(node.content, ox + Int(node.x[]), oy + Int(node.y[]), acc)
    end
    acc
end

@testset "a nested split's splitter meets the splitter that holds it" begin
    # A split pane takes no inset of its own: it draws no chrome, and an inset
    # there would push each nested layout in by that much, leaving every inner
    # splitter short of the one it must meet.
    WIDTH, HEIGHT = 400, 300
    left = PaneGroup(PaneTab[_tab("l")])
    top = PaneGroup(PaneTab[_tab("t")])
    bottom = PaneGroup(PaneTab[_tab("b")])
    tree = PaneTree(PaneSplit(:vertical, [left, PaneSplit(:horizontal, [top, bottom])]))
    context = PrinterContext(EmptyReference(), Cell(WIDTH), Cell(HEIGHT),
                             Dict{Symbol,Any}())
    iomap = print_document(_chain(), nothing, tree, context)

    rects = _global_rects(iomap.output)
    # A splitter is one pixel thick. The root's is the tall one, the nested one
    # the wide one; a tab strip draws nothing that thin.
    verticals = filter(r -> r[3] == 1 && r[4] > 1, rects)
    horizontals = filter(r -> r[4] == 1 && r[3] > 1, rects)
    @test length(verticals) == 1
    @test length(horizontals) == 1
    outer, inner = verticals[1], horizontals[1]

    @test outer[2] == 0                       # the root's splitter starts at the top
    @test outer[2] + outer[4] == HEIGHT       # and runs to the bottom
    @test inner[1] == outer[1] + outer[3]     # the nested one starts where it ends
    @test inner[1] + inner[3] == WIDTH        # and reaches the right edge
end

end # testset
end # function
