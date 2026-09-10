# What the pane tree does with what the widgets report: a tab click focuses, a
# close button closes, the new-tab button opens, and a splitter drag becomes a
# weight change.
#
# Every case drives the whole chain — a real pixel goes in at the graphics end and
# a pane-domain operation comes out — because that is the only way to see the two
# seams (widget report → pane edit, and the reference mapping) working together.
mutable struct _PaneReaderMockEditor
    document::Any
end

function test_pane_reader()
@testset "PaneToWidget reader" begin

_stub(t, f) = (max(1, length(t)) * 10, 24)
_tab(name) = PaneTab(name, WidgetLabel(Point2D(0, 0), name))
_chain() = ChainingProjection(RecursiveProjection(PaneToWidget()),
                              make_widget_projection_example(measure = _stub))

function _apply!(editor, op)
    op === nothing && return nothing
    evaluate_operation(editor, op)
    op
end

# Every write inside an operation, flattened out of any compound.
function _writes(op)
    op isa CompoundOperation && return reduce(vcat, map(_writes, op.operations); init = Any[])
    op isa ReplaceReferencedValueOperation ? Any[op] : Any[]
end

# A grab now arrives inside a compound: the widget's stale measurements are
# cleared in the same step.
_starts_drag(op) = op isa StartSplitterDragOperation ||
                   (op isa CompoundOperation && any(_starts_drag, op.operations))

_is_delete(op) = any(w -> w.value isa AbstractVector && isempty(w.value), _writes(op))
_is_insert(op) = any(w -> w.value isa AbstractVector && length(w.value) == 1 &&
                          w.value[1] isa PaneTab, _writes(op))

# Sweep the pane's top band and collect `x => operation` for every press that
# answered. The band covers the tab strip whatever the theme's padding is.
function _sweep(proj, iomap)
    found = Tuple{Int,Any}[]
    for y in 0:2:40, x in 0:2:400
        op = read_intent(proj, iomap, MousePress(:left, x, y, ModifierKeys()))
        op === nothing || push!(found, (x, op))
    end
    found
end

_first_x(found, predicate) = for (x, op) in found
    predicate(op) && return x
end

@testset "a tab click moves the focus" begin
    group = PaneGroup(PaneTab[_tab("a"), _tab("b")])
    tree = PaneTree(group)
    editor = _PaneReaderMockEditor(tree)
    proj = _chain()
    iomap = print_document(proj, tree)

    wanted = pane_tab_reference(tree, group, 2)
    found = _sweep(proj, iomap)
    hits = [op for (_, op) in found
            if op isa ReplaceSelectionOperation && op.path == wanted]
    @test !isempty(hits)

    _apply!(editor, hits[1])
    @test pane_focus(tree) == (group, 2)
end

@testset "a close button closes its own tab" begin
    group = PaneGroup(PaneTab[_tab("a"), _tab("b")])
    tree = PaneTree(group)
    editor = _PaneReaderMockEditor(tree)
    proj = _chain()
    iomap = print_document(proj, tree)

    closes = [op for (_, op) in _sweep(proj, iomap) if _is_delete(op)]
    @test !isempty(closes)
    kept = group.tabs[2]
    _apply!(editor, closes[1])
    @test length(group.tabs) == 1
    @test group.tabs[1] === kept          # the first tab's button closed the first tab
end

@testset "the new-tab button opens a tab and focuses it" begin
    group = PaneGroup(PaneTab[_tab("a")])
    tree = PaneTree(group)
    editor = _PaneReaderMockEditor(tree)
    proj = _chain()
    iomap = print_document(proj, tree)

    opens = [op for (_, op) in _sweep(proj, iomap) if _is_insert(op)]
    @test !isempty(opens)
    _apply!(editor, opens[1])
    @test length(group.tabs) == 2
    @test pane_focus(tree) == (group, 2)
    @test pane_tab_title_string(group.tabs[2]) == "untitled"
end

@testset "the new-tab factory decides what a tab holds" begin
    group = PaneGroup(PaneTab[_tab("a")])
    tree = PaneTree(group)
    editor = _PaneReaderMockEditor(tree)
    proj = ChainingProjection(
        RecursiveProjection(PaneToWidget(new_tab = () -> _tab("made to order"))),
        make_widget_projection_example(measure = _stub))
    iomap = print_document(proj, tree)

    opens = [op for (_, op) in _sweep(proj, iomap) if _is_insert(op)]
    @test !isempty(opens)
    _apply!(editor, opens[1])
    @test pane_tab_title_string(group.tabs[2]) == "made to order"
end

@testset "a report from a pane that is not ours is declined" begin
    group = PaneGroup(PaneTab[_tab("a")])
    tree = PaneTree(group)
    proj = _chain()
    iomap = print_document(proj, tree)
    stranger = WidgetTabbedPane(Any[("x", WidgetLabel(Point2D(0, 0), "x"))])
    pane_stage = RecursiveProjection(PaneToWidget())
    pane_iomap = print_document(pane_stage, tree)
    @test read_intent(pane_stage, pane_iomap, SelectTabOperation(stranger, 1)) === nothing
    @test read_intent(pane_stage, pane_iomap, CloseTabRequestOperation(stranger, 1)) === nothing
    @test read_intent(pane_stage, pane_iomap, NewTabRequestOperation(stranger)) === nothing
end

@testset "a splitter drag runs from the pointer" begin
    # The whole gesture, through the reader — a button down on the divider, a
    # move, a release. Applying `StartSplitterDragOperation` by hand instead would
    # not notice that the reader never hands it back.
    left = PaneGroup(PaneTab[_tab("l")])
    right = PaneGroup(PaneTab[_tab("r")])
    tree = PaneTree(PaneSplit(:vertical, [left, right]))
    editor = _PaneReaderMockEditor(tree)
    proj = make_pane_projection_example(measure = _stub)
    iomap = print_document(proj, nothing, tree,
                           PrinterContext(EmptyReference(), Cell(400), Cell(300),
                                          Dict{Symbol,Any}()))

    # The divider of an even split sits near the middle; find the band it grabs in.
    grab = nothing
    for x in 190:210
        op = read_intent(proj, iomap, MouseDown(:left, x, 150, ModifierKeys()))
        if _starts_drag(op)
            grab = x
            _apply!(editor, op)
            break
        end
    end
    @test grab !== nothing

    move = read_intent(proj, iomap, MouseMove(300, 150, :left, ModifierKeys()))
    @test move isa ReplaceReferencedValueOperation
    _apply!(editor, move)
    @test pane_weights(tree.root)[1] > 0.6        # the left pane took the space
    @test sum(pane_weights(tree.root)) ≈ 1.0

    finish = read_intent(proj, iomap, MouseUp(:left, 300, 150, ModifierKeys()))
    @test finish isa EndSplitterDragOperation
    _apply!(editor, finish)
    @test tree.root.elements[1] === left          # and the layout kept its shape
end

@testset "a second drag continues from where the first left off" begin
    # The widget anchors a drag on its measured `sizes`, and materializes them
    # only when they are empty. This projection answers every resize with a
    # *weight* write and never lets `sizes` be written, so a second drag would
    # anchor on the first one's measurements and the splitter would jump back.
    left = PaneGroup(PaneTab[_tab("l")])
    right = PaneGroup(PaneTab[_tab("r")])
    tree = PaneTree(PaneSplit(:vertical, [left, right]))
    editor = _PaneReaderMockEditor(tree)
    proj = make_pane_projection_example(measure = _stub)
    iomap = print_document(proj, nothing, tree,
                           PrinterContext(EmptyReference(), Cell(400), Cell(300),
                                          Dict{Symbol,Any}()))

    # Grab the divider wherever it currently is, move to `to`, release.
    function _drag!(to)
        grabbed = false
        for x in 0:399
            operation = read_intent(proj, iomap, MouseDown(:left, x, 150, ModifierKeys()))
            _starts_drag(operation) || continue
            _apply!(editor, operation)
            grabbed = true
            break
        end
        grabbed || return false
        _apply!(editor, read_intent(proj, iomap, MouseMove(to, 150, :left, ModifierKeys())))
        _apply!(editor, read_intent(proj, iomap, MouseUp(:left, to, 150, ModifierKeys())))
        true
    end

    @test _drag!(300)
    after_first = pane_weights(tree.root)[1]
    @test after_first > 0.7

    # The second drag moves the divider a little further right. If it anchored on
    # the first drag's measurements it would snap back towards the middle.
    @test _drag!(330)
    after_second = pane_weights(tree.root)[1]
    @test after_second > after_first
    @test after_second < after_first + 0.15
end

@testset "a nested splitter can be grabbed" begin
    # The parent hit-tests its slots before routing, and a hairline between two
    # panes is not a hit — so without an ungated pass only the outermost splitter
    # would ever answer.
    left = PaneGroup(PaneTab[_tab("l")])
    top = PaneGroup(PaneTab[_tab("t")])
    bottom = PaneGroup(PaneTab[_tab("b")])
    inner = PaneSplit(:horizontal, [top, bottom])
    tree = PaneTree(PaneSplit(:vertical, [left, inner]))
    editor = _PaneReaderMockEditor(tree)
    proj = make_pane_projection_example(measure = _stub)
    iomap = print_document(proj, nothing, tree,
                           PrinterContext(EmptyReference(), Cell(400), Cell(300),
                                          Dict{Symbol,Any}()))

    # The inner divider runs across the right column, near half its height.
    grabbed = findfirst(y -> _starts_drag(read_intent(proj, iomap,
                                MouseDown(:left, 340, y, ModifierKeys()))), 100:200)
    @test grabbed !== nothing
    grabbed === nothing && return
    y = (100:200)[grabbed]
    _apply!(editor, read_intent(proj, iomap, MouseDown(:left, 340, y, ModifierKeys())))
    _apply!(editor, read_intent(proj, iomap, MouseMove(340, y + 60, :left, ModifierKeys())))
    _apply!(editor, read_intent(proj, iomap, MouseUp(:left, 340, y + 60, ModifierKeys())))
    @test pane_weights(inner)[1] > 0.6              # the top pane took the space
    @test pane_weights(tree.root) == [0.5, 0.5]     # and the outer split is untouched
end

@testset "a drag on a split pane this tree did not print passes through" begin
    tree = PaneTree(PaneGroup(PaneTab[_tab("a")]))
    stage = RecursiveProjection(PaneToWidget())
    iomap = print_document(stage, tree)
    stranger = WidgetSplitPane(:horizontal, Any[])
    op = ResizeSplitPaneOperation(stranger, 1, 10, 10)
    # The tree has nothing to add: it does not turn a foreign split's resize into
    # a pane weight, and the operation carries its own document, so applying it is
    # the widget layer's business.
    #
    # It must not swallow it either. A split a tab's content built is exactly this
    # case — the assistant's transcript above its composer — and answering
    # `nothing` killed the drag: the grab started and the first motion went
    # nowhere.
    @test read_intent(stage, iomap, op) === op
end

end # testset
end # function
