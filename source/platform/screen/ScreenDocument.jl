# Fragment of `ScreenModule` — `ScreenDocument`, the root that holds the
# windows, and the window document beneath it.

"""
    ScreenDocument(; windows, pointer_shape = nothing)

The windows that the editor shows, and `pointer_shape`, the shape that the
pointer keeps over every window while a part says one, or `nothing`. A part says
the shape of its drag with [`ChangeScreenPointerShapeOperation`](@ref), and the
screen draws a region of that shape over each window. `pointer_shape` is view
state: a history does not record it.
"""
@document struct ScreenDocument
    windows::CellVector = CellVector()
    pointer_shape::Union{Symbol,Nothing} = nothing
end

# `ScreenDocument()` (empty), `ScreenDocument([w, …])` and `ScreenDocument(w, …)`
# all come from the macro: the keyword constructor plus Rule C's bracketed and
# variadic forms for a struct backed by a single `CellVector`. Only the
# already-wrapped `CellVector` form needs writing — a `CellVector` is a `Document`,
# so this more specific method takes it as the *collection*, not as one element.
ScreenDocument(windows::CellVector) = ScreenDocument(windows, Cell(nothing), Cell(nothing))

# ── WindowDocument ────────────────────────────────────────────────────────

const DEFAULT_BG = (UInt8(249), UInt8(249), UInt8(251), UInt8(255))

# The defaults live on the fields, so `WindowDocument(; content = doc, …)` is the
# macro's keyword constructor. `content` is the one field without a default, and
# is therefore a *required* keyword — which is exactly the old hand-written
# signature.
"""
    WindowDocument(; id, title, x, y, width, height, bg, style, content)

A single window inside a `ScreenDocument`. Metadata fields are copied
verbatim by the projection pipeline; only `content` is recursively
projected.

- `id::Symbol` — stable identity used by the backend to track this
  window across frames. Must be unique within its `ScreenDocument`.
- `title::String` — window title.
- `x::Int`, `y::Int` — screen position; -1 = backend chooses.
- `width::Int`, `height::Int` — initial size in pixels; 0 = auto-size.
- `minimum_size::NTuple{2,Int}`, `maximum_size::NTuple{2,Int}` — the bounds of a
  window that fits its content. A `maximum_size` of `(0, 0)`, the default, is a
  window of a fixed size: it keeps `width` and `height`. A window with a maximum
  is printed at that maximum, and the backend gives it the extent of what it
  printed, clamped between the two.
- `bg::NTuple{4,UInt8}` — background RGBA.
- `style::Symbol` — `:normal`, `:tooltip`, `:floating`, `:popup`, … Backend
  applies per-style behaviour (default `:normal`). A `:popup` is a menu or a
  dropdown list: a window that never takes the focus, so the keyboard stays in
  the window under it.
- `auto_dismiss::Bool` — when `true`, the window is a transient popup: a
  dropdown, a menu or a context menu that closes when the pointer acts
  elsewhere. `WindowManagingProjection` closes it on its own `WindowDefocus`, on
  a `MouseDown` in another window, and on a bare Escape; a `:popup` also closes
  when any window loses the focus. The default window and tooltips stay
  `false`, so losing focus to a popup never closes them. Default `false`.
- `content::Document` — the document tree this window displays. Before
  projection: any domain document. After projection: typically a
  `GraphicsCanvas`.
"""
@document struct WindowDocument
    id::Symbol = :default
    title::String = "ProjecturEd"
    x::Int = -1
    y::Int = -1
    width::Int = 2400
    height::Int = 1600
    minimum_size::NTuple{2,Int} = (0, 0)
    maximum_size::NTuple{2,Int} = (0, 0)
    bg::NTuple{4,UInt8} = DEFAULT_BG
    style::Symbol = :normal
    auto_dismiss::Bool = false
    modal::Bool = false
    content::Document
end

# A window calls itself by the title it shows.
get_document_title(window::WindowDocument) = window.title

# ── Window operations ───────────────────────────────────────────────────────
# The screen domain's own operation vocabulary: requests to open/close/resize a
# window. They live here beside `WindowDocument` (whose schema they mirror); a
# window-manager projection intercepts open/close/popup and applies them to a
# `ScreenDocument`, while `ResizeWindowOperation` writes straight to its target.

"""
    OpenWindowOperation(; id, title, x, y, width, height, minimum_size, maximum_size,
                          bg, style, auto_dismiss, modal, content)

Request that a new `WindowDocument` (with the given fields) be added to the
screen. The fields mirror `WindowDocument`'s schema 1:1. A window-manager
projection intercepts it and appends (or updates) the matching `WindowDocument`
on its `ScreenDocument.windows`. One that reaches the editor, from a wrapper
outside the screen projection or from a verb, is applied by `evaluate_operation`
to the screen that the editor's document wraps.

`bg` is `nothing` by default: the new window takes the background of the screen,
the background of its first window, and follows it, so a window that opens later
has the colour that the appearance gives the windows. An update of a window with
`bg = nothing` keeps its background.
"""
struct OpenWindowOperation <: Operation
    id::Symbol
    title::String
    x::Int
    y::Int
    width::Int
    height::Int
    minimum_size::NTuple{2,Int}
    maximum_size::NTuple{2,Int}
    bg::Union{Nothing,NTuple{4,UInt8}}
    style::Symbol
    auto_dismiss::Bool
    modal::Bool
    content::Document
end

OpenWindowOperation(; id::Symbol,
                      title::AbstractString = "",
                      x::Integer = -1,
                      y::Integer = -1,
                      width::Integer = 0,
                      height::Integer = 0,
                      minimum_size = (0, 0),
                      maximum_size = (0, 0),
                      bg::Union{Nothing,NTuple{4,Integer}} = nothing,
                      style::Symbol = :tooltip,
                      auto_dismiss::Bool = false,
                      modal::Bool = false,
                      content::Document) =
    OpenWindowOperation(id, String(title), Int(x), Int(y), Int(width), Int(height),
                        (Int(minimum_size[1]), Int(minimum_size[2])),
                        (Int(maximum_size[1]), Int(maximum_size[2])),
                        bg === nothing ? nothing : (UInt8(bg[1]), UInt8(bg[2]), UInt8(bg[3]), UInt8(bg[4])),
                        style, auto_dismiss, modal, content)

"""
    OpenPopupOperation(; id, x, y, width = 640, height = 800, auto_dismiss, content)

Request a popup window whose top left is at `(x, y)` in the frame of the reader
that holds the operation. The window takes the extent of what its content
draws, as a tooltip does, and `width` and `height` bound that extent; so no
opener estimates the size of what it opens. The widget that opens a popup answers a position in
its own frame, so "just below me" is `(0, height + gap)`. Each reader on the way
up moves the position into its own frame with `map_operation_position`, by the
place where it put the child that answered, and the layer of the window adds
the screen origin of the window and answers an `OpenWindowOperation`. So no
reader needs the screen position of the widget, and the operation does not
reach `evaluate_operation`.

An opener marks it with `ReplaceViewStateOperation`, because to open a popup is
not an edit, and a history does not record it.
"""
struct OpenPopupOperation <: Operation
    id::Symbol
    x::Int
    y::Int
    width::Int
    height::Int
    auto_dismiss::Bool
    content::Document
end

OpenPopupOperation(; id::Symbol, x::Integer = 0, y::Integer = 0,
                     width::Integer = 640, height::Integer = 800,
                     auto_dismiss::Bool = true, content::Document) =
    OpenPopupOperation(id, Int(x), Int(y), Int(width), Int(height), auto_dismiss, content)

function map_operation_position(operation::OpenPopupOperation, move)
    x, y = move(operation.x, operation.y)
    OpenPopupOperation(operation.id, Int(x), Int(y), operation.width, operation.height,
                       operation.auto_dismiss, operation.content)
end

"""
    CloseWindowOperation(id)

Request that the `WindowDocument` with the matching `id` be removed from the
screen. Intercepted by a window-manager projection, or applied by
`evaluate_operation` to the screen that the editor's document wraps, as an
`OpenWindowOperation` is; a close for an unknown id is silently ignored.
"""
struct CloseWindowOperation <: Operation
    id::Symbol
end

"""
    ChangeScreenPointerShapeOperation(shape)

Give the pointer `shape`, one of `POINTER_SHAPES`, over every window of the
screen, or with `nothing` give the shape back to the regions that the windows
draw. A part answers it at the start of its drag with the shape of the drag, and
with `nothing` at its `DragEnd` and its `DragCancel`, so the pointer keeps the
shape of the drag wherever it goes.

A part marks it with `ReplaceViewStateOperation`, because it is no edit, and a
history does not record it. The window manager takes it on the way up and answers
a write of `pointer_shape` of its input screen instead; one that reaches the
editor applies to the screen that the editor's document wraps.
"""
struct ChangeScreenPointerShapeOperation <: Operation
    shape::Union{Symbol,Nothing}
end

OperationModule.is_self_contained_operation(::ChangeScreenPointerShapeOperation) = true

"""
    make_screen_pointer_shape_operation(shape) -> ReplaceViewStateOperation

The [`ChangeScreenPointerShapeOperation`](@ref) of `shape` marked as view state, as
a part answers it at the start and at the end of its drag.
"""
make_screen_pointer_shape_operation(shape::Union{Symbol,Nothing}) =
    ReplaceViewStateOperation(ChangeScreenPointerShapeOperation(shape))

"""
    ResizeWindowOperation(target, width, height)

Set the `width`/`height` cells of `target` (a `WindowDocument`) to a new pixel
size. Because those cells are the exact range that the printer gives the window's
content, writing them re-lays-out the content reactively — no re-projection. Carries the target document directly, so it bubbles up through
every reader layer unchanged and is applied by `evaluate_operation`.
"""
struct ResizeWindowOperation <: Operation
    target::Any
    width::Int
    height::Int
end

function evaluate_operation(editor, op::ResizeWindowOperation)
    op.target === nothing && return
    op.target.width = op.width
    op.target.height = op.height
end
