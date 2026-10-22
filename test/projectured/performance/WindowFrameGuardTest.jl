# The frame guards of the documents in the window: the printer, the reader and the
# evaluator of a document that a person opens keep each frame flat at any size of
# the document. Each scene opens the application window on an SDL backend, as the
# application tests build it, with one document in a tab, and drives it with real
# SDL events: an idle frame, a key that inserts a character, a caret move by a
# line, a step of the wheel, a click on a line, and a move of the pointer. Run it
# with `SDL_VIDEODRIVER=offscreen`, so no window opens on a display. The harness is
# `FrameGuard.jl` of the kernel tests.

const _WINDOW_GUARD_SDL = ProjecturedSDL.SdlModule

const _WINDOW_GUARD_WIDTH, _WINDOW_GUARD_HEIGHT = 1600, 1000

# ── SDL events ──

# Write one event of type `T` into an `SDL_Event` and push it on the queue of SDL.
function _push_window_guard_event!(payload::T) where {T}
    event = Ref{_WINDOW_GUARD_SDL.SDL_Event}()
    GC.@preserve event begin
        base = Base.unsafe_convert(Ptr{_WINDOW_GUARD_SDL.SDL_Event}, event)
        unsafe_store!(convert(Ptr{T}, base), payload)
        _WINDOW_GUARD_SDL.SDL_PushEvent(event)
    end
    nothing
end

# An event of type `T` with the named fields, and 0 in each other field, because the
# fields differ between the versions of the SDL bindings.
function _make_window_guard_event(::Type{T}; values...) where {T}
    given = Dict{Symbol,Any}(values)
    make_field(name) = (F = fieldtype(T, name); value = get(given, name, 0); value isa F ? value : F(value))
    T((make_field(name) for name in fieldnames(T))...)
end

# The native window of the editor, and a point of the window in device pixels.
_get_window_guard_resource(editor) = only(values(editor.backend.windows))
_to_window_guard_device(resource, v) = round(Int32, v * resource.ratio)

function _push_window_guard_motion!(editor, x, y)
    resource = _get_window_guard_resource(editor)
    # The backend draws a hover at most 30 times a second; each motion of a guard
    # counts.
    editor.backend.last_hover_motion = 0.0
    _push_window_guard_event!(_make_window_guard_event(_WINDOW_GUARD_SDL.SDL_MouseMotionEvent;
        type = 0x00000400, windowID = resource.sdl_id,
        x = _to_window_guard_device(resource, x), y = _to_window_guard_device(resource, y)))
end

function _push_window_guard_click!(editor, x, y)
    resource = _get_window_guard_resource(editor)
    for (type, state) in ((0x00000401, 1), (0x00000402, 0))
        _push_window_guard_event!(_make_window_guard_event(_WINDOW_GUARD_SDL.SDL_MouseButtonEvent;
            type, windowID = resource.sdl_id, button = 1, state, clicks = 1,
            x = _to_window_guard_device(resource, x), y = _to_window_guard_device(resource, y)))
    end
end

function _push_window_guard_wheel!(editor, dy)
    resource = _get_window_guard_resource(editor)
    _push_window_guard_event!(_make_window_guard_event(_WINDOW_GUARD_SDL.SDL_MouseWheelEvent;
        type = 0x00000403, windowID = resource.sdl_id, y = dy))
end

# A press and a release of the key with `keycode` and `scancode`.
function _push_window_guard_key!(editor, keycode, scancode)
    resource = _get_window_guard_resource(editor)
    for (type, state) in ((0x00000300, 1), (0x00000301, 0))
        keysym = _make_window_guard_event(_WINDOW_GUARD_SDL.SDL_Keysym; scancode, sym = keycode)
        _push_window_guard_event!(_make_window_guard_event(_WINDOW_GUARD_SDL.SDL_KeyboardEvent;
            type, windowID = resource.sdl_id, state, keysym))
    end
end

const _WINDOW_GUARD_DOWN = (0x40000051, 81)
const _WINDOW_GUARD_UP = (0x40000052, 82)

# The text that a key types, as SDL gives it after the key.
function _push_window_guard_text!(editor, text::AbstractString)
    resource = _get_window_guard_resource(editor)
    T = _WINDOW_GUARD_SDL.SDL_TextInputEvent
    bytes = codeunits(text)
    field = fieldtype(T, :text)
    characters = field(ntuple(i -> i <= length(bytes) ? eltype(field)(bytes[i]) : eltype(field)(0),
                              fieldcount(field)))
    _push_window_guard_event!(_make_window_guard_event(T; type = 0x00000303,
                                                       windowID = resource.sdl_id, text = characters))
end

# ── The window ──

# The application window on an SDL backend with the file `path` in a tab of the
# middle group, which holds the selection, so the keys reach the file.
function _make_window_frame_guard_editor(path::AbstractString, root::AbstractString)
    settings = make_settings()
    document = make_application_document([path]; root, settings)
    steps = collect(get_reference_steps(strip_reference_types(get_selection(document))))
    at = findlast(==(FieldReferenceStep("tabs")), steps)
    steps = vcat(steps[1:at], RangeReferenceStep(1, 2), FieldReferenceStep("content"),
                 FieldReferenceStep("content"))
    set_selection!(document, extend_reference(EmptyReference(), steps...))
    editor = build_editor(document, make_application_projection(); backend = SdlBackend(), settings,
                          window = (; title = "ProjecturEd", width = _WINDOW_GUARD_WIDTH,
                                    height = _WINDOW_GUARD_HEIGHT,
                                    opened_window_projections = make_opened_window_projections()),
                          fault_policy = FaultPolicy(is_console_enabled = false, is_sound_enabled = false),
                          make_application_wrappers(; root, document)...)
    start_application!(editor)
    drain_operations!(editor)
    run_frame!(editor)
    editor
end

# The place in the window of the first drawn text that is `text`: the place of each
# canvas and viewport and the translation of each viewport add up. A list is walked
# at most 200 links from its head. `nothing` when no drawn text is `text`.
function _find_window_guard_text(node, text::AbstractString, ox::Float64 = 0.0, oy::Float64 = 0.0)
    node = unwrap_cell(node)
    if node isa GraphicsCanvas
        x = ox + unwrap_cell(node.x)
        y = oy + unwrap_cell(node.y)
        elements = unwrap_cell(node.elements)
        if elements isa ListNode
            link, seen = elements, 0
            while link !== nothing && seen < 200
                found = _find_window_guard_text(link.value, text, x, y)
                found === nothing || return found
                link, seen = link.next, seen + 1
            end
        else
            for element in elements
                found = _find_window_guard_text(element, text, x, y)
                found === nothing || return found
            end
        end
    elseif node isa GraphicsViewport
        transform = unwrap_cell(node.transform)
        return _find_window_guard_text(node.content, text, ox + unwrap_cell(node.x) + transform.e,
                                       oy + unwrap_cell(node.y) + transform.f)
    elseif node isa GraphicsText
        string(unwrap_cell(node.text)) == text && return (ox + unwrap_cell(node.x), oy + unwrap_cell(node.y))
    end
    nothing
end

# The place a little inside the first drawn text `text` of the window of `editor`,
# found once for each editor and text.
const _WINDOW_GUARD_POINTS = IdDict{Any,Dict{String,Tuple{Int,Int}}}()

function _find_window_guard_point(editor, text::AbstractString)
    points = get!(() -> Dict{String,Tuple{Int,Int}}(), _WINDOW_GUARD_POINTS, editor)
    get!(points, String(text)) do
        point = _find_window_guard_text(get_iomap_output(editor.iomap).windows[1].content, text)
        point === nothing && error("the window draws no text ", repr(text))
        (round(Int, point[1]) + 4, round(Int, point[2]) + 4)
    end
end

# The caret on the text `mark` of the document, and the pointer over it: a click
# through SDL, and frames until the recognizer gives the click, at most 2 seconds.
function _place_window_guard_caret!(editor, mark::AbstractString)
    point = _find_window_guard_point(editor, mark)
    _push_window_guard_motion!(editor, point...)
    _push_window_guard_click!(editor, point...)
    ends = time() + 2.0
    while time() < ends
        run_frame!(editor)
        editor.operation isa ReplaceSelectionOperation && break
        sleep(0.02)
    end
    for _ in 1:5
        sleep(0.02)
        run_frame!(editor)
    end
    nothing
end

# ── The inputs ──

# Each input is a function of the editor, the size and the number of the frame,
# which it gives the input of that frame. Two marks of the document are the texts
# of two lines near its start, so a click and a move land on the document.
_make_window_guard_inputs(marks::NTuple{2,String}) = (
    "an idle frame" => (editor, frame) -> nothing,
    "a key that types a character" => (editor, frame) -> _push_window_guard_text!(editor, "x"),
    "a caret move by a line" => (editor, frame) ->
        _push_window_guard_key!(editor, (isodd(frame) ? _WINDOW_GUARD_DOWN : _WINDOW_GUARD_UP)...),
    "a step of the wheel" => (editor, frame) -> _push_window_guard_wheel!(editor, isodd(frame) ? -1 : 1),
    "a click on a line" => (editor, frame) ->
        _push_window_guard_click!(editor, _find_window_guard_point(editor, marks[isodd(frame) ? 1 : 2])...),
    "a move of the pointer over the document" => (editor, frame) ->
        _push_window_guard_motion!(editor, _find_window_guard_point(editor, marks[isodd(frame) ? 1 : 2])...))

# The editors of one document, one for each size: the six inputs of a document
# share them, because a large file takes seconds to open.
struct WindowGuardEditors
    make_text::Function
    extension::String
    mark::String
    editors::Dict{Int,Any}
    roots::Dict{Int,String}
end

WindowGuardEditors(make_text, extension, mark) =
    WindowGuardEditors(make_text, extension, mark, Dict{Int,Any}(), Dict{Int,String}())

function _get_window_guard_editor!(editors::WindowGuardEditors, size::Int)
    get!(editors.editors, size) do
        root = editors.roots[size] = mktempdir()
        path = joinpath(root, "document." * editors.extension)
        write(path, editors.make_text(size))
        editor = _make_window_frame_guard_editor(path, root)
        _place_window_guard_caret!(editor, editors.mark)
        editor
    end
end

function _close_window_guard_editors!(editors::WindowGuardEditors)
    foreach(editor -> delete!(_WINDOW_GUARD_POINTS, editor), values(editors.editors))
    foreach(editor -> Base.invokelatest(quit_backend!, editor.backend), values(editors.editors))
    foreach(root -> rm(root; recursive = true, force = true), values(editors.roots))
    empty!(editors.editors)
    empty!(editors.roots)
    nothing
end

# A scene of the document of `editors` and the input `input`.
function _make_window_file_frame_guard_scene(name, editors::WindowGuardEditors, input; sizes)
    frame = Ref(0)
    FrameScene(name; sizes,
        make_editor = size -> (frame[] = 0; _get_window_guard_editor!(editors, size)),
        give_input! = (editor, size) -> input(editor, frame[] += 1))
end

# A scene that opens a new copy of a file of `size` lines in a running window, in
# a frame, as a press on a file of the Explorer opens it. Each copy has a path of
# its own, so each open reads and prints the whole file.
function _make_window_open_frame_guard_scene(name, make_text, extension; sizes)
    root = Ref("")
    copy = Ref(0)
    FrameScene(name; sizes, is_burst = true,
        make_editor = function (size)
            root[] = mktempdir()
            write(joinpath(root[], "first." * extension), make_text(1))
            _make_window_frame_guard_editor(joinpath(root[], "first." * extension), root[])
        end,
        give_input! = function (editor, size)
            path = joinpath(root[], "document $(copy[] += 1)." * extension)
            write(path, make_text(size))
            post_operation!(editor, OpenFileOperation(path))
        end,
        release_editor = function (editor)
            Base.invokelatest(quit_backend!, editor.backend)
            rm(root[]; recursive = true, force = true)
        end)
end

# ── The documents ──

_make_window_guard_julia_text(size) = join(("f$(i)(x) = x + $(i)" for i in 1:size), "\n") * "\n"
_make_window_guard_json_text(size) =
    "[\n" * join(("  {\"n\": $(i), \"name\": \"item $(i)\"}" for i in 1:size), ",\n") * "\n]\n"
_make_window_guard_markdown_text(size) =
    join(("Paragraph $(i) has a few words of text in it, and it ends here." for i in 1:size), "\n\n") * "\n"

# The sizes are small, because a gesture in a large file takes seconds: a caret
# move took 11 s in a Julia file of 10_000 lines, and a move of the pointer 9 s in
# a JSON file of 3_000 objects. A Julia file of 100_000 lines did not open in 14
# minutes.
const _WINDOW_GUARD_DOCUMENTS = (
    (name = "a Julia file", make_text = _make_window_guard_julia_text, extension = "jl",
     sizes = [100, 1_000], marks = ("f3", "f5")),
    (name = "a JSON file", make_text = _make_window_guard_json_text, extension = "json",
     sizes = [100, 1_000], marks = ("item 3", "item 5")),
    # 30 times, so a growth below linear stands clear of the bound.
    (name = "a Markdown file", make_text = _make_window_guard_markdown_text, extension = "md",
     sizes = [100, 3_000], marks = ("Paragraph 3 has a few words of text in it, and it ends here.",
                                    "Paragraph 5 has a few words of text in it, and it ends here.")),
)

# The inputs of the documents whose frames grow with the document, by the names of
# the document and of the input; see step 5 of the guards plan.
const _WINDOW_GUARD_GROWING = Set{Tuple{String,String}}([
    ("a Julia file", "a caret move by a line"), ("a Julia file", "a click on a line"),
    ("a Julia file", "a move of the pointer over the document"),
    ("a Markdown file", "a key that types a character"), ("a Markdown file", "a click on a line"),
    ("a Markdown file", "a move of the pointer over the document")])

# A frame of a window takes up to seconds, so a window scene warms up for 3 frames
# and measures 5.
const _WINDOW_GUARD_FRAMES = (warm_frames = 3, frames = 5)

function test_window_frame_guards()
@testset "the frame guards of the documents in the window" begin
    for document in _WINDOW_GUARD_DOCUMENTS
        @testset "$(document.name)" begin
            editors = WindowGuardEditors(document.make_text, document.extension, first(document.marks))
            try
                for (input_name, input) in _make_window_guard_inputs(document.marks)
                    @testset "$(input_name)" begin
                        scene = _make_window_file_frame_guard_scene(
                            "$(input_name) in $(document.name)", editors, input; sizes = document.sizes)
                        works = measure_frame_work(scene; _WINDOW_GUARD_FRAMES...)
                        growth = compute_frame_growth(works)
                        print_frame_work(scene.name, works)
                        if (document.name, input_name) in _WINDOW_GUARD_GROWING
                            # @broken: the reader and the printer of the document do work that grows with the document; the table of step 5 of plan/pending/guards-keep-the-frame-short-at-any-size.md
                            @test_broken growth.time_ratio <= FLAT_TIME_RATIO
                        else
                            @test growth.time_ratio <= FLAT_TIME_RATIO
                            @test growth.allocation_ratio <= FLAT_ALLOCATION_RATIO
                        end
                    end
                end
            finally
                _close_window_guard_editors!(editors)
            end
            @testset "the open of the file in a running window" begin
                scene = _make_window_open_frame_guard_scene("the open of $(document.name)",
                    document.make_text, document.extension; sizes = document.sizes)
                works = measure_frame_work(scene; repetitions = 1)
                growth = compute_frame_growth(works)
                print_frame_work(scene.name, works)
                @test all(work -> work.is_finished, works)
                # @broken: the open reads and prints the whole file in one frame, and the time grows faster than the file; the table of step 5 of plan/pending/guards-keep-the-frame-short-at-any-size.md
                @test_broken growth.time_ratio <= FLAT_TIME_RATIO
            end
        end
    end
end
end
