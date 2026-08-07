# PaneTree → widgets: the shape the printer builds, the orientation translation,
# the weights, and the reference mapping in both directions.
mutable struct _PaneWidgetMockEditor
    document::Any
end

function test_pane_to_widget()
@testset "PaneToWidget" begin

_stub(t, f) = (max(1, length(t)) * 10, 24)
_tab(name) = PaneTab(name, WidgetLabel(Point2D(0, 0), name))
_pane_stage() = RecursiveProjection(PaneToWidget())
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
    pane = iomap.output
    @test pane isa WidgetTabbedPane
    @test length(pane.selector_element_pairs) == 2
    @test [string(p.selector) for p in pane.selector_element_pairs] == ["a", "b"]
    @test pane.closable === true
    @test pane.new_tab === true
    @test pane.draggable === true
end

@testset "an empty group prints an empty strip" begin
    tree = PaneTree(PaneGroup(PaneTab[]))
    iomap = print_document(_pane_stage(), tree)
    @test iomap.output isa WidgetTabbedPane
    @test isempty(iomap.output.selector_element_pairs)
    # The strip still offers its new-tab button, which is the only way out of
    # the empty start state.
    @test iomap.output.new_tab === true
end

@testset "the two orientation vocabularies are translated" begin
    left, right = PaneGroup(PaneTab[_tab("l")]), PaneGroup(PaneTab[_tab("r")])
    # A vertical split has a vertical divider, so its children sit side by side —
    # which the widget calls a horizontal layout.
    vertical = PaneTree(PaneSplit(:vertical, [left, right]))
    @test print_document(_pane_stage(), vertical).output.orientation === :horizontal

    top, bottom = PaneGroup(PaneTab[_tab("t")]), PaneGroup(PaneTab[_tab("b")])
    horizontal = PaneTree(PaneSplit(:horizontal, [top, bottom]))
    @test print_document(_pane_stage(), horizontal).output.orientation === :vertical
end

@testset "weights become the slots' layout weights" begin
    left, right = PaneGroup(PaneTab[_tab("l")]), PaneGroup(PaneTab[_tab("r")])
    tree = PaneTree(PaneSplit(:vertical, [left, right]; weights = [0.25, 0.75]))
    pane = print_document(_pane_stage(), tree).output
    @test length(pane.elements) == 2
    @test all(e -> e isa LayoutConstraint, [pane.elements[i] for i in 1:2])
    @test [pane.elements[i].weight_width for i in 1:2] == [0.25, 0.75]
    # The children keep their own widgets under the constraint wrapper.
    @test pane.elements[1].child isa WidgetTabbedPane

    # A stacked split carries its weights on the other axis.
    stacked = PaneTree(PaneSplit(:horizontal, [PaneGroup(PaneTab[_tab("t")]),
                                               PaneGroup(PaneTab[_tab("b")])]))
    stacked_pane = print_document(_pane_stage(), stacked).output
    @test [stacked_pane.elements[i].weight_height for i in 1:2] == [0.5, 0.5]
    @test stacked_pane.elements[1].weight_width === nothing
end

@testset "the selection is forwarded onto the widgets" begin
    group = PaneGroup(PaneTab[_tab("a"), _tab("b")])
    tree = PaneTree(group)
    editor = _PaneWidgetMockEditor(tree)
    iomap = print_document(_pane_stage(), tree)
    pane = iomap.output
    @test get_selection(pane) === nothing

    _apply!(editor, pane_focus_operation(tree, group, 2))
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
    split_pane = iomap.output

    _apply!(editor, pane_focus_operation(tree, right, 1))
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
        reference = pane_tab_reference(tree, group, index)
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
    click = @reference ::WidgetTabbedPane.selector_element_pairs::CellVector[2]::WidgetDocument
    @test map_reference_backward(iomap.projection, iomap, click) ==
          pane_tab_reference(tree, group, 2)
end

@testset "the whole chain renders to a canvas" begin
    left = PaneGroup(PaneTab[_tab("l")])
    right = PaneGroup(PaneTab[_tab("r")])
    tree = PaneTree(PaneSplit(:vertical, [left, right]))
    iomap = print_document(_chain(), tree)
    @test iomap.output isa GraphicsCanvas
    @test graphics_size(iomap.output)[1] > 0
end

end # testset
end # function
