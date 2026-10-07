# domain-example/Gallery.jl
#
# The example gallery: `run_example` opens one window per example, side by
# side, with optional cross-domain wrappers (tooltip, clipboard,
# introspection, text filtering/highlighting; that domain
# vocabulary is why the gallery's lowest home is the domain tier). No backend is
# named here: an explicit `backend` wins, otherwise `default_backend()` picks one
# by reflection over the loaded backends (SDL when loaded). The name-lookup entry
# point (`run_example("json")`) lives in the `ProjecturedExample` umbrella, which
# owns the global registry.

function run_example(example::Example; kwargs...)
    run_example([example]; kwargs...)
end

"""
    run_example(examples::Vector{Example}; width, height,
                caching=false, scrolling=false, reset=false,
                tooltip=false, introspection=false, selection=nothing,
                shell=false, dragging=false, gesture_help=false,
                command_palette=false, gesture_log=false,
                fault_tolerant=true, profile=false)

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

When `introspection=true`, each example's content is wrapped in a
`WidgetTabbedPane` with three tabs: the original content (rendered with
the example's own projection), the editor's document, and the editor's
projection (both rendered generically via `ObjectToSyntax`).

When `text_highlighting=true` (or `text_filtering=true`), the example's
projection is replaced by a `ProjectionConfiguringProjection` that stacks an
editable control bar for a `TextHighlighting` (resp. `TextFiltering`)
projection above the projected text. Editing the controls re-highlights /
re-filters live; `Ctrl+F` toggles the bar, `Escape` hides it. Expects a
`TextBlock` document (the text examples). The two flags are mutually exclusive.

When `clipboard=true`, each example is wrapped in a `ClipboardSlice` and the
clipboard projection is stacked on top of the example's own pipeline (the
introspection wrapper pattern), so the selection-driven copy / cut / note /
paste flow (`Ctrl+C` / `Ctrl+X` / `Ctrl+N` / `Ctrl+V`, `Ctrl+/` to toggle the
stored slice) works over any example. `clipboard_collection=true` uses a
`ClipboardCollection` (the elements view) instead. For a `TextBlock` example the
wrapper enables **text mode**: copy / cut / paste operate on character ranges,
the ProjecturEd clipboard is the primary store, and the **OS clipboard** is
mirrored on copy/cut and used as the paste fallback (needs `xclip`/`xsel`/`wl-*`).
For other (structured) domains the generic wrapper leaves the OS-clipboard bridge
off (pasting OS text into an arbitrary node domain is not type-safe); the
dedicated `clipboard_example` wires JSON converters for it. Incompatible with
`tooltip`.

Six more wrappers are layers rather than alternatives, so they compose with
each other and with one of the wrappers above. They apply in this order, and a
projection wrapper that comes later sits further out: `dragging`, `shell`,
`caching`, `gesture_help`, `command_palette`, `gesture_log`.

When `dragging=true`, each example's document is wrapped in a `DraggingState`
and its projection in a `DraggingProjection`. A press that travels more than a
few pixels becomes a drag, and the drop reorders the collection under the grab
point. The wrapper is transparent to the printer, so the content renders
unchanged. The dedicated `dragging_example` wires the same pair by hand.

When `shell=true`, each example's document is wrapped in a `WidgetShell`, so the
content sits inside a top-level window frame with a menu bar, a toolbar, and a
status bar that names the example. The chrome's commands are inert: a submenu
needs a popup resolver, which this pipeline does not compose.

A button and a row of a list light under the pointer: the screen gives each move
to its windows, and each document on the way keeps its mouse target. Each
example's projection is wrapped in a `FocusCyclingProjection`, so Tab starts over
at the ends of each window.

When `gesture_help=true`, each example's projection is wrapped in a
`GestureHelpDecoratorProjection`, so `F1` in the focused window opens a help window
(id `:gesture_help`) listing the gestures collected from that content's own
pipeline. One shared state backs every window, so `F1` toggles one window.

When `command_palette=true`, each example's projection is wrapped in the command
type-in overlay: `Ctrl+Shift+P` opens a field over the content, typing narrows the
list of commands available where the user is, and Enter runs the selected one.
Escape or the same key closes it. Each window gets its own palette, because the
palette is drawn into its window rather than opened beside it.

When `gesture_log=true`, a panel in the top-right corner of each window shows
what the editor did: the last gestures and the operation each one made. One
`GestureLog` is shared by every window. A `GestureLogRecordingProjection` at the
root of the composed projection records the operations, and a
`GestureLogOverlayProjection` around each example's own pipeline draws the
panel. `gesture_log_capacity` is the number of entries the buffer keeps
(default 20) and `gesture_log_filter` is a predicate `(gesture, operation) ->
Bool` that replaces `default_gesture_log_filter`, which drops the selection
operations. The panel is not interactive: a click goes through it to the
content. The editor makes the readability-zoom operation after the pipeline
declines the gesture, so the log does not hold it.

When `profile=true`, the read-eval-print loop runs under `Profile.@profile`.
The profile buffer is cleared first; once the editor window is closed (the
loop exits) a sampled backtrace report is printed via `Profile.print`.
"""
function run_example(examples::Vector{Example}; reset=false, kwargs...)
    isempty(examples) && error("run_example: empty examples vector")
    # Resolve each example to a bare (document, projection) pair — a fresh one
    # from the factories when reset=true, otherwise the example's cached
    # instance — then hand off to the Example-free core, which applies the flags.
    documents   = Any[reset ? ex.make_document()   : ex.document   for ex in examples]
    projections = Any[reset ? ex.make_projection() : ex.projection for ex in examples]
    names       = String[ex.name for ex in examples]
    run_example(documents, projections, names; kwargs...)
end

"""
    run_example(document, projection; name="document", kwargs...)

Open a live editor window on a raw `(document, projection)` pair, with no
`Example` needed. Accepts every keyword the gallery offers (`scrolling`,
`tooltip`, `introspection`,
`clipboard`/`clipboard_collection`, `text_filtering`/`text_highlighting`,
`selection`, `caching`, `profile`, `backend`, `width`, `height`); `name` becomes
the window's id/title. See the `run_example(documents, projections, names)`
overload below for the keyword semantics.
"""
run_example(document, projection; name::AbstractString="document", kwargs...) =
    run_example(Any[document], Any[projection], String[name]; kwargs...)

"""
    run_example(documents::Vector, projections::Vector, names::Vector; kwargs...)

The `Example`-free core: open one window per `(documents[i], projections[i])`
pair, side by side, applying the same optional cross-domain wrappers (tooltip,
introspection, clipboard, text filtering/highlighting,
caching, dragging, shell, gesture help, command palette). `names[i]` is
window i's id/title and must be unique. Every keyword is
identical to the `Example` overloads *except* `reset` — there are no factories to
re-run here, so pass freshly built documents/projections when you need a clean
state. This is the overload the `Example`-based `run_example` methods delegate to.

A caller with work to do before the loop — a driver keeping a derived document in
sync, a watcher, a client — makes the editor with [`make_example_editor`](@ref),
does that work with it, and runs the loop with `run_editor!(editor)`.
"""
run_example(documents::Vector, projections::Vector, names::Vector;
            profile::Bool = false, kwargs...) =
    _run_editor_profiled(make_example_editor(documents, projections, names; kwargs...);
                         profile = profile)

"""
    make_example_editor(documents::Vector, projections::Vector, names::Vector; kwargs...) -> Editor

The editor that [`run_example`](@ref) runs, made and printed once, before its
loop: the same windows side by side, with the same wrappers and keywords, except
`profile`. The editor's fault store reports into the fault log that every window
shows.

Use it to do work with the editor before the loop — start a driver, a timer or a
client — and then run the loop with `run_editor!(editor)`.

# Example

    editor = make_example_editor([log], [projection], ["log"]; feeds = feeds)
    @async produce(store)
    run_editor!(editor)
"""
function make_example_editor(documents::Vector, projections::Vector, names::Vector;
                             width=nothing, height=nothing,
                             caching=false, scrolling=false,
                             tooltip=false, introspection=false,
                             clipboard=false, clipboard_collection=false,
                             text_filtering=false, text_highlighting=false, selection=nothing,
                             shell=false, dragging=false,
                             gesture_help=false, command_palette=false,
                             gesture_log=false, gesture_log_filter=nothing, gesture_log_capacity=20,
                             fault_tolerant=true,
                             backend=nothing, feeds::Vector{Feed}=Feed[])
    isempty(documents) && error("run_example: empty documents vector")
    length(documents) == length(projections) == length(names) ||
        error("run_example: documents, projections and names must have equal length")
    if text_filtering && text_highlighting
        error("run_example: text_filtering and text_highlighting are mutually exclusive")
    end
    clipboard = clipboard || clipboard_collection
    if clipboard && tooltip
        error("run_example: clipboard=true is not compatible with tooltip=true")
    end
    # Resolve the backend up front — the display-size query below needs it. An
    # explicit `backend` wins; otherwise pick a default by reflection over the
    # loaded backends (SDL when loaded, see `default_backend`).
    backend === nothing && (backend = default_backend())
    if width === nothing || height === nothing
        sw, sh = get_display_size(backend)
        width  = something(width,  sw)
        height = something(height, sh)
    end

    # One log for the whole screen: every window's overlay shows it and the
    # recorder at the root fills it.
    log_document = gesture_log ? GestureLog(; capacity = gesture_log_capacity) : nothing

    # One fault log for the whole screen, on the same shape: the editor's
    # store fills it (attached below, once the editor is made), and every window's panel
    # shows it. The panel and its barrier wrap each window's content, where
    # the output is a `GraphicsCanvas` the panel can compose over — the
    # multi-window projection above produces a `ScreenDocument`, which is no
    # altitude for either.
    fault_log = fault_tolerant ? FaultLog() : nothing

    # Apply the flags to each (document, projection) pair.
    docs  = Any[]
    projs = Any[]
    # One open/closed flag for the gesture-help window, shared by every window's
    # decorator, so F1 toggles the same window wherever the focus is.
    help_state = GestureHelpState()
    for i in eachindex(documents)
        document   = documents[i]
        projection = projections[i]
        # Apply a caller-supplied selection to the first pair's bare domain
        # document, before any scrolling/introspection wrapping. The
        # selection-lifting step below then promotes it to a screen-rooted path.
        if selection !== nothing && i == 1
            set_selection!(document, selection)
        end
        if scrolling
            document   = make_scrolling_document(document; width=width, height=height)
            projection = make_scrolling_projection(projection)
        elseif introspection
            document   = make_introspection_document(document, projection; title=names[i])
            projection = make_introspection_projection(projection)
        elseif clipboard
            # Wrap the document in a ClipboardSlice (or ClipboardCollection) and stack
            # the clipboard projection on top of the pair's own pipeline. The
            # seeded selection (set on the bare document above) now lives behind the
            # clipboard's `content`; the selection-lifting loop below re-roots it.
            # For a TextBlock document, enable text mode: copy/cut/paste over character
            # ranges, with the OS clipboard mirrored on copy/cut and used as the paste
            # fallback (the projectured slice is the primary store).
            is_text    = document isa TextBlock
            document   = make_clipboard_document(document; collection=clipboard_collection)
            projection = make_clipboard_projection(projection; collection=clipboard_collection, text=is_text)
        elseif text_highlighting
            # Stack a TextHighlighting control bar above the (text) document; the
            # document's own projection is replaced by the configuring pipeline.
            # A default pattern makes the highlight (and the case_insensitive
            # toggle's effect) visible out of the box. Expects a TextBlock document.
            projection = make_text_configuring_projection(TextHighlighting("dolor"))
        elseif text_filtering
            projection = make_text_configuring_projection(TextFiltering("dolor"))
        end
        # The layered wrappers. Each one composes with the exclusive wrapper above
        # and with the others, in this order, so a projection wrapper that comes
        # later sits further out. Keep the order in step with `content_unwrap`
        # below, which names the fields these document wrappers introduce.
        if dragging
            document   = make_dragging_document(document)
            projection = make_dragging_projection(projection)
        end
        if shell
            document   = make_shell_document(document; title=names[i], width=width, height=height)
            projection = make_shell_projection(projection)
        end
        if caching
            projection = make_graphics_caching(projection)
        end
        projection = FocusCyclingProjection(inner = projection)
        if gesture_help
            # One shared state for every window, so F1 toggles one help window.
            projection = GestureHelpDecoratorProjection(inner = projection, state = help_state)
        end
        if command_palette
            projection = make_command_palette_decorator_projection(projection)
        end
        # The overlay comes last, so it draws over every wrapper above. It is
        # transparent to the reader; the recorder below, at the root, is what
        # fills the log.
        if gesture_log
            projection = GestureLogOverlayProjection(inner = projection, log = log_document)
        end
        # The fault barrier and its panel wrap everything, so a fault in any
        # wrapper above still shows. The panel draws no pixel while the log
        # is empty, which is why this one is on by default.
        if fault_tolerant
            projection, _ = make_fault_tolerant_projection(projection; log = fault_log)
        end
        push!(docs, document)
        push!(projs, projection)
    end

    # When the tooltip flag is on, wrap each window's content in a
    # TooltipSource and pick the tooltip-aware multi-window projection.
    if tooltip
        tt_docs = Any[]
        for i in eachindex(docs)
            push!(tt_docs, _make_tooltip_source(docs[i]; id = Symbol("tooltip_", names[i])))
        end
        docs = tt_docs
    end

    # The fields that lead from `win.content` down to the original
    # (selection-bearing) document, outermost first. The order mirrors the order
    # the wrappers were applied in, reversed.
    content_unwrap = Symbol[]
    tooltip   && push!(content_unwrap, :child)
    shell     && push!(content_unwrap, :content)
    dragging  && push!(content_unwrap, :content)
    clipboard && push!(content_unwrap, :content)
    compose = tooltip ? (p, b) -> _multi_window_projection_tooltipped(p) :
                         (p, b) -> _multi_window_projection(p)
    # The recorder sits at the root of whichever composer runs, because the root
    # is the seam every operation passes through.
    if gesture_log
        inner_compose = compose
        compose = (p, b) -> GestureLogRecordingProjection(
            inner  = inner_compose(p, b),
            log    = log_document,
            filter = something(gesture_log_filter, default_gesture_log_filter))
    end
    # The editor's own fault store — what the frame barriers catch — reports
    # into the same log the per-window panels show, so one panel carries
    # every tier.
    editor = _make_window_scene_editor(docs, projs, names;
                                       width=width, height=height, backend=backend,
                                       compose=compose, content_unwrap=content_unwrap,
                                       feeds=feeds)
    fault_tolerant && attach_fault_target!(editor.faults, fault_log)
    editor
end

"""
    make_example_editor(document, projection; name="document", kwargs...) -> Editor

The editor of one window on a raw `(document, projection)` pair, made and printed
once, before its loop: what `run_example(document, projection; name)` runs.
`name` becomes the window's id and title, and the other keywords are those of
the `make_example_editor(documents, projections, names)` method above.
"""
make_example_editor(document, projection; name::AbstractString="document", kwargs...) =
    make_example_editor(Any[document], Any[projection], String[name]; kwargs...)

# Lay out `docs` as side-by-side WindowDocuments into a ScreenDocument and lift the
# first window-content's selection to a screen-rooted path. Each `names[i]` becomes
# window i's id/title (ids must be unique within the screen). `content_unwrap` names
# the fields that lead from `win.content` down to the original (selection-bearing)
# document, outermost first: `Symbol[]` (the content itself), `[:child]` (a tooltip
# source), `[:content]` (a clipboard, a dragging state, or a shell), and a longer
# chain when those wrappers stack.
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
function _build_window_scene(docs, names; width, height,
                             content_unwrap::Vector{Symbol}=Symbol[])
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
        root_doc = _unwrap_content(win.content, content_unwrap)
        inner_sel = getfield(root_doc, :selection)[]
        inner_sel === nothing && continue
        content_sel = _prefix_content_fields(win.content, content_unwrap, inner_sel)
        full_path = @reference(screen, windows[i].content.^(content_sel))
        set_selection!(screen, full_path)
        break
    end
    screen
end

# Follow `fields` (outermost first) down from `document` to the document that
# carries the seeded selection.
function _unwrap_content(document, fields)
    for f in fields
        document = getproperty(document, f)
    end
    document
end

# Prefix `fields` onto `selection`, so a path rooted at the innermost document
# becomes one rooted at `document`. Each level is built against the document it
# addresses, which is what folds that node's type into the step. The wrappers are
# a closed set, so the two field names they introduce are spelled out — a
# `@reference` path names its steps literally.
function _prefix_content_fields(document, fields, selection)
    isempty(fields) && return selection
    child = getproperty(document, fields[1])
    inner = _prefix_content_fields(child, fields[2:end], selection)
    fields[1] === :child   && return @reference(document, child.^(inner))
    fields[1] === :content && return @reference(document, content.^(inner))
    error("_prefix_content_fields: no wrapper introduces the field :$(fields[1])")
end

# Build the scene (above), compose the screen projection via `compose(projs, backend)`,
# put the gesture tracker around both, and make the editor on `backend`, printed
# once. The shared start of `make_example_editor` and `run_file_editor`.
function _make_window_scene_editor(docs, projs, names; width, height, backend, compose,
                                   content_unwrap::Vector{Symbol}=Symbol[],
                                   feeds::Vector{Feed}=Feed[])
    screen, composed = make_tracking_screen(
        _build_window_scene(docs, names; width=width, height=height, content_unwrap=content_unwrap),
        compose(projs, backend);
        inner_wrappers = [wrap_tooltip_window, wrap_context_menu_window])
    make_editor(screen, composed; backend = backend, feeds = feeds,
                fault_policy = FaultPolicy())
end

# Run the loop of `editor`, under the profiler when `profile` is set.
function _run_editor_profiled(editor; profile::Bool=false,
                              mcp::Union{Bool,NamedTuple}=false)
    if profile
        Profile.clear()
        try
            Profile.@profile run_editor!(editor; mcp=mcp)
        finally
            Profile.print(; mincount=10)
        end
    else
        run_editor!(editor; mcp=mcp)
    end
end

# Make the editor of a window scene and run its loop. The tail of `run_file_editor`.
function _run_window_scene(docs, projs, names; width, height, backend,
                           compose, profile::Bool=false, content_unwrap::Vector{Symbol}=Symbol[],
                           mcp::Union{Bool,NamedTuple}=false, feeds::Vector{Feed}=Feed[])
    editor = _make_window_scene_editor(docs, projs, names; width=width, height=height,
                                       backend=backend, compose=compose,
                                       content_unwrap=content_unwrap, feeds=feeds)
    _run_editor_profiled(editor; profile=profile, mcp=mcp)
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
# `ElementReferenceStep`), which is how the target paths are built.
function _multi_window_projection(projections::Vector; measure=FontFileMeasure())
    n = length(projections)
    targets = Vector{Any}(undef, n)
    for i in 1:n
        targets[i] = @reference ::ScreenDocument.windows::CellVector[i]::WindowDocument.content::Document
    end
    opened = _make_opened_window_dispatch(measure)
    ref_dispatch = ReferenceDispatchingProjection(ref -> begin
        # Exact match — apply that window's example projection here. The
        # NestingProjection (recursion=IdentityProjection) lets the inner
        # projection's own recursion take over below this point. A gesture-help
        # decorator, when the caller asked for one, is already part of that
        # projection — `run_example` wraps it before composing.
        for i in 1:n
            is_reference_equal(strip_reference_types(ref), strip_reference_types(targets[i])) || continue
            return NestingProjection(projections[i]; recursion=IdentityProjection())
        end
        # The ScreenDocument root is the window-management seam: route it
        # through WindowManagingProjection (window open/close/resize ops are
        # owned there) wrapping ScreenToScreen, which projects the screen
        # shell and recurses each window's content back through this dispatch.
        ref isa EmptyReference &&
            return WindowManagingProjection(inner = ScreenToScreen())
        # Anything outside a window's content target: the content of a window
        # that opens later, such as a menu, draws by its type.
        return opened
    end)
    # A type seam in front of the reference dispatch so dynamically-opened windows
    # render by content type: a `WindowDocument` (re-projected by the manager when
    # a window opens) recurses via ScreenToScreen, and a help `GestureMap` window
    # renders down to graphics. Existing content is `Any` → the reference dispatch,
    # unchanged (TypeDispatching is transparent for the matched arm).
    return RecursiveProjection(
        TypeDispatchingProjection(
            WindowDocument => ScreenToScreen(),
            _gesture_map_entry(measure),
            Any            => ref_dispatch,
        ))
end

# The type entry that renders the gesture-help window's content. Every composer
# carries it, so `gesture_help=true` works whichever one the flags pick.
_gesture_map_entry(measure) = GestureMap => make_gesture_map_projection(measure)

# What draws the content of a window that opens later and holds no example: the
# menu of a right click, the options of a select and the menu of a menu bar
# through the rows of the widgets and the layouts, and a tooltip through the
# natural projection; any other document stays as it is. Every composer carries
# it, so a popup draws whichever one the flags pick.
_make_opened_window_dispatch(measure) =
    TypeDispatchingProjection(
        make_opened_window_projections(; gesture_help = false, measure,
                                       content = Pair{Type,Any}[make_natural_tooltip_row(; measure)])...,
        Any => IdentityProjection())

# ── Tooltip variant ──────────────────────────────────────────────────────
#
# Wrap a domain document in a `TooltipSource` whose `content` is a
# *reactive* `TextBlock`: the elements thunk re-reads `doc.selection`
# every frame and rebuilds the colored spans via `ReferenceToText`. The
# `TooltipDecoratorProjection` reader watches the wrapped document and
# emits `OpenWindowOperation` / `CloseWindowOperation` as the selection
# arrives / clears; the `WindowManagingProjection` applies those to the
# screen.

function _make_tooltip_source(doc; id::Symbol)
    short_proj = ReferenceToText()
    long_proj  = ReferenceToHumanReadableText(document = doc)
    content = TextBlock(() -> begin
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
function _multi_window_projection_tooltipped(projections::Vector; measure=FontFileMeasure())
    n = length(projections)
    targets = Vector{Any}(undef, n)
    for i in 1:n
        targets[i] = @reference ::ScreenDocument.windows::CellVector[i]::WindowDocument.content::Document
    end
    decorator = TooltipDecoratorProjection(
        trigger  = (source, _evt) -> source.child.selection !== nothing,
        position = _ -> (100, 100, 1200, 600),
        title    = "Selection",
    )
    opened = _make_opened_window_dispatch(measure)
    ref_dispatch = ReferenceDispatchingProjection(ref -> begin
        for i in 1:n
            is_reference_equal(strip_reference_types(ref), strip_reference_types(targets[i])) || continue
            return NestingProjection(projections[i];
                                      recursion=IdentityProjection())
        end
        for t in targets
            is_reference_prefix(ref, t) || continue
            return CopyingProjection()
        end
        return opened
    end)
    RecursiveProjection(
        TypeDispatchingProjection(
            ScreenDocument => WindowManagingProjection(inner = ScreenToScreen()),
            WindowDocument => ScreenToScreen(),
            CellVector     => CopyingProjection(),
            TooltipSource  => decorator,
            _gesture_map_entry(measure),
            TextBlock       => ChainingProjection(WordWrapping(measure=measure), TextToGraphics(measure=measure)),
            Any            => ref_dispatch,
        ),
    )
end

"""
    run_console_example(; document, projection, ansi=true, clear=nothing, interactive=false)

Render a Text-domain document to the terminal via the `ConsoleBackend`,
preserving the spans' colors. This is the console counterpart to
`run_example`: it bypasses SDL and the `ScreenDocument`/window machinery and
prints the bare `TextBlock` produced by the projection.

Defaults to the JSON example projected through
`make_json_console_projection_example` — the json pipeline **without** the
`TextToGraphics` step, so its output is a `TextBlock` the console can render.

Keywords:
  - `document`    — the domain document (default: a fresh JSON example doc).
  - `projection`  — a projection whose output is a `TextBlock` (default: the
                    json→syntax→text console projection).
  - `ansi`        — emit ANSI color codes (default `true`).
  - `clear`       — clear the screen before each frame. Defaults to `false` for
                    a one-shot render and `true` for the interactive loop.
  - `interactive` — when `true`, run the read-eval-print loop: poll the
                    keyboard, apply operations, repaint. `Home` selects the root
                    node, arrows navigate the tree, `Ctrl+Space` toggles
                    structural ⇄ text selection, `Ctrl+C` quits. Character-level
                    text editing works too: it is in the `@gestures TextBlock`
                    table (`source/platform/text/TextDocument.jl`), geometry-free and so
                    available even though this pipeline omits `TextToGraphics`.
                    Default `false` (one-shot).
"""
function run_console_example(; document=make_json_document_example(),
                               projection=make_json_console_projection_example(),
                               ansi::Bool=true, clear::Union{Bool,Nothing}=nothing,
                               interactive::Bool=false)
    if interactive
        backend = ConsoleBackend(; ansi=ansi, clear=something(clear, true))
        # The editor logs each operation and a perf line via @info; on a terminal
        # that lands on the rendered screen and corrupts it (the console owns the
        # display). Discard those logs for the duration of the interactive loop.
        Base.CoreLogging.with_logger(Base.CoreLogging.NullLogger()) do
            run_editor!(make_editor(document, projection; backend = backend,
                                     devices = Device[Keyboard()],
                                     fault_policy = FaultPolicy()))
        end
    else
        backend = ConsoleBackend(; ansi=ansi, clear=something(clear, false))
        iomap = print_document(projection, document)
        output = iomap.output
        output = output isa Cell ? output[] : output
        write_to_devices!(backend, Device[], output)
    end
    return nothing
end

"""
    record_assistant_conversation_video(filename=tempname()*".mp4"; reply, kwargs...) -> String

Record a headless MP4 of someone composing a multi-part message in the
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
# @optional: the output file stands first, as the destination named at a command line.
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
    assistant  = Assistant(; llm = FakeLlm(reply))
    projection = make_assistant_projection_example()

    # A composer part-break: commit the active part and start the next one.
    tab   = (event = KeyDown(:tab, ModifierKeys();
                             time = time()),              hold = 0.5)
    enter = (event = KeyDown(:return, ModifierKeys();
                             time = time()),           hold = 0.6)
    alt_enter = (event = KeyDown(:return, ModifierKeys(alt=true);
                                 time = time()), hold = 0.8)

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

    record_video(assistant, projection; gestures, filename,
                 width=width, height=height, fps=fps, final_hold=final_hold,
                 wait_for = () -> assistant.status === :idle, kwargs...)
end
