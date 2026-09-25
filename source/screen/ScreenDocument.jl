# Fragment of `ScreenModule` — `ScreenDocument`, the root that holds the
# windows, and the window document beneath it.

@document struct ScreenDocument
    windows::CellVector = CellVector()
end

# `ScreenDocument()` (empty), `ScreenDocument([w, …])` and `ScreenDocument(w, …)`
# all come from the macro: the keyword constructor plus Rule C's bracketed and
# variadic forms for a struct backed by a single `CellVector`. Only the
# already-wrapped `CellVector` form needs writing — a `CellVector` is a `Document`,
# so this more specific method takes it as the *collection*, not as one element.
ScreenDocument(windows::CellVector) = ScreenDocument(windows, Cell(nothing))

# ── WindowDocument ────────────────────────────────────────────────────────

const DEFAULT_BG = (UInt8(253), UInt8(246), UInt8(227), UInt8(255))

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
- `style::Symbol` — `:normal`, `:tooltip`, `:floating`, … Backend
  applies per-style behaviour (default `:normal`).
- `auto_dismiss::Bool` — when `true`, the window closes itself on a
  `WindowDefocus` (it is a transient popup: a dropdown/menu/context menu that
  should vanish when the pointer acts elsewhere). The default window and tooltips
  stay `false`, so losing focus to a popup never closes them. Default `false`.
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
on its `ScreenDocument.windows`; it does not reach `evaluate_operation`.
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
    bg::NTuple{4,UInt8}
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
                      bg::NTuple{4,Integer} = (UInt8(253), UInt8(246), UInt8(227), UInt8(255)),
                      style::Symbol = :tooltip,
                      auto_dismiss::Bool = false,
                      modal::Bool = false,
                      content::Document) =
    OpenWindowOperation(id, String(title), Int(x), Int(y), Int(width), Int(height),
                        (Int(minimum_size[1]), Int(minimum_size[2])),
                        (Int(maximum_size[1]), Int(maximum_size[2])),
                        (UInt8(bg[1]), UInt8(bg[2]), UInt8(bg[3]), UInt8(bg[4])),
                        style, auto_dismiss, modal, content)

"""
    OpenPopupOperation(; id, anchor, dx, dy, width, height, auto_dismiss, content)

Request a popup window **anchored to another element** rather than at absolute
coordinates. `anchor` is a `Reference` (captured at print time by the trigger)
naming the element to anchor under; `(dx, dy)` is the trigger-supplied offset (the
trigger bakes its own size in, so "below the box" is `(0, box_height + gap)`).

A resolver projection turns it into an `OpenWindowOperation` at
`position + (dx, dy)` — resolving `anchor` to an absolute position via
`map_reference_forward` — so the deep trigger reader never needs its own absolute
coordinates. It does not reach `evaluate_operation`.
"""
struct OpenPopupOperation <: Operation
    id::Symbol
    anchor::Reference
    dx::Int
    dy::Int
    width::Int
    height::Int
    auto_dismiss::Bool
    content::Document
end

OpenPopupOperation(; id::Symbol, anchor::Reference,
                     dx::Integer = 0, dy::Integer = 0,
                     width::Integer = 0, height::Integer = 0,
                     auto_dismiss::Bool = true, content::Document) =
    OpenPopupOperation(id, anchor, Int(dx), Int(dy), Int(width), Int(height),
                       auto_dismiss, content)

"""
    CloseWindowOperation(id)

Request that the `WindowDocument` with the matching `id` be removed from the
screen. Intercepted by a window-manager projection; a close for an unknown id is
silently ignored.
"""
struct CloseWindowOperation <: Operation
    id::Symbol
end

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
