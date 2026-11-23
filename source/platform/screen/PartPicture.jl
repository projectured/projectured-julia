# Fragment of `ScreenModule` — a picture of a part, of the selection or of a window,
# as the editor draws it now, in a PNG file of the folder of pictures.

"""
    write_part_picture(part; editor = get_evaluation_editor(), filename = make_picture_filename())
        -> ImageFile or nothing

A picture of `part` as the window draws it now, in the PNG file `filename`, by
default a new file in the folder of pictures. `part` is a part, such as a tab that
`find_pane` gives, whose reference names it from the root of the document of
`editor`, or such a reference. The picture is the canvas that draws the part, all
of it, also what a pane scrolls out of view. A part that a view draws with no
canvas of its own, such as a file under the wrapper of its undo, has the picture
of the nearest part above it that has one. `nothing` when no part on the way has
a canvas, or when no backend writes an image. The code tool gives the picture to
the assistant as an image.

Use it to see a part that has no text, such as a plot, a layout or a widget.

# Example

    write_part_picture(find_pane("notes.md"))

See also `write_window_picture` and `write_selection_picture`.

For the assistant.
"""
function write_part_picture end

write_part_picture(part::ReferencedDocument; kwargs...) = write_part_picture(get_reference(part); kwargs...)

function write_part_picture(reference::Reference; editor = get_evaluation_editor(),
                            filename::AbstractString = make_picture_filename())
    editor isa Editor || return nothing
    run_on_editor_task!(editor; description = "write_part_picture") do
        _write_part_picture(editor, reference, filename)
    end
end

"""
    write_selection_picture(; editor = get_evaluation_editor(), filename = make_picture_filename())
        -> ImageFile or nothing

A picture of the part that the person selected as a whole, with Alt+double click,
as the window draws it now, in the PNG file `filename`, by default a new file in
the folder of pictures, as [`write_part_picture`](@ref) writes a part. `nothing`
when the person selected no part as a whole, or when no backend writes an image.
The code tool gives the picture to the assistant as an image.

Use it to see the part that the person shows you.

# Example

    write_selection_picture()

See also `write_part_picture` and `write_window_picture`.

For the assistant.
"""
function write_selection_picture end

function write_selection_picture(; editor = get_evaluation_editor(),
                                 filename::AbstractString = make_picture_filename())
    editor isa Editor || return nothing
    run_on_editor_task!(editor; description = "write_selection_picture") do
        selection = get_selection(editor.document)
        is_whole_selection(editor.document, selection) ? _write_part_picture(editor, selection, filename) : nothing
    end
end

"""
    write_window_picture(; editor = get_evaluation_editor(), filename = make_picture_filename())
        -> ImageFile or nothing

A picture of the window of `editor`, all that it draws now, in the PNG file
`filename`, by default a new file in the folder of pictures: the window that shows
the selection, else the first window. `nothing` when the editor shows no window,
or when no backend writes an image. The code tool gives the picture to the
assistant as an image.

Use it to see what the window draws.

# Example

    write_window_picture()

See also `write_part_picture` and `write_selection_picture`.

For the assistant.
"""
function write_window_picture end

function write_window_picture(; editor = get_evaluation_editor(),
                              filename::AbstractString = make_picture_filename())
    editor isa Editor || return nothing
    run_on_editor_task!(editor; description = "write_window_picture") do
        _write_window_picture(editor, get_selection(editor.document), filename)
    end
end

# The picture of the part at `source`, a reference from the document of `editor`.
function _write_part_picture(editor, source, filename::AbstractString)
    part, window = _find_picture_target(editor, source)
    part === nothing ? nothing : _write_canvas_picture(part, window, filename)
end

# The picture of the window that shows the part at `source`; with no `source`, or a
# `source` that no window shows, the first window.
function _write_window_picture(editor, source, filename::AbstractString)
    _, window = _find_picture_target(editor, source)
    if window === nothing
        iomap = editor.iomap
        screen = iomap === nothing ? nothing : get_iomap_output(iomap)
        screen isa ScreenDocument || return nothing
        index = findfirst(w -> w isa WindowDocument, collect(screen.windows))
        index === nothing && return nothing
        window = screen.windows[index]
    end
    window.content isa GraphicsCanvas || return nothing
    _write_canvas_picture(window.content, window, filename)
end

# The canvas that draws the part at `source`, or else the nearest part above it
# that has one, or `nothing` when no part on the way has one, and the last window
# on the way to it.
function _find_picture_target(editor, source)
    iomap = editor.iomap
    (iomap === nothing || !(source isa Reference)) && return (nothing, nothing)
    input = get_iomap_input(iomap)
    try_evaluate_reference(input, source, _NO_PART) === _NO_PART && return (nothing, nothing)
    steps = get_reference_steps(strip_reference_types(source))
    window = nothing
    for count in length(steps):-1:1
        path = foldr((step, tail) -> ConcreteReference(step, tail), steps[1:count]; init = EmptyReference())
        image = map_reference_forward(editor.projection, iomap, annotate_reference_types(input, path))
        part, found = _walk_picture_image(get_iomap_output(iomap), image)
        window === nothing && (window = found)
        part === nothing || return (part, found)
    end
    (nothing, window)
end

# Walk `image` from the printed output `node`: the canvas that it reaches, or
# `nothing` when it reaches a text or no canvas, and the last window on its way.
function _walk_picture_image(node, image)
    window = nothing
    while image isa ConcreteReference
        node = try
            _get_cell_value(evaluate_reference_step(get_reference_head(image), node))
        catch exception
            is_fault_exception(exception) || rethrow()
            return (nothing, window)
        end
        node isa WindowDocument && (window = node)
        node isa GraphicsText && return (nothing, window)
        image = get_reference_tail(image)
    end
    (image isa EmptyReference && node isa GraphicsCanvas ? node : nothing, window)
end

_get_cell_value(value) = value isa AbstractCell ? _get_cell_value(value[]) : value

# Write `node` at the origin, at its size, on the background of `window`.
function _write_canvas_picture(node::GraphicsCanvas, window, filename::AbstractString)
    canvas = GraphicsCanvas(Any[node]; x = -Int(node.x), y = -Int(node.y))
    _, _, right, bottom = get_canvas_content_bounds(canvas)
    width = node.w > 0 ? Int(node.w) : right
    height = node.h > 0 ? Int(node.h) : bottom
    (width > 0 && height > 0) || return nothing
    applicable(write_image, canvas, filename) || return nothing
    background = window isa WindowDocument ? window.bg : (0xf9, 0xf9, 0xfb, 0xff)
    write_image(canvas, filename; width, height, background)
end

# The days that a picture stays in the folder of pictures after it is written.
const PICTURE_KEEP_DAYS = 30

"""
    make_picture_filename() -> String

A new name for the PNG file of a picture, in the folder of pictures of the user:
`\$XDG_CACHE_HOME/projectured/pictures`, by default `~/.cache/projectured/pictures`.
The pictures of the folder that are older than `PICTURE_KEEP_DAYS` days go away
first.
"""
function make_picture_filename()
    cache = get(ENV, "XDG_CACHE_HOME", "")
    isempty(cache) && (cache = joinpath(homedir(), ".cache"))
    directory = mkpath(joinpath(cache, "projectured", "pictures"))
    _remove_old_pictures!(directory)
    stem = "picture-" * Libc.strftime("%Y%m%d-%H%M%S", time())
    filename = joinpath(directory, stem * ".png")
    count = 1
    while isfile(filename)
        count += 1
        filename = joinpath(directory, stem * "-$(count).png")
    end
    filename
end

# Remove each picture file `picture-*.png` of `directory` that was written more
# than `days` days ago. Other files of the folder stay.
function _remove_old_pictures!(directory::AbstractString; days::Real = PICTURE_KEEP_DAYS)
    oldest = time() - days * 86400
    for name in readdir(directory)
        startswith(name, "picture-") && endswith(name, ".png") || continue
        path = joinpath(directory, name)
        isfile(path) && mtime(path) < oldest && rm(path; force = true)
    end
    nothing
end
