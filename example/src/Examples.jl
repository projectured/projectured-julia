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
const object_example         = Example("object",         make_object_document_example,         make_object_projection_example)
const line_numbering_example = Example("line_numbering", make_line_numbering_document_example, make_line_numbering_projection_example)
const word_wrapping_example  = Example("word_wrapping",  make_word_wrapping_document_example,  make_word_wrapping_projection_example)
const widget_example         = Example("widget",         make_widget_document_example,         make_widget_projection_example)
const widget_tabbed_pane_example = Example("widget_tabbed_pane", make_widget_tabbed_pane_document_example, make_widget_projection_example)
const layout_example         = Example("layout",         make_layout_document_example,         make_layout_projection_example)
const book_example           = Example("book",           make_book_document_example,           make_book_projection_example)
const filesystem_example     = Example("filesystem",     make_filesystem_document_example,     make_filesystem_projection_example)
const navigator_example      = Example("navigator",      make_navigator_document_example,      make_navigator_projection_example)
const collection_example     = Example("collection",     make_collection_document_example,     make_collection_projection_example)
const reversing_example      = Example("reversing",      make_collection_document_example,     make_reversing_projection_example)
const filtering_example      = Example("filtering",      make_collection_document_example,     make_filtering_projection_example)
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

const examples = [
    json_example, json_sorted_example, json_null_example, json_string_example,
    xml_example, mixed_example, syntax_example, text_example,
    object_example, line_numbering_example, word_wrapping_example,
    widget_example, widget_tabbed_pane_example, layout_example, book_example, filesystem_example, navigator_example,
    collection_example, reversing_example, filtering_example, sorting_example, focusing_example, table_example, math_table_example, workbench_example,
    math_example,
    julia_example,
    graphics_image_example,
    primitive_string_example,
    assistant_example,
]

function run_example(example::Example; kwargs...)
    run_example([example]; kwargs...)
end

"""
    run_example(examples::Vector{Example}; width, height,
                caching=false, scrolling=false, workbench=false, reset=false,
                tooltip=false)

Open one window per example, side by side. Each example contributes a
`WindowDocument` with the example's domain document as content; the
composed projection dispatches each window's content to that example's
own projection by **reference path** (so two examples with the same
content type — e.g. both JSON, both wrapped in `WidgetScrollPane` —
still each render through their own pipeline).

When `tooltip=true`, each example's content is wrapped in a
`TooltipSource`. While the user has a selection inside that example,
a sibling tooltip window opens (id `:tooltip_<example-name>`) showing
the selection's reference path via `ReferenceToText`. The tooltip
closes when the selection is cleared.
"""
function run_example(examples::Vector{Example}; width=nothing, height=nothing,
                     caching=false, scrolling=false, workbench=false, reset=false,
                     tooltip=false)
    isempty(examples) && error("run_example: empty examples vector")
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
    for ex in examples
        document   = reset ? ex.make_document()   : ex.document
        projection = reset ? ex.make_projection() : ex.projection
        if workbench
            document   = make_workbench_document(document; title=ex.name)
            projection = make_workbench_projection()
        elseif scrolling
            document   = make_scrolling_document(document; width=width, height=height)
            projection = make_scrolling_projection(projection)
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
    ref_proj = ReferenceToText()
    content = TextText(() -> begin
        sel = doc.selection
        snapshot = projection_print(ref_proj, sel, nothing, ProjectionContext()).output
        # Extract spans into a plain Vector so the outer CellVector can
        # wrap each one in a fresh Cell on every recompute.
        TextDocument[snapshot[i] for i in 1:length(snapshot)]
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
        position = _ -> (100, 100, 1200, 200),
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
            TextText       => TextToGraphics(measure=measure),
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
    generate_screenshots(; width=960, height=640,
                          image_dir=joinpath(@__DIR__, "..", "..", "image", "example"))

Generate a PNG screenshot for every example in `examples` into `image_dir`.
Filename pattern: `{example-name-with-hyphens}.png`. One failure does not
abort the batch.
"""
function generate_screenshots(; width=960, height=640,
                              image_dir=joinpath(@__DIR__, "..", "..", "image", "example"))
    mkpath(image_dir)
    for ex in examples
        safe_name = replace(ex.name, "_" => "-")
        png = joinpath(image_dir, "$safe_name.png")
        @info "Generating $(ex.name)..."
        try
            write_image_example(ex, png; width=width, height=height)
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

