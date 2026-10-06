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

# A projection with no reader of its own, so the reader of `Projection` answers.
struct _PaneReaderGenericStage <: Projection end

function test_pane_reader()
@testset "PaneToWidget reader" begin

_stub = FixedMeasure(10, 18, 6, 0)
_tab(name) = PaneTab(name, WidgetLabel(name))
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
                   (op isa CompoundOperation && any(_starts_drag, op.operations)) ||
                   (op isa ReplaceViewStateOperation && _starts_drag(get_wrapped_operation(op)))

# The path of the part a press starts the drag of, from the `StartDragOperation`
# inside its answer, or `nothing`. The path a drag reader (`_pr_drag`) sends the
# rest of that drag's gestures to.
function _drag_path(op)
    op isa StartDragOperation && return get_operation_path(op)
    if op isa CompoundOperation
        for member in op.operations
            found = _drag_path(member)
            found === nothing || return found
        end
    end
    op isa ReplaceViewStateOperation && return _drag_path(get_wrapped_operation(op))
    nothing
end

# `gesture` to the part at `path`, the way the drag wrapper sends the rest of a
# drag that `path` started: by the route the press's answer named, with the
# point in the frame of the root, as the original press was.
function _pr_drag(proj, iomap, path, gesture)
    answer = read_intent(proj, nothing, Intent(gesture, nothing, "", "", path), iomap)
    answer isa Intent ? answer.operation : answer
end

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
        op = read_intent(proj, iomap, MouseClick(:left, x, y, ModifierKeys(); time = 0.0))
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
    field = WidgetText("12"; validator = make_numeric_validator())
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
        op = read_intent(proj, iomap, MouseClick(:left, x, y, ModifierKeys(); time = 0.0))
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
    stranger = WidgetTabbedPane(Any[("x", WidgetLabel("x"))])
    pane_stage = RecursiveProjection(PaneToWidget())
    pane_iomap = print_document(pane_stage, tree)
    @test read_intent(pane_stage, pane_iomap, CloseTabOperation(stranger, 1)) === nothing
    @test read_intent(pane_stage, pane_iomap, OpenTabOperation(stranger)) === nothing

    # A tab click names a place and not a pane. A press on the second tab of a
    # strip that another tree printed names a tab this tree does not have.
    other = PaneTree(PaneGroup(PaneTab[_tab("x"), _tab("y")]))
    widget_stage = make_widget_projection_example(measure = _stub)
    widget_iomap = print_document(widget_stage, print_document(pane_stage, other).output)
    clicks = [op for (_, op) in _sweep(widget_stage, widget_iomap)
              if op isa ReplaceSelectionOperation &&
                 occursin("selector_element_pairs[2]", string(op.path))]
    @test !isempty(clicks)
    @test read_intent(pane_stage, pane_iomap, clicks[1]) === nothing
end

@testset "a report of the strip passes a projection that is not a widget" begin
    # Between the strip and the tree, a projection that is not a widget has no
    # reader for a report, so the reader of `Projection` answers for it. A report
    # names its tabbed pane and no place, so that reader passes it up unchanged.
    pane = WidgetTabbedPane(Any[("x", WidgetLabel("x"))])
    between = _PaneReaderGenericStage()
    iomap = SimpleIoMap(between, pane, pane)
    for report in (CloseTabOperation(pane, 1), OpenTabOperation(pane),
                   DragTabOperation(pane, 1), DuplicateTabOperation(pane, 1))
        @test read_intent(between, iomap, report) === report
    end
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
    path = nothing
    for x in 190:210
        op = read_intent(proj, iomap, MouseDown(:left, x, 150, ModifierKeys(); time = 0.0))
        if _starts_drag(op)
            grab = x
            path = _drag_path(op)
            _apply!(editor, op)
            break
        end
    end
    @test grab !== nothing
    @test path isa Reference

    # The weight write comes back marked as view state, as the widget marked the
    # resize it answers, so a history records no part of the drag.
    move = _pr_drag(proj, iomap, path, DragMove(300, 150; time = 0.0))
    @test move isa ReplaceViewStateOperation
    @test get_wrapped_operation(move) isa ReplaceReferencedValueOperation
    _apply!(editor, move)
    @test get_pane_weights(tree.root)[1] > 0.6        # the left pane took the space
    @test sum(get_pane_weights(tree.root)) ≈ 1.0

    # A move to the point of the last move writes no cell: the weights that the
    # split holds are not written again.
    @test _pr_drag(proj, iomap, path, DragMove(300, 150; time = 0.0)) === nothing

    # The release ends the drag of the splitter and gives the shape of the
    # pointer back to the screen, both marked as view state.
    finish = _pr_drag(proj, iomap, path, DragEnd(300, 150; time = 0.0))
    @test finish isa CompoundOperation
    @test all(member -> member isa ReplaceViewStateOperation, finish.operations)
    @test get_wrapped_operation(finish.operations[1]) isa EndSplitterDragOperation
    @test get_wrapped_operation(finish.operations[2]) == ChangeScreenPointerShapeOperation(nothing)
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
        path = nothing
        for x in 0:399
            operation = read_intent(proj, iomap, MouseDown(:left, x, 150, ModifierKeys(); time = 0.0))
            _starts_drag(operation) || continue
            path = _drag_path(operation)
            _apply!(editor, operation)
            break
        end
        path === nothing && return false
        _apply!(editor, _pr_drag(proj, iomap, path, DragMove(to, 150; time = 0.0)))
        _apply!(editor, _pr_drag(proj, iomap, path, DragEnd(to, 150; time = 0.0)))
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
                                MouseDown(:left, 340, y, ModifierKeys(); time = 0.0))), 100:200)
    @test grabbed !== nothing
    grabbed === nothing && return
    y = (100:200)[grabbed]
    down = read_intent(proj, iomap, MouseDown(:left, 340, y, ModifierKeys(); time = 0.0))
    _apply!(editor, down)
    path = _drag_path(down)
    @test path isa Reference
    _apply!(editor, _pr_drag(proj, iomap, path, DragMove(340, y + 60; time = 0.0)))
    _apply!(editor, _pr_drag(proj, iomap, path, DragEnd(340, y + 60; time = 0.0)))
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

_alt_press(x, y) = MouseClick(:left, x, y, ModifierKeys(alt = true); time = 0.0)
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
         node.border_color.blue == get_theme_defaults(GraphicsTheme).selection_ring.blue &&
         node.border_color.red == get_theme_defaults(GraphicsTheme).selection_ring.red) || return
        push!(rings, (x + Int(node.x), y + Int(node.y), Int(node.w), Int(node.h)))
    end
    rings
end
_is_content_selected(tree, group, i) =
    string(strip_reference_types(get_selection(tree))) ==
    string(strip_reference_types(get_pane_content_path(tree, group, i)))

@testset "an Alt+click on a page selects what the tab holds, as a whole" begin
    for content in (WidgetLabel("label"), DocumentNothing())
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

@testset "an Alt+click inside a widget page selects the widget, not the page" begin
    label = WidgetLabel("inner")
    view = WidgetCard(; title = "a view",
                      content = HorizontalLayout(Any[label, WidgetLabel("other")]))
    group = PaneGroup(PaneTab[_tab("a"), PaneTab("view", view)])
    tree = PaneTree(group)
    editor = _PaneReaderMockEditor(tree)
    evaluate_operation(editor, make_pane_focus_operation(tree, group, 2))
    proj = make_pane_projection_example(measure = _stub)
    iomap = print_document(proj, nothing, tree, _page_context())
    at = _page_text_at(iomap.output, "inner")
    @test at !== nothing
    op = read_intent(proj, iomap, _alt_press(at[1] + 2, at[2] + 2))
    @test op isa ReplaceSelectionOperation
    _apply!(editor, op)
    @test evaluate_reference(tree, get_selection(tree)) === label
    # The ring is the layout's, around the label, and not the page's.
    rings = _page_rings(iomap.output)
    @test length(rings) == 1
    (rx, ry, rw, rh) = only(rings)
    @test rx <= at[1] < rx + rw && ry <= at[2] < ry + rh
    @test rw < 200
end

@testset "an Alt answer that names no whole document selects the innermost one on its path" begin
    inner = PrimitiveString("x")
    content = HorizontalLayout(Any[inner])
    group = PaneGroup(PaneTab[PaneTab("page", content)])
    tree = PaneTree(group)
    select = ProjecturedPlatform.PaneModule._select_page_content
    path_of(steps) = foldr(ConcreteReference, steps; init = EmptyReference())
    # What the widget layer answered: a press inside the tab's page.
    page_press = ReplaceSelectionOperation(path_of(Any[
        FieldReferenceStep("selector_element_pairs"), RangeReferenceStep(0, 1),
        FieldReferenceStep("element")]))
    at_content(steps...) = ReplaceSelectionOperation(
        concat_references(get_pane_content_path(tree, group, 1), path_of(Any[steps...])))
    target(op) = evaluate_reference(tree, op.path)
    first_child = (FieldReferenceStep("children"), RangeReferenceStep(0, 1))
    # A caret in the string names the string.
    caret = at_content(first_child..., FieldReferenceStep("value"), RangeReferenceStep(0, 0))
    @test target(select(tree, page_press, caret)) === inner
    # A place a projection introduced names the document it was printed for.
    introduced = at_content(first_child...,
        ProjecturedKernel.ProjectionModule.ProjectionReferenceStep(nothing, EmptyReference()))
    @test target(select(tree, page_press, introduced)) === inner
    # The tab holds no document inside the page, so the content is taken.
    tab = ReplaceSelectionOperation(get_pane_tab_reference(tree, group, 1))
    @test target(select(tree, page_press, tab)) === content
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
        read_intent(p, io, KeyDown(:v, ModifierKeys(ctrl = true); time = 0.0))
    end
    stored = WidgetLabel("stored")
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

@testset "a copy or a note of a focused tab takes what the tab shows" begin
    label = WidgetLabel("shown")
    group = PaneGroup(PaneTab[PaneTab("shown", label)])
    tree = PaneTree(group)
    root = FieldReferenceStep("content")
    slice = ClipboardSlice(tree)
    p = ClipboardSliceToAnyProjection()
    io = print_document(p, IdentityProjection(), slice, PrinterContext())
    press(key) = read_intent(p, io, KeyDown(key, ModifierKeys(ctrl = true); time = 0.0))
    stored(op) = op.operations[1].operations[1].value
    slice.selection = ConcreteReference(root, get_pane_tab_reference(tree, group, 1))
    copied = stored(press(:c))
    @test copied isa WidgetLabel && copied !== label
    @test stored(press(:n)) === label
    # A group shows no document of its own.
    slice.selection = ConcreteReference(root, get_pane_path(tree, group))
    @test !(press(:c) isa CompoundOperation)
    @test !(press(:n) isa CompoundOperation)
end

@testset "a window whose content a clipboard wraps still holds its tree" begin
    tree = PaneTree(PaneGroup(PaneTab[_tab("a")]))
    @test get_window_tree(ClipboardSlice(tree)) === tree
    @test get_window_tree(tree) === tree
    @test get_window_tree(; editor = _PaneReaderMockEditor(tree)) === tree
end

end # testset
end # function
