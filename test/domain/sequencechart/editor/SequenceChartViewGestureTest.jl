# The view gestures of a sequence chart in a window of the editor, as a person
# makes them: each one is window input at the pixels of the chart, so the keys, the
# wheel, the drags, the menu and the buttons reach the chart through the whole
# editor.

using Test

_scg_force(value) = value isa AbstractCell ? _scg_force(value[]) : value

# The first IO map of type `T` in the IO map tree under `root`.
function _scg_find_iomap(root, T)
    seen = Set{UInt}()
    stack = Any[root]
    while !isempty(stack)
        value = _scg_force(pop!(stack))
        value isa T && return value
        if value isa IoMap
            objectid(value) in seen && continue
            push!(seen, objectid(value))
            for name in fieldnames(typeof(value))
                name in (:projection, :input, :output) || push!(stack, getfield(value, name))
            end
        elseif value isa Union{AbstractVector,Tuple}
            append!(stack, value)
        end
    end
    nothing
end

# The point of the window where `canvas` is drawn, or `nothing`.
function _scg_find_place(node, canvas, x = 0, y = 0, seen = Set{UInt}())
    node = _scg_force(node)
    (node === nothing || node isa Union{Number,AbstractString,Symbol,Function,Type,Module,IoMap}) &&
        return nothing
    if node isa Union{AbstractVector,Tuple}
        for child in node
            found = _scg_find_place(child, canvas, x, y, seen)
            found === nothing || return found
        end
        return nothing
    end
    isstructtype(typeof(node)) || return nothing
    if ismutable(node)
        objectid(node) in seen && return nothing
        push!(seen, objectid(node))
    end
    hasproperty(node, :x) && _scg_force(node.x) isa Real && (x += Int(_scg_force(node.x)))
    hasproperty(node, :y) && _scg_force(node.y) isa Real && (y += Int(_scg_force(node.y)))
    node === canvas && return (x, y)
    for name in fieldnames(typeof(node))
        name in (:projection, :input, :output, :parent) && continue
        found = _scg_find_place(getfield(node, name), canvas, x, y, seen)
        found === nothing || return found
    end
    nothing
end

# A window `W` of the editor that shows `chart` through `make_sequence_chart_projection`.
function _scg_open(chart)
    scene = make_window_scene(chart, "W"; width = 1000, height = 640)
    opened = make_opened_window_projections(; measure = FontFileMeasure())
    view = make_sequence_chart_projection(; measure = FontFileMeasure())
    composed = make_window_scene_projection(view; opened_window_projections = opened)
    document, projection = make_tracking_screen(scene, composed; inner_wrappers = [wrap_context_menu_window])
    backend = HeadlessBackend()
    editor = Editor(document, projection; backend, devices = Device[Keyboard(), Mouse()])
    run_frame!(editor)
    time = Ref(0.0)
    send(event) = (push_event!(backend, WindowInput(:W, event)); run_frame!(editor))
    next() = (time[] += 0.6; time[])
    windows() = _scg_force(_scg_force(get_iomap_output(editor.iomap)).windows)
    canvas_iomap() = _scg_find_iomap(editor.iomap, SequenceChartPlotToGraphicsCanvasIoMap)
    origin() = something(_scg_find_place(_scg_force(first(windows())).content, canvas_iomap().output))
    (; editor, send, next, windows, canvas_iomap, origin)
end

"""
    test_sequencechart_view_gestures()

The view gestures of a sequence chart in a window of the editor: Ctrl and the wheel
zoom, Ctrl+0 shows the whole trace, a Shift drag pans the time, a button of the
corner zooms, a right click opens the menu, and a click on an event still selects
it.
"""
function test_sequencechart_view_gestures()
@testset "the view gestures of a sequence chart in the editor" begin
    chart = _sc_chart()
    w = _scg_open(chart)
    iomap = w.canvas_iomap()
    @test iomap !== nothing
    plot = iomap.input
    ox, oy = w.origin()
    g() = w.canvas_iomap().geometry
    mx = ox + round(Int, g().body_x + g().body_w / 2)
    my = oy + round(Int, g().body_y + g().body_h / 2)
    none, ctrl, shift = ModifierKeys(), ModifierKeys(; ctrl = true), ModifierKeys(; shift = true)

    # Ctrl and the wheel zoom; Ctrl+0 shows the whole trace again.
    w.send(MouseScroll(0, 2, mx, my, ctrl; time = w.next()))
    @test plot.view !== nothing
    w.send(KeyDown(:zero, ctrl; time = w.next()))
    @test plot.view === nothing

    # Ctrl+= zooms in, and a Shift drag moves the time window with the pointer.
    w.send(KeyDown(:equals, ctrl; time = w.next()))
    w.send(KeyDown(:equals, ctrl; time = w.next()))
    before = g().lo
    w.send(MouseDown(:left, mx, my, shift; time = w.next()))
    w.send(MouseMove(mx - 60, my, MouseButtons(:left), shift; time = w.next()))
    w.send(MouseUp(:left, mx - 60, my, shift; time = w.next()))
    @test g().lo > before
    @test plot.drag_anchor === nothing

    # A button of the corner, while the pointer is over the chart.
    w.send(KeyDown(:zero, ctrl; time = w.next()))
    w.send(MouseMove(mx, my, MouseButtons(), none; time = w.next()))
    parts = SequenceChartModule._find_shown_sequence_chart_parts(
        g(), plot, iomap.toolbar, iomap.right_scroll_bar, iomap.bottom_scroll_bar)
    @test !isempty(parts) && first(parts).field == "toolbar"
    toolbar = first(parts)
    bx, by = ox + toolbar.x + toolbar.w ÷ 6, oy + toolbar.y + toolbar.h ÷ 2
    w.send(MouseMove(bx, by, MouseButtons(), none; time = w.next()))
    w.send(MouseDown(:left, bx, by, none; time = w.next()))
    w.send(MouseUp(:left, bx, by, none; time = w.next()))
    @test plot.view !== nothing

    # A right click on the body opens a menu window.
    count = length(w.windows())
    w.send(MouseDown(:right, mx, my, none; time = w.next()))
    w.send(MouseUp(:right, mx, my, none; time = w.next()))
    @test length(w.windows()) == count + 1

    # A click on an event still selects it, though a press in the body starts a band.
    plot.view = nothing
    run_frame!(w.editor)
    row = first(g().visible_events)
    ex = ox + round(Int, to_pixel(g().scale, g().coordinates[row]) + g().body_x)
    ey = oy + round(Int, g().lane_of[get_event_axis(chart.events, row)] + g().body_y)
    w.send(MouseMove(ex, ey, MouseButtons(), none; time = w.next()))
    w.send(MouseDown(:left, ex, ey, none; time = w.next()))
    w.send(MouseUp(:left, ex, ey, none; time = w.next()))
    @test chart.selection !== nothing && !(chart.selection isa EmptyReference)
end
end
