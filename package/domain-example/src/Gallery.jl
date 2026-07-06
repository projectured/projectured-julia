# domain-example/src/Gallery.jl
#
# The example gallery: `run_example` opens one window per example, side by
# side, with optional cross-domain wrappers (workbench, tooltip, inspector,
# clipboard, introspection, text filtering/highlighting; that domain
# vocabulary is why the gallery's lowest home is the domain tier). SDL is
# reached only through the `make_backend(:sdl)` seam; an explicit `backend`
# (e.g. the web backend) wins. The name-lookup entry points
# (`run_example("json")`, `run_web_example`) live in the `ProjecturedExample`
# umbrella, which owns the global registry.

function run_example(example::Example; kwargs...)
    run_example([example]; kwargs...)
end

"""
    run_example(examples::Vector{Example}; width, height,
                caching=false, scrolling=false, workbench=false, reset=false,
                tooltip=false, inspector=false, introspection=false, selection=nothing,
                profile=false)

Open one window per example, side by side. Each example contributes a
`WindowDocument` with the example's domain document as content; the
composed projection dispatches each window's content to that example's
own projection by **reference path** (so two examples with the same
content type — e.g. both JSON, both wrapped in `WidgetScrollPane` —
still each render through their own pipeline).

Examples carry no pre-set selection. Pass `selection` (a
reference path, e.g. `@reference entries[1].value.value{2}`) to seed the
initial selection; it is applied to the first example's bare domain
document and then lifted to a screen-rooted path (see below). When
`selection === nothing` (the default) the editor opens with no selection.

When `tooltip=true`, each example's content is wrapped in a
`TooltipSource`. While the user has a selection inside that example,
a sibling tooltip window opens (id `:tooltip_<example-name>`) showing
the selection's reference path in two forms: the short, color-coded
shape from `ReferenceToText` on the first line, followed by a blank
line and the multi-line human-readable narrative from
`ReferenceToHumanReadableText`. The tooltip closes when the selection
is cleared.

When `inspector=true`, a secondary `:inspector` window **follows the mouse**
and shows the reference a single left-click *would* create at the current
pointer — without committing it as a selection. Each example window's content
projection is wrapped in a `HoverProbeProjection`, whose reader reverse-projects
each idle `MouseMove` (feeding a synthetic `MousePress` to the wrapped reader)
and drives the follower window via `OpenWindowOperation` / `CloseWindowOperation`.
The window's content is a `ReferenceInspector` rendered the same two ways as the
tooltip (compact `ReferenceToText` + human-readable `ReferenceToHumanReadableText`).
It closes over dead space. Desktop-only (needs the SDL backend's global mouse via
`get_pointer_position`); mutually exclusive with `tooltip` and `workbench`.

When `introspection=true`, each example's content is wrapped in a
`WidgetTabbedPane` with three tabs: the original content (rendered with
the example's own projection), the editor's document, and the editor's
projection (both rendered generically via `ObjectToSyntax`).

When `text_highlighting=true` (or `text_filtering=true`), the example's
projection is replaced by a `ProjectionConfiguringProjection` that stacks an
editable control bar for a `TextHighlighting` (resp. `TextFiltering`)
projection above the projected text. Editing the controls re-highlights /
re-filters live; `Ctrl+F` toggles the bar, `Escape` hides it. Expects a
`TextText` document (the text examples). The two flags are mutually exclusive.

When `clipboard=true`, each example is wrapped in a `ClipboardSlice` and the
clipboard projection is stacked on top of the example's own pipeline (the
introspection wrapper pattern), so the selection-driven copy / cut / note /
paste flow (`Ctrl+C` / `Ctrl+X` / `Ctrl+N` / `Ctrl+V`, `Ctrl+/` to toggle the
stored slice) works over any example. `clipboard_collection=true` uses a
`ClipboardCollection` (the elements view) instead. For a `TextText` example the
wrapper enables **text mode**: copy / cut / paste operate on character ranges,
the ProjecturEd clipboard is the primary store, and the **OS clipboard** is
mirrored on copy/cut and used as the paste fallback (needs `xclip`/`xsel`/`wl-*`).
For other (structured) domains the generic wrapper leaves the OS-clipboard bridge
off (pasting OS text into an arbitrary node domain is not type-safe); the
dedicated `clipboard_example` wires JSON converters for it. Incompatible with
`tooltip` and `inspector`.

When `profile=true`, the read-eval-print loop runs under `Profile.@profile`.
The profile buffer is cleared first; once the editor window is closed (the
loop exits) a sampled backtrace report is printed via `Profile.print`.
"""
function run_example(examples::Vector{Example}; width=nothing, height=nothing,
                     caching=false, scrolling=false, workbench=false, reset=false,
                     tooltip=false, inspector=false, introspection=false,
                     clipboard=false, clipboard_collection=false,
                     text_filtering=false, text_highlighting=false, selection=nothing,
                     profile=false, backend=nothing, partial_render=nothing, debug_dirty=nothing)
    isempty(examples) && error("run_example: empty examples vector")
    if text_filtering && text_highlighting
        error("run_example: text_filtering and text_highlighting are mutually exclusive")
    end
    if inspector && (tooltip || workbench)
        error("run_example: inspector=true is not compatible with tooltip=true or workbench=true")
    end
    clipboard = clipboard || clipboard_collection
    if clipboard && (tooltip || inspector)
        error("run_example: clipboard=true is not compatible with tooltip=true or inspector=true")
    end
    if width === nothing || height === nothing
        sw, sh = get_display_size()
        width  = something(width,  sw)
        height = something(height, sh)
    end
    if tooltip && workbench
        error("run_example: tooltip=true is not compatible with workbench=true")
    end

    # Prepare (document, projection) pairs with the same flags applied as
    # the single-example path.
    docs  = Any[]
    projs = Any[]
    for (i, ex) in enumerate(examples)
        document   = reset ? ex.make_document()   : ex.document
        projection = reset ? ex.make_projection() : ex.projection
        # Apply a caller-supplied selection to the first example's bare domain
        # document, before any workbench/scrolling/introspection wrapping. The
        # selection-lifting step below then promotes it to a screen-rooted path.
        if selection !== nothing && i == 1
            set_selection!(document, selection)
        end
        if workbench
            document   = make_workbench_document(document; title=ex.name)
            projection = make_workbench_projection()
        elseif scrolling
            document   = make_scrolling_document(document; width=width, height=height)
            projection = make_scrolling_projection(projection)
        elseif introspection
            document   = make_introspection_document(document, projection; title=ex.name)
            projection = make_introspection_projection(projection)
        elseif clipboard
            # Wrap the example in a ClipboardSlice (or ClipboardCollection) and stack
            # the clipboard projection on top of the example's own pipeline. The
            # seeded selection (set on the bare document above) now lives behind the
            # clipboard's `content`; the selection-lifting loop below re-roots it.
            # For a TextText document, enable text mode: copy/cut/paste over character
            # ranges, with the OS clipboard mirrored on copy/cut and used as the paste
            # fallback (the projectured slice is the primary store).
            is_text    = document isa TextText
            document   = make_clipboard_document(document; collection=clipboard_collection)
            projection = make_clipboard_projection(projection; collection=clipboard_collection, text=is_text)
        elseif text_highlighting
            # Stack a TextHighlighting control bar above the (text) document; the
            # example's own projection is replaced by the configuring pipeline.
            # A default pattern makes the highlight (and the case_insensitive
            # toggle's effect) visible out of the box. Expects a TextText document.
            projection = make_text_configuring_projection(TextHighlighting("dolor"))
        elseif text_filtering
            projection = make_text_configuring_projection(TextFiltering("dolor"))
        end
        if caching
            projection = make_graphics_caching(projection)
        end
        push!(docs, document)
        push!(projs, projection)
    end

    # When the tooltip flag is on, wrap each window's content in a
    # TooltipSource and pick the tooltip-aware multi-window projection.
    if tooltip
        tt_docs = Any[]
        for (i, ex) in enumerate(examples)
            push!(tt_docs, _make_tooltip_source(docs[i]; id = Symbol("tooltip_", ex.name)))
        end
        docs = tt_docs
    end

    # An explicit `backend` (e.g. the WebBackend from run_web_example) wins;
    # otherwise build the SDL backend, threading the render-control knobs.
    # Built before composing because the inspector pipeline needs a pointer
    # closure over the backend's global mouse position.
    backend === nothing && (backend = make_backend(:sdl; partial_render=partial_render, debug_dirty=debug_dirty))
    # How deep the original (selection-bearing) document sits under `win.content`.
    content_unwrap = tooltip ? :tooltip : clipboard ? :clipboard : :plain
    # `compose(projs, backend)` — the inspector pipeline needs the backend for its
    # pointer closure, hence the second argument.
    compose = inspector ? (p, b) -> _multi_window_projection_inspector(p; pointer = () -> get_pointer_position(b)) :
              tooltip   ? (p, b) -> _multi_window_projection_tooltipped(p) :
                          (p, b) -> _multi_window_projection(p)
    _run_window_scene(docs, projs, String[ex.name for ex in examples];
                      width=width, height=height, backend=backend,
                      compose=compose, profile=profile, content_unwrap=content_unwrap)
end

# Lay out `docs` as side-by-side WindowDocuments into a ScreenDocument and lift the
# first window-content's selection to a screen-rooted path. Each `names[i]` becomes
# window i's id/title (ids must be unique within the screen). `content_unwrap` says
# how deep the original (selection-bearing) document sits under `win.content`:
# `:plain` (the content itself), `:tooltip` (`.child`), or `:clipboard` (`.content`).
#
# The selection lift matters because the screen and intermediate WindowDocument keep
# `selection = nothing` while the inner document may carry a deep selection; without
# re-rooting it, the next click traverses a different branch and the stale leaf
# selection is never cleared (`_collect_spans` then picks the first cursor it finds,
# so new clicks look ignored). With no seeded selection every document keeps
# `selection = nothing` and this loop is a no-op.
#
# Factored out of `run_example` so other entry points (e.g. `run_file_editor`) share
# the exact same scene assembly. Pure (no backend, no window) so it is testable.
function _build_window_scene(docs, names; width, height, content_unwrap::Symbol=:plain)
    seen_ids = Set{Symbol}()
    windows = WindowDocument[]
    for (i, nm) in enumerate(names)
        id = Symbol(nm)
        id in seen_ids && error("run_example: duplicate example name :$id; window ids must be unique")
        push!(seen_ids, id)
        push!(windows, WindowDocument(;
            id     = id,
            title  = nm,
            x      = 100 + (i - 1) * (width + 40),
            y      = 100,
            width  = width,
            height = height,
            content = docs[i],
        ))
    end
    screen = ScreenDocument(windows)

    for (i, win) in enumerate(windows)
        root_doc = content_unwrap === :tooltip   ? win.content.child :
                   content_unwrap === :clipboard ? win.content.content :
                                                   win.content
        inner_sel = getfield(root_doc, :selection)[]
        inner_sel === nothing && continue
        full_path = content_unwrap === :tooltip   ? (@reference windows[i].content.child.^(inner_sel)) :
                    content_unwrap === :clipboard ? (@reference windows[i].content.content.^(inner_sel)) :
                                                    (@reference windows[i].content.^(inner_sel))
        set_selection!(screen, full_path)
        break
    end
    screen
end

# Build the scene (above), compose the screen projection via `compose(projs, backend)`,
# and run the editor loop on `backend` (optionally under the profiler). The shared tail
# of `run_example` and `run_file_editor`.
function _run_window_scene(docs, projs, names; width, height, backend,
                           compose, profile::Bool=false, content_unwrap::Symbol=:plain,
                           mcp::Bool=false)
    screen = _build_window_scene(docs, names; width=width, height=height, content_unwrap=content_unwrap)
    composed = compose(projs, backend)
    if profile
        Profile.clear()
        try
            Profile.@profile run_editor!(backend, composed, screen; mcp=mcp)
        finally
            Profile.print(; mincount=10)
        end
    else
        run_editor!(backend, composed, screen; mcp=mcp)
    end
end

# Build a projection that projects the screen down to each
# `windows[i].content` reference and applies the matching example's
# projection only at that exact leaf. Dispatch by reference path rather than
# content type so two examples with the same root document type still each
# render through their own pipeline.
#
# `ScreenToScreen` owns the screen spine: it recurses each window's `content`
# (and nothing above it) back through this dispatch, with the content's
# reference being `windows[i].content` (the i-th window is an
# `ElementReference`), which is how the target paths are built.
function _multi_window_projection(projections::Vector; measure=truetype_measure_text)
    n = length(projections)
    targets = Vector{Any}(undef, n)
    for i in 1:n
        targets[i] = @reference windows[i].content
    end
    # One shared open/closed flag for the gesture-help window, threaded into every
    # (per-dispatch, transient) decorator so F1 toggles the same window.
    help_state = GestureHelpState()
    ref_dispatch = ReferenceDispatchingProjection(ref -> begin
        # Exact match — apply that window's example projection here, wrapped in a
        # GestureHelpProjection so F1 in the focused window opens a help window
        # listing the gestures collected from this content's own pipeline. The
        # NestingProjection (recursion=IdentityProjection) lets the inner
        # projection's own recursion take over below this point.
        for i in 1:n
            is_reference_equal(ref, targets[i]) || continue
            return GestureHelpProjection(
                inner = NestingProjection(projections[i]; recursion=IdentityProjection()),
                state = help_state)
        end
        # The ScreenDocument root is the window-management seam: route it
        # through WindowManagingProjection (window open/close/resize ops are
        # owned there) wrapping ScreenToScreen, which projects the screen
        # shell and recurses each window's content back through this dispatch.
        ref isa EmptyReferencePath &&
            return WindowManagingProjection(inner = ScreenToScreen())
        # Anything outside a window's content target — preserve.
        return IdentityProjection()
    end)
    # A type seam in front of the reference dispatch so dynamically-opened windows
    # render by content type: a `WindowDocument` (re-projected by the manager when
    # a window opens) recurses via ScreenToScreen, and a help `GestureMap` window
    # renders down to graphics. Existing content is `Any` → the reference dispatch,
    # unchanged (TypeDispatching is transparent for the matched arm).
    return RecursiveProjection(
        TypeDispatchingProjection(
            WindowDocument => ScreenToScreen(),
            GestureMap     => ChainingProjection(GestureMapToSyntax(),
                                                   RecursiveProjection(SyntaxToText()),
                                                   WordWrapping(measure=measure),
                                                   TextToGraphics(measure=measure)),
            Any            => ref_dispatch,
        ))
end

# ── Tooltip variant ──────────────────────────────────────────────────────
#
# Wrap a domain document in a `TooltipSource` whose `content` is a
# *reactive* `TextText`: the elements thunk re-reads `doc.selection`
# every frame and rebuilds the colored spans via `ReferenceToText`. The
# `TooltipDecoratorProjection` reader watches the wrapped document and
# emits `OpenWindowOperation` / `CloseWindowOperation` as the selection
# arrives / clears; the `WindowManagingProjection` applies those to the
# screen.

function _make_tooltip_source(doc; id::Symbol)
    short_proj = ReferenceToText()
    long_proj  = ReferenceToHumanReadableText(document = doc)
    content = TextText(() -> begin
        sel = doc.selection
        ctx = PrinterContext()
        short = print_document(short_proj, nothing, sel, ctx).output
        long  = print_document(long_proj,  nothing, sel, ctx).output
        spans = TextDocument[]
        for i in 1:length(short.elements)
            push!(spans, short.elements[i])
        end
        push!(spans, TextNewline(font=short_proj.font))
        push!(spans, TextNewline(font=short_proj.font))
        for i in 1:length(long.elements)
            push!(spans, long.elements[i])
        end
        spans
    end)
    TooltipSource(child = doc, content = content, style = :tooltip, id = id)
end

# Same shape as `_multi_window_projection` but with the four extra type
# entries needed for tooltip support, sitting in front of the existing
# reference-based dispatch for example content.
function _multi_window_projection_tooltipped(projections::Vector; measure=truetype_measure_text)
    n = length(projections)
    targets = Vector{Any}(undef, n)
    for i in 1:n
        targets[i] = @reference windows[i].content
    end
    decorator = TooltipDecoratorProjection(
        trigger  = (source, _evt) -> source.child.selection !== nothing,
        position = _ -> (100, 100, 1200, 600),
        title    = "Selection",
    )
    ref_dispatch = ReferenceDispatchingProjection(ref -> begin
        for i in 1:n
            is_reference_equal(ref, targets[i]) || continue
            return NestingProjection(projections[i];
                                      recursion=IdentityProjection())
        end
        for t in targets
            is_prefix_of(ref, t) || continue
            return CopyingProjection()
        end
        return IdentityProjection()
    end)
    RecursiveProjection(
        TypeDispatchingProjection(
            ScreenDocument => WindowManagingProjection(inner = ScreenToScreen()),
            WindowDocument => ScreenToScreen(),
            CellVector     => CopyingProjection(),
            TooltipSource  => decorator,
            TextText       => ChainingProjection(WordWrapping(measure=measure), TextToGraphics(measure=measure)),
            Any            => ref_dispatch,
        ),
    )
end

# Hover click-reference inspector pipeline. Same shape as the tooltip variant,
# but: each example window's content projection is wrapped in a
# `HoverProbeProjection` (which reverse-projects the pointer into the
# would-be-click reference and drives the follower `:inspector` window), and a
# `ReferenceInspector` type entry renders that window's content (compact +
# human-readable reference) down to graphics. `pointer` is the global-mouse
# closure used to make the follower window track the cursor.
function _multi_window_projection_inspector(projections::Vector; measure=truetype_measure_text, pointer)
    n = length(projections)
    targets = Vector{Any}(undef, n)
    for i in 1:n
        targets[i] = @reference windows[i].content
    end
    ref_dispatch = ReferenceDispatchingProjection(ref -> begin
        for i in 1:n
            is_reference_equal(ref, targets[i]) || continue
            inner = NestingProjection(projections[i]; recursion=IdentityProjection())
            return HoverProbeProjection(inner = inner, id = :inspector, pointer = pointer)
        end
        for t in targets
            is_prefix_of(ref, t) || continue
            return CopyingProjection()
        end
        return IdentityProjection()
    end)
    RecursiveProjection(
        TypeDispatchingProjection(
            ScreenDocument     => WindowManagingProjection(inner = ScreenToScreen()),
            WindowDocument     => ScreenToScreen(),
            CellVector         => CopyingProjection(),
            ReferenceInspector => ChainingProjection(ReferenceInspectorToText(),
                                                       WordWrapping(measure=measure),
                                                       TextToGraphics(measure=measure)),
            TextText           => ChainingProjection(WordWrapping(measure=measure), TextToGraphics(measure=measure)),
            Any                => ref_dispatch,
        ),
    )
end

"""
    run_console_example(; document, projection, ansi=true, clear=nothing, interactive=false)

Render a Text-domain document to the terminal via the `ConsoleBackend`,
preserving the spans' colors. This is the console counterpart to
`run_example`: it bypasses SDL and the `ScreenDocument`/window machinery and
prints the bare `TextText` produced by the projection.

Defaults to the JSON example projected through
`make_json_console_projection_example` — the json pipeline **without** the
`TextToGraphics` step, so its output is a `TextText` the console can render.

Keywords:
  - `document`    — the domain document (default: a fresh JSON example doc).
  - `projection`  — a projection whose output is a `TextText` (default: the
                    json→syntax→text console projection).
  - `ansi`        — emit ANSI color codes (default `true`).
  - `clear`       — clear the screen before each frame. Defaults to `false` for
                    a one-shot render and `true` for the interactive loop.
  - `interactive` — when `true`, run the read-eval-print loop: poll the
                    keyboard, apply operations, repaint. `Home` selects the root
                    node, arrows navigate the tree, `Ctrl+Space` toggles
                    structural ⇄ text selection, `Ctrl+C` quits. Character-level
                    text editing is not available (it lives in `TextToGraphics`,
                    which this pipeline omits). Default `false` (one-shot).
"""
function run_console_example(; document=make_json_document_example(),
                               projection=make_json_console_projection_example(),
                               ansi::Bool=true, clear::Union{Bool,Nothing}=nothing,
                               interactive::Bool=false)
    if interactive
        backend = make_backend(:console; ansi=ansi, clear=something(clear, true))
        # The editor logs each operation and a perf line via @info; on a terminal
        # that lands on the rendered screen and corrupts it (the console owns the
        # display). Discard those logs for the duration of the interactive loop.
        Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
            run_editor!(backend, projection, document; devices=Device[Keyboard()])
        end
    else
        backend = make_backend(:console; ansi=ansi, clear=something(clear, false))
        iomap = print_document(projection, document)
        output = iomap.output
        output = output isa Cell ? output[] : output
        write_to_devices(backend, Device[], output)
    end
    return nothing
end

"""
    record_assistant_conversation_video(filename=tempname()*".mp4"; reply, kwargs...) -> String

Record a headless MP4 of someone composing a multi-part message in the workbench
assistant and waiting for the reply. The recorded session, driven entirely
through the live `make_assistant_projection_example` chain
(`KeyPress`/`KeyDown` → composer operations), is:

1. type the prose `"Look what I can do!"`;
2. `TAB` to start a new part, type `julia`, `ENTER` to turn it into a Julia
   source part, type `factorial(6)`, then `ALT+ENTER` to evaluate it into an
   `EvaluatorForm` (code + result `720`);
3. type the prose `"Can you do the same?"`;
4. `ENTER` to submit the draft turn, then wait for the assistant to reply.

The assistant uses a `FakeLlm` so the reply (`reply`) is deterministic and needs
no network. The default reply contains a fenced ```` ```julia ```` block, which
`parse_markdown_blocks` parses into a real `JuliaDocument` part — so the recorded
reply renders the code as a parsed Julia document in the conversation, not plain
text. The reply is streamed on an `@async` task that the recording lets settle
(via `record_video`'s `wait_for`) before holding the final frames for
`final_hold` seconds (longer than the default so the answer lingers on screen).
"""
function record_assistant_conversation_video(filename::AbstractString = tempname() * ".mp4";
                                              reply::AbstractString = """
                                                  Sure! Here's a recursive factorial in Julia:

                                                  ```julia
                                                  fact(n) = n <= 1 ? 1 : n * fact(n - 1)
                                                  ```

                                                  Calling `fact(6)` returns 720 — same as yours.""",
                                              width=1600, height=900, fps=30, final_hold=4.0, kwargs...)
    # A fresh assistant with a deterministic canned reply. The composer edits the
    # draft's active part (cursor defaults to end-of-value), so no selection seed
    # is needed for the keypresses to land.
    assistant  = WorkbenchAssistant(; llm = FakeLlm(reply))
    projection = make_assistant_projection_example()

    # A composer part-break: commit the active part and start the next one.
    tab   = (event = KeyDown(:tab, Modifiers()),              hold = 0.5)
    enter = (event = KeyDown(:return, Modifiers()),           hold = 0.6)
    alt_enter = (event = KeyDown(:return, Modifiers(alt=true)), hold = 0.8)

    gestures = vcat(
        make_typein_gestures("Look what I can do!"),
        [tab],
        make_typein_gestures("julia"),               # name the kind in the chooser
        [enter],                                      # commit chooser → Julia source part
        make_typein_gestures("factorial(6)"),
        [alt_enter],                                  # evaluate → EvaluatorForm (720)
        make_typein_gestures("Can you do the same?"),
        [enter],                                      # submit the draft turn
    )

    record_video(assistant, projection, gestures, filename;
                 width=width, height=height, fps=fps, final_hold=final_hold,
                 wait_for = () -> assistant.status === :idle, kwargs...)
end

"""
    generate_example_screenshots(; filter=nothing, max_width=1920, max_height=1080,
                                 image_dir=joinpath(@__DIR__, "..", "..", "..", "asset", "image", "example"))

Generate a PNG screenshot for every example in `examples` into `image_dir`.
Filename pattern: `{example-name-with-hyphens}.png`. One failure does not
abort the batch.

Each screenshot is sized to its content, capped at `max_width`/`max_height`, so
compact examples (e.g. individual widgets) produce small images rather than a
fixed full-screen canvas.

Pass `filter` (a `Regex` or string compiled to one with `occursin`) to restrict
generation to examples whose name matches, e.g. `filter=r"^widget"` regenerates
only the widget screenshots.
"""
# Export scale for generated screenshots: PNGs are rendered at this many device
# pixels per logical pixel so they stay crisp on HiDPI displays (e.g. GitHub
# viewed on a retina screen) independent of the machine that generates them.
# Guide embeds pin the *displayed* width to the logical size (png width ÷ this)
# via `<img width>`, so the on-page size is unchanged while the extra pixels are
# available for sharp rendering.
