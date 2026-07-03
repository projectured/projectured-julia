"""
    NaturalProjectionModule

The **natural projection**: one generic factory, [`NaturalToGraphics`](@ref),
that projects *almost any* document to a `GraphicsCanvas` — recursively and
bidirectionally — without the caller hand-assembling a per-context dispatch
table.

It is built entirely from existing, already-bidirectional projections
(`TypeDispatchingProjection`, `RecursiveProjection`, `ChainingProjection`, and
the per-domain `*ToSyntax` / `*ToGraphics` projections), so it inherits the
printer, the reader, and both reference maps for free — there are no new
`print_document` / `read_intent` / `map_reference_*` methods here.

## How "render anything, including nestings" works

Two recursion fabrics, tied together by the four-function recursion contract:

- **`natural_to_syntax`** — a `TypeDispatchingProjection` that routes every
  *syntax-producible* domain (JSON, XML, Math, Julia, Book, Primitive,
  FileSystem) to its `*ToSyntax`, collections (`CellVector` / `ListNode`) to
  `CollectionToSyntax`, and *anything else* to `ObjectToSyntax`'s reflection
  table (`Cell`/`Nothing`/`Bool`/`Number`/`String`/`Symbol`/`Char`/`Any`).
  Wrapped in a `RecursiveProjection`, it is the shared element-recursion fabric:
  a collection of mixed-domain values, or any cross-domain nesting, projects to a
  single syntax tree because each element re-enters this same fabric by type.

- **the to-graphics dispatcher** — the returned `RecursiveProjection(
  TypeDispatchingProjection(…))`. It routes layout combinators and widget nodes
  to their direct graphics renderers (which recurse their embedded content back
  through this same dispatcher), prose `TextDocument` to a text→graphics chain,
  and **everything else** (`Any`) to `syntax_to_graphics =
  RecursiveProjection(natural_to_syntax) → SyntaxToText → Text→Graphics`. The
  `Any` catch-all means the renderer never errors — it degrades to a reflected
  object tree for genuinely unknown values.

## Scope

This renders *content / data* documents. Structural shells (the conversation
chat bubbles, the workbench tabs/panes) are projected to widgets by their own
panels as a separate top-level stage; a `ConversationDocument` / `WorkbenchDocument`
reaching a content slot here falls through to the reflective `Any` fallback. A
caller that wants the real rendering injects an entry via `extra`.

## Collections render as stacked blocks

A `CellVector` renders as a `VerticalLayout` of independent graphics blocks
(`CellVectorToVerticalLayout` → `VerticalLayoutToGraphicsCanvas`): each element
re-enters *this* renderer in its own domain (prose→prose, JSON→JSON,
widget→widget), rather than the whole collection collapsing to one syntax tree.
So a `CellVector` of mixed content — including `TextText` prose — renders
naturally.

A `ListNode` is **not** treated this way: it stays in the to-syntax fabric
(`CollectionToSyntax`), because a list may be lazy/infinite and must not be forced
into a finite layout. A `TextText` placed directly inside a `ListNode` therefore
still reflects via `ObjectToSyntax` rather than rendering as prose — an accepted
edge case.
"""
module NaturalProjectionModule

import ..FontModule: font_ubuntu_monospace_regular_20
import ..TypeDispatchingProjectionModule: TypeDispatchingProjection
import ..RecursiveProjectionModule: RecursiveProjection
import ..ChainingProjectionModule: ChainingProjection
import ..WidgetToGraphicsModule: WidgetToGraphics
import ..LayoutToGraphicsModule: LayoutToGraphics, VerticalLayoutToGraphicsCanvas
import ..CollectionToLayoutModule: CellVectorToVerticalLayout
import ..CollectionModule: CellVector
import ..TextToGraphicsModule: TextToGraphics
import ..WordWrappingModule: WordWrapping
import ..SyntaxToTextModule: SyntaxToText
import ..ObjectToSyntaxModule: ObjectToSyntax
import ..CollectionToSyntaxModule: CollectionToSyntax
import ..JsonToSyntaxModule: JsonToSyntax
import ..XmlToSyntaxModule: XmlToSyntax
import ..JuliaToSyntaxModule: JuliaToSyntax
import ..MathToSyntaxModule: MathToSyntax
import ..BookToSyntaxModule: BookToSyntax
import ..PrimitiveToSyntaxModule: PrimitiveToSyntax
import ..FileSystemToSyntaxModule: FileSystemToSyntax
import ..JsonModule: JsonDocument
import ..XmlModule: XmlDocument
import ..MathModule: MathDocument
import ..JuliaModule: JuliaDocument
import ..BookModule: BookDocument
import ..PrimitiveModule: PrimitiveDocument
import ..FileSystemModule: FileSystemDocument
import ..TextModule: TextDocument

export NaturalToGraphics, natural_to_syntax_dispatch

"""
    natural_to_syntax_dispatch() -> Vector{Pair{Type,Any}}

The shared *to-syntax* dispatch table: every syntax-producible domain → its
`*ToSyntax`, collections → `CollectionToSyntax`, and the `ObjectToSyntax`
reflection table as the tail (so plain `Bool`/`Number`/`String`/… render as
leaves and any unknown value as a reflected node). Exposed so callers can splice
or extend it the way `WidgetToGraphics(…).dispatch` is spliced.
"""
function natural_to_syntax_dispatch()
    vcat(
        Pair{Type,Any}[
            JsonDocument       => JsonToSyntax(),
            XmlDocument        => XmlToSyntax(),
            MathDocument       => MathToSyntax(),
            JuliaDocument      => JuliaToSyntax(),
            BookDocument       => BookToSyntax(),
            PrimitiveDocument  => PrimitiveToSyntax(),
            FileSystemDocument => FileSystemToSyntax(),
        ],
        CollectionToSyntax().dispatch,   # CellVector, ListNode
        ObjectToSyntax().dispatch,       # Cell/Nothing/Bool/Number/String/Symbol/Char/Any
    )
end

"""
    NaturalToGraphics(; measure, font=font_ubuntu_monospace_regular_20,
                        wrap=true, extra=Pair{Type,Any}[])
        -> RecursiveProjection

Build the natural projection: a recursive type-dispatching projection mapping
almost any document to a `GraphicsCanvas`. `measure(text, font) -> (w, h)` is the
text-measurement function (backend-supplied; e.g. `truetype_measure_text`).

- `font`    — base font for widget/text rendering.
- `wrap`    — word-wrap prose (`TextDocument`). Structured syntax/code is always
              rendered no-wrap (its layout carries meaning; overflow is the
              viewport's job).
- `extra`   — `Pair{Type,Any}` entries prepended to the table, so a caller can
              override or add routing (e.g. a placeholder text chain, or a real
              renderer for a structural document) without forking the table.
              First match wins, so `extra` beats the defaults.
"""
function NaturalToGraphics(; measure::Function,
                           font = font_ubuntu_monospace_regular_20,
                           wrap::Bool = true,
                           extra = Pair{Type,Any}[])
    w2g = WidgetToGraphics(font; measure = measure)

    # Prose: optionally word-wrapped. Structured syntax/code: never wrapped.
    prose_chain = wrap ?
        ChainingProjection(WordWrapping(measure = measure), TextToGraphics(measure = measure)) :
        TextToGraphics(measure = measure)

    # The shared element-recursion fabric (mixed domains + collections), then the
    # Syntax→Text→Graphics tail.
    syntax_to_graphics = ChainingProjection(
        RecursiveProjection(TypeDispatchingProjection(natural_to_syntax_dispatch())),
        RecursiveProjection(SyntaxToText()),
        TextToGraphics(measure = measure),
    )

    table = vcat(
        Pair{Type,Any}[p for p in extra],
        LayoutToGraphics().dispatch,   # layouts before widgets: a WidgetTable builds a GridLayout
        w2g.dispatch,                  # every widget node (incl. WidgetTable)
        Pair{Type,Any}[
            TextDocument => prose_chain,
            # A collection renders as a stack of independent graphics blocks: each
            # element re-enters this renderer in its own domain (prose→prose,
            # JSON→JSON, widget→widget), instead of collapsing to one syntax tree.
            CellVector   => ChainingProjection(CellVectorToVerticalLayout(),
                                                 VerticalLayoutToGraphicsCanvas()),
            Any          => syntax_to_graphics,
        ],
    )

    RecursiveProjection(TypeDispatchingProjection(table))
end

end # module
