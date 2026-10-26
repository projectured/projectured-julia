# A scroll costs what comes into view. Three panes of the application scroll by
# the wheel: a Julia file in a focused tab, the Files pane and a data frame. Each
# frame is painted by the walk of the partial paint into an offscreen renderer,
# and its pixels are compared with a full paint. The test counts the work of each
# frame: the boxes that it copies, the leaves that it draws, and the elements,
# records and guards of its walk. The counts hold on a busy machine, where a time
# does not.

using Test

const _SW_SDL = ProjecturedSDL.SdlModule
const _SW_WIDTH, _SW_HEIGHT = 1600, 1000
const _SW_BACKGROUND = (0xff, 0xff, 0xff, 0xff)

_sw_read_pixels(off) = (_SW_SDL.SDL_RenderFlush(off.renderer); s = unsafe_load(off.surface);
                        copy(unsafe_wrap(Array, Ptr{UInt32}(s.pixels), (Int(s.pitch) ÷ 4, Int(s.h)))))

# The window of the application over a Julia file of `count` functions, with its
# tab focused, as a person who opened the file has it.
function _sw_make_julia_editor(backend, count::Int)
    directory = mktempdir()
    path = joinpath(directory, "values.jl")
    write(path, join(["# The value $k.\nfunction value_$k(x)\n    x + $k\nend\n" for k in 1:count], "\n"))
    document, projection = make_application_window([path]; root = mkpath(joinpath(directory, "empty")),
                                                   assistant = nothing)
    _app_focus_first_file!(document)
    build_editor(document, projection; backend, tabs = false,
                 window = (; title = "ProjecturEd", width = _SW_WIDTH, height = _SW_HEIGHT,
                           opened_window_projections = make_opened_window_projections()))
end

# The canvases of `canvas` that the paint of `res` draws with more than `limit`
# elements and no layout, or with overlap, as their counts of elements. A walk and
# a paint visit each element of such a canvas, whatever the view shows.
function _sw_find_unlaid_canvases(res, canvas; limit::Int = 200)
    SDL = _SW_SDL
    found = Int[]
    function visit_canvas(canvas, key, ox, oy, edges)
        elements = canvas.elements
        layout = canvas.layout
        early = SDL._is_early_stop_layout(canvas)
        if elements isa ListNode
            early || return nothing
            for node in SDL._collect_drawn_nodes(elements, ox, oy, edges, layout, early)
                value = node.value
                visit(value, SDL._make_placement_key(value, SDL._make_placement_key(node, key)), ox, oy, edges)
            end
            return nothing
        end
        early || length(elements) <= limit || push!(found, length(elements))
        for i in SDL._compute_first_drawn_index(canvas, ox, oy, edges):length(elements)
            elem = elements[i]
            elem isa GraphicsFence && continue
            SDL._is_past_early_stop(elem, ox, oy, edges, layout, early) && break
            visit(elem, SDL._make_placement_key(elem, key), ox, oy, edges)
        end
    end
    function visit(elem, key, ox, oy, edges)
        haskey(res.painted.origins, key) || return nothing
        if elem isa GraphicsCanvas
            visit_canvas(elem, key, ox + Int(elem.x), oy + Int(elem.y), edges)
        elseif elem isa GraphicsViewport
            box, content, transform = SDL._get_viewport_geometry(elem, ox, oy)
            cox, coy, cedges = SDL._compute_viewport_content_place(box, content, transform)
            visit_canvas(content, SDL._make_placement_key(content, key), cox, coy, cedges)
        end
        nothing
    end
    visit_canvas(canvas, SDL._make_placement_key(canvas, UInt(0)), 0, 0,
                 SDL._ClipEdges(0, 0, res.width, res.height))
    found
end

# The frames of `notches` turns of the wheel at `(x, y)` in the window `id` of
# `editor`, after a first paint. Each frame tells whether its pixels equal a full
# paint, the boxes that it copied, the leaves that it drew, the leaves that a paint
# of the whole window draws, and the counts of its walk. Also the canvases with no
# layout that the last frame drew.
function _sw_scroll(editor, backend, id::Symbol, x::Int, y::Int; notches::Int = 6)
    SDL = _SW_SDL
    width, height, background = _SW_WIDTH, _SW_HEIGHT, _SW_BACKGROUND
    partial = SDL.open_offscreen_renderer(width, height; supersample = 1, density = 1)
    full = SDL.open_offscreen_renderer(width, height; supersample = 1, density = 1)
    frames = NamedTuple[]
    canvas() = last(rendered_output(backend)).windows[1].content
    try
        state = SDL.make_offscreen_paint_state(partial)
        foreach(_ -> run_frame!(editor), 1:3)
        SDL.render_offscreen_changes!(partial, state, canvas(); background)
        for n in 1:notches
            push_event!(backend, WindowInput(id, MouseScroll(0, -1, x, y, ModifierKeys(); time = 10.0 + n)))
            run_frame!(editor)
            SDL.render_offscreen_changes!(partial, state, canvas(); background)
            painted = state.res.painted
            SDL._render_canvas_offscreen!(full, canvas(), width, height, background)
            same = _sw_read_pixels(partial) == _sw_read_pixels(full)
            whole = SDL._paint_dirty_rects!(full.renderer, canvas(), [(0, 0, width, height)], background,
                                            width, height, 1.0; records = state.res.dirty_bounds).drawn
            push!(frames, (; same, copies = length(state.last_copies), drawn = state.last_drawn, whole,
                           work = (painted.visits, painted.recordings, painted.new_guards)))
        end
        (frames, _sw_find_unlaid_canvases(state.res, canvas()))
    finally
        SDL.close_offscreen_renderer(partial)
        SDL.close_offscreen_renderer(full)
    end
end

"""
    test_scroll_work()

A scroll of a Julia file in a focused tab, of the Files pane and of a data frame
paints the pixels of a full paint, copies the boxes whose content only moved,
draws a small part of what the window shows, and does work that does not grow
with the length of the file.
"""
function test_scroll_work()
@testset "a scroll costs what comes into view" begin
    @testset "a Julia file in a focused tab" begin
        short_backend, long_backend = HeadlessBackend(), HeadlessBackend()
        short = _sw_make_julia_editor(short_backend, 200)
        long = _sw_make_julia_editor(long_backend, 800)
        short_frames, _ = _sw_scroll(short, short_backend, :ProjecturEd, 700, 500)
        frames, unlaid = _sw_scroll(long, long_backend, :ProjecturEd, 700, 500)
        @test all(f -> f.same, frames)
        # The gutter and the text are two boxes that move.
        # @broken: the focus ring of the pane counts as a graphic over both boxes; plan/pending/a-scroll-costs-what-comes-into-view.md
        @test_broken all(f -> f.copies == 2, frames)
        # A notch of 48 pixels in a pane of 879 draws less than half of what the
        # window shows; a paint of the whole box draws almost all of it.
        # @broken: the focus ring makes the paint draw both boxes; plan/pending/a-scroll-costs-what-comes-into-view.md
        @test_broken all(f -> 2 * f.drawn <= f.whole, frames)
        # A file four times as long costs the same work.
        # @broken: the gutter rows lie in a canvas with no layout, so the walk visits each; plan/pending/a-scroll-costs-what-comes-into-view.md
        @test_broken [f.work for f in frames] == [f.work for f in short_frames]
        # @broken: the gutter rows lie in a canvas with no layout; plan/pending/a-scroll-costs-what-comes-into-view.md
        @test_broken isempty(unlaid)
    end
    @testset "the Files pane" begin
        folder = mktempdir()
        foreach(k -> mkpath(joinpath(folder, string("d", lpad(k, 3, '0')))), 1:50)
        foreach(k -> write(joinpath(folder, string("f", lpad(k, 3, '0'), ".jl")), ""), 1:450)
        explorer = WorkspaceExplorer(Workspace([WorkspaceFolder("folder", folder)]))
        foreach(f -> read_filesystem_folder!(f.directory), explorer.workspace.folders)
        backend = HeadlessBackend()
        editor = build_editor(explorer; backend, window = (; title = "Files", width = _SW_WIDTH, height = _SW_HEIGHT),
                              tabs = (; title = "Files"))
        frames, unlaid = _sw_scroll(editor, backend, :Files, 300, 500)
        @test all(f -> f.same, frames)
        @test all(f -> f.copies == 1, frames)
        @test all(f -> 2 * f.drawn <= f.whole, frames)
        @test isempty(unlaid)
    end
    @testset "a data frame" begin
        frame = DataFrames.DataFrame(id = 1:1000, name = ["row $k" for k in 1:1000], value = [k / 7 for k in 1:1000])
        backend = HeadlessBackend()
        editor = build_editor(ProjecturedDataFrames.DataFrameView(frame); backend,
                              window = (; title = "Data", width = _SW_WIDTH, height = _SW_HEIGHT),
                              tabs = (; title = "Data"))
        frames, unlaid = _sw_scroll(editor, backend, :Data, 700, 500)
        @test all(f -> f.same, frames)
        # @broken: the grid of the cells stays while the cells move, and its rules give more than 32 rectangles; plan/pending/a-scroll-costs-what-comes-into-view.md
        @test_broken all(f -> f.copies >= 1, frames)
        # @broken: the grid of the cells makes the paint draw the whole table; plan/pending/a-scroll-costs-what-comes-into-view.md
        @test_broken all(f -> 2 * f.drawn <= f.whole, frames)
        @test isempty(unlaid)
    end
end
end
