struct Example
    name::String
    make_document
    make_projection
    document
    projection
    Example(name, make_document, make_projection) =
        new(name, make_document, make_projection, make_document(), make_projection())
end

const json_example           = Example("json",           make_json_document_example,           make_json_projection_example)
const json_sorted_example    = Example("json_sorted",    make_json_document_example,           make_json_sorted_projection_example)
const json_null_example      = Example("json_null",      make_json_null_document_example,      make_json_null_projection_example)
const json_string_example    = Example("json_string",    make_json_string_document_example,    make_json_string_projection_example)
const xml_example            = Example("xml",            make_xml_document_example,            make_xml_projection_example)
const mixed_example          = Example("mixed",          make_mixed_document_example,          make_mixed_projection_example)
const syntax_example         = Example("syntax",         make_syntax_document_example,         make_syntax_projection_example)
const text_example           = Example("text",           make_text_document_example,           make_text_projection_example)
const text_with_image_example = Example("text_with_image", make_text_with_image_example,       make_text_projection_example)
const object_example         = Example("object",         make_object_document_example,         make_object_projection_example)
const object_to_widget_example = Example("object_to_widget", make_object_to_widget_document_example, make_object_to_widget_projection_example)
const line_numbering_example = Example("line_numbering", make_line_numbering_document_example, make_line_numbering_projection_example)
const word_wrapping_example  = Example("word_wrapping",  make_word_wrapping_document_example,  make_word_wrapping_projection_example)
const text_filtering_example = Example("text_filtering", make_text_filtering_document_example, make_text_filtering_projection_example)
const text_highlighting_example = Example("text_highlighting", make_text_highlighting_document_example, make_text_highlighting_projection_example)
const widget_example         = Example("widget",         make_widget_document_example,         make_widget_projection_example)
const widget_label_example       = Example("widget_label",       make_widget_label_document_example,       make_widget_projection_example)
const widget_text_example        = Example("widget_text",        make_widget_text_document_example,        make_widget_text_projection_example)
const widget_checkbox_example    = Example("widget_checkbox",    make_widget_checkbox_document_example,    make_widget_projection_example)
const widget_button_example      = Example("widget_button",      make_widget_button_document_example,      make_widget_projection_example)
const widget_tooltip_example     = Example("widget_tooltip",     make_widget_tooltip_document_example,     make_widget_projection_example)
const widget_menu_item_example   = Example("widget_menu_item",   make_widget_menu_item_document_example,   make_widget_projection_example)
const widget_menu_example        = Example("widget_menu",        make_widget_menu_document_example,        make_widget_projection_example)
const widget_toolbar_example     = Example("widget_toolbar",     make_widget_toolbar_document_example,     make_widget_projection_example)
const widget_composite_example   = Example("widget_composite",   make_widget_composite_document_example,   make_widget_projection_example)
const widget_title_pane_example  = Example("widget_title_pane",  make_widget_title_pane_document_example,  make_widget_projection_example)
const widget_split_pane_example  = Example("widget_split_pane",  make_widget_split_pane_document_example,  make_widget_projection_example)
const widget_scroll_bar_example  = Example("widget_scroll_bar",  make_widget_scroll_bar_document_example,  make_widget_projection_example)
const widget_scroll_pane_example = Example("widget_scroll_pane", make_widget_scroll_pane_document_example, make_widget_projection_example)
const widget_shell_example       = Example("widget_shell",       make_widget_shell_document_example,       make_widget_projection_example)
const widget_tabbed_pane_example = Example("widget_tabbed_pane", make_widget_tabbed_pane_document_example, make_widget_projection_example)
const widget_badge_example       = Example("widget_badge",       make_widget_badge_document_example,       make_widget_projection_example)
const widget_separator_example   = Example("widget_separator",   make_widget_separator_document_example,   make_widget_projection_example)
const widget_card_example        = Example("widget_card",        make_widget_card_document_example,        make_widget_projection_example)
const widget_switch_example      = Example("widget_switch",      make_widget_switch_document_example,      make_widget_projection_example)
const widget_progress_example    = Example("widget_progress",    make_widget_progress_document_example,    make_widget_projection_example)
const widget_slider_example      = Example("widget_slider",      make_widget_slider_document_example,      make_widget_projection_example)
const widget_radio_group_example = Example("widget_radio_group", make_widget_radio_group_document_example, make_widget_projection_example)
const widget_avatar_example      = Example("widget_avatar",      make_widget_avatar_document_example,      make_widget_projection_example)
const widget_alert_example       = Example("widget_alert",       make_widget_alert_document_example,       make_widget_projection_example)
const widget_skeleton_example    = Example("widget_skeleton",    make_widget_skeleton_document_example,    make_widget_projection_example)
const widget_toggle_example      = Example("widget_toggle",      make_widget_toggle_document_example,      make_widget_projection_example)
const widget_toggle_group_example = Example("widget_toggle_group", make_widget_toggle_group_document_example, make_widget_projection_example)
const widget_select_example      = Example("widget_select",      make_widget_select_document_example,      make_widget_projection_example)
const widget_textarea_example    = Example("widget_textarea",    make_widget_textarea_document_example,    make_widget_projection_example)
const widget_accordion_example   = Example("widget_accordion",   make_widget_accordion_document_example,   make_widget_projection_example)
const widget_table_example       = Example("widget_table",       make_widget_table_document_example,       make_widget_projection_example)
const widget_tree_example        = Example("widget_tree",        make_widget_tree_document_example,        make_widget_projection_example)
const layout_example         = Example("layout",         make_layout_document_example,         make_layout_projection_example)
const book_example           = Example("book",           make_book_document_example,           make_book_projection_example)
const filesystem_example     = Example("filesystem",     make_filesystem_document_example,     make_filesystem_projection_example)
const navigator_example      = Example("navigator",      make_navigator_document_example,      make_navigator_projection_example)
const collection_example     = Example("collection",     make_collection_document_example,     make_collection_projection_example)
const reversing_example      = Example("reversing",      make_collection_document_example,     make_reversing_projection_example)
const filtering_example      = Example("filtering",      make_collection_document_example,     make_filtering_projection_example)
const searching_example      = Example("searching",      make_collection_document_example,     make_searching_projection_example)
const sorting_example        = Example("sorting",        make_collection_document_example,     make_sorting_projection_example)
const focusing_example       = Example("focusing",       make_focusing_document_example,       make_focusing_projection_example)
const table_example          = Example("table",          make_table_document_example,          make_table_projection_example)
const math_table_example     = Example("math_table",     make_math_table_document_example,     make_math_table_projection_example)
const workbench_example      = Example("workbench",      make_workbench_document_example,      make_workbench_projection_example)
const lazy_example           = Example("lazy",           make_lazy_document_example,           make_lazy_projection_example)
const lazy_bidirectional_example = Example("lazy_bidirectional", make_lazy_bidirectional_document_example, make_lazy_bidirectional_projection_example)
const math_example           = Example("math",           make_math_document_example,           make_math_projection_example)
const julia_example          = Example("julia",          make_julia_document_example,          make_julia_projection_example)
const graphics_image_example = Example("graphics_image", make_json_document_example,           make_graphics_image_projection_example)
const primitive_string_example = Example("primitive_string", make_primitive_string_document_example, make_primitive_string_projection_example)
const assistant_example      = Example("assistant",      make_assistant_document_example,      make_assistant_projection_example)
const dbcatalog_example      = Example("dbcatalog",      make_dbcatalog_document_example,      make_dbcatalog_projection_example)
const sql_syntax_example     = Example("sql_syntax",     make_sql_document_example,            make_sql_syntax_projection_example)
const sql_table_example      = Example("sql_table",      make_sql_document_example,            make_sql_table_projection_example)

const examples = [
    json_example, json_sorted_example, json_null_example, json_string_example,
    xml_example, mixed_example, syntax_example, text_example, text_with_image_example,
    object_example, object_to_widget_example, line_numbering_example, word_wrapping_example, text_filtering_example, text_highlighting_example,
    widget_example,
    widget_label_example, widget_text_example, widget_checkbox_example, widget_button_example,
    widget_tooltip_example, widget_menu_item_example, widget_menu_example, widget_toolbar_example,
    widget_composite_example, widget_title_pane_example, widget_split_pane_example,
    widget_scroll_bar_example, widget_scroll_pane_example, widget_shell_example,
    widget_tabbed_pane_example,
    widget_badge_example, widget_separator_example, widget_card_example, widget_switch_example,
    widget_progress_example, widget_slider_example, widget_radio_group_example,
    widget_avatar_example, widget_alert_example, widget_skeleton_example,
    widget_toggle_example, widget_toggle_group_example, widget_select_example,
    widget_textarea_example, widget_accordion_example, widget_table_example, widget_tree_example,
    layout_example, book_example, filesystem_example, navigator_example,
    collection_example, reversing_example, filtering_example, searching_example, sorting_example, focusing_example, table_example, math_table_example, workbench_example,
    math_example,
    julia_example,
    graphics_image_example,
    primitive_string_example,
    assistant_example,
    dbcatalog_example,
    sql_syntax_example,
    sql_table_example,
]

function run_example(example::Example; kwargs...)
    run_example([example]; kwargs...)
end

"""
    run_example(examples::Vector{Example}; width, height,
                caching=false, scrolling=false, workbench=false, reset=false,
                tooltip=false, introspection=false, selection=nothing)

Open one window per example, side by side. Each example contributes a
`WindowDocument` with the example's domain document as content; the
composed projection dispatches each window's content to that example's
own projection by **reference path** (so two examples with the same
content type — e.g. both JSON, both wrapped in `WidgetScrollPane` —
still each render through their own pipeline).

Examples no longer carry a pre-set selection. Pass `selection` (a
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
`TextText` document (the text examples). The two flags are mutually exclusive.
"""
function run_example(examples::Vector{Example}; width=nothing, height=nothing,
                     caching=false, scrolling=false, workbench=false, reset=false,
                     tooltip=false, introspection=false,
                     text_filtering=false, text_highlighting=false, selection=nothing)
    isempty(examples) && error("run_example: empty examples vector")
    if text_filtering && text_highlighting
        error("run_example: text_filtering and text_highlighting are mutually exclusive")
    end
    if width === nothing || height === nothing
        sw, sh = sdl_display_size()
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

    # Lay out the WindowDocuments side by side. Each example.name becomes
    # the window id — must be unique within the screen, so duplicate
    # names are an error.
    seen_ids = Set{Symbol}()
    windows = WindowDocument[]
    for (i, ex) in enumerate(examples)
        id = Symbol(ex.name)
        id in seen_ids && error("run_example: duplicate example name :$id; window ids must be unique")
        push!(seen_ids, id)
        push!(windows, WindowDocument(;
            id     = id,
            title  = ex.name,
            x      = 100 + (i - 1) * (width + 40),
            y      = 100,
            width  = width,
            height = height,
            content = docs[i],
        ))
    end
    screen = ScreenDocument(windows)

    # Lift the first window-content's selection (seeded from the `selection`
    # keyword above) to a screen-rooted path. Without this, the screen and
    # intermediate WindowDocument keep `selection = nothing` while the inner
    # document carries a deep selection. The next click then traverses a
    # different branch via `set_selection!` and the stale leaf selection on
    # the original branch is never cleared — `_collect_spans` walks both
    # branches and picks the first cursor it finds, which makes new clicks
    # appear to be ignored. When no `selection` was passed every document
    # keeps `selection = nothing` and this loop is a no-op.
    for (i, win) in enumerate(windows)
        # For the tooltip variant the original document sits one level
        # deeper, behind the TooltipSource wrapper's `child` field.
        root_doc = tooltip ? win.content.child : win.content
        inner_sel = getfield(root_doc, :selection)[]
        inner_sel === nothing && continue
        full_path = tooltip ?
            (@reference windows[i].content.child.^(inner_sel)) :
            (@reference windows[i].content.^(inner_sel))
        set_selection!(screen, full_path)
        break
    end

    composed = tooltip ? _multi_window_projection_tooltipped(projs) :
                         _multi_window_projection(projs)
    run!(SdlBackend(), composed, screen)
end

# Build a projection that copies the ScreenDocument / WindowDocument spine
# down to each `windows{i}.content` reference and applies the matching
# example's projection only at that exact leaf. Dispatch by reference path
# rather than content type so two examples with the same root document
# type still each render through their own pipeline.
#
# CopyingProjection's CellVector path encodes element indices as
# `PositionReference(i)` (the `{i}` form of `@reference`); the target
# paths are constructed the same way so `reference_equal` works.
function _multi_window_projection(projections::Vector)
    n = length(projections)
    targets = Vector{Any}(undef, n)
    for i in 1:n
        targets[i] = @reference windows{i}.content
    end
    return RecursiveProjection(ReferenceDispatchingProjection(ref -> begin
        # Exact match — apply that window's example projection here. Wrap
        # in NestingProjection so the inner projection's own recursion
        # takes over for everything below this point; the outer recursion
        # is shut off via PreservingProjection.
        for i in 1:n
            reference_equal(ref, targets[i]) || continue
            return NestingProjection(projections[i];
                                      recursion=PreservingProjection())
        end
        # Spine above any window's content target — copy through.
        for t in targets
            is_prefix_of(ref, t) || continue
            return CopyingProjection()
        end
        # Anything else is outside the screen spine — preserve.
        return PreservingProjection()
    end))
end

# ── Tooltip variant ──────────────────────────────────────────────────────
#
# Wrap a domain document in a `TooltipSource` whose `content` is a
# *reactive* `TextText`: the elements thunk re-reads `doc.selection`
# every frame and rebuilds the colored spans via `ReferenceToText`. The
# `TooltipDecoratorProjection` reader watches the wrapped document and
# emits `OpenWindowOperation` / `CloseWindowOperation` as the selection
# arrives / clears; the `WindowManagerProjection` applies those to the
# screen.

function _make_tooltip_source(doc; id::Symbol)
    short_proj = ReferenceToText()
    long_proj  = ReferenceToHumanReadableText(doc)
    content = TextText(() -> begin
        sel = doc.selection
        ctx = PrinterContext()
        short = projection_print(short_proj, nothing, sel, ctx).output
        long  = projection_print(long_proj,  nothing, sel, ctx).output
        spans = TextDocument[]
        for i in 1:length(short)
            push!(spans, short[i])
        end
        push!(spans, TextNewline(font=short_proj.font))
        push!(spans, TextNewline(font=short_proj.font))
        for i in 1:length(long)
            push!(spans, long[i])
        end
        spans
    end)
    TooltipSource(child = doc, content = content, style = :tooltip, id = id)
end

# Same shape as `_multi_window_projection` but with the four extra type
# entries needed for tooltip support, sitting in front of the existing
# reference-based dispatch for example content.
function _multi_window_projection_tooltipped(projections::Vector; measure=sdl_measure_text)
    n = length(projections)
    targets = Vector{Any}(undef, n)
    for i in 1:n
        targets[i] = @reference windows{i}.content
    end
    decorator = TooltipDecoratorProjection(
        trigger  = (source, _evt) -> source.child.selection !== nothing,
        position = _ -> (100, 100, 1200, 600),
        title    = "Selection",
    )
    ref_dispatch = ReferenceDispatchingProjection(ref -> begin
        for i in 1:n
            reference_equal(ref, targets[i]) || continue
            return NestingProjection(projections[i];
                                      recursion=PreservingProjection())
        end
        for t in targets
            is_prefix_of(ref, t) || continue
            return CopyingProjection()
        end
        return PreservingProjection()
    end)
    RecursiveProjection(
        TypeDispatchingProjection(
            ScreenDocument => WindowManagerProjection(inner = CopyingProjection()),
            WindowDocument => CopyingProjection(),
            CellVector     => CopyingProjection(),
            TooltipSource  => decorator,
            TextText       => SequentialProjection(WordWrapping(measure=measure), TextToGraphics(measure=measure)),
            Any            => ref_dispatch,
        ),
    )
end

function run_example(name="json"; kwargs...)
    idx = findfirst(ex -> ex.name == name, examples)
    if idx === nothing
        available = join(getfield.(examples, :name), ", ")
        error("Unknown example: \"$name\". Available: $available")
    end
    run_example(examples[idx]; kwargs...)
end

"""
    run_example(names::Vector{<:AbstractString}; kwargs...)

Convenience: look up each name in the global `examples` list and open
them side by side. Same semantics as `run_example(::Vector{Example})`.
"""
function run_example(names::Vector{<:AbstractString}; kwargs...)
    selected = Example[]
    for name in names
        idx = findfirst(ex -> ex.name == name, examples)
        idx === nothing && error("Unknown example: \"$name\"")
        push!(selected, examples[idx])
    end
    run_example(selected; kwargs...)
end

function print_example(example::Example)
    iomap = projection_print(example.projection, example.document)
    output = iomap.output
    println(print_object(output isa Cell ? output[] : output; open_delimiter="{", close_delimiter="}"))
end

function print_example(name="json")
    idx = findfirst(ex -> ex.name == name, examples)
    if idx === nothing
        available = join(getfield.(examples, :name), ", ")
        error("Unknown example: \"$name\". Available: $available")
    end
    print_example(examples[idx])
end

function write_image_example(example::Example, filename;
                              width=1200, height=800, kwargs...)
    write_image(example.document, example.projection, filename;
                width=width, height=height, kwargs...)
end

function write_image_example(name="json", filename=tempname()*".bmp"; kwargs...)
    idx = findfirst(ex -> ex.name == name, examples)
    idx === nothing && error("Unknown example: \"$name\"")
    write_image_example(examples[idx], filename; kwargs...)
end

"""
    generate_screenshots(; width=1920, height=1080,
                          image_dir=joinpath(@__DIR__, "..", "..", "image", "example"))

Generate a PNG screenshot for every example in `examples` into `image_dir`.
Filename pattern: `{example-name-with-hyphens}.png`. One failure does not
abort the batch.
"""
function generate_screenshots(; width=1920, height=1080, supersample=3,
                              image_dir=joinpath(@__DIR__, "..", "..", "image", "example"))
    mkpath(image_dir)
    white = (0xff, 0xff, 0xff, 0xff)
    for ex in examples
        safe_name = replace(ex.name, "_" => "-")
        png = joinpath(image_dir, "$safe_name.png")
        @info "Generating $(ex.name)..."
        # Widgets render on the light theme background, so screenshot them on
        # white rather than the default solarized canvas.
        bg = startswith(ex.name, "widget") ? white : (0xfd, 0xf6, 0xe3, 0xff)
        try
            write_image_example(ex, png; width=width, height=height,
                                background=bg, supersample=supersample)
            @info "  ✓ $png"
        catch e
            @warn "  ✗ $(ex.name): $e"
        end
    end
end

"""
    update_guide_screenshots(; repo_root=joinpath(@__DIR__, "..", ".."))

Inject `![...](...)` image references into the guide files and `README.md`.
Idempotent: re-running produces no changes once images are in place.
"""
function update_guide_screenshots(; repo_root=joinpath(@__DIR__, "..", ".."))
    _update_examples_tour(joinpath(repo_root, "guide", "examples-tour.md"))
    _update_domain_guides(joinpath(repo_root, "guide", "document"))
    _update_readme(joinpath(repo_root, "README.md"))
end

const _TOUR_HEADER_RE = r"^## \d+\. .*`run_example\(\"(\w+)\"\)`"

function _example_title(name::AbstractString)
    titlecase(replace(name, "_" => " "))
end

function _update_examples_tour(path::AbstractString)
    isfile(path) || (@warn "Missing $path"; return)
    lines = readlines(path; keep=false)
    out = String[]
    i = 1
    while i <= length(lines)
        line = lines[i]
        push!(out, line)
        m = match(_TOUR_HEADER_RE, line)
        if m !== nothing
            name = m.captures[1]
            safe_name = replace(name, "_" => "-")
            img_line = "![$(_example_title(name)) example](../image/example/$safe_name.png)"
            j = i + 1
            while j <= length(lines) && isempty(strip(lines[j]))
                push!(out, lines[j])
                j += 1
            end
            already_present = j <= length(lines) && startswith(strip(lines[j]), "![")
            if !already_present
                push!(out, img_line)
                push!(out, "")
            end
            i = j
            continue
        end
        i += 1
    end
    new_text = join(out, "\n") * "\n"
    new_text = replace(new_text,
        "Screenshots are in [image/](../image/)." =>
        "Screenshots for each example are embedded inline below.")
    if read(path, String) != new_text
        write(path, new_text)
    end
end

const _DOMAIN_GUIDE_EXAMPLE = Dict(
    "json.md"       => "json",
    "xml.md"        => "xml",
    "text.md"       => "text",
    "syntax.md"     => "syntax",
    "graphics.md"   => "graphics_image",
    "widget.md"     => "widget",
    "workbench.md"  => "workbench",
    "collection.md" => "collection",
)

function _update_domain_guides(dir::AbstractString)
    isdir(dir) || (@warn "Missing $dir"; return)
    for (filename, example_name) in _DOMAIN_GUIDE_EXAMPLE
        path = joinpath(dir, filename)
        isfile(path) || continue
        lines = readlines(path; keep=false)
        if any(l -> occursin("![", l), lines[1:min(end, 15)])
            continue
        end
        heading_idx = findfirst(l -> startswith(l, "# "), lines)
        heading_idx === nothing && continue
        blank_idx = findnext(l -> isempty(strip(l)), lines, heading_idx + 1)
        insert_after = blank_idx === nothing ? heading_idx : blank_idx
        safe_name = replace(example_name, "_" => "-")
        img_line = "![$(_example_title(example_name)) example](../../image/example/$safe_name.png)"
        new_lines = vcat(
            lines[1:insert_after],
            [img_line, ""],
            lines[insert_after+1:end],
        )
        new_text = join(new_lines, "\n") * "\n"
        if read(path, String) != new_text
            write(path, new_text)
        end
    end
end

const _README_SCREENSHOTS_BLOCK = """
## Screenshots

| JSON editor | Widget forms | Table view |
|---|---|---|
| ![JSON example](image/example/json.png) | ![Widget example](image/example/widget.png) | ![Table example](image/example/table.png) |

| Syntax tree | Julia AST | Workbench |
|---|---|---|
| ![Syntax example](image/example/syntax.png) | ![Julia AST example](image/example/julia.png) | ![Workbench example](image/example/workbench.png) |
"""

function _update_readme(path::AbstractString)
    isfile(path) || (@warn "Missing $path"; return)
    text = read(path, String)
    block_re = r"## Screenshots\n(?:.*\n)*?(?=\n## )"
    new_text = if occursin(block_re, text)
        replace(text, block_re => _README_SCREENSHOTS_BLOCK)
    else
        text
    end
    if new_text != text
        write(path, new_text)
    end
end

