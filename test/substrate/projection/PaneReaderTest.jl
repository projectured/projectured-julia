# What the pane tree does with what the widgets report: a tab click focuses, a
# close button closes, a duplicate button duplicates, the new-tab button opens,
# and a splitter drag becomes a weight change.
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
_inserted_titles(op) = [get_pane_tab_title_string(w.value[1]) for w in _writes(op)
                        if w.value isa AbstractVector && length(w.value) == 1 &&
                           w.value[1] isa PaneTab]
# A duplicate is an insert too; its title carries a number.
_is_duplicate(op) = any(t -> occursin(r" \(\d+\)$", t), _inserted_titles(op))
_is_insert(op) = !isempty(_inserted_titles(op)) && !_is_duplicate(op)

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

    wanted = get_pane_tab_reference(tree, group, 2)
    found = _sweep(proj, iomap)
    hits = [op for (_, op) in found
            if op isa ReplaceSelectionOperation && op.path == wanted]
    @test !isempty(hits)

    _apply!(editor, hits[1])
    @test get_pane_focus(tree) == (group, 2)
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

@testset "the + above a close button duplicates its own tab" begin
    group = PaneGroup(PaneTab[_tab("a"), _tab("b")])
    tree = PaneTree(group)
    editor = _PaneReaderMockEditor(tree)
    proj = _chain()
    iomap = print_document(proj, tree)
    # The pane asks each content whether it has a duplicate.
    pane = getfield(iomap, :step_iomaps)[][1][].output.elements[1]
    @test pane.duplicable
    @test pane.selector_element_pairs[1].duplicable

    duplicates = [op for (_, op) in _sweep(proj, iomap) if _is_duplicate(op)]
    @test !isempty(duplicates)
    original = group.tabs[1]
    _apply!(editor, duplicates[1])
    @test length(group.tabs) == 3
    @test get_pane_tab_title_string(group.tabs[2]) == "a (2)"
    @test group.tabs[2].content !== original.content
    @test get_pane_focus(tree) == (group, 2)
end

@testset "a + whose content refuses its duplicate gives no edit" begin
    field = WidgetText(Point2D(0, 0), "12"; validator = make_numeric_validator())
    tree = PaneTree(PaneGroup(PaneTab[PaneTab("field", field)]))
    proj = _chain()
    iomap = print_document(proj, tree)
    found = @test_logs (:warn, "The pane has no duplicate") match_mode = :any _sweep(proj, iomap)
    @test !any(op -> _is_duplicate(op), last.(found))
    @test length(tree.root.tabs) == 1
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
    @test get_pane_focus(tree) == (group, 2)
    @test get_pane_tab_title_string(group.tabs[2]) == "untitled"
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
    @test get_pane_tab_title_string(group.tabs[2]) == "made to order"
end

@testset "a click in a tab's content places a caret in it" begin
    # A tab holds a document of another domain, and the renderer draws it. A click
    # on that text must answer a path INTO the document, so the caret lands in it
    # and the next key has somewhere to go. An answer truncated to the tab is what
    # leaves a form field inside a pane dead to the pointer.
    group = PaneGroup(PaneTab[PaneTab("a", PrimitiveString("hello"))])
    tree = PaneTree(group)
    # The focus, as a window opens with one: a tabbed pane routes a press to the
    # tab its selection names, and names none until something has been clicked.
    set_selection!(tree, get_pane_tab_reference(tree, group, 1))
    editor = _PaneReaderMockEditor(tree)
    proj = make_pane_projection_example(measure = _stub)
    # With an extent to divide, as a window gives one: a tabbed pane draws its
    # page inside the extent it was offered, and a print with no offer draws the
    # tab strip alone.
    iomap = print_document(proj, nothing, tree,
                           PrinterContext(EmptyReference(), Cell(400), Cell(300),
                                          Dict{Symbol,Any}()))

    caret = nothing
    for y in 0:2:300, x in 0:2:400
        op = read_intent(proj, iomap, MousePress(:left, x, y, ModifierKeys()))
        op isa ReplaceSelectionOperation || continue
        occursin("PrimitiveString", string(op.path)) || continue
        caret = op
        break
    end
    @test caret !== nothing
    if caret !== nothing
        _apply!(editor, caret)
        # The whole chain wrote it: the tree, the group, the tab and the string it
        # holds each hold their own share of the path.
        @test get_pane_focus(tree) == (group, 1)
        @test get_selection(group.tabs[1].content) !== nothing
    end
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
    @test read_intent(pane_stage, pane_iomap, CloseTabOperation(stranger, 1)) === nothing
    @test read_intent(pane_stage, pane_iomap, OpenTabOperation(stranger)) === nothing
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
    @test get_pane_weights(tree.root)[1] > 0.6        # the left pane took the space
    @test sum(get_pane_weights(tree.root)) ≈ 1.0

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
    after_first = get_pane_weights(tree.root)[1]
    @test after_first > 0.7

    # The second drag moves the divider a little further right. If it anchored on
    # the first drag's measurements it would snap back towards the middle.
    @test _drag!(330)
    after_second = get_pane_weights(tree.root)[1]
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
    @test get_pane_weights(inner)[1] > 0.6              # the top pane took the space
    @test get_pane_weights(tree.root) == [0.5, 0.5]     # and the outer split is untouched
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

# ── A whole page ─────────────────────────────────────────────────────────

_alt_press(x, y) = MousePress(:left, x, y, ModifierKeys(alt = true))
_page_context() = PrinterContext(EmptyReference(), Cell(400), Cell(300), Dict{Symbol,Any}())

# Where a text is drawn, and the drawn box of every selection ring.
function _page_walk(f, node, x = 0, y = 0)
    node isa ReactiveCell && return _page_walk(f, node[], x, y)
    if node isa GraphicsCanvas
        for element in node.elements
            _page_walk(f, element, x + Int(node.x), y + Int(node.y))
        end
    elseif node isa GraphicsViewport
        _page_walk(f, node.content, x + Int(node.x), y + Int(node.y))
    else
        f(node, x, y)
    end
end
function _page_text_at(root, text)
    found = nothing
    _page_walk(root) do node, x, y
        (found === nothing && node isa GraphicsText && occursin(text, String(node.text))) || return
        found = (x + Int(node.x), y + Int(node.y))
    end
    found
end
function _page_rings(root)
    rings = Tuple{Int,Int,Int,Int}[]
    _page_walk(root) do node, x, y
        (node isa GraphicsRect && Int(node.border_width) > 0 &&
         node.border_color.blue == SELECTION_RING_COLOR.blue &&
         node.border_color.red == SELECTION_RING_COLOR.red) || return
        push!(rings, (x + Int(node.x), y + Int(node.y), Int(node.w), Int(node.h)))
    end
    rings
end
_is_content_selected(tree, group, i) =
    string(strip_reference_types(get_selection(tree))) ==
    string(strip_reference_types(get_pane_content_path(tree, group, i)))

@testset "an Alt+click on a page selects what the tab holds, as a whole" begin
    for content in (WidgetLabel(Point2D(0, 0), "label"), DocumentNothing())
        group = PaneGroup(PaneTab[PaneTab("t", content)])
        tree = PaneTree(group)
        editor = _PaneReaderMockEditor(tree)
        evaluate_operation(editor, make_pane_focus_operation(tree, group, 1))
        proj = make_pane_projection_example(measure = _stub)
        iomap = print_document(proj, nothing, tree, _page_context())
        at = _page_text_at(iomap.output, content isa DocumentNothing ? "Nothing" : "label")
        @test at !== nothing
        op = read_intent(proj, iomap, _alt_press(at[1] + 2, at[2] + 2))
        @test op isa ReplaceSelectionOperation
        _apply!(editor, op)
        @test _is_content_selected(tree, group, 1)
        @test evaluate_reference(tree, get_selection(tree)) === content
        # The page draws the ring, around the text that was pressed.
        rings = _page_rings(iomap.output)
        @test length(rings) == 1
        (rx, ry, rw, rh) = only(rings)
        @test rx <= at[1] < rx + rw && ry <= at[2] < ry + rh
        # A whole tab is not its page: the ring goes.
        _apply!(editor, make_pane_focus_operation(tree, group, 1))
        @test isempty(_page_rings(iomap.output))
    end
end

@testset "a paste fills a tab's content and never replaces a pane" begin
    group = PaneGroup(PaneTab[_tab("a"), PaneTab("", DocumentNothing())])
    tree = PaneTree(group)
    root = FieldReferenceStep("content")
    content_of(i) = ConcreteReference(root, get_pane_content_path(tree, group, i))
    tab_at(i) = ConcreteReference(root, get_pane_tab_reference(tree, group, i))
    paste(slice) = begin
        p = ClipboardSliceToAnyProjection()
        io = print_document(p, IdentityProjection(), slice, PrinterContext())
        read_intent(p, io, KeyDown(:v, ModifierKeys(ctrl = true)))
    end
    stored = WidgetLabel(Point2D(0, 0), "stored")
    slice = ClipboardSlice(tree, stored)
    # The empty content takes the object.
    slice.selection = content_of(2)
    @test paste(slice) isa CompoundOperation
    # A whole tab, the tab list's element, is a pane: the paste is refused.
    slice.selection = tab_at(1)
    @test !(paste(slice) isa CompoundOperation)
    # A whole group, here the root, is a pane too.
    slice.selection = ConcreteReference(root, get_pane_path(tree, group))
    @test !(paste(slice) isa CompoundOperation)
    # And a pane is never pasted, not even into an empty content.
    tab_slice = ClipboardSlice(tree, PaneTab("copied", DocumentNothing()))
    tab_slice.selection = content_of(2)
    @test !(paste(tab_slice) isa CompoundOperation)
end

@testset "a window whose content a clipboard wraps still holds its tree" begin
    tree = PaneTree(PaneGroup(PaneTab[_tab("a")]))
    @test get_window_tree(ClipboardSlice(tree)) === tree
    @test get_window_tree(tree) === tree
    @test get_window_tree(_PaneReaderMockEditor(tree)) === tree
end

end # testset
end # function
