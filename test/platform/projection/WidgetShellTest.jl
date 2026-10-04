# Where a WidgetShell draws its bands and its content, in the room it is given.
#
# A window offers the shell its size, and the shell has none of its own, so what
# the offer becomes is the whole layout of a window: the content fills what the
# bands leave, and the status line runs along the bottom edge. The positions are
# asserted, not the presence: a shell that draws every band in the wrong place
# still holds all of them.

_shell_layout_value(v) = v isa CellModule.Cell ? v[] : v

# Every drawn text and every viewport, at its position in the window.
function _shell_layout_walk(node, ox = 0, oy = 0,
                            texts = Tuple{String,Int,Int}[], ports = NTuple{4,Int}[])
    node = _shell_layout_value(node)
    if node isa GraphicsText
        push!(texts, (String(_shell_layout_value(node.text)),
                      ox + Int(_shell_layout_value(node.x)), oy + Int(_shell_layout_value(node.y))))
    elseif node isa GraphicsViewport
        x = ox + Int(node.x); y = oy + Int(node.y)
        push!(ports, (x, y, Int(node.w), Int(node.h)))
        _shell_layout_walk(node.content, x, y, texts, ports)
    elseif node isa GraphicsCanvas
        x = ox + Int(_shell_layout_value(node.x)); y = oy + Int(_shell_layout_value(node.y))
        foreach(element -> _shell_layout_walk(element, x, y, texts, ports), node.elements)
    end
    (texts, ports)
end

function test_widget_shell_layout()
@testset "a shell lays out its bands in the room it is given" begin
    # A line is as tall as the box of a drawn text in its font: the bounds of a
    # drawn text take their height from the font files, so a measure that
    # answered less would leave every text a little taller than the line it sits
    # in.
    _, ascent, descent = compute_text_extent("", StyleFont("Ubuntu", 20))
    line = ascent + descent
    det = FixedMeasure(8, ascent, descent, 0)
    rec = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(StyleFont("Ubuntu", 20); measure = det).dispatch)))
    offer(w, h) = with_exact_size(PrinterContext();
                                  width = Cell(Int32(w)), height = Cell(Int32(h)))
    shell() = WidgetShell(WidgetScrollPane(WidgetLabel("body");
                                           size = Point2D(0, 0));
                          menu_bar = WidgetMenu(Any[WidgetMenuItem("File"),
                                                    WidgetMenuItem("View")];
                                                orientation = :horizontal),
                          status_bar = WidgetStatusBar(Any["ready"]))

    @testset "inside an offer it fills it" begin
        iomap = print_document(rec, nothing, shell(), offer(800, 600))
        output = iomap.output
        # The shell is exactly the room it was offered, and nothing hangs out.
        @test (Int(output.w), Int(output.h)) == (800, 600)
        texts, ports = _shell_layout_walk(output)
        at(name) = only(t for t in texts if t[1] == name)
        file, view = at("File"), at("View")
        # The menu bar keeps its items side by side, each as wide as its label,
        # and all of them inside the window.
        @test view[3] == file[3]
        @test file[2] + 8 * length("File") <= view[2] < file[2] + 8 * length("File") + 40
        @test view[2] + 8 * length("View") <= 800
        # Menu bar, content and status line, in that order, each where the one
        # before it ends: every band is as tall as it draws.
        (menu, content, status) = getfield(iomap, :child_iomaps)[]
        height(entry) = Int(_shell_layout_value(entry[3].output.h))
        @test menu[2] == 0
        @test content[2] == menu[2] + height(menu)
        @test status[2] == 600 - height(status)
        @test height(status) >= line
        # The content takes the whole width, and all of the height between the
        # menu bar and the status line.
        (x, y, w, h) = only(ports)
        @test (x, w) == (0, 800)
        @test y == content[2]
        @test y + h == status[2]
    end

    @testset "with no offer it takes its content's extent, and still shows the status line" begin
        output = print_document(rec, nothing, shell(), PrinterContext()).output
        texts, ports = _shell_layout_walk(output)
        at(name) = only(t for t in texts if t[1] == name)
        # The pane is as wide as its label, never 0.
        (_, _, w, h) = only(ports)
        @test w == 8 * length("body")
        @test h > 0
        # The status line sits under the content.
        @test at("ready")[3] >= at("body")[3] + line
    end
end
end

# The pointer inside a shell: a down and an up reach the band under the pointer in
# that band's frame, and a drag keeps the band it started in until the release.
function test_widget_shell_pointer()
@testset "a shell hands the pointer to its bands" begin
    _, ascent, descent = compute_text_extent("", StyleFont("Ubuntu", 20))
    line = ascent + descent
    det = FixedMeasure(8, ascent, descent, 0)
    rec = RecursiveProjection(TypeDispatchingProjection(vcat(
        LayoutToGraphics().dispatch,
        WidgetToGraphics(StyleFont("Ubuntu", 20); measure = det).dispatch)))
    offer(w, h) = with_exact_size(PrinterContext();
                                  width = Cell(Int32(w)), height = Cell(Int32(h)))
    # A menu bar and a toolbar above the content, so the content's frame starts
    # well below the window's: a down that kept window coordinates would miss.
    framed(content) = WidgetShell(content;
        menu_bar = WidgetMenu(Any[WidgetMenuItem("File")]; orientation = :horizontal),
        toolbar = WidgetToolbar(Any[WidgetMenuItem("New tab")]),
        status_bar = WidgetStatusBar(Any["ready"]))
    # A drag is view state, so its operations come marked. The press now answers
    # a `CompoundOperation` that also starts the drag (`StartDragOperation`), so
    # the marked operation is found among its members.
    function _unmark(op)
        op isa ReplaceViewStateOperation && return get_wrapped_operation(op)
        if op isa CompoundOperation
            for member in op.operations
                member isa ReplaceViewStateOperation && return get_wrapped_operation(member)
            end
        end
        op
    end

    # The path of the part a press starts the drag of, from the
    # `StartDragOperation` inside its answer, or `nothing`.
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

    # `gesture` to the part at `path`, by the route a press's answer named — the
    # way the drag wrapper sends the rest of a drag, with the point in the root's
    # frame, as the original press was.
    function _shell_drag(projection, iomap, path, gesture)
        answer = read_intent(projection, nothing, Intent(gesture, nothing, "", "", path), iomap)
        answer isa Intent ? answer.operation : answer
    end

    @testset "a down on a tab starts a drag of that tab" begin
        tabs = WidgetTabbedPane(Any[("One", WidgetLabel("first")),
                                    ("Two", WidgetLabel("second"))];
                                draggable = true)
        iomap = print_document(rec, nothing, framed(tabs), offer(800, 600))
        texts, _ = _shell_layout_walk(iomap.output)
        (_, x, y) = only(t for t in texts if t[1] == "Two")
        operation = read_intent(rec, iomap, MouseDown(:left, x + 2, y + 2; time = 0.0))
        @test operation isa DragTabOperation
        @test operation.tab_index == 2
    end

    @testset "a divider drag keeps its band over the status line" begin
        split = WidgetSplitPane(:horizontal, Any[WidgetLabel("left"),
                                                 WidgetLabel("right")];
                                sizes = [300, 300])
        iomap = print_document(rec, nothing, framed(split), offer(800, 600))
        # The divider: the first point at mid-height where a down grabs it.
        grab = nothing
        for x in 0:799
            operation = read_intent(rec, iomap, MouseDown(:left, x, 300; time = 0.0))
            _unmark(operation) isa StartSplitterDragOperation && (grab = (x, operation); break)
        end
        @test grab !== nothing
        (x, operation) = grab
        path = _drag_path(operation)
        @test path isa Reference
        evaluate_operation(nothing, operation)
        # The pointer moves on over the status line with the button held: the
        # divider still follows, and the release still ends the drag.
        moved = _shell_drag(rec, iomap, path, DragMove(x + 40, 600 - line ÷ 2; time = 0.0))
        @test _unmark(moved) isa ResizeSplitPaneOperation
        released = _shell_drag(rec, iomap, path, DragEnd(x + 40, 600 - line ÷ 2; time = 0.0))
        @test _unmark(released) isa EndSplitterDragOperation
    end
end
end
