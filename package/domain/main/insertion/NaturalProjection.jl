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
  *syntax-producible* domain (JSON, XML, Markdown, RST, Math, Julia, Book,
  Primitive, FileSystem) to its `*ToSyntax`, collections (`CellVector` / `ListNode`) to
  `CollectionToSyntax`, and *anything else* to `ObjectToSyntax`'s reflection
  table (`Cell`/`Nothing`/`Bool`/`Number`/`String`/`Symbol`/`Char`/`Any`).
  Wrapped in a `RecursiveProjection`, it is the shared element-recursion fabric:
  a collection of mixed-domain values, or any cross-domain nesting, projects to a
  single syntax tree because each element re-enters this same fabric by type.

- **the to-graphics dispatcher** — the returned `RecursiveProjection(
  TypeDispatchingProjection(…))`. It routes layout combinators and widget nodes
  to their direct graphics renderers (which recurse their embedded content back
  through this same dispatcher), a `GraphGraph` to the two graph stages (whose
  vertex content re-enters here, so a diagram node may be a widget or prose or a
  table), prose `TextDocument` to a text→graphics chain,
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
So a `CellVector` of mixed content — including `TextBlock` prose — renders
naturally.

A `ListNode` is **not** treated this way: it stays in the to-syntax fabric
(`CollectionToSyntax`), because a list may be lazy/infinite and must not be forced
into a finite layout. A `TextBlock` placed directly inside a `ListNode` therefore
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
import ..CollectionModule: CellVector, ComputedCellVector
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
import ..SqlToSyntaxModule: SqlToSyntax
import ..JsonModule: JsonDocument
import ..XmlModule: XmlDocument
import ..MathModule: MathDocument
import ..MathToGraphicsModule: math_to_graphics_dispatch
import ..JuliaModule: JuliaDocument
import ..BookModule: BookDocument
import ..PrimitiveModule: PrimitiveDocument
import ..FileSystemModule: FileSystemDocument
import ..SqlDocumentModule: SqlDocument
import ..TextModule: TextDocument, TextNothing, TextInsertion
import ..DocumentInsertionToSyntaxModule: DomainInsertionToSyntaxLeaf, InsertionNothingToSyntaxLeaf
import ..MarkdownToSyntaxModule: MarkdownToSyntax
import ..RstToSyntaxModule: RstToSyntax
import ..RstModule: RstDocument, RstRoot, RstSection
import ..MarkdownModule: MarkdownDocument, MarkdownRoot
import ..MarkdownToLayoutModule: MarkdownRootToVerticalLayout
import ..RstToLayoutModule: RstRootToVerticalLayout, RstSectionToVerticalLayout
import ..EmbedToSyntaxModule: ReferenceStubToSyntax, FileDocumentToSyntax
import ..FileProjectModule: FileDocument, ReferenceStub
import ..GraphModule: GraphGraph
import ..GraphToGraphLayoutModule: GraphGraphToGraphLayout
import ..GraphLayoutToGraphicsModule: GraphLayoutToGraphicsCanvas

export NaturalToGraphics, natural_to_syntax_dispatch, register_natural_syntax!

"""
    natural_to_syntax_dispatch() -> Vector{Pair{Type,Any}}

The shared *to-syntax* dispatch table: every syntax-producible domain → its
`*ToSyntax`, collections → `CollectionToSyntax`, and the `ObjectToSyntax`
reflection table as the tail (so plain `Bool`/`Number`/`String`/… render as
leaves and any unknown value as a reflected node). Exposed so callers can splice
or extend it the way `WidgetToGraphics(…).dispatch` is spliced.
"""
# Domains that live downstream of this package — a NED file, an INI config —
# cannot be named in the table below, and the natural renderer is supposed to
# render *any* document. So they register themselves, the way a file extension
# or a marker verb does, and their entries go in FRONT of the built-ins so a
# downstream domain can also override one.
const _NATURAL_SYNTAX_EXTRA = Pair{Type,Any}[]

"""
    register_natural_syntax!(pairs::Pair{Type,Any}...) -> nothing

Teach the natural renderer how a downstream domain becomes syntax. Call it from
the registering package's `__init__` (the table is runtime state, not something
to bake into a precompiled image); a type registered twice keeps the first
entry, so a reload does not stack duplicates.

Without this a document from a package this one cannot see falls through to the
reflection tail and renders as its field names instead of as itself.
"""
function register_natural_syntax!(pairs::Pair{Type,Any}...)
    for pr in pairs
        any(e -> first(e) === first(pr), _NATURAL_SYNTAX_EXTRA) && continue
        push!(_NATURAL_SYNTAX_EXTRA, pr)
    end
    nothing
end

function natural_to_syntax_dispatch()
    vcat(
        Pair{Type,Any}[e for e in _NATURAL_SYNTAX_EXTRA],
        Pair{Type,Any}[
            JsonDocument       => JsonToSyntax(),
            XmlDocument        => XmlToSyntax(),
            MarkdownDocument   => MarkdownToSyntax(style = :rendered),
            RstDocument        => RstToSyntax(style = :rendered),
            # An embed renders as what it embeds: the stub prints the value its
            # marker evaluated to, the file document prints its content. Both
            # come *before* the reflection tail, and neither is in a domain's own
            # table — saving goes through that one and stays by-marker.
            ReferenceStub      => ReferenceStubToSyntax(),
            FileDocument       => FileDocumentToSyntax(),
            MathDocument       => MathToSyntax(),
            JuliaDocument      => JuliaToSyntax(),
            SqlDocument        => SqlToSyntax(),
            BookDocument       => BookToSyntax(),
            PrimitiveDocument  => PrimitiveToSyntax(),
            FileSystemDocument => FileSystemToSyntax(),
            # The Text domain's `@domain` pair. Text has no `TextToSyntax` table of
            # its own to carry them (it *is* the layer syntax prints to), and both
            # renderers live here, so its two entries live here — ahead of the
            # `TextDocument` prose route below, which prints a span sequence and
            # would not know what to do with a placeholder or a name buffer.
            TextNothing        => InsertionNothingToSyntaxLeaf(),
            TextInsertion      => DomainInsertionToSyntaxLeaf(TextDocument),
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
            # A markdown page is a stack of blocks, not one syntax tree, so each
            # element re-enters *this* renderer in its own domain. Prose still
            # goes to the syntax fabric; an embed whose document is a widget
            # (a live simulation card) reaches the widget renderer and can be
            # clicked, which a syntax tree could never offer it.
            MarkdownRoot  => ChainingProjection(MarkdownRootToVerticalLayout(),
                                                VerticalLayoutToGraphicsCanvas()),
            # An RST page is a stack of blocks for the same reason. It takes two
            # rules where markdown takes one: an RST section OWNS its blocks, so a
            # root rewrap alone would leave every embed below the first title
            # inside a syntax tree, where a card could not go.
            RstRoot       => ChainingProjection(RstRootToVerticalLayout(),
                                                VerticalLayoutToGraphicsCanvas()),
            RstSection    => ChainingProjection(RstSectionToVerticalLayout(),
                                                VerticalLayoutToGraphicsCanvas()),
            # An embed wears a card here, and only here: a card is a widget, so it
            # belongs in a to-graphics table. The to-syntax fabric above keeps the
            # bare rules, and so does every domain's own table — the save path
            # goes through those and stays by-marker.
            ReferenceStub => ReferenceStubToSyntax(unforced = :prose, wrap = :card),
            FileDocument  => FileDocumentToSyntax(unforced = :prose, wrap = :card),
            # A graph is a diagram, not a syntax tree: it goes through its own two
            # stages (size and place, then draw). No `NestingProjection` here — the
            # stages take *this* renderer as their recursion, so a vertex's content
            # is whatever it is, rendered the same way it would be anywhere else.
            # That is what lets a diagram node be a widget, or prose, or a table.
            GraphGraph    => ChainingProjection(GraphGraphToGraphLayout(),
                                                GraphLayoutToGraphicsCanvas()),
        ],
        # A formula is set, not spelled: it goes to its own typesetter, which
        # places real two-dimensional boxes. The rules are spliced one type at a
        # time (not as one dispatching projection) so every child of a formula
        # re-enters *this* renderer — which is what lets a formula hold an
        # embedded document, and a number inside one render through the shared
        # primitive path and still land on the formula's baseline.
        math_to_graphics_dispatch(measure = measure),
        Pair{Type,Any}[
            # The Text placeholder / name buffer are `TextDocument`s, but they are not
            # prose: they route through the syntax fabric, whose table renders them
            # with the shared `@domain` leaves. Exact types, so they win over the
            # abstract `TextDocument` entry below.
            TextNothing   => syntax_to_graphics,
            TextInsertion => syntax_to_graphics,
            TextDocument  => prose_chain,
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
