# The view gestures of a chart in an application window, as a person makes them:
# each one is window input at the pixels of the chart in a tab, so the keys, the
# wheel, the drags, the menu, the buttons and the bars reach the chart through the
# whole editor.

using Test

_cvg_force(value) = value isa AbstractCell ? _cvg_force(value[]) : value

# The first IO map of type `T` in the IO map tree under `root`.
function _cvg_find_iomap(root, T)
    seen = Set{UInt}()
    stack = Any[root]
    while !isempty(stack)
        value = _cvg_force(pop!(stack))
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

# The point of the window where `canvas` is drawn, or `nothing`: the sum of the
# places of the nodes on the way to it.
function _cvg_find_place(node, canvas, x = 0, y = 0, seen = Set{UInt}())
    node = _cvg_force(node)
    (node === nothing || node isa Union{Number,AbstractString,Symbol,Function,Type,Module,IoMap}) &&
        return nothing
    if node isa Union{AbstractVector,Tuple}
        for child in node
            found = _cvg_find_place(child, canvas, x, y, seen)
            found === nothing || return found
        end
        return nothing
    end
    isstructtype(typeof(node)) || return nothing
    if ismutable(node)
        objectid(node) in seen && return nothing
        push!(seen, objectid(node))
    end
    hasproperty(node, :x) && _cvg_force(node.x) isa Real && (x += Int(_cvg_force(node.x)))
    hasproperty(node, :y) && _cvg_force(node.y) isa Real && (y += Int(_cvg_force(node.y)))
    node === canvas && return (x, y)
    for name in fieldnames(typeof(node))
        name in (:projection, :input, :output, :parent) && continue
        found = _cvg_find_place(getfield(node, name), canvas, x, y, seen)
        found === nothing || return found
    end
    nothing
end

# An application window with `chart` shown in a tab, and the means to press on it.
function _cvg_open(chart)
    window, projection = make_application_window(String[]; root = mktempdir(), assistant = nothing)
    editor = build_editor(window, projection; backend = HeadlessBackend(), tabs = false,
                          window = (; title = "ProjecturEd", width = 1280, height = 720,
                                    opened_window_projections = make_opened_window_projections(;
                                        content = make_application_content_projections())))
    start_application!(editor)
    run_frame!(editor)
    tab = open_pane!(chart; title = "Chart", editor)
    run_frame!(editor)
    show_pane!(tab; editor)
    foreach(_ -> run_frame!(editor), 1:3)
    windows() = _cvg_force(_cvg_force(get_iomap_output(editor.iomap)).windows)
    id = _cvg_force(first(windows())).id
    time = Ref(0.0)
    send(event) = (push_event!(editor.backend, WindowInput(id, event)); run_frame!(editor))
    next() = (time[] += 0.6; time[])
    canvas_iomap() = _cvg_find_iomap(editor.iomap, ChartPlotToGraphicsCanvasIoMap)
    # The place of the chart canvas in the window.
    origin() = (iomap = canvas_iomap();
                something(_cvg_find_place(_cvg_force(first(windows())).content, iomap.output)))
    (; editor, send, next, canvas_iomap, origin, windows)
end

"""
    test_chart_view_gestures()

The view gestures of a chart in a tab of the application window: Ctrl and the
wheel zoom, a Shift drag and a drag with the middle button pan, Ctrl+0 shows all the
data, a page key scrolls, a right click opens the menu, a button of the corner
zooms, a click on the track of a bar scrolls, a click on an axis still selects it,
and Ctrl+Shift with an arrow moves a series.
"""
function test_chart_view_gestures()
@testset "the view gestures of a chart in the editor" begin
    t = collect(0.0:0.1:30.0)
    chart = Chart("Signal", Any[ChartLineSeries("a", t, sin.(t) .* 4 .+ 10),
                                ChartLineSeries("b", t, cos.(t) .* 2 .+ 10)])
    w = _cvg_open(chart)
    iomap = w.canvas_iomap()
    @test iomap !== nothing
    plot = iomap.input
    ox, oy = w.origin()
    g() = w.canvas_iomap().geometry
    middle() = (ox + g().plot_x + g().plot_w ÷ 2, oy + g().plot_y + g().plot_h ÷ 2)
    none, ctrl, shift = ModifierKeys(), ModifierKeys(; ctrl = true), ModifierKeys(; shift = true)
    mx, my = middle()

    # Ctrl and the wheel zoom; Ctrl+0 shows all the data again.
    w.send(MouseScroll(0, 2, mx, my, ctrl; time = w.next()))
    @test plot.view isa ChartView
    w.send(KeyDown(:zero, ctrl; time = w.next()))
    @test plot.view === nothing

    # Ctrl+= zooms in, and a Shift drag pans the window with the pointer.
    w.send(KeyDown(:equals, ctrl; time = w.next()))
    w.send(KeyDown(:equals, ctrl; time = w.next()))
    zoomed = plot.view
    @test zoomed isa ChartView
    w.send(MouseDown(:left, mx, my, shift; time = w.next()))
    w.send(MouseMove(mx - 60, my, MouseButtons(:left), shift; time = w.next()))
    w.send(MouseUp(:left, mx - 60, my, shift; time = w.next()))
    @test plot.view.x_min > zoomed.x_min
    @test plot.view.x_max - plot.view.x_min ≈ zoomed.x_max - zoomed.x_min
    @test plot.drag_anchor === nothing

    # A drag with the middle button pans too.
    panned = plot.view
    w.send(MouseDown(:middle, mx, my, none; time = w.next()))
    w.send(MouseMove(mx + 40, my, MouseButtons(:middle), none; time = w.next()))
    w.send(MouseUp(:middle, mx + 40, my, none; time = w.next()))
    @test plot.view.x_min < panned.x_min

    # Page Down scrolls a page down.
    before = plot.view
    w.send(KeyDown(:page_down, none; time = w.next()))
    @test plot.view.y_max < before.y_max

    # A button in the corner, while the pointer is over the chart.
    w.send(KeyDown(:zero, ctrl; time = w.next()))
    w.send(MouseMove(mx, my, MouseButtons(), none; time = w.next()))
    parts = ChartModule._find_shown_chart_parts(w.canvas_iomap())
    @test !isempty(parts) && first(parts).field == "toolbar"
    toolbar = first(parts)
    bx, by = ox + toolbar.x + toolbar.w ÷ 6, oy + toolbar.y + toolbar.h ÷ 2
    w.send(MouseMove(bx, by, MouseButtons(), none; time = w.next()))
    w.send(MouseDown(:left, bx, by, none; time = w.next()))
    w.send(MouseUp(:left, bx, by, none; time = w.next()))
    @test plot.view isa ChartView

    # A click on the track of the bar under the plot scrolls a page across.
    w.send(MouseMove(mx, my, MouseButtons(), none; time = w.next()))
    under = something(findfirst(part -> part.field == "horizontal_scroll_bar",
                                ChartModule._find_shown_chart_parts(w.canvas_iomap())))
    bar = ChartModule._find_shown_chart_parts(w.canvas_iomap())[under]
    before = plot.view
    tx, ty = ox + bar.x + bar.w - 3, oy + bar.y + bar.h ÷ 2
    w.send(MouseMove(tx, ty, MouseButtons(), none; time = w.next()))
    w.send(MouseDown(:left, tx, ty, none; time = w.next()))
    w.send(MouseUp(:left, tx, ty, none; time = w.next()))
    @test plot.view.x_min > before.x_min

    # A right click on the plot opens a menu window.
    count = length(w.windows())
    w.send(MouseDown(:right, mx, my, none; time = w.next()))
    w.send(MouseUp(:right, mx, my, none; time = w.next()))
    @test length(w.windows()) == count + 1

    # A click on a data point still selects it, though a press in the plot starts a
    # band, and a click on the x axis still selects the axis, though a press there
    # starts a pan.
    plot.view = nothing
    run_frame!(w.editor)
    k = 101
    sx = ox + round(Int, PlotModule.to_pixel(g().xs, t[k]))
    sy = oy + round(Int, PlotModule.to_pixel(g().ys, sin(t[k]) * 4 + 10))
    w.send(MouseMove(sx, sy, MouseButtons(), none; time = w.next()))
    w.send(MouseDown(:left, sx, sy, none; time = w.next()))
    w.send(MouseUp(:left, sx, sy, none; time = w.next()))
    @test get_selected_sample(chart) == (1, k)
    ax, ay = mx, oy + g().plot_y + g().plot_h + 4
    w.send(MouseMove(ax, ay, MouseButtons(), none; time = w.next()))
    w.send(MouseDown(:left, ax, ay, none; time = w.next()))
    w.send(MouseUp(:left, ax, ay, none; time = w.next()))
    @test get_chart_part_index(chart, chart.selection) == 2

    # Ctrl+Shift and an arrow move the selected series, and pan nothing.
    chart.selection = collect_chart_parts(chart)[end]
    plot.view = ChartView(5.0, 15.0, 7.0, 13.0)
    run_frame!(w.editor)
    w.send(KeyDown(:up, ModifierKeys(; ctrl = true, shift = true); time = w.next()))
    @test String(chart.series[1].label) == "b"
    @test plot.view == ChartView(5.0, 15.0, 7.0, 13.0)
end
end
