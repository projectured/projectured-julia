# Fragment of `ScreenModule` — a picture of a part or of a window, as the editor
# draws it now.

"""
    write_part_picture(editor, source, filename) -> ImageFile | Nothing

Write a picture of the part at `source`, a reference from the document of
`editor`, to the PNG file `filename`, with the backend (`write_image`). The part
is mapped forward through the projection of the editor
(`map_reference_forward`), and the picture is the canvas that draws it, all of
it, also what a pane scrolls out of view. A part that a view draws with no canvas
of its own, such as a file under the wrapper of its undo, has the picture of the
nearest part above it that has one.

Answers `nothing` when no part on the way has a canvas, or when no backend writes
an image. See also `write_window_picture`.
"""
function write_part_picture(editor, source, filename::AbstractString)
    part, window = _find_picture_target(editor, source)
    part === nothing ? nothing : _write_canvas_picture(part, window, filename)
end

"""
    write_window_picture(editor, source, filename) -> ImageFile | Nothing

Write a picture of the window that shows the part at `source`, a reference from
the document of `editor`, to the PNG file `filename`, with the backend
(`write_image`): all that the window draws. With no `source`, or a `source`
that no window shows, it is the first window.

Answers `nothing` when the editor shows no window, or when no backend writes an
image.
"""
function write_window_picture(editor, source, filename::AbstractString)
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
