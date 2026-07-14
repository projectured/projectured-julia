"""
    ScreenDocumentModule

The screen domain: the projection-output side of the multi-window pipeline.

A `ScreenDocument` holds a list of `WindowDocument`s. Each `WindowDocument`
carries window metadata (id, title, x/y, width/height, bg, style) and a
`content::Document` of any type. The backend reconciles live native windows
against a `ScreenDocument` — one native window per `WindowDocument.id`.

`ScreenDocument` and `WindowDocument` are ordinary projectional documents:
the existing `CopyingProjection` handles them via its `CellVector` and
struct paths, so no new projection type is needed to project them — only
the example's projection at the `content` leaf.

`EventEnvelope` wraps an input event with the id of the window it came
from; the backend produces these and `CopyingProjection`'s reader uses
them to dispatch events into the matching `WindowDocument.content`'s
sub-iomap.

`WindowClose` is the inner event for the native window's close
button being clicked; readers translate it into a document mutation
(typically: remove the matching `WindowDocument` from `windows`).
"""
module ScreenDocumentModule

import ..CellModule: Cell, set_function!, set_value!
import ..DocumentModule: Document
import ..DocumentModule: @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference, ReferencePath
import ..OperationModule: Operation, evaluate_operation

# `EventEnvelope` is the kernel's event vocabulary; re-exported here so a window
# consumer gets the envelope and the window events from one module.
import ..EventModule: EventEnvelope
export EventEnvelope, WindowClose, WindowResize, WindowDefocus, OpenWindowOperation,
       OpenPopupOperation, CloseWindowOperation, ResizeWindowOperation

# ── ScreenDocument ────────────────────────────────────────────────────────

"""
    ScreenDocument(windows::Vector{WindowDocument})
    ScreenDocument(window::WindowDocument)

Top-level container modelling a set of open windows. `windows` is a
`CellVector` of `WindowDocument`s. The list order is preserved across
frames but carries no visual semantics — window identity is the
`WindowDocument.id` `Symbol`.
"""
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
# The defaults live on the fields, so `WindowDocument(; content = doc, …)` is the
# macro's keyword constructor. `content` is the one field without a default, and
# is therefore a *required* keyword — which is exactly the old hand-written
# signature.
@document struct WindowDocument
    id::Symbol = :default
    title::String = "ProjecturEd"
    x::Int = -1
    y::Int = -1
    width::Int = 2400
    height::Int = 1600
    bg::NTuple{4,UInt8} = DEFAULT_BG
    style::Symbol = :normal
    auto_dismiss::Bool = false
    modal::Bool = false
    content::Document
end

# ── WindowClose ────────────────────────────────────────────────────

"""
    WindowClose()

Inner event carried by an `EventEnvelope` when the user clicks a
window's native close button (`SDL_WINDOWEVENT_CLOSE`). It is a
*request* the application may refuse — the event reports what the
user did, not what must happen. `WindowManagingProjection`'s reader resolves the window by
`EventEnvelope.window_id` and removes the matching `WindowDocument`
from `ScreenDocument.windows` (via `CloseWindowOperation`).
"""
struct WindowClose end

# ── WindowResize ─────────────────────────────────────────────────────

"""
    WindowResize(width, height)

Inner event carried by an `EventEnvelope` when the user resizes a window's
native frame (`SDL_WINDOWEVENT_RESIZED`). `width`/`height` are the new pixel
size of the window's content area. `WindowManagingProjection`'s reader
translates it into a `ResizeWindowOperation` that writes the new size into the
matching `WindowDocument`'s `width`/`height` cells — which the printer reads
as the available layout extent, so the content re-lays-out reactively.
"""
struct WindowResize
    width::Int
    height::Int
end

# ── WindowDefocus ───────────────────────────────────────────────────────

"""
    WindowDefocus()

Inner event carried by an `EventEnvelope` when a window loses input focus
(SDL `SDL_WINDOWEVENT_FOCUS_LOST` / web `blur`). `WindowManagingProjection`'s
reader closes the window **only when its `auto_dismiss` is `true`** — a transient
popup dismissing because the pointer acted elsewhere. The default window and
tooltips (`auto_dismiss = false`) ignore it, so focusing a popup never closes
them.
"""
struct WindowDefocus end

# ── Window operations ───────────────────────────────────────────────────────
# The screen domain's own operation vocabulary: requests to open/close/resize a
# window. They live here beside `WindowDocument` (whose schema they mirror); a
# window-manager projection intercepts open/close/popup and applies them to a
# `ScreenDocument`, while `ResizeWindowOperation` writes straight to its target.

"""
    OpenWindowOperation(; id, title, x, y, width, height, bg, style, auto_dismiss, modal, content)

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
                      bg::NTuple{4,Integer} = (UInt8(253), UInt8(246), UInt8(227), UInt8(255)),
                      style::Symbol = :tooltip,
                      auto_dismiss::Bool = false,
                      modal::Bool = false,
                      content::Document) =
    OpenWindowOperation(id, String(title), Int(x), Int(y), Int(width), Int(height),
                        (UInt8(bg[1]), UInt8(bg[2]), UInt8(bg[3]), UInt8(bg[4])),
                        style, auto_dismiss, modal, content)

"""
    OpenPopupOperation(; id, anchor, dx, dy, width, height, auto_dismiss, content)

Request a popup window **anchored to another element** rather than at absolute
coordinates. `anchor` is a `ReferencePath` (captured at print time by the trigger)
naming the element to anchor under; `(dx, dy)` is the trigger-supplied offset (the
trigger bakes its own size in, so "below the box" is `(0, box_height + gap)`).

A resolver projection turns it into an `OpenWindowOperation` at
`position + (dx, dy)` — resolving `anchor` to an absolute position via
`map_reference_forward` — so the deep trigger reader never needs its own absolute
coordinates. It does not reach `evaluate_operation`.
"""
struct OpenPopupOperation <: Operation
    id::Symbol
    anchor::ReferencePath
    dx::Int
    dy::Int
    width::Int
    height::Int
    auto_dismiss::Bool
    content::Document
end

OpenPopupOperation(; id::Symbol, anchor::ReferencePath,
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
size. Because those cells are the `available_width`/`available_height` the printer
threads into the window's content, writing them re-lays-out the content reactively
— no re-projection. Carries the target document directly, so it bubbles up through
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

end # module
