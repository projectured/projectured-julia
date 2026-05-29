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

`WindowCloseRequest` is the inner event for the native window's close
button being clicked; readers translate it into a document mutation
(typically: remove the matching `WindowDocument` from `windows`).
"""
module ScreenDocumentModule

import ..ReactiveModule: Cell, setfn!, setval!
import ..DocumentModule: Document, @document
import ..CollectionModule: CellVector
import ..ReferenceModule: Reference

export ScreenDocument, WindowDocument, EventEnvelope, WindowCloseRequest,
       IScreenDocument, IWindowDocument

# ── ScreenDocument ────────────────────────────────────────────────────────

"""
    ScreenDocument(windows::Vector{WindowDocument})
    ScreenDocument(window::WindowDocument)

Top-level container modelling a set of open windows. `windows` is a
`CellVector` of `WindowDocument`s. The list order is preserved across
frames but carries no visual semantics — window identity is the
`WindowDocument.id` `Symbol`.
"""
@document struct ScreenDocument <: Document
    windows::CellVector
    selection::Reference
end

ScreenDocument() = ScreenDocument(CellVector(), Cell(nothing))
ScreenDocument(windows::CellVector) = ScreenDocument(windows, Cell(nothing))
ScreenDocument(windows::AbstractVector) =
    ScreenDocument(CellVector(Cell[Cell(w) for w in windows]), Cell(nothing))
ScreenDocument(window) = ScreenDocument([window])

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
- `content::Document` — the document tree this window displays. Before
  projection: any domain document. After projection: typically a
  `GraphicsCanvas`.
"""
@document struct WindowDocument <: Document
    id::Symbol
    title::String
    x::Int
    y::Int
    width::Int
    height::Int
    bg::NTuple{4,UInt8}
    style::Symbol
    content::Document
    selection::Reference
end

function WindowDocument(; id::Symbol = :main,
                          title::AbstractString = "ProjecturEd",
                          x::Integer = -1,
                          y::Integer = -1,
                          width::Integer = 2400,
                          height::Integer = 1600,
                          bg::NTuple{4,Integer} = DEFAULT_BG,
                          style::Symbol = :normal,
                          content)
    WindowDocument(Cell(id), Cell(String(title)),
                   Cell(Int(x)), Cell(Int(y)),
                   Cell(Int(width)), Cell(Int(height)),
                   Cell((UInt8(bg[1]), UInt8(bg[2]), UInt8(bg[3]), UInt8(bg[4]))),
                   Cell(style),
                   Cell(content),
                   Cell(nothing))
end

# ── Event envelope ────────────────────────────────────────────────────────

"""
    EventEnvelope(window_id::Symbol, event)

Wraps an input event with the identity of the window it originated
from. `window_id` is the matching `WindowDocument.id`, or `:none` for
application-level events with no window (e.g. `SDL_QUIT`).

The backend produces envelopes from raw SDL events; `CopyingProjection`'s
reader uses `window_id` to dispatch the inner `event` into the matching
`WindowDocument.content`'s sub-iomap.
"""
struct EventEnvelope
    window_id::Symbol
    event::Any
end

# ── WindowCloseRequest ────────────────────────────────────────────────────

"""
    WindowCloseRequest()

Inner event carried by an `EventEnvelope` when the user clicks a
window's native close button (`SDL_WINDOWEVENT_CLOSE`). Readers
translate it into a document mutation that removes the matching
`WindowDocument` from `ScreenDocument.windows`.
"""
struct WindowCloseRequest end

# ── Display ───────────────────────────────────────────────────────────────

function Base.show(io::IO, s::ScreenDocument)
    print(io, "ScreenDocument(windows=", length(s.windows), ")")
end

function Base.show(io::IO, w::WindowDocument)
    print(io, "WindowDocument(id=:", w.id,
          ", title=", repr(w.title),
          ", ", w.width, "x", w.height,
          ", style=:", w.style, ")")
end

end # module
