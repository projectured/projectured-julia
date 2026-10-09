const examples = [
    json_example, json_sorted_example, json_insertion_example,
    yaml_example,
    xml_example, mixed_example, natural_example, syntax_example, text_example, plain_text_example, text_with_image_example,
    object_example, object_to_widget_example, nested_object_to_widget_example, line_numbering_example, word_wrapping_example, text_filtering_example, text_highlighting_example,
    widget_example,
    widget_label_example, widget_text_example, widget_checkbox_example, widget_button_example,
    widget_button_action_example, widget_button_image_example,
    widget_tooltip_example, widget_menu_item_example, widget_menu_example, widget_toolbar_example,
    widget_toolbar_item_example,
    widget_composite_example, widget_title_pane_example, widget_split_pane_example,
    widget_scroll_bar_example, widget_scroll_pane_example, widget_transform_pane_example,
    widget_offered_example,
    widget_shell_example,
    widget_tabbed_pane_example,
    # The pane examples are deliberately NOT in this list. The sweep drivers walk
    # every registered example, and the type-in driver types at every caret of a
    # whole *layout* — most of which is chrome that rightly declines — so their
    # failures would drown the suite's baseline. Run them by name:
    # `run_example(pane_example)` / `run_example(empty_pane_example)`.
    widget_badge_example, widget_separator_example, widget_card_example, widget_collapsible_card_example, widget_switch_example,
    widget_progress_bar_example, widget_progress_ring_example, widget_slider_example, widget_radio_group_example,
    widget_avatar_example, widget_alert_example, widget_skeleton_example, widget_swatch_example,
    widget_toggle_example, widget_toggle_group_example, widget_select_example,
    widget_textarea_example, widget_accordion_example, widget_table_example,
    widget_table_offered_example, widget_table_frozen_example, widget_tree_example,
    widget_disabled_example, widget_focus_example,
    layout_example, constraint_layout_example, book_example, markdown_example, markdown_rendered_example, filesystem_example, filesystem_widget_example, files_example,
    collection_example, reversing_example, filtering_example, searching_example, sorting_example, focusing_example, table_example, math_table_example, graph_example,
    chart_example, chart_line_example, chart_bar_example, chart_histogram_example, chart_scatter_example, chart_strip_example, chart_inspector_example,
    sequencechart_example, sequencechart_vertical_example, sequencechart_linear_example,
    sequencechart_inspector_example, sequencechart_pair_example,
    fsm_example, fsm_toggle_example, fsm_diagram_example,
    pivot_example,
    workflow_example,
    workflow_journal_example,
    math_example,
    julia_example,
    formula_example,
    graphics_image_example,
    rotating_vector_example,
    assistant_example,
    conversation_widget_example,
    conversation_editor_example,
    sql_syntax_example,
    sql_insert_syntax_example,
    sql_update_syntax_example,
    sql_nested_syntax_example,
    dragging_example,
]

"""
    run_assistant_example(; backend = :ollama, model = "", kwargs...) -> Nothing

The assistant example with a real model behind it: `:ollama` for a local model,
`:anthropic` for Claude. `model` names one, and an empty `model` takes the
default of that backend.

`run_example("assistant")` opens the same example with a `FakeLlm`, which
answers from the canned transcript and needs no server and no key. That is what
the test sweeps run.
"""
function run_assistant_example(; backend::Symbol = :ollama, model::AbstractString = "",
                               kwargs...)
    document = make_assistant_document_example(; backend = backend, model = model)
    run_example(document, make_assistant_projection_example(); name = "assistant",
                kwargs...)
end

# @optional: the name of the example stands first, as at a command line.
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

function print_example(name="json")
    idx = findfirst(ex -> ex.name == name, examples)
    if idx === nothing
        available = join(getfield.(examples, :name), ", ")
        error("Unknown example: \"$name\". Available: $available")
    end
    print_example(examples[idx])
end

# @optional: the name of the example stands first, then the output file, as at a
# command line.
function write_example_image(name="json", filename=tempname()*".bmp"; kwargs...)
    idx = findfirst(ex -> ex.name == name, examples)
    idx === nothing && error("Unknown example: \"$name\"")
    write_example_image(examples[idx], filename; kwargs...)
end

# @optional: the name of the example stands first, then the output file, as at a
# command line.
function write_example_pdf(name="json", filename=tempname()*".pdf"; kwargs...)
    idx = findfirst(ex -> ex.name == name, examples)
    idx === nothing && error("Unknown example: \"$name\"")
    write_example_pdf(examples[idx], filename; kwargs...)
end

# @optional: the output file stands last of the positionals, as the destination
# named at a command line.
function record_example_video(name::AbstractString, gestures,
                              filename=tempname()*".mp4"; kwargs...)
    idx = findfirst(ex -> ex.name == name, examples)
    idx === nothing && error("Unknown example: \"$name\"")
    record_example_video(examples[idx], gestures, filename; kwargs...)
end

# Export density for generated screenshots: PNGs are rendered at this many device
# pixels per logical pixel so they stay crisp on HiDPI displays (e.g. GitHub
# viewed on a retina screen) independent of the machine that generates them.
# Guide embeds pin the *displayed* width to the logical size (png width ÷ this)
# via `<img width>`, so the on-page size is unchanged while the extra pixels are
# available for sharp rendering.
const SCREENSHOT_DENSITY = 2

"""
    generate_example_screenshots(; filter=nothing, max_width=1920, max_height=1080,
                                 image_dir=joinpath(@__DIR__, "..", "..", "asset", "image", "example"))

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
function generate_example_screenshots(; filter=nothing, max_width=1920, max_height=1080, supersample=3,
                                      density=SCREENSHOT_DENSITY,
                                      image_dir=joinpath(@__DIR__, "..", "..", "asset", "image", "example"))
    mkpath(image_dir)
    # The default widget theme's background (slate-100); widget screenshots use
    # it so the canvas matches the themed surfaces rather than showing white.
    widget_bg = (0xf1, 0xf5, 0xf9, 0xff)
    pattern = filter isa AbstractString ? Regex(filter) : filter
    for ex in examples
        if pattern !== nothing && !occursin(pattern, ex.name)
            continue
        end
        safe_name = replace(ex.name, "_" => "-")
        png = joinpath(image_dir, "$safe_name.png")
        @info "Generating $(ex.name)..."
        # Widgets render on the light theme background, so screenshot them on
        # the themed surface rather than the default solarized canvas.
        bg = startswith(ex.name, "widget") ? widget_bg : (0xfd, 0xf6, 0xe3, 0xff)
        try
            write_example_image(ex, png; width=ex.render_width, height=ex.render_height,
                                max_width=max_width, max_height=max_height,
                                background=bg, supersample=supersample, density=density)
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
    _update_examples_tour(joinpath(repo_root, "documentation", "guide", "examples-tour.md"))
    _update_domain_guides(repo_root)
    _update_readme(joinpath(repo_root, "README.md"))
    # Convert any remaining plain Markdown example-images (thumbnail tables, the
    # README hero, etc.) to width-pinned <img> tags. Guides live in the top-level
    # documentation/ tree and in each package's doc/ dir.
    md_files = String[joinpath(repo_root, "README.md")]
    guide_dirs = String[joinpath(repo_root, "documentation")]
    pkg_dir = joinpath(repo_root, "package")
    if isdir(pkg_dir)
        for p in readdir(pkg_dir)
            d = joinpath(pkg_dir, p, "doc")
            isdir(d) && push!(guide_dirs, d)
        end
    end
    for guide_dir in guide_dirs
        isdir(guide_dir) || continue
        for (root, _, files) in walkdir(guide_dir), f in files
            endswith(f, ".md") && push!(md_files, joinpath(root, f))
        end
    end
    foreach(_migrate_example_image_embeds, md_files)
end

const _TOUR_HEADER_RE = r"^## \d+\. .*`run_example\(\"(\w+)\"\)`"

function _example_title(name::AbstractString)
    titlecase(replace(name, "_" => " "))
end

# Width field of a PNG's IHDR header (bytes 16-19, big-endian). Avoids a decode.
function _png_pixel_width(path::AbstractString)
    open(path) do io
        seek(io, 16)
        Int(ntoh(read(io, UInt32)))
    end
end

# Markdown embed for a screenshot. Screenshots are `SCREENSHOT_DENSITY`× their
# logical size, so we pin the displayed width to the logical size with an HTML
# `<img width>` (honored by GitHub): compact on the page, sharp on HiDPI. Falls
# back to a plain Markdown image if the PNG is missing (so docs still build).
function _img_embed(title::AbstractString, rel_path::AbstractString, md_dir::AbstractString)
    _img_embed_raw("$title example", rel_path, md_dir, "![$title example]($rel_path)")
end

# True when a line already holds a screenshot embed (Markdown image or <img>).
_is_image_embed(line) = (s = strip(line); startswith(s, "![") || startswith(s, "<img"))

# Any Markdown image pointing at an example screenshot: ![alt](…image/example/X.png)
const _MD_EXAMPLE_IMG_RE = r"!\[([^\]]*)\]\(([^)]*image/example/[^)]+\.png)\)"

# Convert every plain Markdown example-image in a file to an `<img width>` tag
# pinned to the logical size — covers embeds the heading inserters don't touch
# (thumbnail tables, the README hero). Idempotent: `<img>` tags aren't matched.
function _migrate_example_image_embeds(path::AbstractString)
    isfile(path) || return
    md_dir = dirname(path)
    text = read(path, String)
    new_text = replace(text, _MD_EXAMPLE_IMG_RE => function (s)
        mm = match(_MD_EXAMPLE_IMG_RE, s)
        alt, rel = mm.captures[1], mm.captures[2]
        _img_embed_raw(alt, rel, md_dir, s)
    end)
    new_text != text && write(path, new_text)
end

# Like `_img_embed` but with an explicit alt string and a literal fallback.
function _img_embed_raw(alt::AbstractString, rel::AbstractString, md_dir::AbstractString, fallback::AbstractString)
    abs_png = normpath(joinpath(md_dir, rel))
    isfile(abs_png) || return fallback
    w = max(1, _png_pixel_width(abs_png) ÷ SCREENSHOT_DENSITY)
    "<img width=\"$w\" alt=\"$alt\" src=\"$rel\">"
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
            img_line = _img_embed(_example_title(name), "../asset/image/example/$safe_name.png", dirname(path))
            j = i + 1
            while j <= length(lines) && isempty(strip(lines[j]))
                push!(out, lines[j])
                j += 1
            end
            if j <= length(lines) && _is_image_embed(lines[j])
                # Replace the existing embed (migrates Markdown ↔ <img>).
                push!(out, img_line)
                i = j + 1
            else
                push!(out, img_line)
                push!(out, "")
                i = j
            end
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

# Per-domain guides moved out of documentation/document/ into the package that
# owns each domain; keyed by repo-relative path so the asset link is computed at
# the guide's real depth (see _update_domain_guides).
const _DOMAIN_GUIDE_EXAMPLE = Dict(
    "package/domain/doc/json.md"      => "json",
    "package/domain/doc/xml.md"       => "xml",
    "package/visual/doc/text.md"      => "text",
    "package/visual/doc/syntax.md"    => "syntax",
    "package/visual/doc/graphics.md"  => "graphics_image",
    "package/visual/doc/widget.md"    => "widget",
    "package/domain/doc/chart.md"     => "chart",
    "package/domain/doc/sequencechart.md" => "sequencechart",
    "package/base/doc/collection.md"  => "collection",
)

function _update_domain_guides(repo_root::AbstractString)
    for (guide_rel, example_name) in _DOMAIN_GUIDE_EXAMPLE
        path = joinpath(repo_root, guide_rel)
        isfile(path) || continue
        lines = readlines(path; keep=false)
        heading_idx = findfirst(l -> startswith(l, "# "), lines)
        heading_idx === nothing && continue
        safe_name = replace(example_name, "_" => "-")
        png_abs = joinpath(repo_root, "asset", "image", "example", "$safe_name.png")
        img_src = relpath(png_abs, dirname(path))
        img_line = _img_embed(_example_title(example_name), img_src, dirname(path))
        existing = findfirst(_is_image_embed, lines[1:min(end, 15)])
        new_lines = if existing !== nothing
            # Replace the existing embed in place (migrates Markdown ↔ <img>).
            vcat(lines[1:existing-1], [img_line], lines[existing+1:end])
        else
            blank_idx = findnext(l -> isempty(strip(l)), lines, heading_idx + 1)
            insert_after = blank_idx === nothing ? heading_idx : blank_idx
            vcat(lines[1:insert_after], [img_line, ""], lines[insert_after+1:end])
        end
        new_text = join(new_lines, "\n") * "\n"
        if read(path, String) != new_text
            write(path, new_text)
        end
    end
end

function _readme_screenshots_block(md_dir::AbstractString)
    cell(name, title) = _img_embed(title, "asset/image/example/$name.png", md_dir)
    """
    ## Screenshots

    | JSON editor | Widget forms | Table view |
    |---|---|---|
    | $(cell("json", "JSON")) | $(cell("widget", "Widget")) | $(cell("table", "Table")) |

    | Syntax tree | Julia AST | Assistant |
    |---|---|---|
    | $(cell("syntax", "Syntax")) | $(cell("julia", "Julia AST")) | $(cell("assistant", "Assistant")) |

    ---
    """
end

function _update_readme(path::AbstractString)
    isfile(path) || (@warn "Missing $path"; return)
    text = read(path, String)
    block_re = r"## Screenshots\n(?:.*\n)*?(?=\n## )"
    new_text = if occursin(block_re, text)
        replace(text, block_re => _readme_screenshots_block(dirname(path)))
    else
        text
    end
    if new_text != text
        write(path, new_text)
    end
end

