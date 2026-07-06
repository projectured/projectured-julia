# Reader-level tests for drag-to-resize of WidgetSplitPane splitters. A
# synthetic MouseDown → MouseMove → MouseUp sequence is fed through the standard
# widget renderer; we assert the emitted operations and the resulting `sizes`.
function test_split_pane_drag()
@testset "WidgetSplitPane drag-to-resize" begin

_stub(t, f) = (max(1, length(t)) * 10, 24)
_proj() = make_widget_projection_example(measure=_stub)
_szs(doc) = isempty(doc.sizes) ? Int[] : [Int(doc.sizes[i]) for i in 1:length(doc.sizes)]

# Feed an event through the pipeline and evaluate any resulting operation.
function _feed(proj, iomap, evt)
    op = read_intent(proj, iomap, evt)
    op isa Operation && evaluate_operation(nothing, op)
    op
end

@testset "unconstrained: down/move/up resizes adjacent slots, total conserved" begin
    doc   = make_widget_split_pane_document_example()   # horizontal, sizes=[300,300]
    proj  = _proj()
    iomap = print_document(proj, doc)

    # The lone splitter sits in the ~1px gap before the second child (x≈300).
    down = _feed(proj, iomap, MouseDown(:left, 300, 50, Modifiers()))
    @test down isa StartSplitterDragOperation
    @test down.split === doc
    @test down.splitter_index == 1
    @test doc.active_splitter == 1
    @test doc.drag_anchor !== nothing

    # Grow the left slot by 50px; the right slot gives back exactly 50px.
    move = _feed(proj, iomap, MouseMove(350, 50, :left, Modifiers()))
    @test move isa ResizeSplitPaneOperation
    @test _szs(doc) == [350, 250]
    @test sum(_szs(doc)) == 600

    # A second move resizes relative to the grab origin, not cumulatively.
    _feed(proj, iomap, MouseMove(270, 50, :left, Modifiers()))
    @test _szs(doc) == [270, 330]
    @test sum(_szs(doc)) == 600

    up = _feed(proj, iomap, MouseUp(:left, 270, 50, Modifiers()))
    @test up isa EndSplitterDragOperation
    @test doc.active_splitter == 0
    @test doc.drag_anchor === nothing
end

@testset "a press away from the band does not start a drag" begin
    doc   = make_widget_split_pane_document_example()
    proj  = _proj()
    iomap = print_document(proj, doc)
    # Well inside the left slot, far from the x≈300 splitter band.
    op = read_intent(proj, iomap, MouseDown(:left, 100, 50, Modifiers()))
    @test !(op isa StartSplitterDragOperation)
    @test doc.active_splitter == 0
end

@testset "no MouseMove resize without an active drag" begin
    doc   = make_widget_split_pane_document_example()
    proj  = _proj()
    iomap = print_document(proj, doc)
    op = read_intent(proj, iomap, MouseMove(350, 50, :left, Modifiers()))
    @test !(op isa ResizeSplitPaneOperation)
    @test _szs(doc) == [300, 300]
end

@testset "vertical orientation drags along the y axis" begin
    top    = WidgetTitlePane("T", WidgetLabel(Point2D(8, 8), "t"))
    bottom = WidgetTitlePane("B", WidgetLabel(Point2D(8, 8), "b"))
    doc    = WidgetSplitPane(:vertical, Any[top, bottom]; sizes=[200, 200])
    proj   = _proj()
    iomap  = print_document(proj, doc)

    # Splitter band is in the gap before the second child (y≈200).
    down = _feed(proj, iomap, MouseDown(:left, 40, 200, Modifiers()))
    @test down isa StartSplitterDragOperation
    _feed(proj, iomap, MouseMove(40, 240, :left, Modifiers()))
    @test _szs(doc) == [240, 160]
    @test sum(_szs(doc)) == 400
    _feed(proj, iomap, MouseUp(:left, 40, 240, Modifiers()))
    @test doc.active_splitter == 0
end

@testset "constrained regime: dragged size sticks across a reprint (pinned)" begin
    mk(t) = LayoutConstraint(WidgetTitlePane(t, WidgetLabel(Point2D(8, 8), lowercase(t)));
                             weight_width=1.0, preferred_width=200)
    doc   = WidgetSplitPane(:horizontal, Any[mk("L"), mk("R")])
    proj  = _proj()
    ctx   = with_available_size(PrinterContext(); width=Cell(601), height=Cell(400))
    iomap = print_document(proj, nothing, doc, ctx)

    _feed(proj, iomap, MouseDown(:left, 300, 50, Modifiers()))
    _feed(proj, iomap, MouseMove(380, 50, :left, Modifiers()))
    _feed(proj, iomap, MouseUp(:left, 380, 50, Modifiers()))

    @test _szs(doc) == [380, 220]
    @test [Bool(doc.pinned[i]) for i in 1:length(doc.pinned)] == [true, true]

    # Re-print under the same available width: allocate_axis must honour the
    # dragged size instead of redistributing back to the weighted preference.
    iomap2 = print_document(proj, nothing, doc, ctx)
    xs = [Int(e.x[]) for e in iomap2.output.elements
          if e isa Projectured.GraphicsModule.GraphicsCanvas]
    @test length(xs) == 2
    @test xs[1] == 0
    @test 379 <= xs[2] <= 381   # second child starts right after the 380px slot
end

@testset "splitter inside a WidgetTabbedPane is grabbable at its drawn position" begin
    # Regression: a split nested in a tabbed pane is offset by the tab strip.
    # The tabbed-pane reader must translate the drag events' coordinates into
    # the active tab's frame, otherwise the grab region floats above where the
    # splitter is actually drawn (the bug that made the assistant
    # conversation/draft splitter unmovable in the workbench).
    top    = WidgetTitlePane("T", WidgetLabel(Point2D(8, 8), "t"))
    bottom = WidgetTitlePane("B", WidgetLabel(Point2D(8, 8), "b"))
    split  = WidgetSplitPane(:vertical, Any[top, bottom]; sizes=[150, 150])
    tabbed = WidgetTabbedPane(Any[("Tab", split)])
    proj   = _proj()
    iomap  = print_document(proj, tabbed)

    # The splitter is drawn at slot1 (150px) plus the tab strip offset, i.e.
    # well below screen-y 150. Find where a MouseDown actually starts the drag.
    starts = [y for y in 0:400
              if read_intent(proj, iomap, MouseDown(:left, 40, y, Modifiers())) isa StartSplitterDragOperation]
    @test !isempty(starts)
    @test first(starts) > 150   # grab region sits at the drawn splitter, not at column-local 150

    gy = (first(starts) + last(starts)) ÷ 2
    _feed(proj, iomap, MouseDown(:left, 40, gy, Modifiers()))
    @test split.active_splitter == 1
    _feed(proj, iomap, MouseMove(40, gy + 40, :left, Modifiers()))
    @test [Int(split.sizes[i]) for i in 1:length(split.sizes)] == [190, 110]
    _feed(proj, iomap, MouseUp(:left, 40, gy + 40, Modifiers()))
    @test split.active_splitter == 0
end

end # @testset
end
